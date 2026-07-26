# Session Handoff — 2026-07-25 (evening): slice 3 steps 1–2 shipped, step 3 designed

**Audience:** a fresh session continuing ADR-0007 slice 3. Supersedes
`2026-07-25-slice-3-work-wiring-handoff.md` for steps 1–2 only; that file's decisions, verified
API facts, and gotchas all still stand and are **not** repeated here.

## Where things are

| | state |
|---|---|
| **Step 1** — mint at the commitment points | **merged**, PR #18 → `main` at `8a114da` |
| **Step 2** — detail tags onto the Work, all sources | **merged**, PR #19 |
| **Step 3** — resolve at the seam in `TasteProfile.build` | **implemented** on `slice-3-work-aware-profile`; the three findings below are what it acted on |
| Steps 4–5 | untouched |

224 unit tests green with step 3 in place (201 baseline + 10 + 4 + 9).

### What shipped in steps 1–2

- Minting at read (`HistoryStore.record`), save (`LibraryStore.toggle` / `toggleCollection` /
  `setCollections`), and both feedback taps (`RecommendationEngine`). **Deliberately in the stores,
  not the views** the earlier handoff named: views aren't unit-testable here, and one store edit
  covers six view call sites.
- `WorkStore.noteListingTags(_:for:)` — ungated by source. Never mints (browsing isn't a
  commitment); stages tags in memory when no Work exists and `mint` **consumes** them, one-shot.
- `applyProvisionalSnapshot` is now a **floor, not an overwrite** — it refuses to replace a
  provider snapshot.
- `mint` only marks the store dirty when it actually learns something. It runs on **every page
  turn**, and re-arming the debounce each time meant a long reading session never persisted.

The MangaDex-gated `tasteProfile.recordTags` call in `MangaDetailView` is **still there on
purpose** — dual-write. Step 3 flips the read, step 4 deletes the write.

## Step 3 — three findings that changed the plan

*(All three were acted on. Kept here because the reasoning is not recoverable from the diff.)*

### 1. The golden file cannot show this change

The earlier handoff says "the golden file will move — that is the point." **It won't.**
`RecommendationGoldenTests.makeProfile()` (`:101-114`) constructs a `TasteProfile` from literal
weights and *deliberately bypasses* `TasteProfile.build` — its own comment says so: the harness
isolates **ranking**, and profile construction is "covered by its own unit tests." Changing `build`
therefore produces no golden diff at all.

**Recommendation:** add a *second* golden — `__Goldens__/taste-profile.txt` — rendering
`TasteProfile.build`'s output (tag weights, per-Work engagement, seeds) from a synthetic
**multi-source** history. Commit it **before** the behavior change, so the step-3 diff shows
WeebCentral reads entering the profile for the first time. That is the same argument the existing
harness rests on, applied at the layer where this change actually lives.

### 2. Tag keys have to become normalized names

`TasteProfile.weights` / `orderedTagIds` are keyed by MangaDex `Tag.id` (a UUID). A Work's snapshot
stores `QueryableTag { name, group: String? }` — **there is no id**. So the key space must become
the normalized tag name.

This is safe: every consumer (`CandidateProvider.swift:37, 44, 63, 64`) uses the key only to look
up `tagName[key]` and `weights[key]`. Nothing depends on it being a UUID. Two details:

- `group == nil` (AniList genres) should weight as **`"genre"` (1.0)**, not fall through
  `groupWeight`'s `default: 0.5`. ADR-0007: AniList genres "are all genre-level anyway."
- `orderedTagIds` currently sorts on weight with **no tie-break**, so equal weights order by
  dictionary iteration. Worth adding a name tie-break in the same change — the file's own
  "FIXTURE INVARIANT — NO TIED SCORES" comment explains why this class of nondeterminism bites.

### 3. Legacy history needs a backfill, or every existing user loses their For You rail

This is the one that would ship a regression. All history written before step 1 has **no Work**.
Resolve-through-Works then yields an empty profile on first launch after the update — precisely the
"history orphans" failure ADR-0007 claimed to have deleted. (The ADR's reasoning is still right:
nothing is *orphaned* because no re-key happened. But the seam resolves to nothing until a Work
exists.)

**Fix, inside `RecommendationEngine`, not `TasteProfile`:** for each history entry, resolve-or-mint
(`mint(from: entry.asManga)` — idempotent, and cheap since step 1's dirty-tracking fix), then, when
the resulting Work has no snapshot, seed it from the old `taste.tagCache[entry.mangaId]`. History is
capped at 500 entries, so this is ~500 dictionary lookups per rail build and a no-op in steady state.

**This is also what makes step 4 possible.** Retiring `taste.tagCache` is only safe once its
contents have been migrated onto Works, and this is that migration.

`ReadingEntry.asManga` already exists (`HistoryView.swift:138`).

### Sketch of the new signature

`TasteProfile` must stay a pure value type with no I/O — pass in a resolved structure, never the
store:

```swift
struct WorkSignal {            // built by the caller
    let workId: WorkID
    let entries: [ReadingEntry]   // all Listings' entries for this Work
    let tags: [QueryableTag]      // from the Work's snapshot
}

static func build(signals: [WorkSignal], savedIds: Set<String>, moreLikeThis: Set<String>,
                  now: Date, libraryItems: [Manga] = [], seedLimit: Int = 5) -> TasteProfile
```

Per-Work aggregation notes: `savedIds` / `moreLikeThis` are Listing-keyed, so test them as
`entries.contains { savedIds.contains($0.mangaId) }`. `makeSeeds` currently keys on `mangaId`
(`:96-114`) and needs a representative Listing per Work — prefer a saved library item (it carries
`malId`), else the most recent entry. Cross-source chapter counts merging into one
`distinctChapters` is **accepted** (ADR-0004 accepts per-source chapter numbering).

Also worth doing: make `RecommendationEngine`'s `workStore` **non-optional**. It has only two
construction sites (`Manga_ReaderApp`, the `makeEngine` test helper at
`Manga_ReaderTests.swift:1622`), and an optional dependency that silently disables the feature is
the wrong default here. `HistoryStore` / `LibraryStore` should stay optional — far too many test
construction sites.

## Still true from the previous handoff

Everything under its "Gotchas" and "Working style notes" — in particular: don't stack PRs (CI only
triggers on PRs targeting `main`), new `Manga-ReaderTests/` files need **four** manual pbxproj
edits, SourceKit false alarms are constant (judge only by `xcodebuild`), and
`TEST_RUNNER_REGENERATE_GOLDENS=1` is the only spelling that reaches the runner.

Order of work after step 3 is unchanged: retire `taste.tagCache` (step 4), wire `WorkStore.flush()`
to `scenePhase` (step 5), then the AniList upgrade queue — which is also when
`scheduleBackfill`'s mangadex-only filter can finally come out. Deleting that filter before the
queue exists would send WeebCentral ids to `MangaDexAPI.mangaDetail`, fail silently, record
nothing, and retry forever.
