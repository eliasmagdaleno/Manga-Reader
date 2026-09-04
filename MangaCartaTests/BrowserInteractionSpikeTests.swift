//
//  BrowserInteractionSpikeTests.swift
//  MangaCartaTests
//
//  The S3 spike for acceptance criterion 8: a background challenge must return
//  `interaction_required` WITHOUT presenting UI.
//
//  §4.2 shows `host.browser.extract`'s `interaction` parameter only through its default,
//  `"allowForeground"`, and names no other case — while §9 and criterion 8 both require a
//  mode that never presents a sheet. The enum is missing from the contract. This file is
//  the prototype that says what the cases have to be, and the argument for them is in
//  ADR-0003 Amendment 3.
//
//  Nothing here is the production capability; S5 builds that. What is being proved is the
//  decision rule, against a real `WKWebView` seeing a real `cf-mitigated: challenge`
//  response header — the same signal `WebViewService` keys on today, served by a loopback
//  socket so the test needs no internet and no Cloudflare.
//
//  Two cheaper ways to deliver that header were tried first and neither works, which is
//  worth recording so nobody retries them: a `WKURLSchemeHandler` response reaches
//  `decidePolicyFor navigationResponse` downgraded to a bare `NSURLResponse` with every
//  header stripped, and `loadSimulatedRequest` does not run the response-policy step at
//  all. Only a real network load carries response headers to the delegate.
//

import XCTest
import WebKit
import Network
@testable import MangaCarta

// MARK: - The contract gap, filled

/// What an Extension author may ask for. Not "is the app foregrounded" — an engine cannot
/// know that, and §9 makes the no-UI rule a property of the invocation, not of the author.
enum SpikeInteraction {
    /// §4.2's default. A sheet is permissible, but only when the host is also foreground.
    case allowForeground
    /// Never present a sheet, even in the foreground: speculative or bulk work that is not
    /// worth interrupting the reader for. Any challenge is `interaction_required`.
    case never
}

/// What the host knows and the author does not.
enum SpikeInvocationContext {
    case foreground
    case background
}

/// §9's four distinct outcomes. Only `interactionRequired` is in scope for criterion 8;
/// the others are here because the spec is explicit that they must not be collapsed.
enum SpikeBrowserError: Error, Equatable {
    case interactionRequired
    case interactionDeclined
    case interactionTimedOut
    case cancelled
}

/// The smallest thing that can put a real `cf-mitigated` header on the wire: one loopback
/// TCP listener answering any request with a fixed page. App Transport Security exempts
/// loopback, so plain HTTP is fine here — §10's HTTPS-only rule governs Source-declared
/// origins, not a test fixture.
private final class SpikeLoopbackServer {

    var servesChallenge = true
    private let listener: NWListener
    private let queue = DispatchQueue(label: "spike.loopback")

    init() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> UInt16 {
        listener.newConnectionHandler = { [weak self] connection in
            self?.serve(connection)
        }
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            listener.stateUpdateHandler = { [weak listener] state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    continuation.resume(returning: listener?.port?.rawValue ?? 0)
                case .failed(let error):
                    resumed = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        return port
    }

    func stop() {
        listener.cancel()
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        // Read the request line and headers, then answer. The body never matters here.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] _, _, _, _ in
            guard let self else { return }
            let body = "<html><body><b id='t'>extracted</b></body></html>"
            var headers = [
                "HTTP/1.1 200 OK",
                "Content-Type: text/html; charset=utf-8",
                "Content-Length: \(body.utf8.count)",
                "Connection: close",
            ]
            if self.servesChallenge { headers.append("cf-mitigated: challenge") }
            let response = headers.joined(separator: "\r\n") + "\r\n\r\n" + body
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}

/// A cut-down `WebViewService`: load, notice the challenge header, decide. The decision is
/// the whole point; solving a challenge is not modelled, because criterion 8 is about what
/// happens *before* anyone is asked to solve one.
@MainActor
private final class SpikeBrowserExtractor: NSObject, WKNavigationDelegate {

    /// Stands in for `WebViewService.isChallengeActive`, the flag that drives the sheet.
    /// A background invocation must leave it false.
    private(set) var didPresentChallengeSheet = false

    private let server: SpikeLoopbackServer
    private let webView: WKWebView
    private var sawChallengeHeader = false
    private var loadContinuation: CheckedContinuation<Void, Error>?

    init(servesChallenge: Bool) throws {
        server = try SpikeLoopbackServer()
        server.servesChallenge = servesChallenge
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844),
                            configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    /// Brings the fixture site up and returns its URL.
    func start() async throws -> URL {
        let port = try await server.start()
        return URL(string: "http://127.0.0.1:\(port)/manga/1")!
    }

    func stop() {
        server.stop()
    }

    /// The one rule this prototype exists to state: a sheet may be presented only when the
    /// author allowed it AND the host is foreground. The effective policy is the
    /// intersection of the two, never either alone.
    private func mayPresentSheet(_ interaction: SpikeInteraction,
                                 _ context: SpikeInvocationContext) -> Bool {
        interaction == .allowForeground && context == .foreground
    }

    func extract(url: URL,
                 script: String = "document.getElementById('t').textContent",
                 interaction: SpikeInteraction = .allowForeground,
                 context: SpikeInvocationContext) async throws -> String {
        try await load(url)
        if sawChallengeHeader {
            guard mayPresentSheet(interaction, context) else {
                throw SpikeBrowserError.interactionRequired
            }
            didPresentChallengeSheet = true
            // A real host would wait here. What the spike must show is that the sheet went
            // up at all, which is exactly what criterion 8 forbids elsewhere.
            throw SpikeBrowserError.interactionDeclined
        }
        guard let value = try await webView.evaluateJavaScript(script) as? String else {
            throw SpikeBrowserError.cancelled
        }
        return value
    }

    private func load(_ url: URL) async throws {
        sawChallengeHeader = false
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loadContinuation = continuation
            webView.load(URLRequest(url: url))
        }
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if navigationResponse.isForMainFrame,
           let http = navigationResponse.response as? HTTPURLResponse {
            sawChallengeHeader = http.value(forHTTPHeaderField: "cf-mitigated")?.lowercased() == "challenge"
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: error)
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: error)
        loadContinuation = nil
    }
}

