# Session Handoff — 2026-07-25 (evening): slice 3 steps 1–3 shipped, steps 4–5 next

**Audience:** a fresh session continuing ADR-0007 slice 3. Supersedes
`2026-07-25-slice-3-work-wiring-handoff.md`, whose step-by-step plan is now done through step 3.
That file's **decisions, verified AniList/MangaDex facts, gotchas, and working-style notes all
still stand** and are not repeated here — read it for those.

## State

| | |
|---|---|
| **Step 1** — mint at the commitment points | merged, PR #18 |
| **Step 2** — detail tags onto the Work, every source | merged, PR #19 |
| **Step 3** — profile aggregates by Work | **PR #20 open**, branch `slice-3-work-aware-profile` |
| **Step 4** — retire `taste.tagCache` | not started |
| **Step 5** — `WorkStore.flush()` on `scenePhase` | not started |

**224 unit tests green** (201 baseline + 23). `main` is at `7c776d2`.

**The ADR-0001 bug is fixed as of step 3**: a manga read on WeebCentral now mints a Work, gets tags
from its detail screen, and contributes tag signal and seeds to the recommender.

## What exists now

- **Minting** at read (`HistoryStore.record`), save (`LibraryStore.toggle` / `toggleCollection` /
  `setCollections`), and both feedback taps (`RecommendationEngine`). In the **stores**, not the
  views the original plan named — views aren't unit-testable here, and one store edit covers six
  view call sites.
- **`WorkStore.noteListingTags(_:for:)`** — ungated by source, never mints (browsing isn't a
  commitment), stages tags in memory when no Work exists; `mint` consumes them one-shot.
- **`applyProvisionalSnapshot` is a floor, not an overwrite** — it refuses to replace a provider
  snapshot.
- **`TasteProfile.build(signals:…)`** aggregates by Work; keys are normalized tag **names**;
  `orderedTagKeys` breaks ties on the key.
- **`RecommendationEngine.resolveSignals()`** is the seam. It deliberately mutates the store: mints
  from history entries that predate slice 3, and seeds snapshot-less Works from `taste.tagCache`.
- **Two golden files.** `foryou-ranking.txt` (ranking) and the new `taste-profile.txt` (profile
  construction). See "the golden trap" below.

## Step 4 — retire `taste.tagCache`

**Why it's now safe:** `resolveSignals()` copies `tagCache` onto Works on every rail build, so by
the time a user reaches step 4's code their tags already live on Works. **Do not skip that
reasoning** — retiring the cache before that migration had run would have silently emptied the
profile.

1. Delete the dual-write in `MangaDetailView.onChange(of: vm.detailTags)` — the
   `sourceId == "mangadex"` guard plus `tasteProfile.recordTags`. `noteListingTags` above it stays.
2. Delete `TasteProfileStore.recordTags`, `tagCache`, `mangaIdsMissingTags`, and the
   `taste.tagCache` UserDefaults key. **Keep `notInterested` and `moreLikeThis`.**
3. `RecommendationEngine.backfill(ids:)` and `scheduleBackfill()` go with it — they exist only to
   fill `tagCache`. Their successor is the AniList upgrade queue.
4. Drop the `tagCache` seeding branch in `resolveSignals()` once there is nothing to seed from.
   **Leave it for at least one release** — it *is* the migration, and deleting it in the same
   change that deletes the cache would strand anyone who skipped a version.
5. `Manga_ReaderTests.swift`'s `signals(history:tagCache:)` helper and the `TasteProfileStore` tag
   tests go too.

**This retires a latent bug, not just dead code:** `tagCache` is keyed by a bare `mangaId` with no
`sourceId` (`TasteProfileStore.swift:16,34`), a cross-source key collision that is only dormant
because tag recording was MangaDex-gated. Removing the cache removes the collision rather than
fixing it.

## Step 5 — `flush()` on `scenePhase`

`WorkStore.flush()` exists and is unwired. Call it on `.background` from
`Manga_ReaderApp`/`ContentView`. A debounced save that never fires because the app was suspended is
a lost write. Left out of slice 2 deliberately (no unused hooks) — the hook now has a user.

## Then: the AniList upgrade queue

Unchanged from the original handoff: batch of 5, ~2s spacing, ordered by engagement weight
descending, TTL via `MetadataSnapshot.isStale(now:)`, everything funnelled through
`AniListRateLimiter`, and **`AniListAPI` must not be callable from a view model**.

**`scheduleBackfill`'s mangadex-only filter must not be deleted before this exists.** `backfill`
calls `mangaDexSource.mangaDetail(id:)`; a WeebCentral id is not a MangaDex UUID, so the request
fails, `try?` swallows it, nothing is recorded, and the id stays in the missing list and retries on
every rail build — a permanent futile request loop. The queue is what actually gives non-MangaDex
Works metadata.

## Traps found this session — worth not rediscovering

- **The golden trap.** `RecommendationGoldenTests` builds a `TasteProfile` from **literal weights**
  and bypasses `build` entirely, so it is structurally blind to profile construction. The previous
  handoff expected step 3 to move it; it could not. `TasteProfileGoldenTests` was added to cover
  that layer. Before claiming a golden will show a change, check which layer it actually exercises.
- **Hot-path writes.** `mint` runs on **every page turn**. It used to mark the store dirty
  unconditionally, which cancelled and re-armed the debounced save each time, so a long reading
  session never persisted. Same shape as the `AniListRateLimiter` reentrancy bug: cost that only
  appears under repetition. Anything new on the read path deserves this question.
- **Resolve-through-X needs a migration.** ADR-0007 is right that Listing-keyed edges avoid a
  re-key migration, but "the seam resolves to nothing" is a different failure from "orphaned data",
  and it hits every existing user exactly once.
- **`XCTAssert` on `array[0]` crashes the whole run** rather than failing one test, hiding every
  test after it. Use `try XCTUnwrap(array.first)`.
- **A `#Preview` is a compile-time call site.** Making `RecommendationEngine.workStore`
  non-optional broke `HomeView`'s preview; only a build caught it.
- Adding a file to `Manga-ReaderTests/` still needs **four** manual pbxproj edits — mirror an
  existing entry with fresh ids. Three files were added this way this session.
