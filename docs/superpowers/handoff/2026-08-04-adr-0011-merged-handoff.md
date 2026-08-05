# Session Handoff — 2026-08-04 (night): ADR-0011 is complete and merged

**Audience:** the next session. Supersedes both 2026-08-04 device-check handoffs for **state**.
`2026-08-04-device-check-passed-handoff.md` is still the reference for *how the device check works*
and *why the first one lied* — read it before running another one. The slice-4 handoff's gotchas
still apply.

**There is no work in flight.** The branch is merged, `main` is green, nothing is half-done.

## State

| | |
|---|---|
| `main` | **`c2521fb`** — "Wire the AniList ranked pool into the app (ADR-0011 slice 4) (#32)" |
| Checked out | `main`, clean, up to date with origin |
| PR #32 | **merged** 2026-08-05T00:35Z, squash, 21 commits → 1 |
| `anilist-ranked-pool` | kept locally at `3d95546`, **not deleted** — after a squash it is the only record of the slice-by-slice history. Delete when you no longer want that. |
| Tests | **417 pass / 1 skipped**, locally and on CI |
| CI | both jobs green on the merge commit's run |

## What shipped

ADR-0011 is **done — all four slices**. The AniList ranked axis is no longer dead metadata:

- The pool is the recommender's third candidate pool, blended at `wAniList = 0.6` beside the tag and
  MAL pools, fixed-arity in `CompositeCandidateProvider`.
- `TagVocabularyStore` and `AniListPoolStore` are owned by the composition root. Both are actors
  whose state must outlive a rail build; a per-build instance would mean no refresh is ever in
  flight and the pool would never warm.
- `MoreLikeThisProvider.resolve(works:limit:)` is the single reverse-resolution implementation.
- The vocabulary refresh is kicked at launch, collapsing cold start from three rail builds to two.
- A golden fixture pins the blended ranking.

**Verified live, not just by tests.** A cold container produced a full pool from ordinary reading —
5 seed pairs, 12 of 12 head candidates resolved. A relaunch left that pool byte-identical while the
For You rail rendered, which is the proof the provider receives *single* store instances. That claim
is unreachable from unit tests, which is the entire reason the device check exists.

## The one lesson worth carrying

The first device check reported a failure that wasn't one. The engine's cold-start gate
(`taggedMangaCount >= 3`, `RecommendationEngine.swift:151`) was closed, **upstream** of the wiring
under test — and below it `rebuild()` returns without constructing any provider, so all three pools
go dark and you get an empty rail *and* an absent pool cache from a single cause.

Both hypotheses in the previous handoff were wrong, and one was refutable by reading two lines
(`.task { engine.load() }` is outside the rail's `isEmpty` guard). No instrumented build was needed;
the whole diagnosis came from reading the simulator container off-disk.

**Generalize it:** verify the preconditions before treating an absence as a result. An unmet
precondition makes a run *invalid*, not negative. This is now in ADR-0011's wiring hazard, so a
future check inherits it.

## Next

1. **`MALReverseResolver` extraction.** Deferred deliberately — touching `recommendations(for:)`
   would have given a failed device check two candidate causes instead of one. That reason is spent,
   and the golden fixture is in place to prove the extraction moves nothing.

## Open, recorded, not scheduled

- **The untaggable-source gate.** A reader whose history is dominated by a source supplying neither
  Listing tags nor a resolvable external id can never open Gate 1, however much they read — such
  Works add *weight* to the profile but never to the *count*. Real user-visible consequence: For You
  never appears, with nothing in the UI to explain it. Recorded as an ADR-0011 hazard; **belongs to
  the Work model (ADR-0007/ADR-0009)**, so fix it there, not in the ranked-axis subsystem.
- **`AniListPool.swift` type-checker timeouts.** Two now — the second (`poolReason`) **compiled
  locally and failed on CI**, because the limit is wall-clock and therefore marginal, not
  deterministic. A green local build does not predict a green CI one for this file. Both were fixed
  by naming an intermediate type instead of inferring a tuple mid-chain. ADR-0011 has a revisit
  trigger: **a third occurrence means a house rule for the file, not a third local fix.**
- **The agy post-commit hook fix is machine-local.** `.git/hooks/` is not version-controlled, so it
  rides in no commit and a fresh clone will not have it.
- **SwiftLint warnings** in `ChapterListView.swift` and `HistoryView.swift` — trailing whitespace and
  a 171-character line. Pre-existing, untouched by this branch, job still passes. Small cleanup on
  `main` sometime.

## Also produced this session

A private Artifact explaining the recommender — the two gates, the three pools, the AniList chain
and its TTLs, and a field guide for reading an empty rail. Styled from the app's own `Theme.swift`
tokens. Deliberately contains **no** library contents or read titles, only mechanism.
<https://claude.ai/code/artifact/970880d4-24b1-4676-814a-ccfde4832633>

## Gotchas

All of the slice-4 and device-check-passed handoffs' still apply. The ones that bit this session:

- **The simulator UDID changes between sessions and containers are not interchangeable.** Three
  handoffs in a row have now named a device that no longer existed by the next session. Re-discover
  with `xcrun simctl list devices booted`, then
  `xcrun simctl get_app_container <udid> Elias-Magdaleno.Manga-Reader data`. The bundle id is
  **`Elias-Magdaleno.Manga-Reader`** — guessing `com.eliasmagdaleno.*` fails.
- **`get_app_container` fails against a shut-down simulator** (`code=405 … current state: Shutdown`)
  even though the files are readable at their path. Boot it, or read the path directly.
- **Do not "clear state" by uninstalling** — it takes the Works with it, so the check then runs below
  Gate 1 and produces a confident negative that proves nothing. Delete
  `Library/Caches/anilist-pool.json` only.
- **`works.json` saves are debounced.** A read not followed by backgrounding the app may not be on
  disk when you look.
