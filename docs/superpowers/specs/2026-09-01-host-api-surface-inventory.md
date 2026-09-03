# Host API surface inventory

**Date:** 2026-09-01
**Status:** Research input, not a design
**Verified against:** `4f6e140`

This document inventories the source-facing behavior present in the code. It does not choose a
JavaScript API, extension format, compatibility policy, or final capability surface. The substrate
and built-in MangaDex boundary belong to
[ADR-0003](../../adr/0003-extension-substrate.md); the meanings of **Work**, **Listing**,
**Fulfillment**, **Source**, **Extension**, and **Host API** belong to the
[glossary](../../glossary.md). This document uses those terms without redefining them.

## 1. What `WeebCentralSource` consumes

### Host service dependency

`WeebCentralSource` receives one `SourceContext` at construction and reaches only its `webView`
member. `SourceContext` itself currently contains only a `WebViewExtracting` value
(`MangaCarta/Models/WeebCentralSource.swift:29-34`,
`MangaCarta/Services/SourceContext.swift:16-22`). Every network-backed operation calls the same
generic Swift method:

```swift
extract<T: Decodable>(from url: URL, script: String, as type: T.Type) async throws -> T
```

The arguments are a fully constructed `URL`, a JavaScript source string, and a Swift metatype for
the expected decoded result; the return is that decoded `T`
(`MangaCarta/Services/SourceContext.swift:13-18`). This generic/metatype shape describes the
current Swift seam, not necessarily a JavaScript-callable shape.

### Calls, wire shapes, mapping, and failure behavior

