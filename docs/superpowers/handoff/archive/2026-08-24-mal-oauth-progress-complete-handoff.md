# Handoff — MAL OAuth and push progress complete

Session of 2026-08-24. There is **no active implementation task**. The MyAnimeList OAuth and
push reading-progress plan is complete and merged; this handoff file is the only uncommitted path.

## Repository state

- Branch: `main`
- HEAD: `13b8846` — `Verify MAL progress lifecycle on device (#85)`
- Local `main` matches `origin/main`; the merged implementation is clean, with only this new
  handoff file uncommitted.
- PR #85 was squash-merged on 2026-08-24 and its remote feature branch was deleted.
- The authoritative plan is
  `docs/superpowers/plans/2026-08-21-mal-oauth-progress.md`; all Task 12 boxes are checked.

## What shipped

- Optional MyAnimeList OAuth with Keychain-backed, account-bound credentials.
- Durable, monotonic, push-only reading-progress updates from genuine reader completions.
- Persistent coalescing outbox, retry/backoff, relaunch recovery, foreground draining,
  reauthorization handling, sync enable/disable, and sign-out cleanup.
- Settings presentations for signed-out, signed-in, refreshing, retrying, blocked, and
  reauthorization-required states.
- `PATCH` is the verified MAL list-update verb. The live verification advanced Horimiya from
  chapter 100 to 101, preserved its `reading` status, restored it to 100, and confirmed the
  restoration from a fresh process.
- Reader/library accessibility identifiers used by the lifecycle checks. The reader close button
  now has the VoiceOver label **Close reader**, fixing a real accessibility omission.

## Final verification

- Complete unit suite: 571 XCTest + 76 Swift Testing, 2 skipped, 0 failures.
- Focused final suites (`AppCompositionTests`, `MALProgressCoordinatorTests`, and
  `MALProgressOutboxTests`): 43 tests, 0 failures.
- SwiftLint: 42 warnings, 0 serious — unchanged repository baseline.
- PR #85 CI: **Build & unit tests** passed; **SwiftLint** passed.
- Five seeded iPhone 17 Pro lifecycle checks passed:
  1. signed-out reading remains unchanged and queues nothing;
  2. offline completion queues and survives a cold relaunch;
  3. disabling sync prevents queueing and re-enabling resumes it;
  4. sign-out removes the account and its queued work;
  5. foregrounding after eligibility retries persisted work (`retryCount` advanced 1 → 2).

## Important test details

- The lifecycle checks use the seeded stand-in MAL account plus `-uitest-mal-offline`; no request
  can mutate a real MAL account.
- The shared driver reads **Chainsaw Man chapter 97**. Chapters 230–232 were listed by MangaDex but
  had empty at-home page payloads during verification.
- Completion is edge-triggered. Repeat runs use the real chapter context-menu action
  **Mark as unread** before traversing page 1 through the last page.
- `-uitest-mal-reset-outbox` clears only the DEBUG stand-in account's queue on an initial launch.
  The relaunch persistence test intentionally omits it from the second launch.
- SwiftUI currently exposes the combined **Sync queue** accessibility element as a static text,
  so the UI tests match its semantic identifier across all XCTest element types.
- The live-write test's `MAL_LIVE_WRITE=1` gate works from an Xcode scheme, not from a shell
  environment passed to `xcodebuild` in this project. It must continue to fail closed.

## Deliberately unverified or unscoped

These are not blockers for the shipped feature:

- `PUT` was not tested; verified `PATCH` already answered the update-verb decision.
- Adding an entirely unlisted MAL title is unit-tested only.
- `skippedCount` is in-memory and does not survive launches; persisting it would require a newly
  scoped outbox change.
- The account-switch alert renders and is unit-tested, but triggering it with a real second MAL
  user was not exercised.
- A signed-in account with an empty queue shows no sync-summary line. Changing that UX is unscoped.

## What to do next

Do not continue the MAL implementation plan: it is finished. Start from a new issue or explicit
product decision. If work is requested on any item above, first define the desired behavior and
scope it independently rather than treating it as unfinished Task 12 work.
