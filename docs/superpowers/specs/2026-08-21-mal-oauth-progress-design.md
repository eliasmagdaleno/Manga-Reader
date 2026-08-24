# MyAnimeList OAuth and push reading-progress design

**Status:** Approved
**Date:** 2026-08-21
**Approved:** 2026-08-21
**Research:** [Official MAL OAuth and manga-progress API research](../research/2026-08-21-mal-oauth-and-manga-progress-api.md)

## Goal

Add optional MyAnimeList sign-in and reliable, push-only chapter progress. The existing app stays
fully usable while signed out. A chapter genuinely completed in the reader may advance MAL; local
library maintenance never does. Automatic updates never intentionally lower remote progress.

V1 does not import a MAL list, synchronize the app's Library/History across devices, or expose
scores, reviews, favorites, social features, or reading-taste visualization.

## Product contract

These decisions are approved:

1. Synchronization is push-only. Reading one title's current MAL status before writing it is a
   safety check, not a list import.
2. When an absent title first receives eligible progress, add it explicitly as `reading`. A
   Settings toggle named **Automatically add new titles** controls this and defaults on after
   sign-in. With the toggle off, the event may still be queued so the worker can check whether the
   title already exists; if it is absent, the worker records the event as skipped without writing.
3. Only an incomplete-to-complete transition produced by `HistoryStore.record` is eligible.
   Single/batch mark-read, mark-all-below, mark-unread, deleting history, and clearing history do
   not mutate MAL.
4. Automatic updates are monotonic. They never deliberately decrease `num_chapters_read` and do
   not change an existing MAL list status. V1 does not offer a remote decrement action.
5. V1 never infers `completed`. Status is sent only when adding an absent title, where it is
   `reading`. MAL and source chapter totals can disagree, so completion deserves a later explicit
   product decision.

## Chapter-number mapping

MAL accepts only an integer `num_chapters_read`; the source model intentionally stores chapter
numbers as strings. The mapping is conservative and pure:

- Trim whitespace, then parse the entire value as a locale-independent nonnegative decimal.
- A positive whole number maps to itself: `12` becomes 12.
- A positive fractional number maps down to its completed whole-chapter floor: `12.5` becomes 12.
  Completing an extra between 12 and 13 must not claim chapter 13.
- Zero (`0`, `0.5`) produces no MAL progress. Negative values produce no progress.
- Specials, extras, ranges, blank values, and other nonnumeric labels produce no progress.
- Values outside Swift `Int` or MAL's eventual verified accepted range produce no progress.

One-shots numbered `1` therefore advance to 1; a source that labels its one-shot `0` does not sync
in v1. Unsupported labels remain ordinary local completions. Settings reports a count of skipped
events without interrupting the reader.

Coalescing uses the mapped integer, not completion count. This accepts that source numbering and
MAL's count can diverge; it is transparent and never guesses an ordering for named specials.

## Authentication

### Browser and callback

`MALAuthenticationSession` presents an `ASWebAuthenticationSession`. It generates a fresh,
cryptographically random 43–128 character verifier and state for every attempt. MAL currently
documents only `code_challenge_method=plain`, so challenge equals verifier; do not substitute
`S256` until MAL documents support.

The proposed callback is a registered custom URL such as `mangareader://oauth/mal`, handled by
the authentication session's callback scheme. It must be confirmed in MAL's developer console
before implementation. Universal links would require web infrastructure the project does not
have. PKCE and exact state comparison mitigate authorization-code interception and callback
spoofing; any missing/mismatched state, wrong scheme/host/path, missing code, duplicate callback,
or callback after cancellation fails closed.

MAL does not document denial/error callback fields. The callback parser recognizes standard
`error` and optional `error_description` values for a useful message but treats every callback
without a valid code and state as unsuccessful rather than relying on undocumented semantics.
User cancellation returns to signed out without an error banner.

### Token exchange and storage

Authorization-code exchange and refresh use form-encoded `POST` requests to MAL's token endpoint.
The registered redirect URI is supplied identically at authorization and exchange. A native app
must not claim a bundled client secret is confidential; client registration must be verified to
support a public client before shipping.

Access token, refresh token, token type, computed access expiry, and authenticated MAL user id are
stored as one versioned Keychain record using a device-only accessibility class. The account name
and picture are non-secret presentation cache data and may live beside the account model on disk.
No token, authorization code, verifier, or callback URL is logged.

Each token response's `expires_in` is authoritative because MAL's prose contradicts its example.
Apply a small refresh safety margin. A successful refresh is transactional: persist the complete
replacement token set first, then expose it to callers; never delete the previous record before
the new record is durable.

Refresh is single-flight. Concurrent callers await the same task. A request receiving a 401 may
join one refresh and retry exactly once; a second 401 requires reauthorization.

On first launch of an installation, an installation marker outside Keychain is compared with the
credential record. If the marker is absent, any surviving Keychain record is removed, preventing
an uninstall/reinstall from silently restoring account access. Local logout deletes credentials,
identity cache, account-bound outbox data, and deferred events. MAL publishes no remote revocation
endpoint, so the UI says **Sign out on this device**, not **Revoke access**.

