# Session Handoff — 2026-07-25 (later session): ADR-0007 slices 1–2 shipped, slice 3 next

**Audience:** a fresh session picking up cross-source Work identity. Self-contained — you should
not need the prior chat. Supersedes the earlier `2026-07-25-session-handoff.md`, whose "Next
steps" list is now half done.

## TL;DR

A design grilling closed the ten open questions the earlier handoff left, producing **ADR-0007**;
then slices 1 and 2 shipped test-first. **`main` is at `a90e8c5`, clean, 201 unit tests green, no
open PRs.**

What exists now, all unwired: an AniList client, a rate limiter, and the `Work` + `WorkStore`
identity layer. **Nothing in the app calls any of it.** Slice 3 is the wiring, and it is the first
slice that changes existing behavior.

## What shipped (PRs #13–#16, all merged)

| PR | Contents |
|---|---|
| #13 | **ADR-0007** (the Work's shape and lifecycle), glossary terms, ADR-0002 amended |
| #14 | `Models/AniListAPI.swift`, `Services/AniListRateLimiter.swift` (slice 1) |
| #15 | `.gitignore` for `.agy_code_review.md` |
| #16 | `Models/Work.swift`, `Services/WorkStore.swift` (slice 2) |

### The decisions you must not re-litigate

They're all in [ADR-0007](../../adr/0007-work-shape-and-lifecycle.md) with reasoning and rejected
alternatives. The load-bearing ones for slice 3:

- **The edges stay Listing-keyed; the Work lives at the seam.** `HistoryStore`, `LibraryStore`,
  `TasteProfileStore` keep recording `(sourceId, mangaId)`. **There is no data migration**, and
  there should not be one — this is what deletes the "history orphans on first launch" risk.
- **Minting happens on user commitment only** — read, save, *Not interested*, *More like this*,
  manual link — and is **synchronous, local, network-free**. Never on browse, search, or a
  candidate pool: pools are 40 titles per rail refresh, and minting those would grow the store
  with *browsing*, which breaks the sizing argument the JSON-file decision rests on.
- **One snapshot from one authority.** MangaDex tags are a free provisional tier; an AniList
  snapshot replaces it wholesale (guarded against empty). Ids and known titles accumulate.
- **Two tag axes.** `genres: [QueryableTag]` is **searchable** and drives generation; `tags:
  [RankedTag]` carries AniList's 0–100 rank, is **not searchable**, and is for scoring only.

## Verified facts — do not re-derive

Checked live 2026-07-25:

- **AniList's rate limit is `x-ratelimit-limit: 30`/min**, not the 90 the docs advertise.
- **MangaDex has 77 tags** (25 genre / 38 theme / 12 format / 2 content). **AniList has 19
  `genres` + 425 `tags`.** Only **32 of MangaDex's 77 names exist in AniList's tag vocabulary** —
  the missing 45 are the load-bearing ones (`Action`, `Romance`, `Fantasy`, `Comedy`, `Drama`,
  `Horror`, `Mystery`, `Sci-Fi`, `Slice of Life`, `Supernatural`) because AniList models those as
  `genres`, a separate field. **The two systems are two granularities, not rival vocabularies.**
- Ongoing series still report `chapters: null` (One Piece, Berserk both `RELEASING`).
- AniList's `romaji` is often *not* the title a user recognizes — Solo Leveling's is
  `"Na Honjaman Level Up"`. This is why `displayTitle` is sticky.

## Slice 3 — the wiring (this is the next task)

**Goal: make non-MangaDex reading count.** That's the bug ADR-0001 documented and nothing has
fixed yet.

### The bug, precisely

`MangaDetailView.swift:56` guards `manga.sourceId == "mangadex"` before recording tags.
`RecommendationEngine.scheduleBackfill` (`RecommendationEngine.swift:149-157`) filters history to
mangadex. `TasteProfile.build` then skips untagged manga **before** computing engagement weight
(`TasteProfile.swift:59` — `guard let tags = tagCache[mangaId], !tags.isEmpty else { continue }`). Chain it: a manga read on
WeebCentral gets no tags → no engagement weight → it can neither contribute tag signal nor become a
MAL seed. **Non-MangaDex reading is structurally invisible to the recommender.**

### The work, in the order I'd do it

1. **Mint at the five commitment points.** Call sites, all verified:
   - read → `ReaderView.swift:200` (`history.record(manga:chapter:page:pageCount:)`)
   - save → `LibraryStore.toggle(_:)` (`LibraryStore.swift:128`); note
     `toggleCollection(for:collectionId:)` (`:148`) and `setCollections(for:collectionIds:)` (`:178`)
     are also save-shaped entry points and want the same treatment
   - *Not interested* → `RecommendationEngine.swift:82`
   - *More like this* → `RecommendationEngine.swift:87`
   - manual link → doesn't exist yet (ADR-0005, later slice)

   Minting is sync and network-free, so these are one-line additions. A `Manga` carrying `malId`
   (MangaDex publishes `attributes.links.mal`) dedupes through the index with no request.

2. **Move tag recording onto the Work.** Replace `MangaDetailView.swift:56-57`'s guarded
   `tasteProfile.recordTags(mangaId:tags:)` with `workStore.applyProvisionalSnapshot(tags:to:)` —
   and **delete the `sourceId == "mangadex"` guard**. Also delete the mangadex-only filter in
   `scheduleBackfill`.

3. **Resolve at the seam in `TasteProfile.build`.** Its signature today is
   `build(history:savedIds:tagCache:moreLikeThis:now:libraryItems:seedLimit:)`
   (`TasteProfile.swift:43-49`), where `tagCache: [String: [Tag]]`. It needs to aggregate by
   **Work** instead: group history entries by resolved Work id, take tags from the Work's snapshot.
   `TasteProfile` is documented as a pure value type with no I/O — **keep it that way.** Pass in a
   resolved structure (e.g. `[WorkID: (entries, snapshot)]`) built by the caller, rather than
   handing it the store.

