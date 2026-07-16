# Extension System — Phase 2 (Cloudflare WebView + WeebCentral) Design

Date: 2026-07-15

## Context

Phase 1 (merged to `main`) delivered the multi-source plumbing: `isNSFW`, `sourceId`
persistence, and a Settings source picker — but MangaDex is still the only registered
source, so the picker shows one entry. Phase 2 adds the **first real second source,
WeebCentral**, and with it the reusable host capability every remaining source needs: a
**Cloudflare-bypassing WebView service** that also does HTML extraction.

This is the heaviest infrastructure phase and the first to run the hard implementation on
the **Fable** model.

### How WeebCentral actually works (grounding)

From the Paperback reference extension
([`inkdex/general-extensions/src/WeebCentral`](https://github.com/inkdex/general-extensions/tree/main/src/WeebCentral)):

- Domain `https://weebcentral.com`. **Everything is server-rendered HTML** (no JSON API):
  - Homepage / latest: `/` and `/latest-updates/{page}`
  - Details: `/series/{mangaId}`
  - Chapter list: `/series/{mangaId}/full-chapter-list`
  - Chapter images: `/chapters/{chapterId}/images?reading_style=long_strip`
  - Search: `/search/…` with query items (title, genres, status, order)
- Content rating: EVERYONE (not adult — no NSFW gating needed; the Phase-1 adult toggle
  stays for private-source in Phase 3).
- **Cloudflare** manifests as a `cf-mitigated: challenge` response header. Paperback reacts
  by surfacing a WebView so the user clears the challenge, then reuses the `cf_clearance`
  cookie.
- Page images are **plain image URLs** on WeebCentral's CDN — **no scrambling**. So the
  existing `pageURLs -> [URL]` contract and the Phase-1 image cache work unchanged.

## Decisions

- **Option A — WebView extraction** (chosen). Load each WeebCentral page in a `WKWebView`
  and run injected `document.querySelectorAll(...)` JS that returns JSON. Rationale: the
  WebView is a real browser, so it (a) clears Cloudflare's JS challenge automatically and
  (b) lets us extract via DOM selectors in JS — **no native HTML parser** (we have no
  third-party deps), and the WebView is required for Cloudflare regardless. This is the
  proven Paperback pattern. (Rejected Option B — cookie-capture + `URLSession` + native
  HTML parsing — because it needs a vendored HTML parser and separate cookie/UA lifecycle
  for no real gain here.)
- **`SourceContext` arrives now** (deferred from Phase 1) carrying a `webView` service.
  Sources receive the context and call `context.webView.extract(...)`. MangaDex is
  unaffected (it keeps its own `MangaDexAPI` client and ignores the webView service).
- **Fable model** for the hard `WebViewService` implementation subtask.

## Architecture

### 1. `WebViewExtracting` protocol + `WebViewService` — `Services/WebViewService.swift` (new)

The Phase-2 spine. `@MainActor` (WKWebView is UIKit/main-thread).

```swift
protocol WebViewExtracting {
    /// Load `url` in a WebView (clearing Cloudflare as needed), run `script`
    /// (JS returning a JSON-serializable value), and decode the result as T.
    func extract<T: Decodable>(from url: URL, script: String, as type: T.Type) async throws -> T
}

@MainActor
final class WebViewService: WebViewExtracting {
    // - Persistent WKWebsiteDataStore (shared) so cf_clearance survives across loads/launches.
    // - A shared off-screen WKWebView reused across calls (one navigation at a time; serialize).
    // - Sets a real desktop/mobile User-Agent consistently (cf_clearance is UA-bound).
    // - Navigate to url; wait for load; if the response/DOM indicates a Cloudflare
    //   interactive challenge (e.g. cf-mitigated, Turnstile markers, or a challenge title),
    //   surface the WebView to the user to solve, then continue once it lands on content.
    // - evaluateJavaScript(script) → JSON string (script ends with JSON.stringify(result));
    //   parse to Data → JSONDecoder().decode(T).
    // - Timeouts + typed errors (SourceError.cloudflareUnsolved, .extractionFailed).
}
```

Notes for the implementer:
- WKWebView runs **non-interactive** Cloudflare JS challenges automatically; only
  interactive Turnstile needs the user. Design a presentable challenge surface (a sheet
  hosting the `WKWebView`) that appears only when a challenge is detected, and dismisses
  when the target host content is reached.
- Serialize navigations (an `actor`-like queue or a serial async gate) — one WKWebView,
  one in-flight load at a time.
- Cookies/cf_clearance live in the WebView's `WKWebsiteDataStore`; because we also load
  content pages in the same WebView, no cookie hand-off to URLSession is needed.

### 2. `SourceContext` — `Services/SourceContext.swift` (new)

```swift
struct SourceContext {
    let webView: WebViewExtracting
    // (net/storage join later when a source needs them)
}
```

`SourceRegistry` builds one shared `SourceContext` (with the real `WebViewService`) and
passes it to source initializers. `MangaDexSource` gains an ignored `context` parameter (or
a no-context convenience init) so all sources construct uniformly.

### 3. `WeebCentralSource` — `Models/WeebCentralSource.swift` (new) + models/scripts

`struct WeebCentralSource: MangaSource` with `id = "weebcentral"`, `name = "WeebCentral"`,
`isNSFW = false`, holding a `SourceContext`. Each protocol method:
- Builds the WeebCentral URL (paths above).
- Calls `context.webView.extract(from:script:as:)` with a page-specific JS extraction
  script that returns JSON.
- Maps the decoded JSON DTOs into domain types (`Manga` with `sourceId = "weebcentral"` and
  a `coverURL`, `Chapter`, `MangaDetail`, page `[URL]`).

Extraction scripts (DOM selectors) should be **ported from the reference**
`inkdex/general-extensions/src/WeebCentral/parsers.ts` and **verified against live HTML**
during implementation (selectors are the most volatile part). Keep each script small and
co-located with its method. Representative shape:

```js
// search/latest: return [{id, title, cover}]
return JSON.stringify([...document.querySelectorAll('article, .some-card')].map(el => ({
  id: el.querySelector('a[href*="/series/"]')?.href.split('/series/')[1]?.split('/')[0],
  title: el.querySelector('...')?.textContent?.trim(),
  cover: el.querySelector('img')?.src
})).filter(x => x.id));
```

Method coverage for Phase 2:
- `search(title:limit:offset:)` — `/search?text=…` (title only; genre/status filters deferred).
- `popular` / `newTitles` — map to WeebCentral's homepage / `/latest-updates/{page}` feeds
  (whichever the homepage exposes; `latestUpdates` may throw `.unsupported` if no clean feed).
- `mangaDetail(id:)` — `/series/{id}` (description, authors, tags, status).
- `chapters(mangaId:)` — `/series/{id}/full-chapter-list`.
- `pageURLs(chapterId:preferDataSaver:)` — `/chapters/{id}/images?reading_style=long_strip`
  → the `<img>` src list (plain URLs; `preferDataSaver` ignored — WeebCentral has one size).

### 4. Registration + picker

Add `WeebCentralSource(context:)` to `SourceRegistry.shared.sources`. The Phase-1 picker
now shows **MangaDex + WeebCentral**; selecting WeebCentral re-sources Home. Saved
WeebCentral items already route correctly via `SourceRegistry.source(for:)` (Phase 1).

## Testing

The WebView integration itself can't be meaningfully unit-tested (real browser + network +
Cloudflare). Strategy:
- **`WebViewExtracting` is a protocol**, so `WeebCentralSource` is tested with a
  `MockWebView` that returns canned JSON for a given `(url, script)` — verifying URL
  construction and JSON-DTO → domain-type mapping (search results, details, chapters, page
  URLs, `sourceId == "weebcentral"`).
- Unit-test any pure helpers (URL building, DTO decoding) with fixture JSON.
- `WebViewService` itself is verified **live**, not in unit tests.

## Verification (end-to-end, live)

1. Build for iPhone 17 simulator; unit tests (mock-webView `WeebCentralSource` tests) pass.
2. Live: Settings → pick **WeebCentral**; Home browses WeebCentral; open a title → detail
   loads; open a chapter → reader pages load (served through the Phase-1 image cache); if a
   Cloudflare challenge appears, the WebView surfaces for a tap and then proceeds. Confirm
   switching back to MangaDex still works and a saved WeebCentral bookmark reopens via
   WeebCentral.

## Scope boundaries

- **This phase:** `WebViewService` + `SourceContext` + `WeebCentralSource` (core browse/
  search/details/chapters/read) + registration.
- **Deferred:** private-source (Phase 3 — reuses the WebView service; adds NSFW-in-practice,
  gallery→single-chapter, image throttling); comix.to descrambler + JS-signing (Phase 4);
  JS-loadability (Phase 5). Also deferred within WeebCentral: advanced search filters
  (genres/status/order), settings form, `SourceContext.net`/`storage`.

## References (technique only — nothing copied/matched)

- `inkdex/general-extensions/src/WeebCentral/{network.ts,parsers.ts,models.ts}` — endpoints,
  DOM selectors, and the `cf-mitigated: challenge` detection pattern.
