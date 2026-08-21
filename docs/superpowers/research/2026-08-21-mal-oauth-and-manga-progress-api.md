# MyAnimeList OAuth and manga-progress API research

**Checked:** 2026-08-21
**Scope:** official MyAnimeList sources only; no third-party wrappers or blog posts are used
as evidence. No authenticated or mutating request was made.

## Executive findings

- MAL's current OAuth guide documents only the Authorization Code Grant with PKCE. The
  authorization endpoint is `https://myanimelist.net/v1/oauth2/authorize`; authorization-code
  exchange and refresh both use `POST https://myanimelist.net/v1/oauth2/token` with
  `application/x-www-form-urlencoded` bodies. [Official OAuth guide](https://myanimelist.net/apiconfig/references/authorization#overview)
- MAL still documents **only `plain` PKCE**, not `S256`. A unique verifier is required for every
  authorization request, and both challenge and verifier must be 43–128 characters.
  [PKCE steps and limits](https://myanimelist.net/apiconfig/references/authorization#step-1-generate-a-code-verifier-and-challenge)
- The callback shown by MAL is the registered redirect URI with `code` and `state` query items;
  the client should verify `state`. MAL does not document denial/error callbacks or prescribe an
  iOS presentation mechanism. [Redirect step](https://myanimelist.net/apiconfig/references/authorization#step-5-myanimelist-redirects-back-to-the-client)
- The user identity probe is `GET https://api.myanimelist.net/v2/users/@me` with a bearer token.
  The base user model contains `id`, `name`, and `picture`.
  [Get my user information](https://myanimelist.net/apiconfig/references/api/v2#operation/users_user_id_get)
- The manga-list mutation route is
  `https://api.myanimelist.net/v2/manga/{manga_id}/my_list_status`. It adds an absent title or
  updates only supplied fields and returns the resulting manga-list status.
  [Update my manga list status](https://myanimelist.net/apiconfig/references/api/v2#operation/manga_manga_id_my_list_status_put)
- `num_chapters_read` is an integer. The official schema supplies no minimum, maximum, fractional
  mapping, total-chapter relationship, or automatic-completion rule. Decimal chapters and
  specials therefore cannot be represented faithfully by this field without a product mapping.
- The official documents contain important contradictions: access-token lifetime and the update
  endpoint's HTTP verb disagree within the docs. Runtime `expires_in` must be authoritative, and
  the mutation verb needs a controlled live verification before implementation is called done.
- MAL publishes no numeric rate quota, `429` contract, `Retry-After` behavior, or token-revocation
  endpoint in the current OAuth/API references. These remain explicit implementation gaps.

## 1. Authorization request

MAL documents this request shape:

```http
GET https://myanimelist.net/v1/oauth2/authorize
    ?response_type=code
    &client_id=CLIENT_ID
    &state=STATE
    &redirect_uri=REGISTERED_REDIRECT_URI
    &code_challenge=CODE_CHALLENGE
    &code_challenge_method=plain
```

[Official authorization request and parameter table](https://myanimelist.net/apiconfig/references/authorization#step-2-client-requests-oauth-2.0-authentication)

| Parameter | Official contract |
| --- | --- |
| `response_type` | Required; exactly `code`. |
| `client_id` | Required. |
| `state` | Recommended by MAL. The callback returns it and the client should verify it. |
| `redirect_uri` | Optional only when exactly one URI was pre-registered. When sent, it must exactly match a pre-registered URI. |
| `code_challenge` | Required; 43–128 characters. |
| `code_challenge_method` | Optional, defaults to `plain`; MAL says only `plain` is supported. |

The guide says to generate a **unique** verifier for every authorization request. Under the only
supported `plain` method, the challenge is not SHA-256 transformed; the verifier value is what is
carried as the challenge. Do not send `S256` unless MAL changes its official contract.

### Callback behavior that is documented

The successful redirect example is:

```http
HTTP/1.1 302 Found
Location: REGISTERED_REDIRECT_URI?code=AUTHORIZATION_CODE&state=STATE
```

MAL says an authorization code is normally nearly 1,000 bytes, so callback parsing and storage
must not assume a small value. It explicitly says the client should verify the returned `state`.
[Official callback response](https://myanimelist.net/apiconfig/references/authorization#step-5-myanimelist-redirects-back-to-the-client)

### Callback/documentation gaps

The official guide does **not** specify:

- the callback query for user denial or authorization-server errors;
- authorization-code lifetime, one-time-use behavior, or replay error details;
- whether custom URL schemes, universal links, or HTTPS callbacks are accepted for a native app;
- how multiple registered redirect URIs are selected beyond exact-match rules;
- `ASWebAuthenticationSession`, ephemeral browser sessions, or an iOS callback URL scheme;
- any required `scope` parameter in the authorization request.

The API reference associates authenticated user and manga-list operations with the
`write:users` scope, described as permission to see/modify basic profile information and user list
data, but the OAuth guide neither requests `scope` nor returns it in the sample token response.
[API authentication scheme](https://myanimelist.net/apiconfig/references/api/v2#section/Authentication)
That mismatch should be verified during a real authorization run; the client should not invent a
scope parameter absent from MAL's authorization guide.

## 2. Authorization-code exchange

Both documented client-authentication schemes post a form to:

```http
POST https://myanimelist.net/v1/oauth2/token
Content-Type: application/x-www-form-urlencoded
```

[Official code exchange](https://myanimelist.net/apiconfig/references/authorization#step-6-exchange-authorization-code-for-refresh-and-access-tokens)

The form parameters are:

| Parameter | Official contract |
| --- | --- |
| `client_id` | Optional with HTTP Basic client authentication; required when credentials are in the form body. |
| `client_secret` | Must not be in the form when using Basic; required in the form-body scheme only if that client has a secret. |
| `grant_type` | Required; exactly `authorization_code`. |
| `code` | Required callback authorization code. |
| `redirect_uri` | If it was included in the authorization request, it must be included identically here. It may be omitted only under MAL's one-pre-registered-URI-and-previously-omitted rule. |
| `code_verifier` | Required; 43–128 characters. |

MAL permits either:

1. HTTP Basic client authentication, with `client_id` as username and `client_secret` as password;
   the password is empty if the client has no secret; or
2. client credentials in the form body, omitting `client_secret` when that client has none.

The documentation therefore contemplates clients without a secret, but it does not explain how a
native/public client is registered without one. It also does not make a bundled native-app secret
confidential. Registration behavior is a gap to inspect in the developer console.

The documented successful JSON has:

```json
{
  "token_type": "Bearer",
  "expires_in": 2415600,
  "access_token": "ACCESS_TOKEN",
  "refresh_token": "REFRESH_TOKEN"
}
```

[Official token response](https://myanimelist.net/apiconfig/references/authorization#response-to-token-requests)

No `scope` field is shown.

## 3. Expiry, refresh, and revocation

### Documented refresh request

Refresh uses the same token endpoint and the same client-authentication choice:

```http
POST https://myanimelist.net/v1/oauth2/token
Content-Type: application/x-www-form-urlencoded

grant_type=refresh_token&refresh_token=REFRESH_TOKEN
```

`grant_type` and `refresh_token` are required. A successful refresh returns the same response shape
as the initial token exchange. [Official refresh flow](https://myanimelist.net/apiconfig/references/authorization#refreshing-an-access-token)

MAL further states:

- refresh may occur at any time;
- once a new access token is issued, the old access token is revoked automatically;
- the old refresh token remains usable until it expires, although MAL strongly recommends
  discarding it after a successful refresh; and
- an expired/invalid access token is represented as HTTP `401`, a
  `WWW-Authenticate: Bearer ... invalid_token` header, and JSON `{"error":"invalid_token"}`.

### Lifetime contradiction

The same official page gives three incompatible signals:

- its overview table says **access token: one hour**, **refresh token: one month**;
- its token-response example says `expires_in: 2415600` seconds, about 28 days rather than one
  hour; and
- its refresh prose says the expiration date of the "new token" is one month, without clearly
  distinguishing access from refresh token.

[OAuth overview lifetime table](https://myanimelist.net/apiconfig/references/authorization#overview),
[token response](https://myanimelist.net/apiconfig/references/authorization#response-to-token-requests),
[refresh prose](https://myanimelist.net/apiconfig/references/authorization#refreshing-an-access-token)

Consequently, the client must calculate access expiry from each received `expires_in` value (with
a safety margin) rather than hard-code one hour or one month. It must persist the replacement
refresh token before discarding the previous one.

### Revocation gaps

Neither the current OAuth guide nor API v2 reference publishes an end-user token revocation or
logout endpoint. The API License and Developer Agreement says MAL may revoke a Client ID at any
time and requires credentials to be kept secure, but that is application credential revocation,
not a user-facing token-revocation protocol.
[Official API License and Developer Agreement](https://myanimelist.net/static/apiagreement.html)

For design purposes, local logout can reliably delete local tokens; remote revocation cannot be
claimed until an official endpoint or account-console workflow is found. The documents also do
not state what refresh-token error proves permanent revocation versus expiry.

## 4. Authenticated user identity

The official identity operation is:

```http
GET https://api.myanimelist.net/v2/users/@me
Authorization: Bearer ACCESS_TOKEN
```

The path template is `/users/{user_name}`, but its parameter description says only `@me` can be
specified. It requires OAuth `main_auth` with `write:users`.
[Official user operation](https://myanimelist.net/apiconfig/references/api/v2#operation/users_user_id_get)

The base user schema contains:

- `id`: 32-bit integer;
- `name`: string;
- `picture`: URI string.

Optional requested fields include `gender`, `birthday`, `location`, `joined_at`,
`anime_statistics`, `time_zone`, and `is_supporter`. For a minimal Settings identity, `id` and
`name` are sufficient; `picture` should still be decoded defensively because the official example
omits it even though the schema marks it non-null.

## 5. Manga-list progress mutation

### Route and authorization

The official route is:

```text
https://api.myanimelist.net/v2/manga/{manga_id}/my_list_status
```

`manga_id` is an integer. The operation requires a bearer token with `write:users`; client-ID-only
authentication is not listed for this mutation. The request body is
`application/x-www-form-urlencoded`. On success it returns HTTP `200` and a `MangaListStatus`
object. [Official update operation](https://myanimelist.net/apiconfig/references/api/v2#operation/manga_manga_id_my_list_status_put)

The official description is important for push-only behavior: the operation adds an absent manga
to the user's list, updates an existing one, and changes only the fields supplied by the request.

### Supported update fields

No update field is marked required in the current OpenAPI schema.

| Form field | Documented type or values |
| --- | --- |
| `status` | String: `reading`, `completed`, `on_hold`, `dropped`, `plan_to_read` |
| `is_rereading` | Boolean |
| `score` | Integer, 0–10 |
| `num_volumes_read` | Integer |
| `num_chapters_read` | Integer |
| `priority` | Integer, 0–2 |
| `num_times_reread` | Integer |
| `reread_value` | Integer, 0–5 |
| `tags` | String in the update form; returned as an array of strings |
| `comments` | String |

The response model also contains `start_date`, `finish_date`, and `updated_at`, but the current
update request schema does not list `start_date` or `finish_date` as accepted fields.
[Update operation](https://myanimelist.net/apiconfig/references/api/v2#operation/manga_manga_id_my_list_status_put),
[manga-list status schema](https://myanimelist.net/apiconfig/references/api/v2#operation/users_user_id_mangalist_get)

### Numeric chapter constraints and gaps

The update schema says only that `num_chapters_read` is an integer. The response schema describes
it as "0 or the number of read chapters." It declares no `minimum`, `maximum`, integer format, or
relationship to the title's `num_chapters` value.

The official contract therefore does not answer:

- whether negative values are rejected;
- whether a value greater than MAL's known total is rejected or clamped;
- whether setting progress equal to a known total changes status to `completed`;
- how chapter `0`, decimal chapters such as `12.5`, specials, extras, or unknown-number chapters
  should map;
- whether `num_chapters_read` counts distinct chapters, numbered position, or the highest chapter
  label; or
- what default status an absent title receives if progress is supplied without `status`.

A conservative client contract is therefore a nonnegative whole number sent explicitly with the
desired status. The app's decimal/special-to-integer policy is a product rule, not something MAL's
API documentation resolves.

### HTTP verb contradiction

The embedded official OpenAPI document registers this operation under **`PATCH`**, but its
operation ID ends in `_put` and the official curl sample uses **`-X PUT`**. The rendered fragment
name likewise ends in `_put`.
[Official update operation and curl sample](https://myanimelist.net/apiconfig/references/api/v2#operation/manga_manga_id_my_list_status_put)

On 2026-08-21, unauthenticated/non-mutating probes of both `PATCH` and `PUT` reached MAL's bearer
validation and returned the same `401 invalid_token`; that does not reveal which method is the
supported mutation contract after authentication. A controlled, explicitly approved live test
with a known list item is required. Until then, the verb is an unresolved documentation defect.

## 6. Errors and rate limits

The API reference documents this common error format:

```json
{
  "error": "invalid_token",
  "message": "token is invalid"
}
```

and these common statuses:

| HTTP status | Official meaning |
| --- | --- |
| `400 Bad Request` | Invalid parameters |
| `401 Unauthorized` | `invalid_token`; expired or invalid access token, etc. |
| `403 Forbidden` | DoS detected, etc. |
| `404 Not Found` | No further common meaning documented |

[Official common error/status documentation](https://myanimelist.net/apiconfig/references/api/v2#section/Common-status-codes)

The update operation itself documents only a `200` response. It does not enumerate validation,
authorization, not-found, conflict, or throttling responses. On 2026-08-21, a read-only live call
to `/v2/users/@me` with a deliberately invalid bearer token returned `401`,
`WWW-Authenticate: Bearer error="invalid_token"`, and `{"error":"invalid_token"}`, consistent
with the OAuth guide. Calling it with no credentials returned `403` and
`{"message":"","error":"forbidden"}`, showing that clients should classify by HTTP status and
error code rather than depend on `message` being present or meaningful.
[Official live identity endpoint](https://api.myanimelist.net/v2/users/@me)

### Rate-limit gap

The official API reference does not document:

- a request quota or concurrency limit;
- `429 Too Many Requests`;
- `Retry-After` or rate-limit response headers; or
- whether throttling is per IP, user, token, or Client ID.

The official developer agreement reserves MAL's right to limit/restrict API data usage at any
time, prohibits circumventing limitations, and requires applications not to place an unreasonable
burden on MAL's servers. It does not publish a machine-readable retry contract or numeric limit.
[Official API License and Developer Agreement](https://myanimelist.net/static/apiagreement.html)

The durable outbox should therefore be prepared to treat `429` and `5xx` as transient if observed,
honor `Retry-After` when valid, and back off with jitter, but those behaviors are defensive client
policy—not a guarantee established by MAL's current documentation.

## 7. Decisions the official contract supports

These conclusions follow directly from the current MAL contract and the approved v1 product
direction:

- **Push-only is possible without list import.** The mutation operation adds or partially updates
  one title and returns its resulting status.
- **Adding an absent title as `reading` should be explicit.** Send both `status=reading` and the
  integer `num_chapters_read`; the docs do not promise an implicit status.
- **Monotonicity is client-owned.** MAL exposes a setter, not a monotonic increment operation, so
  the app must prevent stale queued values from lowering progress.
- **Local decimal/special chapters need an explicit mapping.** MAL provides only an integer count.
- **Credential refresh must be transaction-like.** Persist the newly returned token set before
  retiring the old one because refresh invalidates the old access token and MAL recommends
  discarding the prior refresh token.

## 8. Verification checklist before production implementation

These questions cannot be settled from the official documents and should remain visible in the
design/plan:

1. Register/inspect the native client and confirm its allowed redirect URI forms and whether it is
   issued or expected to use a client secret.
2. Complete one real authorization to confirm callback success, cancellation/denial parameters,
   granted scope behavior, token response fields, and actual `expires_in`.
3. With an exact mutation preview and explicit approval, verify `PATCH` versus `PUT` on a known MAL
   list entry, then restore the previous remote state if the test changes it.
4. Probe nonnegative integer boundaries only if needed and only against an approved test title;
   do not use a real account mutation merely to discover behavior that the app can avoid relying
   on.
5. Capture real transient/auth error bodies and any rate-limit headers opportunistically without
   deliberately generating abusive load.
6. Confirm the user-visible remote revocation path, if any; otherwise describe logout honestly as
   local credential deletion.

## Official sources

- [MyAnimeList OAuth 2.0 authorization guide](https://myanimelist.net/apiconfig/references/authorization)
- [MyAnimeList API v2 reference](https://myanimelist.net/apiconfig/references/api/v2)
- [MyAnimeList API License and Developer Agreement](https://myanimelist.net/static/apiagreement.html)

## 2026-08-21 — Task 0: developer-console inspection

Inspected the existing published client at <https://myanimelist.net/apiconfig> against the
Task 0 checklist. **The gate is open: no client secret is involved, so no backend token
exchange is required and the feature proceeds as designed.** Non-secret facts only; the
client ID is deliberately not reproduced here (it lives in the git-ignored
`Secrets.xcconfig`, and MAL's console states it must not be disclosed).

| Question | Answer |
| --- | --- |
| Client type | **`ios`** — a fixed value on the page, not a dropdown. MAL classifies this app as a native client. |
| Client secret | **None.** The page renders a Client ID row and no secret row at all. |
| `mangareader://oauth/mal` registered exactly | **Yes**, stored verbatim in *App Redirect URL* — custom scheme accepted, no host requirement, no trailing-slash rewrite. |
| Redirect URI count | **One.** The field notes multiple URLs are separated by line breaks; only this one is present. |
| Xcode URL type / callback scheme | **`mangareader`** — the Info.plist URL type must declare exactly this. |
| API status | `PUBLISHED`. |

### What this settles

- The registration gap identified earlier in this note is closed. MAL's docs contemplate
  clients without a secret but never explain how one is registered that way; the answer is
  that App Type `ios` simply is not issued a secret. Nothing confidential would ship in the
  binary, so the design's stop condition is not triggered.
- Because **exactly one** redirect URI is registered, `redirect_uri` is optional in the
  authorization request. Keep sending it anyway — it must match exactly when sent, and an
  explicit value stays correct if a second URI is ever added.

### Not answered by the console

- **PKCE `S256`.** The page says nothing about PKCE at all. The public documentation still
  specifies `plain` only, so the design's choice of `plain` with a fresh 43–128 character
  verifier per request stands unchanged; there is no new evidence either way.
- **Rate limits.** No published number on the API config page. The outbox retry/backoff
  policy therefore remains an engineering judgement, not a documented contract.

### Unrelated observation

*Commercial / Non-Commercial* is set to `commercial` while *Purpose of Use* is `hobbyist`.
That combination looks unintended and is worth a second look — it is an account/ToS matter,
not a technical blocker for this feature.

### Still gated

Task 0 unblocks implementation only. The `PATCH` versus `PUT` question (Task 11) remains
blocked on an explicitly approved live verification against a known list entry, with
restoration of its prior state.
