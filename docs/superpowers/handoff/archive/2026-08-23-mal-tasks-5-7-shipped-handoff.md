# Handoff — MAL Tasks 5–7 built, Tasks 5 and 6 on `main`

Session of 2026-08-23 (evening). Tasks 5, 6, and 7 of the MAL OAuth plan are implemented
test-first. **Tasks 5 and 6 are merged; Task 7 is committed on a branch and not yet pushed.**
Nothing is blocked on a decision except the standing live-authorization and list-mutation gates.

## Resume here

1. **Push `mal-account-store` and open its PR** (Task 7, commit `1f94a68`, one commit off
   `main`, already rebased and CI-clean locally). Nothing else is pending on it.
2. Then **Task 8 — reconciliation and the serial drain** — is the next unstarted work, per the
   Task 8 checklist in `docs/superpowers/plans/2026-08-21-mal-oauth-progress.md`. It is the
   largest remaining task: per-title safety read, the five reconciliation rules in the spec's
   "Remote reconciliation and conflicts", jittered backoff, pause/resume, and one request per
   MAL id at a time.

## What landed

**Task 5 — token transport and single-flight refresh** (PR #73, merged as `c12b509`):

- `Services/MALTokenClient.swift` — `MALHTTPTransport` seam (`URLRequest -> (Data,
  HTTPURLResponse)`) plus a `URLSession` adapter. Expiry is computed from the runtime
  `expires_in` against an injected clock; a non-positive `expires_in` is rejected rather than
  stored as a token dead on arrival, and a reply missing either half of the token pair is
  malformed rather than half-adopted. No `MALTokenError` case carries a token or a body.
- `Services/MALTokenManager.swift` — an actor. Refresh is single-flight: concurrent callers
  await one task. The new set is **persisted before it is published**, so a failed save keeps
  the prior complete record and fails the refresh. A permanent refusal (400/401/403) deletes
  the record.

**Task 6 — the authenticated client** (PR #74, merged as `0b333ab`):

- `Services/MALAuthenticatedClient.swift` — identity, one title's `my_list_status`, progress
  update. No whole-list endpoint, and the static client-id-only `MyAnimeListAPI` is untouched.
- The update verb is injected and **has no default**, because MAL's reference contradicts
  itself; choosing it is Task 11's live verification, not a guess.
- One 401 refreshes and retries once via `MALTokenManager.accessToken(replacing:)`, so a burst
  of 401s costs one token request. A second 401, or a failed refresh, is
  `reauthorizationRequired`.
- `MALRequestFailure` classifies cancellation, offline/timeout, 408/429/5xx, 400/404, 403,
  decode failures, and undocumented statuses, carrying no response body. `Retry-After` is
  honored only as a positive number of seconds.

**Task 7 — account state and web authentication** (branch `mal-account-store`, unpushed):

- `Services/MALAccountStore.swift` — `@MainActor ObservableObject` with the spec's six states;
  `.error(message:previousStable:)` carries the state it interrupted.
- `Services/MALAuthenticationSession.swift` — `MALAuthPresenting`; `ASWebAuthenticationSession`
  and the anchor lookup stay in the production adapter. The sheet is ephemeral so a stale
  Safari session cannot decide who signs in.
- Sign-in reads the identity **before** persisting, so a failed identity fetch cannot leave a
  half-known account. Sign-out is local-only and deletes credential, profile cache, and that
  account's queue while leaving History/Library/Works untouched.
- A different MAL user id raises `pendingAccountSwitch`; the previous account's queue is
  deleted only on `confirmAccountSwitchDeletion()`. The queued-account marker therefore
  outlives sign-out, which is why `MALAccountPreferenceStore` has separate
  `loadQueuedAccountUserID`/`saveQueuedAccountUserID`.

## Verification

- **544 XCTest cases, 2 skipped, 0 failures**, plus **60 Swift Testing cases in 10 suites**
  (50 of them added this session), iPhone 17 Pro, `-parallel-testing-enabled NO`.
- `swiftlint lint`: 42 violations repo-wide, all pre-existing, **zero in any MAL file**.
- CI passed on both #73 and #74 before merge.

## Gotchas worth carrying

**Cancelling a caller does not cancel an unstructured `Task` it is awaiting.** Task 7's
sign-in joins a shared `Task` so a second tap cannot open a second web sheet — and the
cancellation test proved the cancel never reached it: the fake presenter's 10-second hang ran
to completion. The fix is `withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }`.
Any other "join the in-flight task" the drain grows in Task 8 needs the same treatment.

**The simulator's `Application failed preflight checks / Busy` is a flake, not a failure.**
Two consecutive runs failed that way with the code unchanged; `simctl` reported the device
already Shutdown, and the next run passed. **Do not erase the simulator** to clear it — the
seeded fixture lives in that app container.

**A rebase across parallel test files conflicts only in `project.pbxproj`, additively.** Each
branch registers its own test file with `xcp`; the resolution is to keep both sides, exactly as
in the 2026-08-21 handoff. Not a judgement call.

**Task N+1 usually needs Task N's types.** Branching Task 7 off `main` failed to compile
because Task 6 was still in an open PR. The working rhythm this session was: merge the green
PR, `git rebase main`, then continue — which also avoids the stacked-PR trap.

## State of the world

- `main` at `0b333ab`. PRs #73 and #74 merged; **no open PRs**. Branches `mal-token-transport`
  and `mal-authenticated-client` were deleted on merge; a `git fetch --prune` has been run.
- Local branches: `main`, `mal-account-store` (Task 7, unpushed), `worktree-helper`,
  `eliasmagdaleno/capricorn` (Orca workspace).
- Earlier in this session the three merged MAL worktrees and their branches were removed, and
  stale remote refs pruned.
- Nothing is wired into `AppComposition` yet — no MAL OAuth object is constructed at app
  startup. That arrives with Tasks 9/10 (`Manga_ReaderApp` lifecycle and the Settings section).

## Still gated

No real authorization and no MAL list mutation without Elias's explicit approval. Every test in
Tasks 5–7 uses a scripted transport and an in-memory credential store; nothing has contacted
MAL. The `PATCH` versus `PUT` question (Task 11) stays open, and `MALListUpdateVerb` has no
default until it is settled against a known list entry whose prior state is restored afterward.
