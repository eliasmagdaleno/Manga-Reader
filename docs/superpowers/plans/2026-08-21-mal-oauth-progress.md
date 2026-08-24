# MyAnimeList OAuth and push reading-progress implementation plan

**Status:** Ready for implementation
**Date:** 2026-08-21
**Spec:** `docs/superpowers/specs/2026-08-21-mal-oauth-progress-design.md`
**Research:** `docs/superpowers/research/2026-08-21-mal-oauth-and-manga-progress-api.md`

## Goal

Ship optional MyAnimeList sign-in and durable, push-only, monotonic reading-progress updates.
Only a chapter completed in the reader is eligible. Manual read-state changes remain local, and
the app remains fully functional while signed out or while MAL is unavailable.

## Global constraints

- Pure SwiftUI/Foundation/AuthenticationServices/Security; no third-party dependencies.
- Preserve the existing read-only `MyAnimeListAPI` behavior used by discovery and resolution.
- All production dependencies are composed in `AppComposition`; add no global singleton.
- Tokens, codes, verifiers, and callback URLs must never be logged.
- New files under `Models/` and `Services/` compile through synchronized groups. A new file under
  `Views/` or `Manga-ReaderTests/` must be added with `xcp`; do not hand-edit the project unless
  `xcp` is unavailable.
- Every `xcodebuild test` command uses:
  `-destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO`.
- Unit tests use isolated storage and fake transports; they never use a real Keychain or MAL
  account.
- Stage only MAL feature files. Preserve unrelated skill/documentation changes.
- Live authorization and list mutation are separate approval gates. Never infer approval from
  approval of this plan.

## Intended module shape

```text
HistoryStore --ChapterCompleted--> MALProgressCoordinator --> MALProgressOutbox
       |                                  |                         |
       v                                  v                         v
   WorkStore <---- metadata signal -- MetadataUpgradeQueue    disk persistence
                                          |
                                          v
                                  MALAuthenticatedClient
                                          |
                           MALAccountStore / token refresh
                                          |
                                MALCredentialStore (Keychain)

SettingsView <------ observable account + sync summaries
Manga_ReaderApp ---- start / stop / flush lifecycle
```

## Task 0: Confirm the native-client boundary

This is a human/account gate and must happen before live authentication, but it need not block
pure unit-tested implementation.

**Evidence to record:** append a dated section to the research note; never record secrets.

- [x] Inspect the MAL developer console and confirm whether the existing client is a public/native
  client or expects a secret.
- [x] Confirm that `mangareader://oauth/mal` (or the final chosen URI) can be registered exactly.
- [x] Confirm the Xcode URL type/callback scheme that corresponds to the registered URI.
- [x] If MAL requires a confidential client secret in the shipped app, stop: do not embed it.
  Amend the design around a backend token exchange or decline the feature. *(Not triggered:
  App Type `ios` is issued no secret.)*
- [x] Record only client type, callback URI, and non-secret configuration outcome.

**Outcome (2026-08-24):** gate open. Console inspection recorded 2026-08-21 in the research
note; re-confirmed against the live console 2026-08-24, unchanged. App Type `ios`, no client
secret row, `mangareader://oauth/mal` registered verbatim as the sole redirect URI, status
`PUBLISHED`. The shipped `MAL_CLIENT_ID` was confirmed to be this same app by digest
comparison, without reproducing either value. The `mangareader` URL type now ships in
`Manga-Reader/Info.plist` and was verified in the built bundle.

## Task 1: Add pure progress mapping and completion events

**Files:**

- Add: `Manga-Reader/Models/MALReadingProgress.swift`
- Modify: `Manga-Reader/Services/HistoryStore.swift`
- Add test: `Manga-ReaderTests/MALReadingProgressTests.swift` (register with `xcp`)

**Interfaces:**

- `MALChapterProgress.map(chapterNumber: String) -> Int?`
- `ChapterCompletion` value containing `Manga`, `Chapter`, `WorkID`, mapped progress, and date
- injectable synchronous `HistoryStore.ChapterCompleted` sink, defaulting to a no-op

- [ ] Write mapping tests for whole numbers, whitespace, decimals, `0`, `0.5`, negative values,
  blank strings, named specials, ranges, locale commas, and overflow.
