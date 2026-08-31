# Handoff — ADR-0021 merged; docs and memory reconciled

> **STATUS 2026-08-30: consumed. Historical record — do not work from it.** Its "pick up from
> GitHub Issues" instruction was followed: the backlog held exactly one open issue, **#90**
> (manual VoiceOver traversal), and the session that picked this up built the checklist for it
> and fixed the code defects that checklist surfaced. See
> `2026-08-30-voiceover-accessibility-labels-handoff.md`. Everything below about ADR-0021 and
> the CI toolchain gap remains accurate.

Date: 2026-08-30
Repository: `/Users/eliasmagdaleno/Manga-Reader`
Branch: `main` (clean, pushed)

## State

ADR-0021 background library refresh is **done and merged**. Nothing is in flight; there is no
half-finished work to resume. This handoff exists to record what shipped and the three
corrections made after it.

- **PR #101** — ADR-0021 Tasks 1–8, squashed to `a24c3fd`, closed issue **#92**.
  Task 8 (seeded-simulator UI verification) turned out to be already implemented when the
  previous handoff was picked up, so it was *verified* rather than executed.
- Verification at merge: `Manga-ReaderTests` green, `UpdatesUITests` 5/5 with screenshot
  attachments (two at `AccessibilityXXXL`), strict SwiftLint clean, both CI checks green.
- Later commits on `main`: `be2a744`, `bdf8df3`, `f82c99c` (docs only, see below).

## The one thing that failed, and why it will again

`extension BGTask: @MainActor BGTaskLike {}` — an SE-0470 **isolated conformance**, Swift 6.2
only — compiled locally and failed CI with `error: unknown attribute 'MainActor'`.

**CI's toolchain is a major version behind this machine.** CI pins `macos-15` → Xcode 16.4 /
Swift 6.0; local is Xcode 26.x / Swift 6.2. A green local build is not CI evidence for anything
touching new concurrency syntax — isolated conformances, `nonisolated(nonsending)`,
`@concurrent`, `Task.immediate`. Fixed by boxing `BGTask` in a `@MainActor BGTaskBox` wrapper.
Now written into `CLAUDE.md`'s Commands section and the `ci-on-main` memory.

## Corrections made after the merge (all pushed)

1. **`CLAUDE.md` current state** (`f82c99c`) — "refreshing *content* is manual … nothing polls
   for new chapters" went false when #101 merged. Replaced with a Background refresh bullet.
   Third instance of this exact rot pattern in this repo; the mirror rule (grep the docs when
   you change a behaviour) is what catches it.
2. **`CLAUDE.md` commands** (`be2a744`) — records the CI/local Xcode gap above.
3. **The task-8 handoff** (`bdf8df3`) — banner-marked consumed, per the task-12 convention.

Memory was reconciled in the same pass (memory dir, not the repo): `ci-on-main` gained the
toolchain gap, `no-parallel-test-clones` was **reversed** (parallel sim clones are fine on the
M5 now — do not pass `-parallel-testing-enabled NO` locally; CI's own `NO` is unrelated and
stays), `ui-verification-technique` carried a second stale copy of that same rule,
and `flaky-live-network-ui-tests` now distinguishes the fixture-backed `UpdatesUITests` from the
live-network suites — a red run in the former IS signal.

## Two facts worth carrying

- **Branch protection on `main` does not stop this account.** `enforce_admins: false`, so a
  direct push reports `Bypassed rule violations` and lands, waiving both required checks. The
  user has chosen to keep it that way. Treat the PR flow as a convention and ask before pushing
  to `main`; a bad push will not bounce.
- **`UpdatesUITests` seeding pattern** (`-uitest-updates-state <empty|not-checked|refresh-complete|updates-filter>`)
  is the model for any future deterministic UI evidence: a DEBUG-only fixture with a local
  source and a fresh defaults suite / temp directory per state, so no test treats live source
  availability as a signal or inherits the seeded simulator's library or permissions.

## Suggested next work

Nothing is owed on ADR-0021. Pick up from GitHub Issues (`gh issue list`), which is where the
backlog lives — not from handoff docs.
