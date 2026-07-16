# Extension System Phase 2 (Cloudflare WebView + WeebCentral) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Cloudflare-clearing `WKWebView` extraction service and WeebCentral as the app's second manga source, selectable in Settings and readable end-to-end.

**Architecture:** A `@MainActor WebViewService` loads pages in a shared off-screen `WKWebView` (a real browser, so Cloudflare's JS challenge clears itself; interactive Turnstile surfaces the WebView in a sheet), runs injected JS ending in `JSON.stringify(...)`, and decodes the result into Codable DTOs. A `SourceContext` carries the service behind the `WebViewExtracting` protocol into source initializers. `WeebCentralSource` builds weebcentral.com URLs, extracts with page-specific scripts, and maps DTOs to domain types stamped `sourceId = "weebcentral"`.

**Tech Stack:** Swift / SwiftUI / WebKit (system framework) / XCTest. **No third-party dependencies.**

**Spec:** `docs/superpowers/specs/2026-07-15-extension-system-phase-2-design.md` (authoritative).

## Global Constraints

- **Pure SwiftUI + Foundation + system frameworks (WebKit is fine). NO third-party deps, no SPM/CocoaPods.**
- Deployment target iOS 17.5; branch `feature/extension-system-phase-2`.
- New files ONLY in `Manga-Reader/Services/`, `Manga-Reader/Models/`, `Manga-Reader/Views/Components/` (Xcode synchronized groups — auto-compiled, **no pbxproj edits**). `Views/` itself and the test target are NOT synchronized — modify existing files there only (`ContentView.swift`, `Manga-ReaderTests/Manga_ReaderTests.swift`).
- Build: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' build`
- Unit tests (UI-test runner is flaky — always scope to the unit target):
  `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:Manga-ReaderTests`
  Builds/tests take a few minutes; be patient — don't chain short sleeps.
- After any build, if `git status` shows a cosmetic `project.pbxproj` reshuffle: `git checkout -- Manga-Reader.xcodeproj/project.pbxproj`.
- Every commit ends with the trailer: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
- DOM selectors are ported from the reference extension (`inkdex/general-extensions`, branch `0.9/stable`, `src/WeebCentral/{parsers,network,main}.ts`) — **technique only, never copy code or match their API**. Selectors are the most volatile part; Task 5 verifies them against live HTML.

### Known accepted tradeoffs (do not "fix" these in this phase)

- The hidden WebView loads chapter pages' actual images before extraction (slower than a bare HTML fetch). Acceptable; a content-blocker optimization is out of scope.
- WeebCentral list feeds don't carry status/description → `Manga.status = "unknown"`, `description = ""` for cards. Detail screen still gets description via `mangaDetail`.
- The three Home feeds serialize through one WebView (three sequential page loads).

---

### Task 1: Source-layer contract — `SourceError` cases, `WebViewExtracting`, `SourceContext`

The seam every later task depends on. The `WebViewExtracting` protocol lives with `SourceContext` (sources depend on the abstraction; `Services/WebViewService.swift` in Task 2 holds only the implementation — deliberate small deviation from the spec's file sketch).

**Files:**
- Modify: `Manga-Reader/Models/MangaSource.swift` (the `SourceError` enum, currently lines 43–53)
- Create: `Manga-Reader/Services/SourceContext.swift`
- Test: `Manga-ReaderTests/Manga_ReaderTests.swift` (append)

**Interfaces:**
- Consumes: existing `SourceError` enum.
- Produces (later tasks rely on these exact names):
  - `protocol WebViewExtracting { func extract<T: Decodable>(from url: URL, script: String, as type: T.Type) async throws -> T }`
  - `struct SourceContext { let webView: WebViewExtracting }` (memberwise init)
  - `SourceError.cloudflareUnsolved`, `SourceError.navigationFailed(String)`, `SourceError.extractionFailed(String)`

- [ ] **Step 1: Write the failing test**

Append to the end of the `Manga_ReaderTests` class in `Manga-ReaderTests/Manga_ReaderTests.swift`:

```swift
    // MARK: - Source-layer contract (Phase 2)

    func testSourceErrorWebViewCasesHaveDescriptions() {
        XCTAssertEqual(SourceError.cloudflareUnsolved.errorDescription,
                       "Cloudflare verification wasn't completed.")
        XCTAssertEqual(SourceError.navigationFailed("timeout").errorDescription,
                       "Couldn't load the page: timeout")
        XCTAssertEqual(SourceError.extractionFailed("bad JSON").errorDescription,
                       "Couldn't read the page: bad JSON")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:Manga-ReaderTests 2>&1 | tail -20`
Expected: **build failure** — `type 'SourceError' has no member 'cloudflareUnsolved'`.

- [ ] **Step 3: Implement**

In `Manga-Reader/Models/MangaSource.swift`, replace the `SourceError` enum with:

```swift
/// Errors common to the source layer (distinct from a source's own transport errors).
enum SourceError: LocalizedError {
    /// The source does not implement an optional capability (carries the capability name).
    case unsupported(String)
    /// A Cloudflare interactive challenge was shown but never completed (dismissed/timed out).
    case cloudflareUnsolved
    /// The WebView could not load the page (carries the underlying reason).
    case navigationFailed(String)
    /// The extraction script failed or its output couldn't be decoded (carries the reason).
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let capability):
            return "This source doesn't support \(capability)."
        case .cloudflareUnsolved:
            return "Cloudflare verification wasn't completed."
        case .navigationFailed(let reason):
            return "Couldn't load the page: \(reason)"
        case .extractionFailed(let reason):
            return "Couldn't read the page: \(reason)"
        }
    }
}
```

Create `Manga-Reader/Services/SourceContext.swift`:

```swift
//
//  SourceContext.swift
//  Manga-Reader
//
//  The host-capability bundle handed to every `MangaSource` at construction. Sources
//  that scrape HTML sites call `webView.extract(...)`; API-backed sources (MangaDex)
//  ignore it. More capabilities (net, storage) join in later phases when a source
//  actually needs them.
//

import Foundation

/// Loads a page in a real browser (clearing Cloudflare as needed), runs a JS extraction
/// script whose final expression is a `JSON.stringify(...)` string, and decodes it.
/// Implemented by `WebViewService`; mocked in tests.
protocol WebViewExtracting {
    func extract<T: Decodable>(from url: URL, script: String, as type: T.Type) async throws -> T
}

/// Capabilities available to sources. Built once by `SourceRegistry` and shared.
struct SourceContext {
    let webView: WebViewExtracting
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:Manga-ReaderTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **` (all existing tests + the new one).

- [ ] **Step 5: Commit**

```bash
git checkout -- Manga-Reader.xcodeproj/project.pbxproj 2>/dev/null || true
git add Manga-Reader/Models/MangaSource.swift Manga-Reader/Services/SourceContext.swift Manga-ReaderTests/Manga_ReaderTests.swift
git commit -m "Add WebViewExtracting/SourceContext seam + webview SourceError cases

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: `WebViewService` — Cloudflare-clearing WKWebView extraction engine  **(RUN ON FABLE)**

The Phase-2 spine and the hardest task. The code below is a complete reference implementation; the implementer owns making it actually work (WKWebView delegate edge cases are subtle — think through double-resume, challenge sub-navigations, and dismissal races; adjust as reality demands but keep the public surface exactly as specified).

**Files:**
- Create: `Manga-Reader/Services/WebViewService.swift`
- Create: `Manga-Reader/Views/Components/CloudflareChallengeView.swift`
- Modify: `Manga-Reader/ContentView.swift` (attach the challenge sheet)
- Test: none (verified live in Task 5 — real browser + network + Cloudflare can't be unit-tested meaningfully)

**Interfaces:**
- Consumes: `WebViewExtracting`, `SourceError.{cloudflareUnsolved,navigationFailed,extractionFailed}` (Task 1).
- Produces:
  - `@MainActor final class WebViewService: NSObject, ObservableObject, WebViewExtracting` with `static let shared`, `@Published var isChallengeActive: Bool`, `let webView: WKWebView`, `func cancelChallenge()`.
  - `struct CloudflareChallengeView: View` (no-arg init, observes `WebViewService.shared`).

**Design contract (from the spec):**
- Persistent `WKWebsiteDataStore.default()` so `cf_clearance` survives loads AND app relaunches.
- One pinned, real Safari User-Agent for every load (`cf_clearance` is UA-bound).
- One shared off-screen `WKWebView`; navigations strictly serialized (one in-flight `extract` at a time).
- Cloudflare challenge detection: main-frame response header `cf-mitigated: challenge` (the documented signal; the reference extension keys off exactly this). Non-interactive JS challenges clear themselves in a real WebView; only when the challenge page is reached does the sheet surface. When a later main-frame load lands **without** the header, the challenge is solved → dismiss and continue.
- User dismissing the sheet, or 120 s elapsing → `SourceError.cloudflareUnsolved`. Page-load timeout 30 s → `SourceError.navigationFailed`.
- `evaluateJavaScript` — use the **completion-handler variant wrapped in a continuation** (the async overload traps when JS returns nil).

- [ ] **Step 1: Write `Manga-Reader/Services/WebViewService.swift`**

```swift
//
//  WebViewService.swift
//  Manga-Reader
//
//  The Cloudflare-clearing HTML-extraction engine behind WebView-based sources
//  (WeebCentral now; private-source/comix in later phases). Loads a page in a shared
//  off-screen WKWebView — a real browser, so Cloudflare's non-interactive JS
//  challenge clears itself — then runs an injected JS script whose final expression
//  is a JSON string, and decodes it into a Codable DTO. When Cloudflare demands an
//  interactive (Turnstile) tap, `isChallengeActive` flips and ContentView presents
//  the WebView in a sheet; once the target page loads challenge-free, extraction
//  resumes automatically.
//

import Foundation
import WebKit
import Combine

@MainActor
final class WebViewService: NSObject, ObservableObject, WebViewExtracting {
    static let shared = WebViewService()

    /// True while an interactive Cloudflare challenge needs the user. Drives the
    /// sheet in ContentView; the service flips it back off when the challenge clears.
    @Published var isChallengeActive = false

    /// The shared browser. Exposed so CloudflareChallengeView can host it on screen
    /// while a challenge is active; lives off-screen the rest of the time.
    let webView: WKWebView

    private let navigationTimeout: TimeInterval = 30
    private let challengeTimeout: TimeInterval = 120

    // Single-flight state — only ever touched on the MainActor.
    private var lockBusy = false
    private var lockWaiters: [CheckedContinuation<Void, Never>] = []
    private var loadContinuation: CheckedContinuation<Void, Error>?
    private var challengeContinuation: CheckedContinuation<Void, Error>?
    private var sawChallengeHeader = false

    override init() {
        let config = WKWebViewConfiguration()
        // Persistent store: cf_clearance must survive across loads AND app relaunches.
        config.websiteDataStore = .default()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        // cf_clearance is bound to the UA that earned it — pin one real UA for every load.
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
        super.init()
        webView.navigationDelegate = self
    }

    // MARK: - WebViewExtracting

    func extract<T: Decodable>(from url: URL, script: String, as type: T.Type) async throws -> T {
        try await withLock {
            try await self.load(url)
            if self.sawChallengeHeader {
                try await self.awaitChallengeResolution()
            }
            let json = try await self.runScript(script)
            do {
                return try JSONDecoder().decode(T.self, from: Data(json.utf8))
            } catch {
                throw SourceError.extractionFailed("decoding script output: \(error.localizedDescription)")
            }
        }
    }

    /// Called when the user dismisses the challenge sheet without solving it.
    /// Safe to call redundantly (e.g. from the sheet's onDismiss after success).
    func cancelChallenge() {
        resumeChallenge(.failure(SourceError.cloudflareUnsolved))
    }

    // MARK: - Navigation plumbing

    private func load(_ url: URL) async throws {
        sawChallengeHeader = false
        let deadline = Task { [navigationTimeout] in
            try? await Task.sleep(for: .seconds(navigationTimeout))
            self.resumeLoad(.failure(SourceError.navigationFailed("timed out loading \(url.absoluteString)")))
        }
        defer { deadline.cancel() }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            loadContinuation = cont
            webView.load(URLRequest(url: url))
        }
    }

    private func awaitChallengeResolution() async throws {
        isChallengeActive = true
        defer { isChallengeActive = false }
        let deadline = Task { [challengeTimeout] in
            try? await Task.sleep(for: .seconds(challengeTimeout))
            self.resumeChallenge(.failure(SourceError.cloudflareUnsolved))
        }
        defer { deadline.cancel() }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            challengeContinuation = cont
        }
    }

    private func runScript(_ script: String) async throws -> String {
        // Completion-handler variant on purpose: the async overload traps if JS returns nil.
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    cont.resume(throwing: SourceError.extractionFailed(error.localizedDescription))
                } else if let json = result as? String {
                    cont.resume(returning: json)
                } else {
                    cont.resume(throwing: SourceError.extractionFailed("script did not return a JSON string"))
                }
            }
        }
    }

    // Single-resume guards: delegate callbacks and timeouts can race; whoever gets
    // there first wins, later calls are no-ops.
    private func resumeLoad(_ result: Result<Void, Error>) {
        guard let cont = loadContinuation else { return }
        loadContinuation = nil
        cont.resume(with: result)
    }

    private func resumeChallenge(_ result: Result<Void, Error>) {
        guard let cont = challengeContinuation else { return }
        challengeContinuation = nil
        cont.resume(with: result)
    }

    /// Serializes extracts: one WKWebView, one in-flight navigation at a time.
    private func withLock<T>(_ body: () async throws -> T) async rethrows -> T {
        while lockBusy {
            await withCheckedContinuation { lockWaiters.append($0) }
        }
        lockBusy = true
        defer {
            lockBusy = false
            if !lockWaiters.isEmpty { lockWaiters.removeFirst().resume() }
        }
        return try await body()
    }
}