- [ ] Write HistoryStore tests proving the sink fires once on `false -> true`, does not fire on
  repeated last-page callbacks, and receives the Work id returned by `mint`.
- [ ] Prove that opening creates an incomplete history entry and mints its Work without making
  `isRead` true or emitting a MAL event. Keep "has an entry" distinct from "is read" throughout.
- [ ] Prove reopened/reread sessions cannot emit a larger duplicate unless their mapped progress
  is actually larger; downstream coalescing remains the final idempotency boundary.
- [ ] Prove single/batch `markRead`, `markUnread`, toggles, history deletion, and clear never call
  the sink.
- [ ] Keep the seeded-fixture expectation explicit: 18 history entries, 14 complete/read-through
  entries, and four mid-chapter entries. A result of 14 here is not a regression.
- [ ] Implement the pure mapper and the network-free completion callback.
- [ ] Run `MALReadingProgressTests` and the existing reading-position/history tests.

## Task 2: Build the persistent account-bound outbox

**Files:**

- Add: `Manga-Reader/Services/MALProgressOutbox.swift`
- Add test: `Manga-ReaderTests/MALProgressOutboxTests.swift` (register with `xcp`)

**Data:** versioned envelope with ready items keyed by `(malUserID, malMangaID)`, deferred items
keyed by `(malUserID, WorkID)`, and compact skipped/blocked summaries. Ready items contain desired
progress, first/latest completion dates, retry count, next attempt, and failure classification.

- [ ] Write tests for `max(old,new)` coalescing, distinct account isolation, distinct-title order,
  deferred Work coalescing, and promotion after a MAL id appears.
- [ ] Test reconstruction from disk, atomic replacement, flush, empty/missing file, unsupported
  envelope version, and corrupt-file quarantine rather than silent overwrite.
- [ ] Test delivered removal, transient reschedule, permanent block, skipped-absent accounting,
  and clearing exactly one account.
- [ ] Implement behind a narrow `MALProgressOutboxProtocol`; make the filesystem directory and
  clock injectable.
- [ ] Keep titles, URLs, chapter labels, tokens, and page history out of the persisted payload.
- [ ] Run the new suite twice, including a reconstruction round trip.

## Task 3: Implement OAuth values and callback validation as pure logic

**Files:**

- Add: `Manga-Reader/Services/MALOAuth.swift`
- Add test: `Manga-ReaderTests/MALOAuthTests.swift` (register with `xcp`)

- [ ] Define authorization request, token request/response, stored credential, and callback error
  values without importing SwiftUI.
- [ ] Inject secure random bytes and test verifier length, allowed URL-safe characters,
  uniqueness, and MAL's documented plain challenge (`challenge == verifier`).
- [ ] Test the exact authorization URL: response type, client id, state, redirect URI, challenge,
  and `code_challenge_method=plain`; do not invent a scope query until the live contract proves it.
- [ ] Test callback acceptance only for exact scheme/host/path, matching state, and one nonempty
  authorization code. Reject missing/mismatched state, wrong URL, duplicate completion, callback
  after cancellation, and malformed query items.
- [ ] Recognize standard `error`/`error_description` defensively, while treating cancellation as a
  distinct non-error outcome.
- [ ] Test form encoding for authorization-code exchange and refresh, including exact redirect URI
  and absence of a client secret for a verified public client.
- [ ] Run `MALOAuthTests`.

## Task 4: Add credential storage and reinstall protection

**Files:**

- Add: `Manga-Reader/Services/MALCredentialStore.swift`
- Add test: `Manga-ReaderTests/MALCredentialStoreTests.swift` (register with `xcp`)

- [ ] Define `MALCredentialStore` with load/save/delete and implement a Keychain-backed production
  adapter plus an in-memory fake.
- [ ] Store one versioned record containing token type, access token, refresh token, expiry, and MAL
  user id with a device-only accessibility class.
- [ ] Test transactional replacement: a failed save leaves the old complete record readable; a
  successful save exposes only the new complete record.
- [ ] Add an injectable installation marker store. On a new installation marker, delete any
  surviving credential before account restoration.
- [ ] Test first install, ordinary relaunch, simulated reinstall, corrupt record, logout deletion,
  and Keychain error presentation.