| Source operation | Request and extraction input | Decoded output and mapping | Failure behavior |
|---|---|---|---|
| `search(title:limit:offset:)` | Builds `/search/data` with `sort=Best Match`, `display_mode=Full Display`, decimal `limit`/`offset`, and a nonempty `text`; then uses the series-list script (`MangaCarta/Models/WeebCentralSource.swift:38-40`, `MangaCarta/Models/WeebCentralSource.swift:108-121`). | Expects an array of `{id: String, title: String, cover?: String}`. The script drops rows missing an id or title and resolves relative covers against the loaded page; Swift maps each remaining row to a Listing-shaped `Manga`, with empty description, `unknown` status, no year or MAL id, and a cover only when its string forms a `URL` (`MangaCarta/Models/WeebCentralSource.swift:96-105`, `MangaCarta/Models/WeebCentralSource.swift:134-138`, `MangaCarta/Models/WeebCentralSource.swift:168-188`). | URL construction is non-failable because it starts from a constant valid base. Extraction errors propagate unchanged. A malformed optional cover is silently converted to `nil`; malformed/missing rows are silently filtered by the script (`MangaCarta/Models/WeebCentralSource.swift:38-40`, `MangaCarta/Models/WeebCentralSource.swift:96-105`, `MangaCarta/Models/WeebCentralSource.swift:175-186`). |
| `popular(limit:offset:)` | Uses the same `/search/data` path and script with no `text` and `sort=Popularity` (`MangaCarta/Models/WeebCentralSource.swift:42-44`, `MangaCarta/Models/WeebCentralSource.swift:108-121`). | Same series-list wire shape and `Manga` mapping as search (`MangaCarta/Models/WeebCentralSource.swift:96-105`, `MangaCarta/Models/WeebCentralSource.swift:134-138`). | Same propagation and silent row/cover loss as search (`MangaCarta/Models/WeebCentralSource.swift:96-105`, `MangaCarta/Models/WeebCentralSource.swift:175-186`). |
| `newTitles(limit:offset:)` | Uses the same `/search/data` path and script with no `text` and `sort=Recently Added` (`MangaCarta/Models/WeebCentralSource.swift:46-48`, `MangaCarta/Models/WeebCentralSource.swift:108-121`). | Same series-list wire shape and `Manga` mapping as search (`MangaCarta/Models/WeebCentralSource.swift:96-105`, `MangaCarta/Models/WeebCentralSource.swift:134-138`). | Same propagation and silent row/cover loss as search (`MangaCarta/Models/WeebCentralSource.swift:96-105`, `MangaCarta/Models/WeebCentralSource.swift:175-186`). |
| `latestUpdates(limitTitles:language:offset:)` | Ignores `language`, converts the item offset to a 1-based page as `offset / limitTitles + 1` (or page 1 when the limit is not positive), loads `/latest-updates/{page}`, and runs the updates script (`MangaCarta/Models/WeebCentralSource.swift:50-56`). | Expects an array of `{mangaId: String, chapterId: String, title: String, cover?: String}`. The script drops entries missing either id or title and resolves relative covers. Swift truncates to `limitTitles` and maps each entry to `MangaUpdate`; the embedded `Manga` uses the same sparse mapping as list results (`MangaCarta/Models/WeebCentralSource.swift:57-59`, `MangaCarta/Models/WeebCentralSource.swift:103-105`, `MangaCarta/Models/WeebCentralSource.swift:153-158`, `MangaCarta/Models/WeebCentralSource.swift:250-271`). | Extraction errors propagate. Invalid optional covers become `nil`; incomplete DOM entries are silently filtered. A negative `limitTitles` reaches `prefix(_:)`, whose precondition is nonnegative, because this method performs no input validation (`MangaCarta/Models/WeebCentralSource.swift:50-59`, `MangaCarta/Models/WeebCentralSource.swift:257-270`). |
| `mangaDetail(id:)` | Loads `/series/{id}` and runs the detail script (`MangaCarta/Models/WeebCentralSource.swift:62-65`). | Expects `{description?: String, authors: [String], tags: [String], adult?: Bool}`. DOM absence becomes an empty/nil value in the script. Swift turns tag names into `Tag` values with empty id/group, defaults description to `""`, and maps `adult == true` to `erotica`, everything else to `safe` (`MangaCarta/Models/WeebCentralSource.swift:65-71`, `MangaCarta/Models/WeebCentralSource.swift:140-145`, `MangaCarta/Models/WeebCentralSource.swift:190-216`). | Extraction errors propagate. Missing adult evidence is treated as safe rather than unknown; missing description becomes empty. Missing required `authors` or `tags` keys is a decode failure because those DTO fields are non-optional (`MangaCarta/Models/WeebCentralSource.swift:65-71`, `MangaCarta/Models/WeebCentralSource.swift:140-145`). |
| `chapters(mangaId:)` | Loads `/series/{mangaId}/full-chapter-list` and runs the chapter script (`MangaCarta/Models/WeebCentralSource.swift:74-77`). | Expects an array of `{id: String, title: String, date?: String}`; the script drops only rows without an id. Swift derives the displayed number from the last numeric token (or `?`), retains the title, and parses fractional or plain ISO-8601 dates, returning `nil` for missing/empty/invalid dates (`MangaCarta/Models/WeebCentralSource.swift:78-79`, `MangaCarta/Models/WeebCentralSource.swift:124-129`, `MangaCarta/Models/WeebCentralSource.swift:147-151`, `MangaCarta/Models/WeebCentralSource.swift:218-238`, `MangaCarta/Models/MangaDexAPI.swift:204-214`). | Extraction errors propagate. Missing `title` causes decoding to fail even though the script filters only on id. An unparseable title/date degrades to `?`/`nil` rather than throwing (`MangaCarta/Models/WeebCentralSource.swift:78-79`, `MangaCarta/Models/WeebCentralSource.swift:124-129`, `MangaCarta/Models/WeebCentralSource.swift:147-151`, `MangaCarta/Models/WeebCentralSource.swift:225-236`). |
| `pageURLs(chapterId:preferDataSaver:)` | Ignores `preferDataSaver`, loads `/chapters/{chapterId}/images?reading_style=long_strip`, and runs the pages script (`MangaCarta/Models/WeebCentralSource.swift:82-86`). | Expects `[String]`. The script reads `src`/`data-src`, drops absent attributes, and resolves relative values against the page; Swift then drops any string that cannot initialize a `URL` (`MangaCarta/Models/WeebCentralSource.swift:86-87`, `MangaCarta/Models/WeebCentralSource.swift:240-248`). | Extraction errors propagate. Missing DOM images and malformed returned URLs are silent omissions, including the possibility of a successful empty page list (`MangaCarta/Models/WeebCentralSource.swift:86-87`, `MangaCarta/Models/WeebCentralSource.swift:240-247`). |

`webURL(forManga:)` does not consume a host capability: it synchronously appends
`series/{id}` to the compiled-in base URL (`MangaCarta/Models/WeebCentralSource.swift:90-92`).
Likewise, URL construction, chapter-number parsing, DTO-to-domain mapping, and the extraction
scripts all execute inside the compiled source today rather than through `SourceContext`
(`MangaCarta/Models/WeebCentralSource.swift:94-167`).