// MARK: - Tests

@MainActor
final class BrowserInteractionSpikeTests: XCTestCase {

    private var extractor: SpikeBrowserExtractor!

    private func startExtractor(servesChallenge: Bool) async throws -> URL {
        extractor = try SpikeBrowserExtractor(servesChallenge: servesChallenge)
        return try await extractor.start()
    }

    override func tearDown() async throws {
        extractor?.stop()
        extractor = nil
    }

    /// Criterion 8. The header says "challenge", the invocation is background: the call
    /// comes back `interaction_required` and no sheet was raised.
    func testBackgroundChallengeReturnsInteractionRequiredWithoutPresentingUI() async throws {
        let url = try await startExtractor(servesChallenge: true)

        do {
            _ = try await extractor.extract(url: url, interaction: .allowForeground, context: .background)
            XCTFail("a background challenge returned a value instead of an error")
        } catch {
            XCTAssertEqual(error as? SpikeBrowserError, .interactionRequired)
        }
        XCTAssertFalse(extractor.didPresentChallengeSheet,
                       "a background invocation put a challenge sheet in front of the reader")
    }

    /// The same refusal for an author who asked never to interrupt, even in the foreground.
    /// This is the case §4.2's signature does not name.
    func testNeverInteractionRefusesInForegroundToo() async throws {
        let url = try await startExtractor(servesChallenge: true)

        do {
            _ = try await extractor.extract(url: url, interaction: .never, context: .foreground)
            XCTFail("`never` presented or solved a challenge")
        } catch {
            XCTAssertEqual(error as? SpikeBrowserError, .interactionRequired)
        }
        XCTAssertFalse(extractor.didPresentChallengeSheet)
    }

    /// The control that gives the two assertions above their meaning. Same challenge, same
    /// code path, allowed and foreground — the sheet goes up, and the error is the distinct
    /// `interaction_declined`. Without this, `didPresentChallengeSheet == false` could just
    /// mean the flag never flips.
    func testForegroundChallengePresentsTheSheetAndReportsDeclineDistinctly() async throws {
        let url = try await startExtractor(servesChallenge: true)

        do {
            _ = try await extractor.extract(url: url, interaction: .allowForeground, context: .foreground)
            XCTFail("the spike is not supposed to solve challenges")
        } catch {
            XCTAssertEqual(error as? SpikeBrowserError, .interactionDeclined,
                           "decline must stay distinct from interaction_required")
        }
        XCTAssertTrue(extractor.didPresentChallengeSheet,
                      "the foreground path never raised a sheet, so the tests above prove nothing")
    }

    /// And the other control: background does not mean "fail everything". An unchallenged
    /// page extracts normally, so `interaction_required` above is a response to the
    /// challenge and not to the context.
    func testBackgroundExtractionSucceedsWhenThereIsNoChallenge() async throws {
        let url = try await startExtractor(servesChallenge: false)

        let value = try await extractor.extract(url: url, interaction: .allowForeground, context: .background)

        XCTAssertEqual(value, "extracted")
        XCTAssertFalse(extractor.didPresentChallengeSheet)
    }
}
