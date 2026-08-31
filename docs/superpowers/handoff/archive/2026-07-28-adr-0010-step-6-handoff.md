# Session Handoff — 2026-07-28: ADR-0010 written, step 6 built, step 7 remains

**Audience:** a fresh session finishing the upgrade queue. Supersedes
`2026-07-26-adr-0009-steps-1-5-handoff.md`, whose steps 1–5 are all on this branch.

> **RESOLVED the same day, in the same session — step 7 shipped as `276abad`.** This file is
> kept as the record of *why* step 7 looks the way it does; everything below describes the state
> before that commit. Two things below are now known to be wrong:
>
> - **"Step 7 — not started"** is stale. It is done, with three tests in `Manga_ReaderTests.swift`
>   ("Engagement weight push"). It was built as written, with no deviations.
> - **The UI test is not a suspect.** `testChapterPreviewKeepsRailReachable` passes on this
>   branch (73.8s, 0 failures) *with the queue wired in*. The earlier failure was flaky. Treat
>   that test as a weak signal generally — it drives live MangaDex data over the network.

## State

| | |
|---|---|
| `main` | `a24fb3c` |
| **`adr-0009-work-weights`** | 8 commits, **unpushed, no PR**. Steps 1–6 + ADR-0010. |
| Step 7 | **not started** — the only thing left |

**267 unit tests pass, 0 failures** (iPhone 17, `-parallel-testing-enabled NO`). SwiftLint clean on
every changed file.

One UI test fails: `Manga_ReaderUITests.testChapterPreviewKeepsRailReachable` ("should have opened a
manga detail page"). It drives **live MangaDex data**, is not run by CI, and cannot be caused by this
branch — `MetadataUpgradeQueue` is referenced by nothing outside its own file until step 7. Not
investigated; verify against `main` before assuming it is ours.

## Read ADR-0010 before writing anything

`docs/adr/0010-upgrade-queue-drain-loop-and-wiring.md`. It came out of a grilling session and
**amends ADR-0009 in three places**, two of which are corrections rather than refinements: ADR-0009
as written shipped two permanent 2-second re-fetch loops. ADR-0009 now carries inline
`> **Amended by ADR-0010**` blockquotes at each site, so reading it alone is safe.

## What step 6 built

`Manga-Reader/Services/MetadataUpgradeQueue.swift` + `Manga-ReaderTests/MetadataUpgradeQueueTests.swift`
(19 tests, 0.35s, no wall-clock dependence).

Public surface — this is all step 7 touches:

```swift
@MainActor final class MetadataUpgradeQueue: ObservableObject {
    init(works: WorkStore, anilist: AniListAPI = .init(), rateLimiter: AniListRateLimiter = .init(),
         resolver: MALEntityResolver? = nil,   // nil ⇒ MALEntityResolver(store: .shared)
         memory: UpgradeAttemptMemory? = nil,
         idleInterval: TimeInterval = 60, now: @escaping () -> Date = Date.init,
         sleep: @escaping Sleep = ...)
    func setPriority(_ weights: [WorkID: Double])   // ← the engine pushes here
    func start()    // idempotent
    func stop()     // cancels without awaiting
    func flush()    // delegates to UpgradeAttemptMemory
}
```

`resolver` and `memory` are nil-defaulted rather than defaulted to the real thing because both are
`@MainActor` and a default argument is evaluated in a nonisolated context. Don't "tidy" this back.

Also changed: `AniListWork.hasContent` was added (`AniListAPI.swift`) and `WorkStore.apply` now reads
it instead of its own local binding. **One definition, two readers, on purpose** — see ADR-0010.

## Step 7 — the whole remaining task

Three edits, all in `Manga_ReaderApp.swift` unless noted.

1. **Construct it.** In `init()`, after `wk`, before the engine:
   `let queue = MetadataUpgradeQueue(works: wk)` → `@StateObject private var queue`.
   **Do not** add `.environmentObject(queue)` — it has zero `@Published` properties by ADR-0009, so
   a view that reached it could only misuse it.
2. **Push the weights.** `RecommendationEngine` gains
   `typealias PriorityPush = ([WorkID: Double]) -> Void` and an init param **defaulted to
   `{ _ in }`** so no existing test or construction site changes. Call it from
   `profileAndExclusions()` (`RecommendationEngine.swift:128-144`) **after** the gate at `:141` —
   not `rebuild()`, and not before the gate, which would overwrite a good ordering with a cold-start
   blank. App wires `pushPriority: queue.setPriority`.
3. **Lifecycle.** Extend the `scenePhase` block (`Manga_ReaderApp.swift:55-60`) to
   `.active → queue.start()`, `.background → queue.stop(); works.flush(); queue.flush()`, and
   **`default: break` — `.inactive` is not a stop signal** (a notification banner would otherwise
   tear down the pass's skip set several times a minute). Add `.task { queue.start() }` on
   `ContentView`, because `onChange` does not fire for the initial value.

Tests worth having: the push fires only above the gate; `.inactive` does not stop the loop. The
first is a `RecommendationEngine` test with a spy closure; the second may not be worth testing
through SwiftUI at all — judgement call.

**How it was settled:** the spy-closure tests were written (three of them, including one pinning
that "See all" pushes too, which is what holds the call in `profileAndExclusions` rather than
`rebuild`). The `scenePhase` behaviour was **not** tested — driving SwiftUI lifecycle from a unit
test buys a test of SwiftUI, not of us. `start()`'s idempotency, the part that actually matters
there, is already covered by `testStartingTwiceRunsOneLoop`.

## Gotchas

- **`agy` post-commit hook makes `git commit` take >2 minutes.** Use `run_in_background: true`.
- **SourceKit lies constantly here** — "No such module 'XCTest'", "Cannot find type 'WorkID' in
  scope". Judge only by `xcodebuild`.
- **`xcp` reformats the three `PBXFileSystemSynchronizedRootGroup` entries**, and unstably: Xcode
  rewrites them back on its own schedule if the project is open. Step 6's commit carries the ~27
  extra lines. Check `git diff --stat` immediately before `git add`. **Step 7 needs no new files**,
  so this should not come up again.
- **`memory.record` defaults `now:` to `Date()`.** The queue must pass its injected `now` — this was
  a real bug caught by tests, silent in production because wall clock and injected clock agree there.
- The queue's `loopTask` is `private(set) internal` **only** so tests can `await queue.loopTask?.value`.

## TDD note, stated honestly

Batches 1–3 each had a genuine red phase (6, 8 and 3 failing tests before any implementation). The
two merge tests are the exception: they passed on first run because `drainOnce` already followed
ADR-0010's order of operations from batch 1. They were earned by **mutation** instead — changing
`live.id` back to `work.id` fails exactly `testAnOutcomeAfterAMergeIsRecordedAgainstTheSurvivingWork`
and nothing else. If you touch that path, re-run that mutation.

Step 7 had the same shape once: `testAColdStartProfilePushesNothing` passed on its first run,
because at that moment nothing pushed at all — a test that cannot tell "correctly suppressed"
from "feature absent" is not yet a test. Its mutation is **moving `pushPriority(...)` above the
gate** in `profileAndExclusions()`; that fails it, and only it. Re-run it if you touch that guard.

## Not done, deliberately

- **`MyAnimeListDebugView.swift:138` builds `MALEntityResolver(store: EntityResolutionStore())`** —
  a fresh instance, frozen at launch, which is exactly the mistake ADR-0010's last decision exists to
  prevent. Harmless in a debug view, out of scope for this branch, worth a one-line drive-by
  sometime.
- Nothing has been pushed and there is no PR. The branch is 8 commits ahead of `main`.