### Failure behavior supplied by the host service

The shared extractor serializes all extractions through one WebView. It checks cancellation after
waiting for that serialization lock and again after page load, but the second check runs only on
the branch that detected a challenge and before presenting that challenge. The navigation,
challenge, and JavaScript waits use checked continuations rather than cancellation handlers. A
cancelled challenge-free load can therefore continue into script evaluation; cancellation during
an already-presented challenge or a pending script does not itself resume the wait
(`MangaCarta/Services/WebViewService.swift:94-114`,
`MangaCarta/Services/WebViewService.swift:130-159`,
`MangaCarta/Services/WebViewService.swift:161-188`,
`MangaCarta/Services/WebViewService.swift:240-250`). Navigation has a 30-second timeout;
interactive challenges have a 120-second timeout; scripts have a 15-second timeout
(`MangaCarta/Services/WebViewService.swift:31-35`,
`MangaCarta/Services/WebViewService.swift:130-170`).

Navigation failures become `SourceError.navigationFailed`, challenge decline/timeout becomes
`SourceError.cloudflareUnsolved`, JavaScript errors/non-string results/timeouts become
`SourceError.extractionFailed`, and JSON decoding errors are wrapped as
`SourceError.extractionFailed("decoding script output: …")`
(`MangaCarta/Services/WebViewService.swift:85-91`,
`MangaCarta/Services/WebViewService.swift:130-188`,
`MangaCarta/Services/WebViewService.swift:230-238`).

## 2. `MangaSource` as the extension-facing contract

The protocol comment claims every parameter is `Int`/`String` and every return is a value/Codable
domain type (`MangaCarta/Models/MangaSource.swift:9-12`). The actual surface is:

| Member | Shape | Required behavior today |
|---|---|---|
| Identity | `id: String`, `name: String` | Required; no defaults (`MangaCarta/Models/MangaSource.swift:18-22`). |
| Adult declaration | `isNSFW: Bool` | Optional behavior through a default of `false` (`MangaCarta/Models/MangaSource.swift:23-24`, `MangaCarta/Models/MangaSource.swift:102-104`). |
| Search | `search(title: String, limit: Int, offset: Int) async throws -> [Manga]` | Required; no default (`MangaCarta/Models/MangaSource.swift:26-27`). |
| Tag browsing declaration | `supportsTagBrowse: Bool` | Optional behavior through a default of `false` (`MangaCarta/Models/MangaSource.swift:28-32`, `MangaCarta/Models/MangaSource.swift:105-105`). |
| Tag browsing | `mangaByTag(tag: String, limit: Int, offset: Int) async throws -> [Manga]` | Optional; default throws `SourceError.unsupported("mangaByTag")` (`MangaCarta/Models/MangaSource.swift:33-35`, `MangaCarta/Models/MangaSource.swift:107-109`). |
| Popular feed | `popular(limit: Int, offset: Int) async throws -> [Manga]` | Required; no default (`MangaCarta/Models/MangaSource.swift:36-37`). |
| New-title feed | `newTitles(limit: Int, offset: Int) async throws -> [Manga]` | Optional; default throws `SourceError.unsupported("newTitles")` (`MangaCarta/Models/MangaSource.swift:38-39`, `MangaCarta/Models/MangaSource.swift:111-113`). |
| Latest-update feed | `latestUpdates(limitTitles: Int, language: String, offset: Int) async throws -> [MangaUpdate]` | Optional; default throws `SourceError.unsupported("latestUpdates")`. A Swift-only convenience overload supplies `offset: 0` (`MangaCarta/Models/MangaSource.swift:40-45`, `MangaCarta/Models/MangaSource.swift:115-123`). |
| Detail | `mangaDetail(id: String) async throws -> MangaDetail` | Required; no default (`MangaCarta/Models/MangaSource.swift:46-47`). |
| Chapters | `chapters(mangaId: String) async throws -> [Chapter]` | Required; no default (`MangaCarta/Models/MangaSource.swift:48-49`). |
| Pages | `pageURLs(chapterId: String, preferDataSaver: Bool) async throws -> [URL]` | Required; no default (`MangaCarta/Models/MangaSource.swift:50-51`). |
| Image concurrency | `imagePrefetchConcurrency: Int` | Optional behavior through a default of 5 (`MangaCarta/Models/MangaSource.swift:52-54`, `MangaCarta/Models/MangaSource.swift:125-125`). |
| Human-facing site URL | `webURL(forManga id: String) -> URL?` | Optional behavior through a default of `nil` (`MangaCarta/Models/MangaSource.swift:55-57`, `MangaCarta/Models/MangaSource.swift:127-127`). |
| Home presentation | `homeRailTitles: [String]`, `homeRailEyebrows: [String]`, `latestRailShowsNewBadge: Bool` | Optional behavior through defaults of three titles, no eyebrows, and `true`; they are protocol requirements so existential dispatch reaches source overrides (`MangaCarta/Models/MangaSource.swift:59-69`, `MangaCarta/Models/MangaSource.swift:129-132`). |