### Account states and Settings UI

`MALAccountStore` exposes one explicit state:

- `signedOut`
- `authorizing` (cancelable)
- `signedIn(profile, syncEnabled, automaticallyAddsTitles)`
- `refreshing(profile)`
- `reauthorizationRequired(profile?, reason)`
- `error(message, previousStableState)` for a recoverable presentation/transport failure

Settings gains a **MyAnimeList** section:

- Signed out: short explanation and **Sign in**.
- Authorizing: progress indicator and **Cancel**.
- Signed in: user name/picture, **Sync reading progress**, **Automatically add new titles**,
  pending/failed/skipped summary, **Retry now**, and **Sign out on this device**.
- Refreshing: retain the signed-in presentation, disable destructive/repeated auth actions, and
  show a compact activity indicator.
- Reauthorization required: keep the pending count, explain that local reading is safe, and offer
  **Sign in again** or local sign-out.
- Recoverable error: inline, nonmodal message with retry. Reader screens never display sync
  banners or repeated toasts.

Sign-in remains optional. Turning **Sync reading progress** off stops draining and prevents new
events from entering the MAL outbox; it does not sign out. Existing queued events remain paused
and visible until sync is re-enabled or the user signs out.

## Completion capture and identity

`HistoryStore.record` already owns the durable local completion fact. While updating an existing
session entry, it compares `wasComplete` with the new `isComplete`; while inserting a session, it
compares false with the inserted value. Only `false -> true` invokes an injected synchronous,
network-free `ChapterCompleted` sink. Repeated last-page callbacks and rereads cannot create a
larger duplicate after coalescing.

A history entry is not itself a read chapter. Opening a chapter still creates an incomplete entry,
mints the Work, and enables resume/vertical-reader recording, but `HistoryStore.isRead` becomes true
only for a completed entry (`pageCount > 0 && page >= pageCount - 1`) or a manual read mark. Manual
marks remain deliberately excluded from the MAL completion sink. The seeded fixture currently has
18 history entries but only 14 completed entries; any test or metric on this path must preserve that
distinction rather than treating all 18 entries as read.

The sink receives the `Manga`, `Chapter`, mapped progress, completion time, and the `WorkID`
returned by `WorkStore.mint`. It persists before scheduling network work. It never performs OAuth,
Keychain, or network work on the reader path.

If the Manga/Work already carries a MAL id, the event enters the account-bound outbox keyed by MAL
id. Otherwise it enters a small deferred table keyed by `WorkID`, coalesced to the maximum mapped
progress. `MetadataUpgradeQueue` remains responsible only for metadata; after it learns an external
id it invokes an injected `workMetadataChanged(WorkID)` signal. The progress coordinator then
promotes any deferred event. Queue startup also rescans deferred records, so a missed in-process
signal cannot strand progress.

An unresolved Work is never title-matched independently by the progress subsystem. It waits for
the existing precision-biased resolution path. Permanent resolution misses remain deferred until
metadata changes or the user signs out; Settings counts them as **Waiting for a MAL match**.

## Durable outbox

`MALProgressOutbox` is a separate Application Support file, not `UserDefaults` and not part of
`MetadataUpgradeQueue`. Its protocol exposes narrow operations: enqueue/coalesce, next eligible
item, mark delivered, reschedule, block, promote deferred Work, clear account, and flush.

Each ready item contains only:

- authenticated MAL user id (account boundary);
- MAL manga id;
- maximum desired whole-chapter progress;
- earliest completion time and latest completion time;
- retry count, next-attempt date, and compact failure classification.

It does not persist access tokens, manga titles, source URLs, chapter titles, or page history.
Enqueue replaces the desired value only with `max(old, new)`. One hundred local completions for a
title can therefore produce one remote update. Writes are atomic and versioned. The app flushes
the outbox when backgrounded but performs no background network assertion in v1.

The drain is serial and idempotent. It starts when the scene becomes active, sign-in succeeds,
sync is enabled, an item is enqueued, or **Retry now** is tapped; it stops on background, logout,
sync disablement, or cancellation. Only one drain task and one request per MAL id may be active.

## Remote reconciliation and conflicts

Before each mutation, fetch that manga with authenticated `my_list_status` (and only the minimal
fields required). This is a per-title safety read, not library import.

1. If remote `num_chapters_read >= desired`, remove the item without writing.
2. If the title is absent and automatic addition is on, send `status=reading` and
   `num_chapters_read=desired`.
3. If the title is absent and automatic addition is off, remove the event as skipped and increment
   the visible skipped count. It must not retry forever.
4. If the title exists with lower progress, send only `num_chapters_read=desired`; preserve its
   `reading`, `completed`, `on_hold`, `dropped`, or `plan_to_read` status and every unrelated field.
5. Decode the returned list status and require its progress to be at least desired before removing
   the item. An unexpected lower result is retried/blocked rather than reported as delivered.

