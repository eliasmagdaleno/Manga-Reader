# Handoff — MAL Tasks 8–10 built, Tasks 8 and 9 on `main`

Session of 2026-08-23 evening into 2026-08-24. Tasks 8, 9, and 10 of the MAL OAuth plan are
implemented test-first. **Tasks 8 and 9 are merged; Task 10 is committed on a branch and not
yet pushed.** Nothing is blocked on a decision except the standing gates — and those gates
are now the only thing left between this feature and shipping.

## Resume here

1. **Push `mal-settings-account` and open its PR** (Task 10, commit `c85b632`, one commit off
   `main`). CI-clean locally; nothing else is pending on it.
2. Then the remaining plan tasks are **all gated on Elias**, in this order:
   - **Task 0** — the MAL developer console: confirm the client is public/native (no secret),
     that `mangareader://oauth/mal` can be registered *exactly*, and add the matching Xcode
     URL type. Until this is done, sign-in fails at the callback and none of Task 10's other
     states can be reached.
   - **Task 11** — one controlled live authorization, then the `PATCH` vs `PUT` verification
     against a known list entry, with prior state restored. This mutates the account: stop and
     present the exact preview before sending.
   - **Task 12** — full verification and delivery.

There is **no further unit-testable work** in the plan. Everything that can be built without an
account is built.

## What landed

**Task 8 — reconciliation and the serial drain** (PR #76, merged as `d48c606`):

- `Services/MALProgressCoordinator.swift`. The completion sink is synchronous and network-free;
  signed out or with sync off it queues nothing, so a completion can never become a future
  account's update. No MAL id → deferred by `WorkID`, promoted on `workMetadataChanged`.
- The drain is one serial task — concurrent callers join the pass in flight, so only one request
  per MAL id is ever open. The signed-in user id is re-checked each iteration.
- All five reconciliation rules from the spec, and delivery requires the returned status to
  report progress ≥ desired.
- Backoff 60s → ×2 → 6h cap, jitter injected, longer `Retry-After` wins. Cancelled = no attempt;
  400/404 blocks one item and the rest drain; 401 and 403 pause and retain the queue.
- `MALProgressDelivering` and `MALSyncAccount` are the two seams; `MALAuthenticatedClient` and
  `MALAccountStore` conform.

**Task 9 — metadata promotion and app composition** (PR #77, merged as `2658c3b`):

- `MetadataUpgradeQueue` gained an injected, default-no-op `workMetadataChanged(WorkID)`, fired
  after the MAL id is written and carrying the **survivor** of any merge. The queue gained no
  progress dependency.
- `AppComposition` builds the MAL stack once and wires `HistoryStore`'s completion sink *and*
  the queue's signal to that one coordinator. Three nil-defaulting seams (`malCredentials`,
  `anilist`, `malResolver`) let tests build the real graph.
- `Manga_ReaderApp` restores the account at launch, starts the drain on `.active`, stops it
  before the flushes on `.background`. `.inactive` is still not a stop signal.

**Task 10 — the Settings account surface** (branch `mal-settings-account`, unpushed):

- `Models/MALAccountPresentation.swift` — `MALSyncSummary`, `MALSyncToggles`,
  `MALAccountSection`, and `make(state:summary:toggles:)`. Six states plus an error wrapping any
  of them is more branching than a view body should carry, so it is decided here and tested.
- `MALAccountStore` gained the published `syncSummary`, `syncActivityChanged(skipped:)` (a new
  `MALSyncAccount` requirement the drain calls after each item), and `retryNow()`.
- `Views/MALAccountSettingsView.swift` (registered with `xcp`) plus one line in `SettingsView`.

## Verification

- **571 XCTest cases, 2 skipped, 0 failures**, plus **70 Swift Testing cases in 12 suites**,
  iPhone 17 Pro, `-parallel-testing-enabled NO`.
- `swiftlint lint`: zero violations in any MAL file.
- CI passed on #76 and #77 before merge.
- One UI test (`testSettingsShowsTheSignedOutMyAnimeListSection`) proves the section is in
  `SettingsView` and reaches the store through the environment; its screenshot was inspected.

## Open decisions Elias should look at

**`AppComposition.malUpdateVerb` is `.patch`, unverified.** The graph needs a verb to compile.
It is the single point Task 11 changes and cannot fire without a signed-in account — but it is a
guess sitting in production code.

**`AppComposition.malRedirectURI` is `mangareader://oauth/mal`, unregistered.** The plan's
proposed string. Task 0 has not confirmed it against the developer console, and the Xcode URL
type does not exist yet.

**`skippedCount` is in-memory, not persisted.** The outbox has no skipped storage and a skipped
title is dropped rather than stored, so the count resets on relaunch. If Settings must show it
across launches, that is an outbox change nobody has scoped.

**Only the signed-out Settings state has ever been rendered.** Signed-in, refreshing,
reauthorization, and the account-switch alert are covered by presentation tests but have never
been seen on a simulator, because reaching them needs a real sign-in. The plan's "inspect
signed-in, retry, reauthorization, and large-text states" checkbox is **not** ticked.

## Gotchas worth carrying

**The drain loop only runs after an explicit `start()`.** A completion recorded while
backgrounded is queued but starts no network work of its own. This was a deliberate change made
while writing Task 8's tests — auto-starting from the sink made every test race against a
background loop that advanced the injected clock. If a future test sees a mysteriously advanced
clock, this is why.

**`MALProgressOutbox.nextEligible(userID:at:)` respects `nextAttemptAt`, and a freshly enqueued
item's `nextAttemptAt` is its `completedAt`.** Three Task 8 tests failed for one boring reason:
they queued a second item at `now + 1` and then drained at `now`. Advance the test clock, or
queue at the same instant.

**Cancelling a caller does not cancel an unstructured `Task` it awaits.** Carried forward from
the 2026-08-23 handoff and now applied in two more places — `MALProgressCoordinator.drain()` uses
`withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }`, same as sign-in.

**Retry now needed a weak handle, not a closure over a `var`.** `MALAccountStore` needs the
coordinator; the coordinator needs the store. `AppComposition.MALDrainHandle` holds it weakly so
the graph has no cycle. A closure capturing a local `var` would have worked and would have
retained both forever.

**`xcp` behaved.** Two `add-file` calls this session, both 4-line `project.pbxproj` diffs with no
synchronized-group reformat. Still check `git diff --stat` immediately before `git add` — the
CLAUDE.md warning stands, this session simply did not trip it.

## State of the world

- `main` at `2658c3b`. PRs #76 and #77 merged; **no open PRs**; both branches deleted locally
  and remotely.
- Local branches: `main`, `mal-settings-account` (Task 10, unpushed), `worktree-helper`,
  `eliasmagdaleno/capricorn` (Orca workspace).
- The MAL objects are now constructed at app startup (Task 9), and the account store is in the
  environment. Nothing contacts MAL until someone signs in.

## Still gated

No real authorization and no MAL list mutation without Elias's explicit approval. Every test in
Tasks 8–10 uses a scripted transport, a deterministic clock, and an in-memory credential store;
nothing has contacted MyAnimeList. `MALListUpdateVerb` still has no default in the client itself —
only `AppComposition` names one, and that name is what Task 11 replaces with a verified answer.