### Existing bridge strains and violations

- `pageURLs` takes a `Bool` and returns Foundation `[URL]`; `isNSFW`, `supportsTagBrowse`, and
  `latestRailShowsNewBadge` are also booleans, contradicting the narrower “every parameter is an
  `Int`/`String`” comment and requiring representation choices at a JavaScript boundary
  (`MangaCarta/Models/MangaSource.swift:9-12`, `MangaCarta/Models/MangaSource.swift:23-24`,
  `MangaCarta/Models/MangaSource.swift:28-32`, `MangaCarta/Models/MangaSource.swift:50-51`,
  `MangaCarta/Models/MangaSource.swift:68-69`).
- Of the domain returns, only `Manga` is `Codable`. `MangaUpdate`, `Chapter`, and `MangaDetail`
  are plain value types without `Codable` conformance; `MangaDetail` contains `[Tag]`, whose
  element type is `Codable`, but the container type itself is not
  (`MangaCarta/Models/MangaDexAPI.swift:18-42`,
  `MangaCarta/Models/MangaDexAPI.swift:44-55`,
  `MangaCarta/Models/MangaDexAPI.swift:190-215`,
  `MangaCarta/Models/MangaDexAPI.swift:225-238`).
- The protocol's `throws` boundary does not constrain failures to `SourceError`. MangaDex forwards
  transport/HTTP/decode errors from `MangaDexAPI`, while WebView extraction wraps only its own
  navigation/script/decode paths in `SourceError`
  (`MangaCarta/Models/MangaDexSource.swift:26-55`,
  `MangaCarta/Models/MangaDexAPI.swift:401-436`,
  `MangaCarta/Services/WebViewService.swift:85-91`).
- Capability support has two different representations: explicit boolean plus throwing method for
  tag browsing, but only a throwing default for the two optional feeds. Other defaulted behaviors
  use fallback values (`false`, `5`, `nil`, or presentation arrays), which does not distinguish
  “unsupported” from “supported with that value”
  (`MangaCarta/Models/MangaSource.swift:97-132`).
- The latest-updates offset describes the underlying source feed rather than a guaranteed offset
  into returned Listings; MangaDex pages chapters and deduplicates afterward, while WeebCentral
  translates it into a page number. The same signature therefore carries source-specific paging
  semantics (`MangaCarta/Models/MangaSource.swift:40-45`,
  `MangaCarta/Models/WeebCentralSource.swift:50-59`,
  `MangaCarta/Models/MangaDexAPI.swift:506-557`).

## 3. `WebViewService` and `SourceContext` today

`SourceContext` exposes exactly one source capability, `webView.extract`; it has no HTTP, storage,
logging, clock, or other member (`MangaCarta/Services/SourceContext.swift:13-22`). The registry
constructs one context around `WebViewService.shared` and injects it into WeebCentral; MangaDex is
constructed without a context and calls its compiled API client directly
(`MangaCarta/Services/SourceRegistry.swift:54-60`,
`MangaCarta/Models/MangaDexSource.swift:13-55`).

The WebView behavior a JavaScript author would encounter is:

- One shared off-screen `WKWebView` uses `WKWebsiteDataStore.default()`, so browser data including
  `cf_clearance` survives loads and app relaunches. It also pins a Safari/iOS 17.5 user agent because
  that cookie is bound to the user agent that earned it
  (`MangaCarta/Services/WebViewService.swift:68-77`).
- The script must evaluate to a Swift `String` containing JSON. A JavaScript object/array, `null`, or
  `undefined` is rejected as “script did not return a JSON string”; WeebCentral's scripts therefore
  end by returning `JSON.stringify(...)`
  (`MangaCarta/Services/WebViewService.swift:173-186`,
  `MangaCarta/Models/WeebCentralSource.swift:160-165`).