// MARK: - WKNavigationDelegate

extension WebViewService: WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if navigationResponse.isForMainFrame,
           let http = navigationResponse.response as? HTTPURLResponse {
            sawChallengeHeader = http.value(forHTTPHeaderField: "cf-mitigated") == "challenge"
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if loadContinuation != nil {
            // Initial load finished — possibly on the challenge page; extract() checks
            // sawChallengeHeader next and waits for resolution if needed.
            resumeLoad(.success(()))
        } else if challengeContinuation != nil, !sawChallengeHeader {
            // A main-frame load completed without the challenge header while we were
            // waiting: the user solved it and Cloudflare reloaded the target page.
            resumeChallenge(.success(()))
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        resumeLoad(.failure(SourceError.navigationFailed(error.localizedDescription)))
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        resumeLoad(.failure(SourceError.navigationFailed(error.localizedDescription)))
    }
}
```

Implementer notes (verify these while building — they are the sharp edges):
- **Challenge sub-navigations:** while the Turnstile page is up, Cloudflare fires additional main-frame navigations (the challenge page itself reloading). Those arrive with `cf-mitigated: challenge` still set → the `didFinish` guard `!sawChallengeHeader` correctly ignores them. Only the post-solve reload (no header) resolves the wait.
- **`decidePolicyFor navigationResponse` only fires for HTTP(S) responses**; redirects settle before it. If WKWebView coalesces `didFinish` oddly on the challenge page, an acceptable fallback detection is checking `webView.title` for "Just a moment" — but try the header first; it's the documented signal.
- **Double-resume:** every path funnels through `resumeLoad`/`resumeChallenge` which nil-check-and-clear. Keep it that way.
- The sheet's `onDismiss` calls `cancelChallenge()` even after success — harmless because the continuation is already nil.

- [ ] **Step 2: Write `Manga-Reader/Views/Components/CloudflareChallengeView.swift`**

```swift
//
//  CloudflareChallengeView.swift
//  Manga-Reader
//
//  Sheet content that puts WebViewService's shared browser on screen while a
//  Cloudflare interactive challenge needs a human tap. Purely presentational:
//  the service decides when a challenge is active and when it's cleared.
//

