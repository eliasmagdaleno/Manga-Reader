# Session Handoff — 2026-08-04: ADR-0011 slice 3 shipped, slice 4 (the golden diff) is next

**Audience:** the next session. Supersedes `2026-08-03-adr-0011-slice-2-handoff.md` for **state**
only. That file's **gotchas still apply verbatim** — the `xcp`/pbxproj churn and the rewritten `agy`
hook both bit again today. Behind it, `2026-07-30-webtoon-shipped-adr-0011-next-handoff.md` still
holds the **eight deferred hand-checks** and the **`page 5/5` false-finish experiment**, neither
touched by this work.

## State

| | |
|---|---|
| `main` | `80bd1f6` — unchanged |
| Working branch | **`anilist-ranked-pool`** at **`ee8a0bf`**, tree clean, **10 commits ahead of `main`, not pushed, no PR** |
| Unit tests | **416 pass, 1 skipped, 0 failures** — was 389. The skip is `TagPairSeedingDiagnostic`, by design |
| ADRs | 0007–0014 accepted; 0011 **amended twice today**; next free number is **0015** |
| Device | iPhone 16 Pro `BE0AB07B-8A4E-5D2C-A674-5698010C4D27` |
| Code review | `ee8a0bf` **passed** — 416/0, 0 serious lint, notes restate the design without contradicting it |

## What shipped

### `d6deda8` — the triangle finding, closed on evidence

The one open item slice 2 left behind. The 2026-08-03 diagnostic found the top 5 seeds contain a
triangle (`Demons∧Magic`, `Demons∧Found Family`, `Found Family∧Magic`) and **assumed** three of five
queries therefore ask nearly the same question. Measured against live AniList: **they don't.** 36
slots, **29 distinct titles**, only Berserk and The Greatest Estate Developer in all three. The tags
overlap; the catalogue regions mostly don't — `Demons∧Magic` returns shounen battle,
`Demons∧Found Family` returns darker ensembles, `Found Family∧Magic` returns slice-of-life.

Two consequences, **both no-change**, in ADR-0011's `Measured 2026-08-04` block:

- Breadth costs ~7 duplicate slots in 36. Not worth a seeding rule.
- `withinPool` sums over contributing pairs, so a title in all three edges collects three terms —
  the same "agreement outranks strength" shape rejected for the cross-pool agreement term, one level
  down. **It stands**, because it applies to 2 titles, one of which is a library title the candidate
  path drops anyway. A **revisit trigger** was added: if a future diagnostic shows the top-5 pairs
  sharing more than ~40% of their results, reopen the sum. Today's figure is ~19%.

**Do not re-derive the numbers; re-run the three queries.** They are three `curl` calls against
`https://graphql.anilist.co` with `tag_in`, `minimumTagRank: 60`, `isAdult: false`,
`sort: POPULARITY_DESC`, `perPage: 12` — no device, no build.

### `ee8a0bf` — slice 3, the provider

| File | |
|---|---|
| `Models/AniListPool.swift` | new — record types, pure core (`rankPoolCandidates`, `withinPoolScore`), reason strings |
| `Services/AniListPoolStore.swift` | new — the actor: `Caches/anilist-pool.json`, both TTLs, in-flight dedupe |
| `Models/AniListCandidateProvider.swift` | new — the shell: gate, read-through, `buildRecord` |
| `Manga-ReaderTests/AniListPoolTests.swift` | new — 25 tests (needed a pbxproj entry) |
| `Models/TagPairSeeding.swift` | `SeededTagPair.contributingWorks`, `TagPair: Comparable` |
| `Services/TagVocabularyStore.swift` | `cachedVocabulary()` + `refreshIfNeeded()`; `vocabulary()` untouched |
| `Models/AniListAPI.swift` | `media(tags:minimumTagRank:limit:)` + `PagePayload` |
| `Models/MangaDexAPI.swift` | `Manga: Codable, Equatable` |

Every ADR policy has a deterministic test, which is the whole point of the injected `Query`/`Resolve`
closures: the all-or-nothing abort (throws on query 3 and **stops** — asserts the remaining two are
never issued), zero-results-is-not-failure, score-before-resolve (asserts exactly the top 12 ids
reach `Resolve`, in score order), no floor and no backfill, the 14d/24h split, in-flight dedupe,
corrupt file as miss, and the gate counting contributing Works (7 Works with a ranked axis, 2
contributing, gate shut, zero budget spent).

## Decisions made this session — do not silently reverse

All are in ADR-0011. The four easiest to undo by accident:

1. **`finish()` guards on the seeds still being in flight.** `guard inFlight?.seeds == seeds else
   { return }`. Without it a refresh for superseded seeds — which may finish *last* — overwrites a
   newer pool. Pinned by `testARefreshForSupersededSeedsIsDiscardedNotWritten`.
2. **The refresh task captures `self` strongly, deliberately.** `[weak self]` was the first version
   and it silently dropped a completed 5-query result when the store deallocated — the exact opposite
   of read-through. The cycle it creates is temporary; `finish` clears `inFlight`.
3. **`Query` takes the limit as a parameter**, not as something the closure hardcodes. It is half the
   fan-out budget and belongs to the type that documents it. It was declared-and-never-wired in the
   first version; the review caught it.
4. **The gate counts contributing Works, not Works with a ranked axis.** A Work can carry ranked tags
   where none clears 60 or all sit in excluded categories.