- Extracts are single-file across every WebView-backed Source: one load/challenge/script pipeline
  owns the shared browser at a time (`MangaCarta/Services/WebViewService.swift:94-115`,
  `MangaCarta/Services/WebViewService.swift:240-250`).
- A main-frame response whose `cf-mitigated` header is `challenge` triggers a wait. The service
  publishes `isChallengeActive`; `ContentView` presents the WebView in a sheet, and dismissal calls
  `cancelChallenge()` (`MangaCarta/Services/WebViewService.swift:23-29`,
  `MangaCarta/Services/WebViewService.swift:256-285`,
  `MangaCarta/ContentView.swift:98-100`).
- A challenge can resolve through a challenge-free navigation, explicit dismissal, or the
  120-second deadline. An unsolved result arms a 30-second window in which queued extracts that
  encounter a challenge fail fast; a solved challenge clears the window. Challenge-free pages are
  not blocked by it (`MangaCarta/Services/WebViewService.swift:47-54`,
  `MangaCarta/Services/WebViewService.swift:101-112`,
  `MangaCarta/Services/WebViewService.swift:147-159`,
  `MangaCarta/Services/WebViewService.swift:205-219`).
- Cancellation is checked after a queued extract obtains the WebView lock. After navigation it is
  checked only when the response was identified as a challenge, immediately before challenge
  presentation. The navigation, challenge, and script continuations have no cancellation handler,
  so cancellation alone does not end an in-progress wait; a challenge-free cancelled load can
  proceed to script evaluation. The timeout tasks guard against their own cancelled sleeps becoming
  stale failures (`MangaCarta/Services/WebViewService.swift:94-113`,
  `MangaCarta/Services/WebViewService.swift:130-188`).
- `runScript` times out after 15 seconds. Each run increments `scriptGeneration`; the completion
  callback compares its captured generation so a callback arriving after timeout cannot resume a
  later extraction's continuation (`MangaCarta/Services/WebViewService.swift:31-46`,
  `MangaCarta/Services/WebViewService.swift:161-188`).
- If WebKit terminates the content process, the service fails pending load, challenge, and script
  continuations with a navigation error, clears challenge presentation and decline stickiness, and
  relies on WebKit to recreate the process on the next load
  (`MangaCarta/Services/WebViewService.swift:298-316`).

## 4. Source capabilities outside the browse/read methods

These members are declared on `MangaSource`, but they are not part of its browse/read method set and
are easy to miss when deriving an extension contract from entry points alone:

| Capability | Current use |
|---|---|
| `isNSFW` | Filters the source picker, controls whether adult settings are relevant, affects background-refresh presentation, and suppresses notification detail when adult content is hidden (`MangaCarta/Services/SourceRegistry.swift:85-102`, `MangaCarta/Services/LibraryRefreshCoordinator.swift:177-180`, `MangaCarta/Services/UpdateNotifier.swift:133-140`). WeebCentral explicitly declares `false`; MangaDex inherits the default (`MangaCarta/Models/WeebCentralSource.swift:21-23`, `MangaCarta/Models/MangaSource.swift:102-104`). |
| `supportsTagBrowse` | Controls whether detail tags can become browse links. MangaDex opts in; WeebCentral inherits `false` and does not implement `mangaByTag` (`MangaCarta/Views/MangaDetailView.swift:133-139`, `MangaCarta/Models/MangaDexSource.swift:24-31`, `MangaCarta/Models/WeebCentralSource.swift:36-92`). |
| `imagePrefetchConcurrency` | Passed to the image cache after page URLs load. Both sources currently inherit 5, even though the hook exists for rate-sensitive image CDNs (`MangaCarta/Models/ReaderViewModel.swift:160-167`, `MangaCarta/Models/MangaSource.swift:52-54`, `MangaCarta/Models/MangaSource.swift:125-125`). |
| `webURL(forManga:)` | Supplies the detail screen's “open in browser” destination. Both built-ins construct source-specific URLs; the default is `nil` (`MangaCarta/Views/MangaDetailView.swift:37-41`, `MangaCarta/Models/WeebCentralSource.swift:90-92`, `MangaCarta/Models/MangaDexSource.swift:58-60`, `MangaCarta/Models/MangaSource.swift:127-127`). |
| Home rail titles, eyebrows, and latest-update badge | `HomeView` expects three titles (falling back if fewer are supplied), indexes up to three eyebrows, and uses the badge flag to change the middle rail's stamp and tint. Both built-ins override only eyebrows; the remaining values come from defaults (`MangaCarta/Views/HomeView.swift:146-161`, `MangaCarta/Models/MangaSource.swift:63-69`, `MangaCarta/Models/MangaSource.swift:129-132`, `MangaCarta/Models/WeebCentralSource.swift:25-27`, `MangaCarta/Models/MangaDexSource.swift:21-24`). |
| Stable source id stamping | WeebCentral's mapping explicitly stamps every returned `Manga` with `weebcentral`; MangaDex stamps during API-to-domain conversion. The registry later resolves a Source from that persisted `sourceId` (`MangaCarta/Models/WeebCentralSource.swift:18-21`, `MangaCarta/Models/WeebCentralSource.swift:102-105`, `MangaCarta/Models/MangaDexAPI.swift:129-140`, `MangaCarta/Services/SourceRegistry.swift:67-82`). |

