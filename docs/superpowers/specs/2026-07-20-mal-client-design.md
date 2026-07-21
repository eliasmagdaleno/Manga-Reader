# MyAnimeList Read-Only Client — Design

Date: 2026-07-20

## Context

The reading loop, multi-source abstraction, search, and an on-device (MangaDex-only)
recommendation engine are all shipped. The next goal is **cross-source recommendations**:
a "More Like This" tab on the manga detail page, and eventually a recommendation engine
that isn't limited to MangaDex. Neither is possible without a source-independent notion of
"this is the same manga," and MangaDex doesn't catalog every source's titles anyway.

MyAnimeList becomes the canonical identity/metadata backbone for that. This is a
**three-subsystem** piece of work, each meant to get its own spec:

1. **Read-only MAL client** ← *this spec*
2. Cross-source entity resolution (match a source's manga to a MAL id; MangaDex already
   exposes external-id links for most entries, so that direction is closer to free —
   scraped sources will need title-based matching)
3. "More Like This" UI + extending the recommendation engine past MangaDex-only

This spec covers only the client: enough to fetch MAL manga metadata, related manga, and
recommendations, plus a throwaway debug screen to verify it against the real API. No
entity-resolution logic and no production UI yet.

**Explicitly out of scope for the whole three-subsystem effort** (per roadmap discussion):
MAL OAuth / list-tracking / pushing reading progress, and the Paperback/Aidoku-style
hot-loadable extension system — neither is on the critical path for cross-source recs, so
both stay shelved.

## Decisions

- **MAL registration is commercial.** The app plans donations plus a Patreon tier gating
  early TestFlight access — a payment unlocking a benefit counts as monetization even
  though the app itself stays free, so the MAL app is registered commercial to avoid a
  ToS mismatch surfacing after the app has real users.
- **Namespace struct, not a stateful service.** `MyAnimeListAPI` mirrors `MangaDexAPI`'s
  shape (a namespace of `static` async methods over a private `request<T>` helper) rather
  than a class/singleton — it's stateless and read-only, same reasoning that keeps
  `MangaDexSource`/`WeebCentralSource` as separate adapters instead of a forced shared
  base. No code is shared with `MangaDexAPI`: the auth header and error type genuinely
  differ per source.
- **Client ID via gitignored xcconfig.** `Secrets.xcconfig` (already created, already
  gitignored) holds `MAL_CLIENT_ID`; the Xcode project reads it into the generated
  Info.plist as a build setting rather than a checked-in constant.
- **Testing matches the existing convention, not a new one.** `MangaDexAPI` has no
  network-mocking harness today — the established pattern in this codebase is unit-test
  the pure/decoding layer and verify live behavior manually (see the "no tap tool"
  convention). This client follows the same split: fixture-JSON decode tests, live
  verification via the debug screen.

## Design

### 1. Secrets wiring — `Secrets.xcconfig` (done) + `project.pbxproj` + Info.plist

- Add `Secrets.xcconfig` as the `baseConfigurationReference` for the app target's Debug
  and Release `XCBuildConfiguration` entries.
- Add build setting `INFOPLIST_KEY_MALClientID = $(MAL_CLIENT_ID)` so it flows into the
  `GENERATE_INFOPLIST_FILE = YES` generated Info.plist (the project has no static
  Info.plist file to hand-edit).
- Runtime read: `Bundle.main.object(forInfoDictionaryKey: "MALClientID") as? String`,
  sent as the `X-MAL-CLIENT-ID` header on every request. Empty/missing → throw
  `.missingClientID` immediately rather than let MAL bounce an opaque 401.

### 2. `MyAnimeListAPI` — `Models/MyAnimeListAPI.swift` (new)

Lands in `Models/`, a synchronized group — no `pbxproj` edits needed for the file itself.
Base URL: `https://api.myanimelist.net/v2` (matches `MangaDexAPI`'s pattern of a
hardcoded base URL constant inside the file; both v1 endpoints are `GET`-only).

```swift
struct MyAnimeListAPI {
    static func searchManga(title: String, limit: Int = 10) async throws -> [MyAnimeListManga]
    static func mangaDetail(id: Int) async throws -> MyAnimeListMangaDetail

    private static func request<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem]
    ) async throws -> T
}
```

