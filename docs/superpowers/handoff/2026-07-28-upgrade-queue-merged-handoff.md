# Session Handoff — 2026-07-28: upgrade queue merged, ranked tag axis unspent

**Audience:** the next session picking up the recommender. Supersedes
`2026-07-28-adr-0010-step-6-handoff.md` and `2026-07-26-adr-0009-steps-1-5-handoff.md`, both of
which describe branch work that is now on `main`. Those two are kept as the record of *why* the
queue looks the way it does; this file is the record of *where things stand*.

## State

| | |
|---|---|
| `main` | `566c636` — "Build the metadata upgrade queue (ADR-0009, ADR-0010) (#24)" |
| Working tree | clean, in sync with origin, no open branch |
| Unit tests | **270 pass, 0 failures** (iPhone 17, `-parallel-testing-enabled NO`) — was 248 |
| ADRs | 0007–0010 all accepted; **next free number is 0011** |

Everything ADR-0009 and ADR-0010 specified is shipped. There is no in-flight work.

## The finding that should drive the next session

**The queue fetches AniList's ranked tag axis, stores it, and nothing reads it.**

- `MetadataSnapshot.tags: [RankedTag]` is declared at `Work.swift:90` and written by
  `WorkStore.apply` at `WorkStore.swift:216`.
- Grepping `RankedTag` across `Manga-Reader/` returns **only** that declaration and
  `AniListAPI.swift`. There is no reader.
- The taste profile still builds from the *searchable* axis alone:
  `RecommendationEngine.swift:193` → `tags: workStore.work(id)?.snapshot?.genres ?? []`.

So the app now spends its 30/min AniList budget retrieving a 425-tag vocabulary with 0–100
per-title relevance, and then scores recommendations on the 19 genres it could already get from
MangaDex for free. The entire ADR-0007 → ADR-0010 arc exists to make that data available. The
payoff is unspent.

**This is a design decision, not a coding task.** ADR-0007 defines the two axes as different
things — genres are searchable and drive candidate *generation*; ranked tags are scoring-only
and cannot drive search, because AniList's 425 tags share only 32 names with MangaDex's 77.
Folding rank into signal strength needs a decided answer to "what does rank 78 mean next to a
genre the user has read four times?" Grill it before writing code; it likely earns **ADR-0011**.

> **Resolved 2026-07-28 — see [ADR-0011](../../adr/0011-ranked-axis-generation.md).** Decided and
> written, no code yet. The axis is spent on **generation via AniList**, not on scoring MangaDex
> candidates: a third `CandidateProvider` queries AniList with **tag pairs** that co-occur in the
> user's own Works (`minimumTagRank: 60`, top 5 by
> `Σ engagement × min(rank_a, rank_b)/100`), read-through-cached so it never blocks the rail.
> ADR-0007 is amended in two places — the ranked axis *is* searchable on AniList, and the budget
> rule is one owner of the *limiter*, not one caller.
>
> Two facts found while grilling that the next session should not re-derive: **`tag_in` is AND, not
> OR** (a pair at rank ≥ 80 is frequently empty), and **candidates carry no tags at all**
> (`MangaDexAPI.swift:13-22`) even though MangaDex's list endpoint returns them free — recovering
> those is separate, unclaimed work, deliberately not bundled so the golden diff stays
> attributable.

## Recommended order

1. **Verify the queue against the live AniList API — do this first.** It has never run against
   the real thing; every test stubs `AniListAPI.Transport`. One launch on a device with real
   reading history is the whole test. Everything below assumes the queue works.
2. ~~**Grill and decide the ranked-axis consumption** (→ ADR-0011)~~ — **done 2026-07-28**, ADR-0011
   accepted. What remains is implementing it, which is still gated on step 1: the AniList pool sits
   downstream of a queue that has never run live.
3. **Retire `MyAnimeListDebugView`** + its 3 live UI tests. Owed since 2026-07-22, now that the
   real rails are proven. Its resolver was fixed in `6708662` (it was building a private
   `EntityResolutionStore`, frozen at launch, writing to a cache nothing read) — housekeeping
   on a screen that should not outlive the feature it was built to prove.

## Behaviour change now live on `main`

The app **starts a background network loop on launch and on every `.active`**, stopping only on
`.background`. Paced by `AniListRateLimiter`, idles immediately when nothing is stale, so a
fresh install does nothing. A device with reading history will start making AniList requests the
first time it is opened. Intended — but it is the first user-visible network behaviour that runs
without anyone tapping anything, so it is worth watching.

## Gotchas learned this session

- **The `agy` post-commit hook runs its own `xcodebuild`** (on *iPhone 17 Pro*, not the iPhone 17
  this repo otherwise standardizes on) and holds the DerivedData lock for 2+ minutes. Any
  concurrent build dies with `accessing build database ... database is locked`. The commit
  returns in seconds, so it looks finished long before it is. Commit in the background and gate
  follow-up builds on `until ! pgrep -f "agy --model" >/dev/null; do sleep 15; done`.
- **The UI tests hit live MangaDex and are not in CI.** `testChapterPreviewKeepsRailReachable`
  failed once this session and passed later on the same branch with *more* code wired in. Treat
  a single red UI test as no signal: re-run it, and check `main` before blaming a branch. The
  unit suite is the trustworthy gate.
- **SourceKit is unreliable in this repo** — "No such module 'XCTest'", "Cannot find type
  'WorkID' in scope" on files that compile fine. Judge only by `xcodebuild`.

## Testing notes worth preserving

Three tests across steps 6 and 7 passed on their first run, which proves nothing on its own.
Each was earned by mutation instead, and the mutations are the real documentation:

| Test | Mutation that must fail it |
|---|---|
| `testAnOutcomeAfterAMergeIsRecordedAgainstTheSurvivingWork` | `live.id` → `work.id` in the `.absentFromProvider` record calls |
| `testAMergeIntoAnAlreadyFreshWorkSkipsTheFetch` | same |
| `testAColdStartProfilePushesNothing` | move `pushPriority(...)` above the gate in `profileAndExclusions()` |

Re-run the relevant mutation if you touch those paths. Two real bugs were caught during step 6
purely by injecting the clock (`memory.record` was stamping wall-clock time; an empty scan was
not clearing the skip set) — both silent in production, where the two clocks agree. Keep the
`now:` and `sleep:` seams.

## Still-open threads (older, none blocking)

- Extend More Like This reverse-resolution beyond MangaDex-only.
- Add `malId` to `LibraryItem` so saved seeds skip the title search.
- `MyAnimeListMangaDetail` does not decode `alternative_titles` — widen only if a need appears.