4. **Retire `taste.tagCache`.** Once tags live on the Work it's redundant — and it is keyed by a
   **bare `mangaId` with no `sourceId`** (`TasteProfileStore.swift:16,34`), a latent cross-source
   key collision that's only dormant because tag recording is MangaDex-gated today. Retiring it
   removes the collision rather than fixing it. Keep `notInterested` / `moreLikeThis`.

5. **Wire `WorkStore.flush()` to `scenePhase`** on backgrounding. A debounced save that never fires
   because the app was suspended is a lost write. Left out of slice 2 on purpose (no unused hooks).

### The golden file will move — that is the point

`Manga-ReaderTests/RecommendationGoldenTests.swift` + `__Goldens__/foryou-ranking.txt`. Expect the
diff, read it carefully, and treat it as the evidence: it shows what non-MangaDex reading counting
for the first time actually does to the ranking. There is no labeled relevance data for this app, so
a reviewable diff is the *only* available evidence a ranking change did what was intended.

Regenerate with **`TEST_RUNNER_REGENERATE_GOLDENS=1`** — `xcodebuild` silently drops plain env vars
for simulator tests; only `TEST_RUNNER_`-prefixed ones reach the runner (prefix stripped). A bare
`REGENERATE_GOLDENS=1` fails silently and looks like a broken harness.

## After slice 3

4. **Upgrade queue** — batch of 5, ~2s spacing, ordered by **engagement weight descending**, TTL
   via `MetadataSnapshot.isStale(now:)`. Reuse `scheduleBackfill`'s shape
   (`RecommendationEngine.swift:149-166`). **All AniList access must funnel through
   `AniListRateLimiter`** — the budget is global and this is the app's first rate-limited resource.
   `AniListAPI` must not be called from a view model.
5. **Count cache + fulfillment routing** (ADR-0004). Separate, evictable, in `Caches/`. **A missing
   count means *unknown*, never zero** — defaulting to `0` silently ranks that source last.
6. **Manual link override UI** (ADR-0005), including unlink. Resolution failures must become
   *visible*; `Work.knownTitles` exists to give that screen something useful to show
   ("known as X, Y, Z — none matched").
7. **Extensions** (ADR-0003) — last. First task there is *porting WeebCentral to the host API*, not
   designing the API in the abstract.

**Smaller, independently useful:** `AniListAPI.work(anilistId:)` and title search (deferred until
resolution/TTL need them); treating `.cancelled` as terminal in `isStale` (currently TTL'd —
harmless, untested); retiring `MyAnimeListDebugView`; splitting `Manga_ReaderTests.swift` (2,279
lines, over SwiftLint's `file_length`).

## Gotchas (this session's, plus carried forward)

- **Actors are reentrant.** The first `AniListRateLimiter` slept then recorded "when the last
  request finished"; a concurrent-callers test showed **4 requests firing in 0.7ms with no spacing
  at all**. Fixed by reserving a slot in one uninterrupted step *before* any suspension point. If
  you write anything else that paces work, the same trap applies.
- **`WorkStore` has no public dictionary, deliberately.** Lookups follow merge aliases; an accessor
  callers can bypass is one they will bypass. Don't "helpfully" expose `works` to make a view
  easier — that breaks aliasing silently.
- **`mint` must never fuzzy-match titles.** There's a test pinning this
  (`testMintDoesNotGuessAcrossSourcesWithoutAnExternalId`) that passes by construction; it exists so
  a future "helpful" match becomes a loud failure. Linking is resolution's job, and it is
  precision-biased for a reason (ADR-0005).
- **Don't stack PRs.** CI only triggers on PRs targeting `main` (`.github/workflows/ci.yml`), so a
  stacked PR gets no checks. I nearly stacked slice 2 on the gitignore branch; `git stash push -u` →
  `checkout main` → new branch → `stash pop` is the recovery when the work is still uncommitted.
- **`SourceKit` false alarms are constant here** — "No such module 'XCTest'", "Cannot find type
  'Manga' in scope" across files. Ignore them; judge only by `xcodebuild`.
- **New files in `Manga-ReaderTests/` need four manual pbxproj edits** (that group is a plain
  `PBXGroup`). `Models/`, `Services/`, and `Views/Components/` are synchronized — files there just
  work. Mirror `AniListAPITests.swift`'s four entries.
- **The AGY post-commit hook works now** and runs a full build + test + high-effort model review on
  **every commit**, synchronously (several minutes). It rewrote its own hook file mid-run once
  (fixing a hardcoded `iPhone 16` destination), so don't be surprised if `.git/hooks/post-commit`
  differs from what you last read. Output lands in `.agy_code_review.md` (now gitignored).
- **`Secrets.xcconfig` lives at the repo root** and is gitignored but is the app target's base
  config — any new worktree needs it copied in or the build fails immediately.
- `main` is branch-protected: branch → PR → both checks green → merge. Squash merges, matching
  history.

## Working style notes (carried forward)

- User is a **new-grad dev learning SWE from this project** — teach and give rationale, don't just
  do it.
- **Prose discussion at big forks**, not `AskUserQuestion` prompts.
- **iPhone 17 (or 17 Pro) + `-parallel-testing-enabled NO`** for every test run.
- TDD is expected: write the test, **watch it fail for the right reason**, then implement. If you
  catch yourself having written untested branches, strip them and let a test drive them — that
  happened three times this session and each strip found something (the alias chain returning
  `nil`, an opaque `DecodingError` on 5xx).