- `searchManga` → `GET /v2/manga?q={title}&limit={n}&fields=alternative_titles,main_picture`.
  This is what entity resolution (subsystem 2) will call for sources with no direct MAL
  link.
- `mangaDetail` → `GET /v2/manga/{id}?fields=alternative_titles,synopsis,main_picture,genres,related_manga,recommendations`.
  `relatedManga` and `recommendations` are the fields "More Like This" (subsystem 3) will
  consume.
- `request<T>` mirrors `MangaDexAPI.request`'s shape (build `URLRequest`, decode with
  `.convertFromSnakeCase`, retry once on 429) but sends `X-MAL-CLIENT-ID` instead of no
  auth, and throws `MyAnimeListError` instead of `MangaDexError`.

### 3. DTOs

MAL's v2 API wraps referenced manga in a `{node: {...}}` envelope for list/relation
fields — model that shape explicitly rather than fighting it with custom decoding, same
spirit as `MangaDexAPI`'s small private wire-DTOs:

```swift
struct MyAnimeListManga: Decodable {
    let id: Int
    let title: String
    let mainPicture: MainPicture?

    struct MainPicture: Decodable { let medium: String?; let large: String? }
}

struct MyAnimeListMangaDetail: Decodable {
    let id: Int
    let title: String
    let synopsis: String?
    let mainPicture: MyAnimeListManga.MainPicture?
    let genres: [Genre]?
    let relatedManga: [Relation]?
    let recommendations: [Recommendation]?

    struct Genre: Decodable { let id: Int; let name: String }
    struct Relation: Decodable {
        let node: MyAnimeListManga
        let relationType: String
        let relationTypeFormatted: String
    }
    struct Recommendation: Decodable {
        let node: MyAnimeListManga
        let numRecommendations: Int
    }
}

private struct SearchResponse: Decodable {
    struct Entry: Decodable { let node: MyAnimeListManga }
    let data: [Entry]
}
```

### 4. Errors

```swift
enum MyAnimeListError: LocalizedError {
    case missingClientID
    case invalidResponse
    case decodingFailed
    case http(status: Int)
}
```

Same shape as `MangaDexError`; reuses the existing retry-on-429-once behavior for
consistency (MAL is known to soft rate-limit, and it's a few lines given the precedent
already proven for MangaDex).

### 5. Temporary debug screen

- `Views/MyAnimeListDebugView.swift` (new): a title search field, a results list from
  `searchManga`, tap-through to a raw dump of synopsis/genres/related/recommendations
  from `mangaDetail` for the tapped id.
- A `#if DEBUG`-gated row in `SettingsView` pushes it.
- `Views/` is not a synchronized group — add the new file's `PBXFileReference`,
  `PBXBuildFile`, group entry, and Sources-phase entry to `project.pbxproj` by hand,
  mirroring an existing `Views` file across all four sections.
- Explicitly commented as throwaway in the file header — deleted once the real "More
  Like This" UI (subsystem 3) ships.

## Explicitly deferred (YAGNI)

- Cross-source entity resolution (subsystem 2 — separate spec).
- "More Like This" UI and extending the recommendation engine past MangaDex (subsystem
  3 — separate spec).
- MAL OAuth, list-tracking, pushing reading progress.
- The hot-loadable extension/repo system (Paperback/Aidoku-style) — shelved per roadmap
  discussion, unrelated to this effort.
- Any caching of MAL responses — the debug screen makes requests on demand; caching is a
  question for when this is wired into real UI with real call volume.

## Testing

- Fixture-JSON decode tests for `SearchResponse` (unwraps `node` correctly) and
  `MyAnimeListMangaDetail` (present and absent `related_manga`/`recommendations`, since
  both are optional fields MAL omits when empty).
- `MyAnimeListError` mapping: missing client ID, non-2xx status, malformed JSON.
- No live-network stub tests, per the Decisions section above.

## Verification (end-to-end)

1. Build for iPhone 17 simulator; unit tests (existing + new) pass.
2. Confirm `Secrets.xcconfig` is genuinely excluded from git (`git status` shows it
   untracked, `git log -p` never touches it).
3. Live-drive: launch the app, open Settings → MAL Debug (debug builds only), search a
   known title (e.g. "One Piece"), confirm results render, tap one, confirm the
   synopsis/genres/related/recommendations dump renders without crashing — this is what
   proves the `node`-wrapper decoding matches the real API shape, not just the fixtures.