- [ ] Audit all debug descriptions and error paths to prove secrets are not interpolated.
- [ ] Run `MALCredentialStoreTests`.

## Task 5: Add token transport and single-flight refresh

**Files:**

- Add: `Manga-Reader/Services/MALTokenClient.swift`
- Add: `Manga-Reader/Services/MALTokenManager.swift`
- Add test: `Manga-ReaderTests/MALTokenManagerTests.swift` (register with `xcp`)

- [ ] Put URL loading behind a small async transport protocol using `URLRequest -> (Data,
  HTTPURLResponse)` so tests use scripted responses.
- [ ] Decode `token_type`, `access_token`, `refresh_token`, and runtime `expires_in`; calculate
  expiry from an injected clock with a named safety margin.
- [ ] Test malformed/negative expiry, missing replacement fields, server error bodies, transport
  errors, and cancellation.
- [ ] Implement actor-isolated single-flight refresh. Concurrent callers await one request and
  receive the same result.
- [ ] Persist the returned complete token set before publishing it. If persistence fails, keep the
  prior record and fail the refresh.
- [ ] Test proactive refresh near expiry, no refresh while comfortably valid, one refresh for many
  callers, old access-token retirement, and permanent refresh failure.
- [ ] Run `MALTokenManagerTests` with strict concurrency diagnostics from the project settings.

## Task 6: Add the authenticated MAL client

**Files:**

- Add: `Manga-Reader/Services/MALAuthenticatedClient.swift`
- Add test: `Manga-ReaderTests/MALAuthenticatedClientTests.swift` (register with `xcp`)

**Operations:** current user identity; one manga's `my_list_status`; update progress. Do not add a
whole-list endpoint to the v1 interface.

- [ ] Test bearer header, form encoding, minimal fields, snake-case decoding, absent
  `my_list_status`, and defensive optional picture handling.
- [ ] Keep the update verb in one injectable/configurable implementation point because MAL's
  official reference contradicts itself. Default only after Task 11's live verification.
- [ ] Test one refresh-and-retry after 401, joining the token manager's single flight; a second 401
  returns reauthorization-required.
- [ ] Classify cancellation, offline/timeout, 408, 429, 5xx, 400/404, 403, decoding failures, and
  unknown status without relying on a nonempty server message.
- [ ] Parse a valid `Retry-After` defensively but do not assume MAL always supplies it.
- [ ] Leave the existing static, client-id-only `MyAnimeListAPI` untouched.
- [ ] Run the new client tests plus existing `MyAnimeListAPITests`.

## Task 7: Build account state and web authentication presentation

**Files:**

- Add: `Manga-Reader/Services/MALAccountStore.swift`
- Add: `Manga-Reader/Services/MALAuthenticationSession.swift`
- Add test: `Manga-ReaderTests/MALAccountStoreTests.swift` (register with `xcp`)

- [ ] Implement the explicit states from the spec: signed out, authorizing, signed in, refreshing,
  reauthorization required, and recoverable error with a stable fallback.
- [ ] Wrap `ASWebAuthenticationSession` behind `MALAuthPresenting`; keep presentation-anchor lookup
  inside the production adapter and use a fake in tests.
- [ ] Test successful sign-in through identity fetch, user cancellation, callback rejection, token
  exchange failure, identity failure, repeated sign-in taps, and task cancellation.
- [ ] Persist only identity cache/preferences outside Keychain. Default progress sync and automatic
  addition on after first successful sign-in.
- [ ] Implement **Sign out on this device**: stop work, delete credential, identity cache, and the
  authenticated account's outbox/deferred data; preserve local History/Library/Works.
- [ ] Test reauthorization with the same account resumes retained work; a different MAL user id
  requires explicit confirmation before deleting the old account's queue.
- [ ] Run `MALAccountStoreTests`.

## Task 8: Implement reconciliation and the serial drain

**Files:**

- Add: `Manga-Reader/Services/MALProgressCoordinator.swift`
- Add test: `Manga-ReaderTests/MALProgressCoordinatorTests.swift` (register with `xcp`)

- [ ] Test the completion sink persists synchronously and never performs network work inline.
- [ ] Test signed-out and sync-disabled behavior explicitly. Signed-out completions remain local and
  do not become associated with a future unknown account; sync-disabled completions do not enter
  the outbox.