There are also source implementation needs outside both the protocol and `SourceContext`:

- WeebCentral owns a base URL, URL/query construction, DOM scripts, parsing helpers, and private
  decode DTOs in compiled Swift (`MangaCarta/Models/WeebCentralSource.swift:29-34`,
  `MangaCarta/Models/WeebCentralSource.swift:94-167`).
- MangaDex owns a plain-HTTP client with a custom user agent, status validation, JSON decoding,
  and one `429` retry honoring `Retry-After`; none is available through `SourceContext`
  (`MangaCarta/Models/MangaDexAPI.swift:390-436`,
  `MangaCarta/Services/SourceContext.swift:20-22`).
- MangaDex supports tag browsing, preserves alternate titles and a MAL id on Listings, returns
  richer detail tags with stable id/group, supports full versus data-saver page images, paginates
  chapter lists, and deduplicates chapter numbers. WeebCentral does none of those things or lacks
  the corresponding site data (`MangaCarta/Models/MangaDexSource.swift:24-55`,
  `MangaCarta/Models/MangaDexAPI.swift:119-140`,
  `MangaCarta/Models/MangaDexAPI.swift:225-260`,
  `MangaCarta/Models/MangaDexAPI.swift:582-626`,
  `MangaCarta/Models/WeebCentralSource.swift:50-105`). This is inventory only; the reason
  MangaDex remains built in is owned by
  [ADR-0003 Amendment 1](../../adr/0003-extension-substrate.md#amendment-1--mangadex-stays-built-in-2026-08-31).

## 5. Questions the host API specification must settle

Each item below is intentionally a question, not a proposed answer.

1. **What is the wire representation and validation policy for every domain result?** The protocol
   returns `Manga`, `MangaUpdate`, `MangaDetail`, `Chapter`, and `[URL]`, but only `Manga` is Codable;
   WeebCentral currently uses four separate private DTO shapes and performs lossy/defaulting maps
   before returning domain values (`MangaCarta/Models/MangaSource.swift:26-57`,
   `MangaCarta/Models/MangaDexAPI.swift:18-55`,
   `MangaCarta/Models/MangaDexAPI.swift:190-238`,
   `MangaCarta/Models/WeebCentralSource.swift:94-158`). Which fields are required, optional,
   defaulted, rejected, or silently dropped at the Extension boundary?
2. **How does an Extension declare supported capabilities?** Today tag browse uses a boolean plus an
   unsupported-throwing method; new/latest feeds use only unsupported throws; browser URLs and UI
   metadata use default values; popular/detail/chapters/pages have no unsupported default
   (`MangaCarta/Models/MangaSource.swift:26-69`,
   `MangaCarta/Models/MangaSource.swift:97-132`). Is support declared before invocation, inferred
   from exported functions, or learned from failures, and how are defaulted values distinguished
   from absence?
3. **Which behavior belongs in a manifest and which belongs in executable entry points?** Stable id,
   display name, adult declaration, tag support, image concurrency, browser URL support, and Home
   presentation all sit on the Swift protocol today, while id and name are instance values and the
   rest mix defaults with overrides (`MangaCarta/Models/MangaSource.swift:18-69`,
   `MangaCarta/Models/MangaSource.swift:97-132`). What must be knowable without running extension
   code?
4. **What plain-HTTP capability is exposed, and what policy does the host enforce?** The chosen
   substrate assumes per-request plain HTTP or WebView fetching, but `SourceContext` currently has
   only WebView extraction. MangaDex's separate client supplies request headers, status handling,
   decoding, and one `Retry-After`-aware retry (`MangaCarta/Services/SourceContext.swift:13-22`,
   `MangaCarta/Models/MangaDexAPI.swift:401-436`). Who controls method, headers, body, cookies,
   redirect behavior, timeout, decoding, retry, and cancellation?
5. **What WebView primitive crosses into JavaScriptCore?** Swift currently hands
   `extract` a URL, arbitrary page-context script, and a Swift `Decodable` metatype, then returns a
   decoded value; the WebView requires the page script itself to return a JSON string
   (`MangaCarta/Services/SourceContext.swift:13-18`,
   `MangaCarta/Services/WebViewService.swift:85-91`,
   `MangaCarta/Services/WebViewService.swift:173-186`). Does an Extension receive raw JSON, parsed
   values, DOM extraction output, or some other result, and where are schema validation and errors
   applied?
6. **What concurrency and cancellation guarantees are contractual?** The current service globally
   serializes WebView work, checks cancellation at two pipeline boundaries, and uses separate
   navigation/challenge/script deadlines; the protocol itself says only `async throws`
   (`MangaCarta/Services/WebViewService.swift:94-170`,
   `MangaCarta/Services/WebViewService.swift:240-250`,
   `MangaCarta/Models/MangaSource.swift:26-51`). Can calls overlap, can a Source hold work after its
   caller cancels, and which deadlines are host policy versus implementation detail?
7. **What error taxonomy and observability cross the boundary?** `SourceError` has unsupported,
   challenge, navigation, and extraction cases, MangaDex exposes a different transport taxonomy,
   and several WeebCentral mappings silently omit invalid data
   (`MangaCarta/Models/MangaSource.swift:72-95`,
   `MangaCarta/Models/MangaDexAPI.swift:401-436`,
   `MangaCarta/Models/WeebCentralSource.swift:96-105`,
   `MangaCarta/Models/WeebCentralSource.swift:240-247`). Which failures are retriable, user-facing,
   source bugs, host-policy violations, or partial success, and what structured logging is available
   to authors without exposing reader data?
8. **What rate-limiting and resource-budget controls exist per Extension, per origin, and globally?**
   MangaDex implements its own single `429` retry; WebView extraction is globally serialized; image
   prefetch has a per-Source width (`MangaCarta/Models/MangaDexAPI.swift:406-436`,
   `MangaCarta/Services/WebViewService.swift:240-250`,
   `MangaCarta/Models/MangaSource.swift:52-54`). How are request rates, concurrent HTTP work,
   WebView occupancy, script CPU/time, response sizes, and image concurrency bounded and surfaced?
9. **What storage scopes and lifecycle are available?** `SourceContext` has no storage member, while
   the WebView uses a shared persistent browser data store and the registry persists the active
   source id in global `UserDefaults` (`MangaCarta/Services/SourceContext.swift:20-22`,
   `MangaCarta/Services/WebViewService.swift:68-75`,
   `MangaCarta/Services/SourceRegistry.swift:22-27`). Are Extension key/value data, cookies,
   credentials, cache data, and host preferences isolated per Extension and/or origin, and what
   survives update, disablement, uninstall, and reinstall?
10. **How are API and Extension versions negotiated over time?** `MangaSource` and
    `SourceContext` contain no version member, while adding protocol requirements has relied on
    defaults to preserve existing Swift conformers (`MangaCarta/Models/MangaSource.swift:18-70`,
    `MangaCarta/Models/MangaSource.swift:97-132`,
    `MangaCarta/Services/SourceContext.swift:20-22`). What version is declared, what compatibility
    range is checked, and what happens when an Extension requests a capability the installed host
    does not have (or the host encounters an older Extension)?
11. **What are the pagination and input-validity contracts?** Most feeds accept `limit` and
    `offset`, but latest updates pages an underlying feed, WeebCentral converts offset to a page,
    and no protocol-level range constraints prevent negative limits or offsets
    (`MangaCarta/Models/MangaSource.swift:26-45`,
    `MangaCarta/Models/WeebCentralSource.swift:50-59`,
    `MangaCarta/Models/MangaDexAPI.swift:506-557`). Who validates inputs, and how does a caller know
    whether a short or empty result means exhaustion, filtering, partial failure, or invalid input?
12. **Which Source-authored presentation is stable API, and how is it validated/localized?** Home
    consumes positional arrays for exactly three rails and contains a fallback for too few titles,
    while eyebrow access is conditional by index (`MangaCarta/Views/HomeView.swift:146-161`,
    `MangaCarta/Models/MangaSource.swift:63-69`). Are those labels Extension-authored data, host
    localization keys, feed metadata, or not part of the Extension contract?
13. **How are browser identity, cookies, and interactive challenges isolated and disclosed?** All
    WebView Sources share one persistent store, one pinned UA, one browser, and one app-level
    challenge sheet (`MangaCarta/Services/WebViewService.swift:21-29`,
    `MangaCarta/Services/WebViewService.swift:68-77`,
    `MangaCarta/Services/SourceRegistry.swift:54-60`,
    `MangaCarta/ContentView.swift:98-100`). Are cookies shared across Extensions, may authors alter
    the UA or navigation target, and how does the sheet identify which Source/origin is asking the
    reader to interact?
14. **Which URL schemes and destinations may an Extension produce?** Listings contain optional
    cover URLs, pages return `[URL]`, and `webURL` supplies a browser destination; current mapping
    accepts anything Foundation parses as a URL and often drops malformed strings silently
    (`MangaCarta/Models/MangaDexAPI.swift:18-26`,
    `MangaCarta/Models/MangaSource.swift:50-57`,
    `MangaCarta/Models/WeebCentralSource.swift:82-92`,
    `MangaCarta/Models/WeebCentralSource.swift:96-105`). Which schemes, origins, redirects, and
    cross-origin image/page loads are permitted and validated by the host?
15. **What language semantics apply to feeds and chapter lists?** `latestUpdates` accepts a language
    string, which MangaDex sends as `translatedLanguage[]` and WeebCentral explicitly ignores;
    `chapters` has no language argument even though MangaDex hardcodes English in that request
    (`MangaCarta/Models/MangaSource.swift:40-49`,
    `MangaCarta/Models/MangaDexAPI.swift:517-529`,
    `MangaCarta/Models/MangaDexAPI.swift:582-596`,
    `MangaCarta/Models/WeebCentralSource.swift:50-53`). Is language a per-call input, Source
    declaration, reader preference, fixed Source property, or some combination, and how is an
    ignored or unavailable language represented?
16. **What happens when a background Source call encounters an interactive challenge?** Library
    refresh invokes each Source's `chapters` method in task-group work, including during the
    best-effort background refresh path, while `WebViewService` represents an interactive challenge
    by publishing app-level sheet state and waiting up to 120 seconds
    (`MangaCarta/Services/LibraryRefreshCoordinator.swift:166-186`,
    `MangaCarta/Services/WebViewService.swift:23-29`,
    `MangaCarta/Services/WebViewService.swift:94-115`,
    `MangaCarta/Services/WebViewService.swift:147-159`,
    `MangaCarta/ContentView.swift:98-100`). May a non-foreground operation request interaction,
    must it fail or defer, and how is that outcome distinguished from a user decline or timeout?
17. **What is the lifecycle and collision policy for a stable Source id?** The id is persisted in
    each Listing and used for registry lookup; an absent id currently falls back to another Source
    for refresh, while a missing per-Work pinned Source falls back without deleting the pin
    (`MangaCarta/Models/MangaSource.swift:19-20`,
    `MangaCarta/Services/SourceRegistry.swift:67-82`,
    [glossary](../../glossary.md) terms **Listing**, **Listing key**, and **Pin**). Who allocates and
    validates ids, what prevents two installed Extensions from claiming the same one, may an update
    rename it, and how do disablement, uninstall, reinstall, or repository replacement affect
    existing Listings and pins?
18. **How is an Extension's adult-content declaration established and trusted?** `isNSFW` controls
    Source visibility and active-Source fallback, is copied into refresh results, and can suppress
    notification details for a Work; its protocol default is `false`
    (`MangaCarta/Models/MangaSource.swift:23-24`,
    `MangaCarta/Models/MangaSource.swift:102-104`,
    `MangaCarta/Services/SourceRegistry.swift:85-102`,
    `MangaCarta/Services/LibraryRefreshCoordinator.swift:166-181`,
    `MangaCarta/Services/UpdateNotifier.swift:133-140`). Is the declaration author-supplied,
    repository-supplied, host-reviewed, inferred per Listing, or mutable, and what happens when it
    is missing or inaccurate?

## Scope note

This inventory records current evidence only. It deliberately leaves the above questions open and
does not amend the decisions owned by ADR-0003 or the terminology owned by the glossary.