import SwiftUI
import WebKit

struct CloudflareChallengeView: View {
    @ObservedObject private var service = WebViewService.shared

    var body: some View {
        NavigationStack {
            ChallengeWebViewHost(webView: service.webView)
                .navigationTitle("Verification Required")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Hosts the service's existing WKWebView instance (never creates its own —
/// the challenge must run in the same browser that holds the cookies).
private struct ChallengeWebViewHost: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
```

- [ ] **Step 3: Wire the sheet into `Manga-Reader/ContentView.swift`**

Add the state object and wrap the existing `if #available` in a `Group` so one sheet covers both branches. The `body` becomes:

```swift
struct ContentView: View {
    @State private var selectedTab: Tabs = .home
    @StateObject private var webViewService = WebViewService.shared
    
    enum Tabs: Equatable, Hashable, Identifiable  {
        case home
        case bookmarks
        case history
        case search
        case settings

        var id: Self { self }
    }
    
    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                // ... existing TabView (unchanged) ...
            } else {
                // ... existing TabView (unchanged) ...
            }
        }
        .sheet(isPresented: $webViewService.isChallengeActive,
               onDismiss: { webViewService.cancelChallenge() }) {
            CloudflareChallengeView()
        }
    }
}
```

Only the `Group { ... }` wrapper, the `@StateObject` line, and the `.sheet` modifier are new — the two `TabView` blocks are untouched.

- [ ] **Step 4: Build**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Run existing unit tests (regression only — no new tests this task)**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:Manga-ReaderTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git checkout -- Manga-Reader.xcodeproj/project.pbxproj 2>/dev/null || true
git add Manga-Reader/Services/WebViewService.swift Manga-Reader/Views/Components/CloudflareChallengeView.swift Manga-Reader/ContentView.swift
git commit -m "Add WebViewService: Cloudflare-clearing WKWebView JS extraction + challenge sheet

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: `WeebCentralSource` — source #2, TDD against a mock WebView

All URL construction and DTO→domain mapping under unit test via a `MockWebView`. JS scripts are data here (their DOM correctness is verified live in Task 5).

**Files:**
- Create: `Manga-Reader/Models/WeebCentralSource.swift`
- Test: `Manga-ReaderTests/Manga_ReaderTests.swift` (append — the test target is NOT a synchronized group; do not create new test files)

**Interfaces:**
- Consumes: `WebViewExtracting` + `SourceContext` (Task 1); domain types `Manga`, `MangaUpdate`, `MangaDetail`, `Chapter` (memberwise inits, see test code); `MangaSource` protocol.
- Produces: `struct WeebCentralSource: MangaSource` with `static let sourceID = "weebcentral"`, `init(context: SourceContext)`, plus internal (test-visible) statics `WeebCentralSource.searchURL(text:sort:limit:offset:)` and `WeebCentralSource.chapterNumber(fromTitle:)`.

**Endpoint mapping (from the reference extension's network.ts/main.ts):**

| Protocol method | URL |
|---|---|
| `search(title:limit:offset:)` | `/search/data?sort=Best Match&display_mode=Full Display&limit=…&offset=…&text=…` |
| `popular(limit:offset:)` | same, `sort=Popularity`, no `text` |
| `newTitles(limit:offset:)` | same, `sort=Recently Added`, no `text` |
| `latestUpdates(limitTitles:language:)` | `/latest-updates/1` (language ignored — English-only site) |
| `mangaDetail(id:)` | `/series/{id}` |
| `chapters(mangaId:)` | `/series/{id}/full-chapter-list` |
| `pageURLs(chapterId:preferDataSaver:)` | `/chapters/{id}/images?reading_style=long_strip` (`preferDataSaver` ignored — one size) |

`/search/data` is the server-rendered results fragment the site itself fetches (via HTMX) — loading it directly renders a plain document the scripts can query. Using its `sort` values gives all three browse feeds with real `limit`/`offset` pagination through ONE extraction script.

- [ ] **Step 1: Write the failing tests**

Append to `Manga-ReaderTests/Manga_ReaderTests.swift`, inside the `Manga_ReaderTests` class:

```swift
    // MARK: - WeebCentralSource (Phase 2)

    /// Canned-response fake for the WebView seam: returns fixture JSON per URL and
    /// records what was requested, so tests cover URL building + DTO→domain mapping.
    @MainActor
    private final class MockWebView: WebViewExtracting {
        var responses: [String: String] = [:]           // URL absoluteString → JSON
        private(set) var requestedURLs: [URL] = []

        func extract<T: Decodable>(from url: URL, script: String, as type: T.Type) async throws -> T {
            requestedURLs.append(url)
            guard let json = responses[url.absoluteString] else {
                throw SourceError.extractionFailed("no canned response for \(url.absoluteString)")
            }
            return try JSONDecoder().decode(T.self, from: Data(json.utf8))
        }
    }

    @MainActor
    private func makeWeebCentral() -> (WeebCentralSource, MockWebView) {
        let mock = MockWebView()
        return (WeebCentralSource(context: SourceContext(webView: mock)), mock)
    }

    @MainActor func testWeebCentralIdentity() {
        let (source, _) = makeWeebCentral()
        XCTAssertEqual(source.id, "weebcentral")
        XCTAssertEqual(source.name, "WeebCentral")
        XCTAssertFalse(source.isNSFW)
    }

    @MainActor func testWeebCentralSearchBuildsURLAndMapsManga() async throws {
        let (source, mock) = makeWeebCentral()
        let expected = "https://weebcentral.com/search/data?sort=Best%20Match&display_mode=Full%20Display&limit=20&offset=0&text=Naruto"
        mock.responses[expected] = #"""
        [{"id": "01J76XYZ", "title": "Naruto", "cover": "https://temp.compsci88.com/cover/naruto.webp"},
         {"id": "01J76ABC", "title": "Boruto", "cover": null}]
        """#
        let results = try await source.search(title: "Naruto", limit: 20, offset: 0)
        XCTAssertEqual(mock.requestedURLs.first?.absoluteString, expected)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].id, "01J76XYZ")
        XCTAssertEqual(results[0].sourceId, "weebcentral")
        XCTAssertEqual(results[0].title, "Naruto")
        XCTAssertEqual(results[0].coverURL?.absoluteString, "https://temp.compsci88.com/cover/naruto.webp")
        XCTAssertNil(results[1].coverURL)
    }

    @MainActor func testWeebCentralPopularAndNewTitlesUseSortFeeds() async throws {
        let (source, mock) = makeWeebCentral()
        let popularURL = "https://weebcentral.com/search/data?sort=Popularity&display_mode=Full%20Display&limit=10&offset=5"
        let newURL = "https://weebcentral.com/search/data?sort=Recently%20Added&display_mode=Full%20Display&limit=10&offset=0"
        mock.responses[popularURL] = #"[{"id": "p1", "title": "Popular One", "cover": null}]"#
        mock.responses[newURL] = #"[{"id": "n1", "title": "New One", "cover": null}]"#
        let popular = try await source.popular(limit: 10, offset: 5)
        let new = try await source.newTitles(limit: 10, offset: 0)
        XCTAssertEqual(popular.first?.id, "p1")
        XCTAssertEqual(new.first?.id, "n1")
        XCTAssertEqual(new.first?.sourceId, "weebcentral")
    }

    @MainActor func testWeebCentralMangaDetailMapping() async throws {
        let (source, mock) = makeWeebCentral()
        mock.responses["https://weebcentral.com/series/01J76XYZ"] = #"""
        {"description": "A ninja story.", "authors": ["Masashi Kishimoto"],
         "tags": ["Action", "Adventure"], "adult": false}
        """#
        let detail = try await source.mangaDetail(id: "01J76XYZ")
        XCTAssertEqual(detail.description, "A ninja story.")
        XCTAssertEqual(detail.authors, ["Masashi Kishimoto"])
        XCTAssertEqual(detail.tags, ["Action", "Adventure"])
        XCTAssertEqual(detail.contentRating, "safe")
    }

    @MainActor func testWeebCentralChaptersMapping() async throws {
        let (source, mock) = makeWeebCentral()
        mock.responses["https://weebcentral.com/series/01J76XYZ/full-chapter-list"] = #"""
        [{"id": "chap3", "title": "Chapter 105"},
         {"id": "chap2", "title": "Special 3.5"},
         {"id": "chap1", "title": "Oneshot"}]
        """#
        let chapters = try await source.chapters(mangaId: "01J76XYZ")
        XCTAssertEqual(chapters.map(\.id), ["chap3", "chap2", "chap1"])
        XCTAssertEqual(chapters.map(\.number), ["105", "3.5", "?"])
        XCTAssertEqual(chapters[0].title, "Chapter 105")
    }

    @MainActor func testWeebCentralPageURLs() async throws {
        let (source, mock) = makeWeebCentral()
        mock.responses["https://weebcentral.com/chapters/chap3/images?reading_style=long_strip"] = #"""
        ["https://official.lowee.us/manga/x/0001.png", "https://official.lowee.us/manga/x/0002.png"]
        """#
        let pages = try await source.pageURLs(chapterId: "chap3", preferDataSaver: true)
        XCTAssertEqual(pages.map(\.absoluteString),
                       ["https://official.lowee.us/manga/x/0001.png",
                        "https://official.lowee.us/manga/x/0002.png"])
    }

    @MainActor func testWeebCentralLatestUpdates() async throws {
        let (source, mock) = makeWeebCentral()
        mock.responses["https://weebcentral.com/latest-updates/1"] = #"""
        [{"mangaId": "01J76XYZ", "chapterId": "chapZ", "title": "Naruto",
          "cover": "https://temp.compsci88.com/cover/naruto.webp"},
         {"mangaId": "01J76ABC", "chapterId": "chapY", "title": "Boruto", "cover": null}]
        """#
        let updates = try await source.latestUpdates(limitTitles: 1, language: "en")
        XCTAssertEqual(updates.count, 1)                 // truncated to limitTitles
        XCTAssertEqual(updates[0].chapterId, "chapZ")
        XCTAssertEqual(updates[0].manga.id, "01J76XYZ")
        XCTAssertEqual(updates[0].manga.sourceId, "weebcentral")
    }

    func testWeebCentralChapterNumberHelper() {
        XCTAssertEqual(WeebCentralSource.chapterNumber(fromTitle: "Chapter 105"), "105")
        XCTAssertEqual(WeebCentralSource.chapterNumber(fromTitle: "Special 3.5"), "3.5")
        XCTAssertEqual(WeebCentralSource.chapterNumber(fromTitle: "Season 2 Chapter 12"), "12")
        XCTAssertEqual(WeebCentralSource.chapterNumber(fromTitle: "Oneshot"), "?")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:Manga-ReaderTests 2>&1 | tail -20`
Expected: **build failure** — `cannot find 'WeebCentralSource' in scope`.

- [ ] **Step 3: Implement `Manga-Reader/Models/WeebCentralSource.swift`**

```swift
//
//  WeebCentralSource.swift
//  Manga-Reader
//
//  WeebCentral (weebcentral.com) as source #2 — a server-rendered HTML site behind
//  Cloudflare, with no JSON API. Every method loads a page through the context's
//  WebView (which clears Cloudflare) and runs a small JS extraction script whose
//  result is JSON; decoded DTOs are mapped to domain types stamped with
//  `sourceId = "weebcentral"`. DOM selectors were ported (technique only) from the
//  inkdex/general-extensions WeebCentral parsers and verified against live HTML —
//  they are the most volatile part of this source; when WeebCentral redesigns,
//  update the scripts below.
//

import Foundation

struct WeebCentralSource: MangaSource {
    /// Single source of truth for this source's identifier (mirrors `MangaDexSource.sourceID`).
    static let sourceID = "weebcentral"

    let id = WeebCentralSource.sourceID
    let name = "WeebCentral"
    let isNSFW = false

    private let context: SourceContext
    private static let base = URL(string: "https://weebcentral.com")!

    init(context: SourceContext) {
        self.context = context
    }

    // MARK: - MangaSource

    func search(title: String, limit: Int, offset: Int) async throws -> [Manga] {
        try await seriesList(url: Self.searchURL(text: title, sort: "Best Match", limit: limit, offset: offset))
    }

    func popular(limit: Int, offset: Int) async throws -> [Manga] {
        try await seriesList(url: Self.searchURL(text: nil, sort: "Popularity", limit: limit, offset: offset))
    }

    func newTitles(limit: Int, offset: Int) async throws -> [Manga] {
        try await seriesList(url: Self.searchURL(text: nil, sort: "Recently Added", limit: limit, offset: offset))
    }

    func latestUpdates(limitTitles: Int, language: String) async throws -> [MangaUpdate] {
        // `language` ignored: WeebCentral is English-only.
        let url = Self.base.appending(path: "latest-updates/1")
        let items = try await context.webView.extract(from: url, script: Self.latestUpdatesScript,
                                                      as: [WCUpdateItem].self)
        return items.prefix(limitTitles).map { item in
            MangaUpdate(chapterId: item.chapterId, manga: manga(id: item.mangaId, title: item.title, cover: item.cover))
        }
    }

    func mangaDetail(id: String) async throws -> MangaDetail {
        let url = Self.base.appending(path: "series/\(id)")
        let detail = try await context.webView.extract(from: url, script: Self.detailScript, as: WCDetail.self)
        return MangaDetail(
            description: detail.description ?? "",
            authors: detail.authors,
            tags: detail.tags,
            contentRating: detail.adult == true ? "erotica" : "safe"
        )
    }

    func chapters(mangaId: String) async throws -> [Chapter] {
        let url = Self.base.appending(path: "series/\(mangaId)/full-chapter-list")
        let items = try await context.webView.extract(from: url, script: Self.chaptersScript,
                                                      as: [WCChapterItem].self)
        return items.map { Chapter(id: $0.id, number: Self.chapterNumber(fromTitle: $0.title), title: $0.title) }
    }

    func pageURLs(chapterId: String, preferDataSaver: Bool) async throws -> [URL] {
        // `preferDataSaver` ignored: WeebCentral serves a single image size.
        let url = Self.base.appending(path: "chapters/\(chapterId)/images")
            .appending(queryItems: [URLQueryItem(name: "reading_style", value: "long_strip")])
        let strings = try await context.webView.extract(from: url, script: Self.pagesScript, as: [String].self)
        return strings.compactMap(URL.init(string:))
    }

    // MARK: - Mapping helpers

    private func seriesList(url: URL) async throws -> [Manga] {
        let items = try await context.webView.extract(from: url, script: Self.seriesListScript,
                                                      as: [WCSeriesItem].self)
        return items.map { manga(id: $0.id, title: $0.title, cover: $0.cover) }
    }

    /// List feeds carry only id/title/cover — description and status arrive with `mangaDetail`.
    private func manga(id: String, title: String, cover: String?) -> Manga {
        Manga(id: id, sourceId: Self.sourceID, title: title, description: "",
              status: "unknown", year: nil, coverURL: cover.flatMap(URL.init(string:)))
    }

    /// `/search/data` is the server-rendered results fragment the site itself fetches;
    /// its `sort` values ("Best Match" / "Popularity" / "Recently Added") back all three
    /// browse feeds with real limit/offset pagination.
    static func searchURL(text: String?, sort: String, limit: Int, offset: Int) -> URL {
        var items = [
            URLQueryItem(name: "sort", value: sort),
            URLQueryItem(name: "display_mode", value: "Full Display"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if let text, !text.isEmpty {
            items.append(URLQueryItem(name: "text", value: text))
        }
        return base.appending(path: "search/data").appending(queryItems: items)
    }

    /// Chapter rows read like "Chapter 105" / "Special 3.5" — the display number is the
    /// LAST numeric token; rows with no number (e.g. "Oneshot") show "?".
    static func chapterNumber(fromTitle title: String) -> String {
        guard let match = title.matches(of: /\d+(\.\d+)?/).last else { return "?" }
        return String(title[match.range])
    }
}

// MARK: - Wire DTOs (shape produced by the JS extraction scripts)

private struct WCSeriesItem: Decodable {
    let id: String
    let title: String
    let cover: String?
}

private struct WCDetail: Decodable {
    let description: String?
    let authors: [String]
    let tags: [String]
    let adult: Bool?
}

private struct WCChapterItem: Decodable {
    let id: String
    let title: String
}

private struct WCUpdateItem: Decodable {
    let mangaId: String
    let chapterId: String
    let title: String
    let cover: String?
}

// MARK: - JS extraction scripts
//
// Each script is an IIFE whose final expression is a JSON string (the WebView seam's
// contract). Selectors ported from the reference extension and verified live; the
// shared `seg(href, name)` helper pulls the path segment AFTER a given one, so both
// "/series/{id}" and "/series/{id}/{slug}" URL shapes yield the id.

private extension WeebCentralSource {
    static let seriesListScript = #"""
    (() => {
      const seg = (href, name) => {
        const parts = (href || '').replace(/\/$/, '').split('/');
        const i = parts.indexOf(name);
        return i >= 0 && parts[i + 1] ? parts[i + 1] : null;
      };
      const items = [...document.querySelectorAll('article.flex.gap-4')].map(el => {
        const link = el.querySelector('a[href*="/series/"]');
        const titleEl = el.querySelector('a.link.link-hover') || link;
        const img = el.querySelector('img');
        const rawCover = img ? (img.getAttribute('src') || img.getAttribute('data-src')) : null;
        return {
          id: link ? seg(link.getAttribute('href'), 'series') : null,
          title: titleEl ? titleEl.textContent.trim() : '',
          cover: rawCover ? new URL(rawCover, location.href).href : null
        };
      }).filter(x => x.id && x.title);
      return JSON.stringify(items);
    })()
    """#

    static let detailScript = #"""
    (() => {
      const strongWith = (label) =>
        [...document.querySelectorAll('strong')].find(s => s.textContent.includes(label));
      const collect = (root, selector) => {
        const out = [];
        if (root && root.parentElement) {
          root.parentElement.querySelectorAll(selector).forEach(a => {
            const t = a.textContent.trim();
            if (t) out.push(t);
          });
        }
        return out;
      };
      const descEl = document.querySelector('.whitespace-pre-wrap');
      const adultStrong = strongWith('Adult Content');
      const adult = adultStrong && adultStrong.nextElementSibling
        ? adultStrong.nextElementSibling.textContent.trim().toLowerCase() === 'yes'
        : false;
      return JSON.stringify({
        description: descEl ? descEl.textContent.trim() : null,
        authors: collect(strongWith('Author'), 'span a'),
        tags: collect(strongWith('Tag'), 'a'),
        adult
      });
    })()
    """#

    static let chaptersScript = #"""
    (() => {
      const seg = (href, name) => {
        const parts = (href || '').replace(/\/$/, '').split('/');
        const i = parts.indexOf(name);
        return i >= 0 && parts[i + 1] ? parts[i + 1] : null;
      };
      const items = [...document.querySelectorAll('a.flex.items-center')].map(a => {
        const titleEl = a.querySelector('span.grow.flex.gap-2 span')
          || a.querySelector('span.grow span')
          || a.querySelector('span');
        return {
          id: seg(a.getAttribute('href'), 'chapters'),
          title: titleEl ? titleEl.textContent.trim() : ''
        };
      }).filter(x => x.id);
      return JSON.stringify(items);
    })()
    """#

    static let pagesScript = #"""
    (() => {
      const urls = [...document.querySelectorAll('section.cursor-pointer img')]
        .map(img => img.getAttribute('src') || img.getAttribute('data-src'))
        .filter(Boolean)
        .map(u => new URL(u, location.href).href);
      return JSON.stringify(urls);
    })()
    """#

    static let latestUpdatesScript = #"""
    (() => {
      const seg = (href, name) => {
        const parts = (href || '').replace(/\/$/, '').split('/');
        const i = parts.indexOf(name);
        return i >= 0 && parts[i + 1] ? parts[i + 1] : null;
      };
      const items = [...document.querySelectorAll('article')].map(el => {
        const mangaLink = el.querySelector('a.aspect-square') || el.querySelector('a[href*="/series/"]');
        const chapterLink = el.querySelector('a.min-w-0') || el.querySelector('a[href*="/chapters/"]');
        const titleEl = el.querySelector('div.font-semibold');
        const img = el.querySelector('a img');
        const rawCover = img ? (img.getAttribute('src') || img.getAttribute('data-src')) : null;
        return {
          mangaId: mangaLink ? seg(mangaLink.getAttribute('href'), 'series') : null,
          chapterId: chapterLink ? seg(chapterLink.getAttribute('href'), 'chapters') : null,
          title: titleEl ? titleEl.textContent.trim() : '',
          cover: rawCover ? new URL(rawCover, location.href).href : null
        };
      }).filter(x => x.mangaId && x.chapterId && x.title);
      return JSON.stringify(items);
    })()
    """#
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:Manga-ReaderTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **` — all new `testWeebCentral*` tests plus every pre-existing test.

- [ ] **Step 5: Commit**

```bash
git checkout -- Manga-Reader.xcodeproj/project.pbxproj 2>/dev/null || true
git add Manga-Reader/Models/WeebCentralSource.swift Manga-ReaderTests/Manga_ReaderTests.swift
git commit -m "Add WeebCentralSource: HTML-extraction source #2 with mock-WebView tests

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Register WeebCentral in `SourceRegistry`

Wire the real `WebViewService` into a shared `SourceContext` and register WeebCentral as a default source. The Phase-1 Settings picker then shows both sources with zero UI changes.

**Files:**
- Modify: `Manga-Reader/Services/SourceRegistry.swift` (the `init`, currently lines 29–37)
- Test: `Manga-ReaderTests/Manga_ReaderTests.swift` (append)

**Interfaces:**
- Consumes: `WebViewService.shared` (Task 2), `WeebCentralSource(context:)` (Task 3), `SourceContext` (Task 1).
- Produces: `SourceRegistry.init(sources: [MangaSource]? = nil)` — `nil` (the default) builds `[MangaDexSource(), WeebCentralSource(context:)]`. Existing callers that pass explicit arrays (all the Phase-1 tests) still compile unchanged; `MangaDexSource()` keeps its no-context init (the spec's "no-context convenience init" option).

- [ ] **Step 1: Write the failing test**

Append inside the `Manga_ReaderTests` class:

```swift
    // MARK: - Default source registration (Phase 2)

    @MainActor func testDefaultRegistryContainsMangaDexAndWeebCentral() {
        let registry = SourceRegistry()
        XCTAssertEqual(registry.sources.map(\.id), ["mangadex", "weebcentral"])
        XCTAssertNotNil(registry.source(id: "weebcentral"))
        // WeebCentral is not adult content — visible without the adult toggle.
        XCTAssertTrue(registry.visibleSources(includeAdult: false).contains { $0.id == "weebcentral" })
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:Manga-ReaderTests 2>&1 | tail -20`
Expected: `testDefaultRegistryContainsMangaDexAndWeebCentral` FAILS — `["mangadex"] is not equal to ["mangadex", "weebcentral"]`. (It builds; the default registry just lacks WeebCentral.)

- [ ] **Step 3: Implement**

In `Manga-Reader/Services/SourceRegistry.swift`, replace the `init` (and its doc comment) with:

```swift
    /// - Parameter sources: Sources to register, or `nil` for the app's built-in set
    ///   (MangaDex + WeebCentral, sharing one WebView-backed `SourceContext`).
    ///   Injectable so tests can supply mock sources.
    init(sources: [MangaSource]? = nil) {
        let sources = sources ?? Self.builtInSources()
        precondition(!sources.isEmpty, "SourceRegistry requires at least one source")
        self.sources = sources
        // Restore the persisted active source if it still exists; otherwise fall back to the first.
        let stored = UserDefaults.standard.string(forKey: Self.activeKey)
        self.activeSourceID = sources.contains(where: { $0.id == stored }) ? stored! : sources[0].id
    }

    /// The app's compiled-in sources. One `SourceContext` (backed by the shared
    /// Cloudflare-clearing WebView) is built here and handed to every source that
    /// needs it; MangaDex talks to its own API client and takes no context.
    private static func builtInSources() -> [MangaSource] {
        let context = SourceContext(webView: WebViewService.shared)
        return [MangaDexSource(), WeebCentralSource(context: context)]
    }
```

- [ ] **Step 4: Run the full unit suite**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:Manga-ReaderTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **` — the new registration test AND all Phase-1 registry/picker tests (they inject explicit source arrays, so the signature change is compatible).

- [ ] **Step 5: Commit**

```bash
git checkout -- Manga-Reader.xcodeproj/project.pbxproj 2>/dev/null || true
git add Manga-Reader/Services/SourceRegistry.swift Manga-ReaderTests/Manga_ReaderTests.swift
git commit -m "Register WeebCentralSource as a built-in source (shared WebView context)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Live verification — selectors against real HTML, end-to-end reading loop

The scripts' DOM selectors and the Cloudflare flow can only be proven against the live site. This task builds the app, installs it on the simulator, and walks the spec's E2E checklist. **Interactive steps (source switching, Turnstile taps) need the human** — the executor prepares everything, verifies what's automatable, then checkpoints.

**Files:** none created; fix-forward edits to `WeebCentralSource.swift` scripts (and, only if the challenge flow misbehaves, `WebViewService.swift`) as live HTML demands.

- [ ] **Step 1: Verify live HTML matches the selectors (automatable)**

WeebCentral may serve curl without a challenge (Cloudflare is intermittent). Probe each page shape and grep for the selector anchors:

```bash
UA="Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
# 1. Search fragment: expect <article class="... flex gap-4 ..."> rows with /series/ links
curl -s -A "$UA" "https://weebcentral.com/search/data?sort=Best%20Match&display_mode=Full%20Display&limit=5&offset=0&text=naruto" -D - -o /tmp/wc-search.html | grep -i "cf-mitigated"; grep -c "article" /tmp/wc-search.html
# 2. Pick a series id from the search output, then:
#    /series/{id}            → expect <strong>Author…, .whitespace-pre-wrap
#    /series/{id}/full-chapter-list → expect a.flex.items-center rows with /chapters/ hrefs
#    /chapters/{id}/images?reading_style=long_strip → expect section.cursor-pointer imgs
```

If `cf-mitigated: challenge` comes back, curl can't see the HTML — skip to Step 2 and verify selectors through the app itself. If HTML IS visible and a selector doesn't match, fix the script in `WeebCentralSource.swift` (and update the reference-comment) — the mock tests won't notice script changes, that's by design.

- [ ] **Step 2: Build and install on the simulator**

```bash
xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3
xcrun simctl boot "iPhone 17" 2>/dev/null || true
APP=$(find ~/Library/Developer/Xcode/DerivedData -path "*Build/Products/Debug-iphonesimulator/Manga-Reader.app" -newer /tmp -print -quit 2>/dev/null || find ~/Library/Developer/Xcode/DerivedData -path "*Debug-iphonesimulator/Manga-Reader.app" -print -quit)
xcrun simctl install booted "$APP"
xcrun simctl launch booted Elias-Magdaleno.Manga-Reader
```

Expected: app launches to the Home tab (MangaDex feeds — unchanged behavior).

- [ ] **Step 3: Human checkpoint — interactive E2E (from the spec)**

Ask the user to run this checklist in the booted simulator (there is no tap tool; per project convention interactive flows are human-verified):

1. Settings → source picker shows **MangaDex + WeebCentral**; select WeebCentral.
2. Home re-sources: Popular / New Titles / Latest Updates rails fill from WeebCentral (first loads take seconds — three serialized WebView navigations; a Cloudflare sheet may appear once — tap it through).
3. Search for a title → results appear.
4. Open a title → detail loads (description, authors, tags).
5. Open a chapter → pages render in the reader (through the Phase-1 image cache).
6. Bookmark the title, switch the source back to MangaDex → Home shows MangaDex again → reopen the WeebCentral bookmark from Library → it loads via WeebCentral (`source(for:)` routing).

Fix any failures (selector tweaks in the scripts, challenge-flow adjustments in `WebViewService`) and re-run the failing step until the checklist passes. Re-run the unit suite after any source-file change.

- [ ] **Step 4: Final full test run + clean tree**

```bash
xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:Manga-ReaderTests 2>&1 | tail -5
git checkout -- Manga-Reader.xcodeproj/project.pbxproj 2>/dev/null || true
git status --short
```

Expected: `** TEST SUCCEEDED **`; working tree clean except intentionally-modified files.

- [ ] **Step 5: Commit any live-verification fixes**

```bash
git add -u Manga-Reader/
git commit -m "Fix WeebCentral selectors/challenge flow after live verification

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

(Skip if Step 3 needed no changes.)

---

## Addendum (2026-07-15, post-checkpoint): human E2E findings + requested follow-ups

Checkpoint results: pages ✓, details ✓, switching works but Home only re-sources after app relaunch (spec gap — spec says "selecting WeebCentral re-sources Home"). User also requested: persistent reader zoom, a source label on the detail page, and an open-on-web button (in-app Safari).

### Task 6: Home re-sources immediately when the active source changes

**Files:**
- Modify: `Manga-Reader/Models/HomeViewModel.swift`
- Modify: `Manga-Reader/Views/HomeView.swift` (lines 9 and 51)
- Test: `Manga-ReaderTests/Manga_ReaderTests.swift` (append)

**Interfaces:**
- Consumes: `SourceRegistry.shared` (`@Published var activeSourceID: String`, `var active: MangaSource`).
- Produces: `HomeViewModel.init(source: MangaSource? = nil)` (same signature as today), `var source: MangaSource` now resolves the registry's active source dynamically when no override was injected.

- [ ] **Step 1: Write the failing test** (append inside the `Manga_ReaderTests` class):

```swift
    // MARK: - Home source switching (Phase 2 addendum)

    @MainActor func testHomeViewModelInjectedSourceWins() {
        let vm = HomeViewModel(source: MockSource(id: "mock", name: "Mock"))
        XCTAssertEqual(vm.source.id, "mock")
    }

    @MainActor func testHomeViewModelDefaultsToRegistryActiveSource() {
        // No override → the vm must track SourceRegistry.shared.active *at read time*,
        // not capture it at init.
        let vm = HomeViewModel()
        XCTAssertEqual(vm.source.id, SourceRegistry.shared.activeSourceID)
    }
```

> **Executed as amended:** `testHomeViewModelDefaultsToRegistryActiveSource` was dropped during
> review (it passed under both the old and new implementations — a tautology) and replaced by
> `testSupersededHomeLoadNeitherClobbersRailsNorSurfacesCancellation`, which pins the
> stale-source clobber fix (commit 2c0df62).

Note: `MockSource` already exists in the test file (~line 320). Do NOT mutate `SourceRegistry.shared.activeSourceID` in tests (it persists to real UserDefaults).

- [ ] **Step 2: Run tests, expect** `testHomeViewModelDefaultsToRegistryActiveSource` to pass trivially but `testHomeViewModelInjectedSourceWins` to pass too under the CURRENT code — so the real red is behavioral, not unit-testable: the unit tests pin the contract; the fix is verified live. If both pass before the change, proceed (document this in the report).

- [ ] **Step 3: Implement.** In `HomeViewModel`:

```swift
    /// Injected source for tests; nil means "track the registry's active source".
    private let sourceOverride: MangaSource?
    /// The source these browse feeds come from — resolved at read time so a Settings
    /// switch re-sources Home without an app relaunch.
    var source: MangaSource { sourceOverride ?? SourceRegistry.shared.active }
    /// The source id the current feed arrays were loaded from (nil before first load).
    private var loadedSourceID: String?

    init(source: MangaSource? = nil) {
        self.sourceOverride = source
    }

    func loadHome() {
        // Clear stale feeds when the active source changed since the last load, so the
        // previous source's rails don't linger while the new one fetches.
        let activeID = source.id
        if let loaded = loadedSourceID, loaded != activeID {
            popular = []; latestUpdates = []; newTitles = []
            errorMessage = nil
        }
        loadedSourceID = activeID
        Task {
            await loadHomeAsync()
        }
    }
```

(`loadHomeAsync` and the reload helpers stay as they are; they already read `source` per call.)

In `HomeView`: add `@ObservedObject private var registry = SourceRegistry.shared` under the `@StateObject` line, and change `.task { vm.loadHome() }` to `.task(id: registry.activeSourceID) { vm.loadHome() }`.

- [ ] **Step 4: Run the unit suite** (green) and build.
- [ ] **Step 5: Commit** `Manga-Reader/Models/HomeViewModel.swift Manga-Reader/Views/HomeView.swift Manga-ReaderTests/Manga_ReaderTests.swift` — message: `Re-source Home immediately when the active source changes` + trailer.

### Task 7: Reader zoom must not reset on its own

**Files:**
- Modify: `Manga-Reader/Views/ReaderView.swift` (the `ZoomablePage` struct, lines ~279-374)
- Test: none (gesture behavior — build + manual verification; describe your manual reasoning in the report)

**Symptom (user report):** after double-tap-to-zoom or pinch-to-zoom, the page zooms back out by itself.

**Required behavior:** zoom persists until the user explicitly zooms out (double-tap while zoomed, or pinch back below 1×). Resetting when the user pages away to a DIFFERENT page is acceptable and desirable. Webtoon mode has no zoom — out of scope.

**Prime suspects (verify, then fix what's real):**
1. `.onDisappear { resetZoom() }` (~line 305) — in a `.page`-style `TabView`, offscreen-neighbor churn / chrome (toolbar) toggling can fire `onDisappear` for the still-visible page, nuking the zoom. If confirmed: remove it and instead reset when the pager's selection actually changes (e.g. pass the current selection index into `ZoomablePage` and `.onChange(of:)` it, or reset via the existing `index` when it stops being the selected page).
2. The structural branch `if scale > 1 { base.gesture(pan) } else { base }` (~lines 308-312) — switching branches mid-pinch tears down the in-flight gesture. Replace with a structurally-stable mask: `base.gesture(pan, including: scale > 1 ? .all : .subviews)` so the pan gesture exists always but yields to the TabView swipe at 1×.

Keep the fix minimal and inside `ZoomablePage` (plus its call site if the selection index needs passing). Preserve: pan-only-while-zoomed (TabView must still own the swipe at 1×), double-tap toggles 1×/2.5×, pinch clamped 1×–4×, snap-back animation when pinching below 1×.

- [ ] **Step 1:** Read `ZoomablePage` and its call site; confirm which suspect(s) actually cause the reset (reason it through; note SwiftUI TabView page lifecycle).
- [ ] **Step 2:** Implement the minimal fix.
- [ ] **Step 3:** Build (`** BUILD SUCCEEDED **`) and run the unit suite (green — no reader tests exist, this is regression only).
- [ ] **Step 4: Commit** `Manga-Reader/Views/ReaderView.swift` — message: `Keep reader zoom until the user zooms out` + trailer.

### Task 8: Detail page shows the manga's source + opens its page in an in-app browser

**Files:**
- Modify: `Manga-Reader/Models/MangaSource.swift` (protocol + default impl)
- Modify: `Manga-Reader/Models/MangaDexSource.swift`
- Modify: `Manga-Reader/Models/WeebCentralSource.swift`
- Create: `Manga-Reader/Views/Components/SafariView.swift`
- Modify: `Manga-Reader/Views/MangaDetailView.swift`
- Test: `Manga-ReaderTests/Manga_ReaderTests.swift` (append)

**Interfaces:**
- Produces: `MangaSource.webURL(forManga id: String) -> URL?` — optional capability, default `nil` (same pattern as `newTitles`); `struct SafariView: UIViewControllerRepresentable` with `let url: URL`.

- [ ] **Step 1: Write the failing tests** (append inside the class):

```swift
    // MARK: - Source web URLs (Phase 2 addendum)

    func testMangaDexWebURL() {
        XCTAssertEqual(MangaDexSource().webURL(forManga: "abc-123")?.absoluteString,
                       "https://mangadex.org/title/abc-123")
    }

    @MainActor func testWeebCentralWebURL() {
        let (source, _) = makeWeebCentral()
        XCTAssertEqual(source.webURL(forManga: "01J76XYZ")?.absoluteString,
                       "https://weebcentral.com/series/01J76XYZ")
    }

    func testWebURLDefaultsToNil() {
        XCTAssertNil(MockSource(id: "x", name: "X").webURL(forManga: "y"))
    }
```

- [ ] **Step 2: Run tests** — expect build failure (`webURL` not defined).
- [ ] **Step 3: Implement.**

`MangaSource.swift` — add to the protocol (below `pageURLs`):
```swift
    /// The human-facing web page for a manga on the source's site (for "open in
    /// browser"). Optional capability; nil when the source has no web presence.
    func webURL(forManga id: String) -> URL?
```
and to the optional-capabilities extension:
```swift
    func webURL(forManga id: String) -> URL? { nil }
```

`MangaDexSource.swift`:
```swift
    func webURL(forManga id: String) -> URL? {
        URL(string: "https://mangadex.org/title/\(id)")
    }
```

`WeebCentralSource.swift` (below `pageURLs`):
```swift
    func webURL(forManga id: String) -> URL? {
        Self.base.appending(path: "series/\(id)")
    }
```

`Views/Components/SafariView.swift` (new):
```swift
//
//  SafariView.swift
//  Manga-Reader
//
//  In-app Safari (SFSafariViewController) presented as a sheet — used by the manga
//  detail screen's "open on web" action so users never leave the app.
//

import SwiftUI
import SafariServices

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
```

`MangaDetailView.swift`:
- Add state + helpers:
```swift
    @State private var showingWebPage = false

    /// The registered source this manga came from (nil if its source was unregistered).
    private var mangaSource: MangaSource? {
        SourceRegistry.shared.source(id: manga.sourceId)
    }

    private var mangaWebURL: URL? {
        mangaSource?.webURL(forManga: manga.id)
    }
```
- In the hero's stamp `HStack` (after the content-rating stamp), show the originating source:
```swift
                        InkStamp(text: (mangaSource?.name ?? manga.sourceId).uppercased(), tinted: true)
```
- Add a toolbar item (inside the existing `.toolbar`, alongside the `if isSelecting` group):
```swift
            ToolbarItem(placement: .topBarTrailing) {
                if let url = mangaWebURL {
                    Button {
                        showingWebPage = true
                    } label: {
                        Image(systemName: "safari")
                    }
                    .accessibilityLabel("Open on \(mangaSource?.name ?? "web")")
                    .sheet(isPresented: $showingWebPage) {
                        SafariView(url: url)
                            .ignoresSafeArea()
                    }
                }
            }
```

- [ ] **Step 4: Run the unit suite** (all green) and build.
- [ ] **Step 5: Commit** the five source files + test file — message: `Show manga's source on detail + open its page in in-app Safari` + trailer.