- [ ] For an existing MAL id, enqueue by account/manga id. For a missing id, enqueue deferred by
  account/Work id and promote when signaled or on startup rescan.
- [ ] Implement a single serial drain task with start/stop/flush and per-title idempotency.
- [ ] Test reconciliation rules: remote progress equal/higher drops without mutation; lower updates
  only progress; absent title adds `status=reading` only when automatic addition is on; absent plus
  toggle off records skipped; every existing status is preserved.
- [ ] Require the update response to report progress at least as high as desired before delivery.
- [ ] Implement exponential backoff with injected jitter, one-minute initial delay, six-hour cap,
  and longer valid `Retry-After`; a higher coalesced desired value resets retry metadata.
- [ ] Test cancellation does not increment attempts; 401 pauses for reauth; 400/404 block one item
  while others continue; 403 pauses the drain; unknown/decode failures back off without spinning.
- [ ] Test that a newly signed-in different user can never drain the prior user's items.
- [ ] Run the coordinator/outbox/client suites together.

## Task 9: Connect Work metadata promotion and app composition

**Files:**

- Modify: `Manga-Reader/Services/MetadataUpgradeQueue.swift`
- Modify: `Manga-Reader/Services/AppComposition.swift`
- Modify: `Manga-Reader/Manga_ReaderApp.swift`
- Modify: `Manga-Reader/Services/HistoryStore.swift`
- Modify: `Manga-ReaderTests/AppCompositionTests.swift`
- Modify: relevant existing upgrade/history tests

- [ ] Add an injected, default-no-op `workMetadataChanged(WorkID)` callback after WorkStore learns
  external ids. Do not give MetadataUpgradeQueue a progress/outbox dependency.
- [ ] Wire HistoryStore's completion sink and the metadata callback to one coordinator constructed
  in `AppComposition`.
- [ ] Expose the account store for environment injection; retain coordinator/token services for the
  app lifetime without making network-only objects observable.
- [ ] On scene active, start metadata and MAL drains. On background, stop MAL work before flushing
  outbox/history/works. Preserve the existing `.inactive` semantics.
- [ ] Expand AppComposition tests to prove all relevant objects share the intended store,
  coordinator, and callbacks; use temp storage and fake auth/network adapters.
- [ ] Run AppComposition, MetadataUpgradeQueue, WorkStore, HistoryStore, and coordinator tests.

## Task 10: Add the Settings account surface

**Files:**

- Modify: `Manga-Reader/Views/SettingsView.swift`
- Add if needed: `Manga-Reader/Views/MALAccountSettingsView.swift` (register with `xcp` because
  `Views/` is not synchronized)
- Add UI/unit tests as appropriate; register new test files with `xcp`

- [ ] Render all account states specified by the design using the existing Ink components and
  Settings section rhythm.
- [ ] Signed out: explanation and Sign in. Authorizing: progress and Cancel. Signed in: identity,
  sync and automatic-add toggles, pending/failed/skipped/waiting counts, Retry now, and device-only
  sign out.
- [ ] Refreshing preserves signed-in content with compact activity. Reauthorization keeps pending
  counts visible and offers Sign in again. Recoverable errors are inline and nonmodal.
- [ ] Add confirmation for signing into a different account when retained outbox data exists.
- [ ] Ensure Dynamic Type, VoiceOver labels/values, focus order, button traits, and reduced-motion
  behavior are correct. Never show raw server bodies or secrets.
- [ ] Add deterministic view-model/state tests. Add a small UI test only for wiring that cannot be
  proven below the UI.
- [ ] Build and inspect signed-out, signed-in, retry, reauthorization, and large-text states on the
  iPhone 17 Pro simulator.

## Task 11: Perform controlled live contract verification

This task mutates the user's MAL account. Stop immediately before the mutation and request explicit
approval with the exact preview.

- [x] Complete one real authorization only after Task 0. Record callback success/denial shape,
  granted scope behavior, and actual `expires_in` without recording secrets. *(2026-08-24:
  callback round-tripped, `Bearer`, `expires_in=2678400` — 31 days, not the documented hour.
  Signed-in Settings state rendered on device for the first time.)*
- [x] Select a MAL manga whose current list presence, status, and chapter progress are known.
- [x] Present: title/id, current remote values, candidate HTTP verb, exact fields/value to send,
  expected result, and restoration operation.
