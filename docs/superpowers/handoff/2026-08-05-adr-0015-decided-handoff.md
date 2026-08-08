# Session Handoff — 2026-08-05: ADR-0015 decided, implementation not started

**Audience:** the next session. Supersedes `2026-08-04-adr-0011-merged-handoff.md` for **state**;
that file's *gotchas* still apply and are not repeated here except where they bit.

**Work in flight:** branch `foryou-rail-state`, one commit, **ADR only — no code**.

## State

| | |
|---|---|
| `main` | **`16c10cf`** — "Extract MALReverseResolver, and correct the record on what the golden proves (#33)" |
| Checked out | `foryou-rail-state` at `de3ce2b`, one commit ahead of `main`, clean |
| PR #33 | **merged** 2026-08-05, squash, remote branch deleted |
| Tests | **426 pass / 1 skipped** on `main` (417 + 9 new) |
| CI | both jobs green on #33 |

## What shipped this session

**`MALReverseResolver` (PR #33, merged).** ADR-0011's last parked item is discharged. Reverse
resolution — MAL id → openable MangaDex `Manga` — now has its own type owning `ReverseTarget`, the
cache-hit/miss partition, the bounded-concurrency search, and the batch fetch.
`MoreLikeThisProvider.resolve(works:limit:)` is gone, not shimmed; callers lost 162 lines and gained
22. Ordering, and only ordering, stayed with the callers.

**The correction that came out of it, which matters more than the refactor.** ADR-0011 and three
handoffs all said the extraction could be done "with the golden in place to prove nothing moved."
**That was false.** Every AniList test stubs `Resolve` (`AniListPoolTests.swift:315`, `:349`, `:390`)
and the MAL path stubs `SimilarTitlesProviding` — both safety nets inject *past* the extracted code,
which had zero coverage. It was private and called `MangaDexAPI` statics.

So the extraction carries its own net: `search`/`fetchByIds` are injected `@Sendable` closures
defaulting to the real endpoints, and `MALReverseResolverTests` (9 tests) pins the cache-write
discipline — `.resolved` / `.unresolved` / **nothing on a thrown search**. Recorded as a general
hazard in ADR-0011: *a fixture that stubs a dependency is a promise it does not execute that
dependency.*

## The technique worth reusing

**Mutation-check a test before trusting it.** Flipping `else if didSearch` to `else` in the resolver
failed exactly `testThrownSearchRecordsNothing` and `testOneThrownSearchDoesNotAffectItsSiblings`,
and nothing else — then it was restored. A green suite on new tests proves the tests *run*, not that
they would catch anything. Cheap, and worth doing whenever a test is the only guard on an invariant
whose failure mode is silent.

## Next: implement ADR-0015

**All design decisions are settled and written down.** `docs/adr/0015-accounting-for-an-absent-for-you-rail.md`
is the spec — read it first; this section is a checklist, not an argument. Three commits, one PR, no
stacking.

**1. Engine (tests first — it's pure decision logic).**

- `RecommendationEngine.RailState`: `.building`, `.needMoreReading(tagged:needed:)`,
  `.noTaggableSignal`, `.ready`. Published.
- `typealias TagBlocked = (WorkID) -> Bool`, init param defaulted to `{ _ in false }` — same shape
  as `PriorityPush` (`RecommendationEngine.swift:74`), so no existing construction site changes.
- `profileAndExclusions()` returns the refusal reason instead of `nil`. It has two callers
  (`:120`, `:131`); the grid ignores the state and still returns `[]`.
- `noTaggableSignal` = enough read Works to clear the threshold *if tagged*, and every untagged one
  currently blocked.
- **Assign `railState` before `rebuild()`'s `Task.isCancelled` check (`:122`) and on `load()`'s
  `loadedOnce` short-circuit (`:87-92`)** — otherwise a cancelled rebuild strands the UI on a stale
  explanation. Cover both with tests.
- `makeEngine` already exists at `Manga_ReaderTests.swift:1662` — use it, don't build a second
  harness.

**2. View.** `HomeView.swift:42` currently renders the rail only when non-empty. Add the
`noTaggableSignal` branch and nothing else — `building` and `needMoreReading` deliberately render
nothing. Copy is fixed in the ADR and was approved verbatim; the MangaDex mention is intentional.

**3. Composition root.** Wire `TagBlocked` to `UpgradeAttemptMemory.suppresses` in
`Manga_ReaderApp.init`. Note the queue owns the memory — check how it's reachable before assuming.

## Gotchas

The ADR-0011-merged handoff's gotchas all still apply. Specific to this work:

- **The `.agy_review_running` lock.** Wait on it before building or committing; a burst of commits
  gets one review, and a stale review file is not a broken hook.
- **`xcp` reformats the three synchronized-group entries**, and the reformat can vanish on its own
  if Xcode is open. Check `git diff --stat` immediately before `git add`, not right after `xcp`.
  This session's `xcp add-file` produced only 13 insertions, so it did not bite — do not conclude
  from that that it can't.
- **SourceKit reports phantom "Cannot find type" errors** for a newly added file in a synchronized
  group until a real build runs. They are index staleness, not compile errors. Confirm with
  `xcodebuild`, not the editor.
- **`@MainActor` test cases and `@Sendable` closures.** Fixtures called from inside a task group's
  child tasks must be file-scope functions, not `XCTestCase` methods, or they capture `self` across
  the isolation boundary. See the note in `MALReverseResolverTests.swift`.
- **`gh pr checks` can hang past a 2-minute tool timeout.** `gh pr view <n> --json statusCheckRollup`
  returns immediately and says the same thing.

## Open, recorded, not scheduled

Unchanged from the previous handoff except where noted:

- **`AniListPool.swift` type-checker timeouts** — two so far; ADR-0011's revisit trigger says a
  **third** means a house rule for the file, not a third local fix. A green local build does not
  predict a green CI one here.
- **The agy post-commit hook fix is machine-local** — `.git/hooks/` is not version-controlled.
- **SwiftLint warnings** in `ChapterListView.swift` and `HistoryView.swift` — pre-existing, job
  still passes. `MoreLikeThisProvider.swift:32` has one too (vertical parameter alignment on
  `topRecommendations`), also pre-existing and untouched by #33.
- **Widening `MoreLikeThis.pickMatch` to multiple titles** — still parked, deliberately. It changes
  matching behaviour, and #33's whole claim was that nothing moved. Tempting to fold into any future
  session touching `ReverseTarget`; don't, without its own before/after evidence.
- **The mixed-library hazard** (new, ADR-0015): three taggable Works alongside twenty untaggable ones
  clears the gate and builds a rail from an eighth of the reader's taste. Not addressed — the rail is
  present, so the failure is thin rather than silent.
