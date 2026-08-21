# Handoff — MAL Task 1 shipped locally; durable outbox started

Session of 2026-08-21. Work continues only in the isolated worktree at
`/Users/eliasmagdaleno/Manga-Reader-mal-oauth` on branch `mal-oauth`.

## Resume here

1. Confirm the worktree is clean and `git branch --show-current` reports `mal-oauth`.
2. Read the research, spec, and plan named in the prior MAL handoff.
3. Continue Task 2 in `MALProgressOutbox.swift` and `MALProgressOutboxTests.swift` using the
   existing red-to-green seams. Do not start Task 3 until the complete Task 2 checklist passes.
4. Keep live authentication and any MAL list mutation gated. Task 0 still needs the developer
   console facts described below.

## Completed this session

### Task 1: chapter mapping and completion event

Commit `14c9521 Emit MAL progress on chapter completion` adds:

- `MALChapterProgress.map(chapterNumber:)`, accepting positive whole chapters and flooring positive
  decimal labels; zero, negative, blank, named, ranged, locale-comma, and overflow labels skip sync;
- `ChapterCompletion`, carrying the listing, chapter, minted `WorkID`, mapped progress, and date;
- an injected synchronous, default-no-op `HistoryStore.ChapterCompleted` sink;
- emission only on an incomplete-to-complete `HistoryStore.record` transition;
- no emissions from opening, repeated final-page callbacks, unmappable labels, manual read-state
  actions, deletion, or clear.

Verification: 7 MAL progress tests plus `ReadingPositionTests` and `WorkMintingTests` passed, 33
tests total, on iPhone 17 Pro with parallel testing disabled.

### Task 2: first two outbox slices

The current checkpoint commit adds the beginning of the durable outbox:

- an account-and-MAL-id keyed ready queue;
- max-progress coalescing with earliest/latest completion dates;
- account-isolated, deterministic `nextEligible` selection;
- atomic version-1 JSON persistence on enqueue;
- stale-safe `markDelivered`: an in-flight delivery cannot remove a higher value coalesced while
  the request was running.

Two focused outbox tests pass: max coalescing/account isolation and stale-safe delivery removal.

## Task 2 work still required

Follow the plan checklist, especially:

- reconstruction from disk and deterministic distinct-title order;
- deferred items keyed by `(MAL user id, WorkID)`, max coalescing, and promotion to a MAL id;
- retry rescheduling, higher-value retry reset, permanent blocking, skipped-absent accounting, and
  compact per-account summary;
- exact-account clearing and flush;
- missing/empty file behavior, unsupported envelope version, and corrupt-file quarantine;
- a narrow `MALProgressOutboxProtocol` used by the later coordinator;
- tests proving payloads never contain titles, URLs, chapter labels, tokens, or page history;
- run the outbox suite twice, including a reconstruction round trip.

The intended deep-module interface keeps encoding, versioning, key representation, atomic writes,
and quarantine inside the outbox. Caller-facing operations should remain enqueue/defer, next
eligible, delivery/reschedule/block, promotion, summary, clear-account, and flush. Preserve the
stale-attempt rule already established by `markDelivered` when adding reschedule/block: a result for
progress 12 must not overwrite retry state for a newly coalesced progress 15.

## External state and blockers

- PR #70 and PR #71 were both still open, mergeable, and green when checked this session. Nothing
  new was integrated into `mal-oauth`; `origin/main` remained `eb8a2de`.
- Task 0 remains a human/account gate: inspect the MAL developer console and record only whether
  the existing client is public/native, whether it expects a secret, and whether
  `mangareader://oauth/mal` can be registered exactly. If a shipped client secret is required, stop
  and revise the design around a backend exchange or decline the feature.
- Do not perform a real authorization or list update without the plan's explicit approval gates.
- SwiftLint is not installed locally (`swiftlint` was not found and Homebrew reported no installed
  formula). CI-equivalent lint therefore did not run locally; `git diff --check` was clean.

## Operational gotchas

- Work only in `/Users/eliasmagdaleno/Manga-Reader-mal-oauth`, not the shared primary checkout.
- `xcp` expands the three synchronized-root declarations in `project.pbxproj`; collapse only that
  formatting churn while retaining the four intentional entries for each new test file.
- Every test command uses iPhone 17 Pro and `-parallel-testing-enabled NO`.
- `Secrets.xcconfig` is an ignored symlink. Never stage it.