- [x] Obtain explicit approval immediately before sending the update.
- [x] Determine whether the supported verb is PATCH or PUT; capture only status/headers/sanitized
  response shape.
- [x] Restore the prior remote state if verification changed it and confirm restoration.
- [x] Lock the verified verb into `MALAuthenticatedClient` and update research/design with dated
  evidence. If neither verb works as expected, stop and revise the design.

**Outcome (2026-08-24):** **`PATCH`.** Verified against Horimiya (MAL 42451), which was
`reading` at 100 chapters; sent `num_chapters_read=101` with no `status` field, MAL echoed
`reading`/101, the entry was restored to 100, and a fresh process confirmed the restoration.
The `#if DEBUG` launch-argument harness used for this has been deleted.
`MALAuthenticatedClient.updateVerb` now defaults to `.patch` and `AppComposition.malUpdateVerb`
is gone. `PUT` was not tested — it would be a second mutation for no decision it would change.

## Task 12: Full verification and delivery

- [x] Run focused MAL suites first.
- [x] Run the complete unit suite (2026-08-24: 571 XCTest + 76 Swift Testing, 2 skipped, 0 failures):

  ```sh
  xcodebuild -scheme Manga-Reader \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -parallel-testing-enabled NO test
  ```

- [x] Run SwiftLint using the repository's existing CI-equivalent command (42 warnings, 0 serious — unchanged baseline).
- [ ] Build the app for the same destination and manually verify signed-out reading is unchanged.
- [x] **Render every account state on a device** — done 2026-08-24 via `-uitest-mal-state`
  (`testMyAnimeListSettingsStatesRender`, `testMyAnimeListSettingsAtAccessibilityTextSize`).
  Signed-in, refreshing, reauthorization-required, the account-switch alert, and the signed-in
  section at `AccessibilityXXXL` are all screenshotted and were inspected, not just asserted.
  Wiring `refreshing` needed an app change: the state had **no producer** — see
  `MALTokenManager.refreshDidChange`.
- [ ] Exercise offline completion, relaunch persistence, foreground retry, toggle disable/enable,
  logout cleanup, and reauthorization on the seeded iPhone 17 Pro.
- [x] Confirm no secrets appear in source control, build settings output, logs, screenshots, test
  fixtures, or failure descriptions.
- [x] Re-check `project.pbxproj` immediately before staging; discard only unrelated Xcode churn,
  never intentional `xcp` file entries.
- [x] Update README Deferred/current-state wording and add an ADR if implementation reveals a
  lasting architectural decision not already captured by the approved spec.
- [ ] Check `git diff --check`, inspect the exact staged paths, commit the scoped implementation,
  push the branch, and open a draft PR. Require SwiftLint and Build & unit tests to pass before
  marking it ready.

### Still unverified after Task 12

- **`PUT` as a list-update verb.** `PATCH` is verified and answers the question; a second
  mutation of a real account would have changed no decision.
- **Adding an unlisted title.** Unit-tested only — the Task 11 harness refused to write to an
  unlisted title by design.
- **`skippedCount` across launches.** In-memory, and the outbox stores no skipped item. If
  Settings must show it after a relaunch, that is an outbox change nobody has scoped.
- **The account-switch *trigger*.** Its presentation is now on screen, but reaching it for real
  needs a completed sign-in as a second MAL user; the trigger stays unit-tested.
- **The empty sync summary.** The signed-in section shows no summary line with an empty queue.
  That is now confirmed to be what it *does*; whether it is what it *should* do is unasked.

## Completion criteria

- Signed-out operation is unchanged.
- A genuine reader completion maps, persists, coalesces, and eventually advances MAL when eligible.
- Manual read-state actions cannot mutate MAL.
- Automatic writes preserve existing status and never deliberately lower observed remote progress.
- Restart, offline errors, rate limiting, token expiry, cancellation, backgrounding, and
  reauthorization do not lose queued progress or create retry spam.
- Credentials are Keychain-only, account-bound, locally removable, and absent from logs/tests.
- Every account state and retry/blocked/skipped state has a recoverable Settings presentation.
- Official-documentation gaps are either verified with approval or remain explicit blockers rather
  than hidden assumptions.