Two decisions the design **did not** make, both forced, both amended in:

- **`LoadWorks = @Sendable () async -> [Work]`** — seeding needs Works, `WorkStore` is `@MainActor`,
  this provider deliberately is not. Same one-way shape as `RecommendationEngine.PriorityPush`.
- **`Manga: Codable, Equatable` on the type**, not an extension — Swift only synthesizes those in the
  declaring file. **Accepted cost:** `Manga` is persistable everywhere now, and a field added to it
  silently changes the pool cache format. Corrupt-file-is-a-miss is what contains that.

Two ADR predictions were wrong in our favour, also recorded: the slice-2 reopening cost **one new
test, not 15** (the existing tests assert on `.pair`/`.weight`, never whole values), and
`rankPoolCandidates` **cannot** be written as a fused `map`/`sorted`/`prefix`/`map` chain — the type
checker times out. It is explicit loops; the ordering comments carry the intent alone.

## Verification actually performed

Not strictly red-green this time, and that is the honest gap. The 23 original tests were written
before the implementation but run after it. **The two review fixes were red-green properly** — the
clobber test fails on both assertions against the old `finish`, and the limit test could not compile
against the old signature.

Full suite green (416/1/0) both before and after the pbxproj restore below. SwiftLint clean on all
five touched files; the 36 repo-wide warnings are pre-existing.

## Pick up here — slice 4, and it is the last one

1. ~~Tag vocabulary cache~~ — `51c4cbe`
2. ~~Pair seeding~~ — `d945315`
3. ~~The provider + read-through cache~~ — **`ee8a0bf`**
4. **Fold into `CompositeCandidateProvider` and diff `Manga-ReaderTests/__Goldens__/foryou-ranking.txt`** ← next

Slice 4 is last and alone so the golden diff has exactly one cause. Wiring means constructing the
provider in `RecommendationEngine.swift:66`, which today passes `tag:` and `mal:` only — you will
need to supply `loadWorks` (hopping to the `@MainActor` `WorkStore`), a `Query` that goes through
`AniListRateLimiter` into `AniListAPI.media`, and a `Resolve` that reverse-resolves `idMal` →
MangaDex. `MoreLikeThisProvider.swift:49-57` and `:107` are the pattern for the last of those.

**Expect the first run to look broken.** Slice 3 landed unreferenced, so nothing has ever kicked a
refresh — the first Home appearance after wiring is a cold miss on the pool and possibly the
vocabulary, and the golden will show an **empty AniList pool**. That is the read-through rule
working. Run it, wait a beat, run it again. Wiring at `wAniList = 0` to pre-warm was considered and
rejected in the ADR: a zero weight still moves the golden via reasons and pool membership.

Also still true: `reverseResolveViaSearch` is **deliberately not extracted** into a shared helper
until after slice 4, and the two known refactors are parked behind the same argument — a
`CachedJSONFile<T>` to collapse `AniListPoolStore`/`TagVocabularyStore` boilerplate, and a
`PoolScorer` value to carry `(contributions, weights)` together. Both touch a shipped path; do them
with the golden in place to prove nothing moved.

## Gotchas — all hit again today

- **`project.pbxproj` churn is still the top time sink, and `git diff` right after the edit is still
  untrustworthy.** Xcode collapsed the three `PBXFileSystemSynchronizedRootGroup` blocks and stripped
  `lastKnownFileType`/`name` from five unrelated `PBXFileReference` entries **on its own**, turning
  4 lines into 48. What worked: `git checkout HEAD -- Manga-Reader.xcodeproj/project.pbxproj`, then a
  python script inserting the four entries by mirroring `TagPairSeedingTests.swift`'s lines
  (`PBXBuildFile`, `PBXFileReference`, the group child, the `Sources` phase), then **re-run the full
  suite** — a hand-edited pbxproj that fails to compile is the obvious risk. **`git diff --cached
  --stat` must read `4 +` immediately before `git commit`.**
- **The `agy` hook behaved exactly as its rewrite intends.** Detached, no blocking commit, sentinel
  `.agy_review_running` absent when checked, footer `# agy review complete — exit 0` present, correct
  SHA in the header. **One caveat: its file-by-file summary is loose.** It described
  `TagVocabularyStore` as "extended vocabulary lookup and normalization utilities" when the actual
  change is two new non-fetching accessors. Trust its pass/fail numbers; read the diff for what
  changed.
- **SourceKit errors are noise** — "Cannot find type 'Work' in scope", "No such module 'XCTest'" on
  files that compile clean. Judge only by `xcodebuild`.
- **`await` inside an `XCTAssert` autoclosure does not compile.** Bind to a local first. Cost a build
  cycle.
- **Do not stack PRs.** Merging a base with `--delete-branch` closes the child unrecoverably.

## Still-open threads (older, none blocking)

Unchanged: the **eight deferred hand-checks** (load-bearing one: whether `.coordinateSpace(.named(…))`
yields viewport-relative frames — if not, every webtoon resume fraction is meaningless); the
**`page 5/5` false-finish** experiment; **externally hosted chapters** reading as broken because
`ChapterAttributes` doesn't decode `pages` (`MangaDexAPI.swift:125-131`); the **5xx wording** in
`readerFailureMessage`; and **decoding MangaDex's free list-endpoint tags**, still unclaimed until
the AniList pool has been through a golden diff — which is now one slice away.