MAL exposes a setter with no compare-and-swap. A read followed by a write cannot strictly prevent
another client from advancing progress in the intervening instant. V1 guarantees that this app
never sends a value lower than the remote value it most recently observed; absolute cross-client
monotonicity is impossible under the published API and is stated as such in the design.

The official reference contradicts itself on `PATCH` versus `PUT`. **Resolved 2026-08-24: it is
`PATCH`**, measured against a known list entry under explicit approval, with the entry restored
and the restoration confirmed from a fresh process. Omitting `status` from the body preserves the
entry's existing status, which is the behaviour this design's minimal write depends on. The
transport still keeps the verb in one implementation point so a future contract change can be
re-measured the same way. See the Task 11b section of the research note.

## Failure and retry policy

- Cancellation and backgrounding: leave the item unchanged; do not count an attempt.
- Offline errors, connection loss, timeout, HTTP 408, 429, and 5xx: transient. Exponential backoff
  with jitter, beginning near one minute and capped at six hours. Honor a valid `Retry-After` if it
  is longer. Reset retry metadata when a higher desired progress coalesces into the item.
- HTTP 401/`invalid_token`: single-flight refresh and retry once. If refresh fails or the retried
  request is 401, enter `reauthorizationRequired`, pause the whole drain, and retain the outbox.
- HTTP 400 or 404 for one manga/update: permanent item failure; block that item and continue with
  other titles. Settings exposes its count and a retry-after-reauth/release path without showing
  raw response bodies.
- HTTP 403: pause the drain as an account/service-policy failure. MAL uses 403 for more than one
  condition and does not publish enough detail to safely discard an item.
- Decode errors and undocumented statuses: retain and back off as unknown failures, eventually
  surfacing them in Settings. Never spin.

A newly authenticated account must match the outbox's MAL user id before draining. If it differs,
the old account's queued data is deleted only after an explicit confirmation; it is never sent to
the new account.

## Interfaces and ownership

Production types are composed in `AppComposition`, with no new singleton:

- `MALAuthPresenting`: presents/cancels the web authentication session.
- `MALCredentialStore`: versioned Keychain load/save/delete.
- `MALTokenClient`: exchanges and refreshes tokens.
- `MALAuthenticatedClient`: identity read, per-title status read, and progress update.
- `MALAccountStore`: observable account state and user actions.
- `MALProgressOutbox`: persistent queue/deferred storage.
- `MALProgressCoordinator`: completion sink, identity promotion, and drain lifecycle.
- `Clock`, `Sleep`, and jitter sources: injected for deterministic retry tests.

The existing read-only `MyAnimeListAPI` and its client-id-only behavior remain unchanged for
entity resolution and recommendations. Authenticated operations live behind the new client
protocol so a token refresh cannot accidentally become a dependency of read-only discovery.

`Manga_ReaderApp` owns the account store and coordinator for the app lifetime, injects the account
store into Settings, starts both queues when active, and stops/flushes both when backgrounded.

## Verification

Unit tests use isolated defaults/directories, an in-memory credential store, a fake auth presenter,
scripted HTTP transport, deterministic clock/sleep/jitter, and never a live MAL account.

Required coverage:

- PKCE length/charset/uniqueness and plain challenge; authorization URL and exact redirect URI;
- callback success, mismatched/missing state, wrong URL, cancellation, duplicate callback, and
  standard error callback;
- token decoding uses `expires_in`; transactional replacement; single-flight refresh; one retry
  after 401; logout and reinstall-marker cleanup;
- every account state and Settings action;
- chapter mapping for whole, decimal, zero, negative, blank, special, range, overflow, and one-shot
  labels;
- exactly one event on incomplete-to-complete transition; no events from any manual read action;
- outbox persistence across reconstruction, max coalescing, account isolation, deferred promotion,
  flush/cancellation, and corrupted-file recovery;
- absent-title toggle behavior; preservation of every existing MAL status; stale remote progress
  suppresses a write; response verification;
- transient/permanent/auth failure classification, jittered backoff, `Retry-After`, pause/resume,
  and non-spammy summaries;
- `AppComposition` proves that History, WorkStore, upgrade queue, account store, outbox, and
  coordinator share the intended instances.

Before declaring implementation shipped, perform these external checks separately:

1. Inspect/register the native client and callback form.
2. Complete one real authorization, recording callback shape, scopes, and actual token lifetime
   without recording secrets.
3. Preview the exact list item, previous status/progress, candidate HTTP verb, and intended
   mutation; obtain explicit approval immediately before the write.
4. Verify the update verb and response, then restore the prior remote state if the test changed it.

## Open implementation gates

The design is complete enough to plan once approved, but implementation cannot be called complete
until these official-documentation gaps are tested safely:

- MAL developer-console support for the chosen native callback and public-client configuration;
- real denial/cancellation callback behavior and granted scope;
- actual `expires_in` from a real token response;
- supported list-update HTTP verb;
- any remote access-revocation workflow beyond deleting this device's credentials.
