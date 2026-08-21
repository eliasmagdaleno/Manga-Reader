//
//  MALOAuthTests.swift
//  Manga-ReaderTests
//
//  Pure OAuth value construction and callback validation for MyAnimeList.
//

import XCTest
@testable import Manga_Reader

final class MALOAuthTests: XCTestCase {

    // MARK: - PKCE

    func testVerifierUsesOnlyURLSafeCharactersAndTheDocumentedLength() {
        let verifier = MALPKCE.makeVerifier(randomBytes: { count in
            Data(repeating: 0xFF, count: count)
        })

        XCTAssertGreaterThanOrEqual(verifier.count, 43)
        XCTAssertLessThanOrEqual(verifier.count, 128)
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        XCTAssertTrue(verifier.unicodeScalars.allSatisfy(allowed.contains),
                      "verifier must be unreserved URL characters only")
    }

    func testChallengeEqualsTheVerifierBecauseMALSupportsOnlyPlain() {
        let verifier = MALPKCE.makeVerifier(randomBytes: { Data(repeating: 0x01, count: $0) })
        XCTAssertEqual(MALPKCE.challenge(for: verifier), verifier)
    }

    func testDistinctRandomnessProducesDistinctVerifiers() {
        var seed: UInt8 = 0
        let next = { (count: Int) -> Data in
            seed += 1
            return Data(repeating: seed, count: count)
        }
        let first = MALPKCE.makeVerifier(randomBytes: next)
        let second = MALPKCE.makeVerifier(randomBytes: next)
        XCTAssertNotEqual(first, second)
    }

    // MARK: - Authorization URL

    private static let config = MALOAuthConfiguration(
        clientID: "test-client",
        redirectURI: "mangareader://oauth/mal")

    func testAuthorizationURLCarriesExactlyTheDocumentedParameters() throws {
        let url = MALOAuth.authorizationURL(configuration: Self.config,
                                            state: "state-123",
                                            verifier: "verifier-abc")

        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "myanimelist.net")
        XCTAssertEqual(components.path, "/v1/oauth2/authorize")

        let items = Dictionary(uniqueKeysWithValues:
            (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["response_type"], "code")
        XCTAssertEqual(items["client_id"], "test-client")
        XCTAssertEqual(items["state"], "state-123")
        XCTAssertEqual(items["redirect_uri"], "mangareader://oauth/mal")
        XCTAssertEqual(items["code_challenge"], "verifier-abc")
        XCTAssertEqual(items["code_challenge_method"], "plain")
        XCTAssertNil(items["scope"], "no scope is sent until the live contract proves one is needed")
        XCTAssertNil(items["client_secret"], "a public client must never carry a secret")
        XCTAssertEqual(items.count, 6)
    }

    // MARK: - Callback validation

    func testCallbackIsAcceptedOnlyForTheExactRedirectAndMatchingState() throws {
        let url = try XCTUnwrap(URL(string: "mangareader://oauth/mal?code=abc123&state=state-123"))
        let outcome = MALOAuth.outcome(for: url, configuration: Self.config, expectedState: "state-123")
        XCTAssertEqual(outcome, .code("abc123"))
    }

    func testCallbackWithMismatchedOrMissingStateIsRejected() throws {
        let mismatched = try XCTUnwrap(URL(string: "mangareader://oauth/mal?code=abc&state=wrong"))
        XCTAssertEqual(MALOAuth.outcome(for: mismatched, configuration: Self.config,
                                        expectedState: "state-123"), .rejected)

        let missing = try XCTUnwrap(URL(string: "mangareader://oauth/mal?code=abc"))
        XCTAssertEqual(MALOAuth.outcome(for: missing, configuration: Self.config,
                                        expectedState: "state-123"), .rejected)
    }

    func testCallbackForAForeignURLIsRejected() throws {
        for raw in ["https://myanimelist.net/oauth/mal?code=abc&state=state-123",
                    "mangareader://oauth/other?code=abc&state=state-123",
                    "otherapp://oauth/mal?code=abc&state=state-123"] {
            let url = try XCTUnwrap(URL(string: raw))
            XCTAssertEqual(MALOAuth.outcome(for: url, configuration: Self.config,
                                            expectedState: "state-123"), .rejected,
                           "\(raw) must not be treated as our callback")
        }
    }

    func testCallbackWithAnEmptyOrAbsentCodeIsRejected() throws {
        for raw in ["mangareader://oauth/mal?code=&state=state-123",
                    "mangareader://oauth/mal?state=state-123"] {
            let url = try XCTUnwrap(URL(string: raw))
            XCTAssertEqual(MALOAuth.outcome(for: url, configuration: Self.config,
                                            expectedState: "state-123"), .rejected)
        }
    }

    func testUserCancellationIsADistinctOutcomeRatherThanAnError() throws {
        let url = try XCTUnwrap(URL(string:
            "mangareader://oauth/mal?error=access_denied&state=state-123"))
        XCTAssertEqual(MALOAuth.outcome(for: url, configuration: Self.config,
                                        expectedState: "state-123"), .cancelled)
    }

    func testOtherStandardErrorsArePreservedWithTheirDescription() throws {
        let url = try XCTUnwrap(URL(string:
            "mangareader://oauth/mal?error=invalid_request&error_description=bad%20thing&state=state-123"))
        XCTAssertEqual(MALOAuth.outcome(for: url, configuration: Self.config,
                                        expectedState: "state-123"),
                       .failed(code: "invalid_request", description: "bad thing"))
    }

    // MARK: - Token request encoding

    func testAuthorizationCodeExchangeSendsTheDocumentedFormAndNoSecret() throws {
        let request = MALTokenRequest.authorizationCode(code: "the code", verifier: "verifier-abc")
        let body = try XCTUnwrap(String(bytes: request.formBody(configuration: Self.config), encoding: .utf8))

        XCTAssertEqual(body,
                       "client_id=test-client"
                       + "&grant_type=authorization_code"
                       + "&code=the%20code"
                       + "&redirect_uri=mangareader%3A%2F%2Foauth%2Fmal"
                       + "&code_verifier=verifier-abc")
        XCTAssertFalse(body.contains("client_secret"),
                       "the MAL client is issued no secret; sending one would be a leak, not auth")
    }

    func testRefreshSendsOnlyGrantTypeClientAndRefreshToken() throws {
        let request = MALTokenRequest.refresh(refreshToken: "refresh-1")
        let body = try XCTUnwrap(String(bytes: request.formBody(configuration: Self.config), encoding: .utf8))

        XCTAssertEqual(body, "client_id=test-client&grant_type=refresh_token&refresh_token=refresh-1")
        XCTAssertFalse(body.contains("redirect_uri"), "refresh carries no redirect URI")
        XCTAssertFalse(body.contains("client_secret"))
    }

    func testTokenRequestPostsFormEncodedToTheDocumentedEndpoint() {
        let request = MALTokenRequest.refresh(refreshToken: "r").urlRequest(configuration: Self.config)

        XCTAssertEqual(request.url?.absoluteString, "https://myanimelist.net/v1/oauth2/token")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"),
                       "application/x-www-form-urlencoded")
        XCTAssertNotNil(request.httpBody)
    }

    // MARK: - Token response and credential

    func testTokenResponseDecodesTheDocumentedPayload() throws {
        let json = Data(#"{"token_type":"Bearer","expires_in":2415600,"access_token":"ACCESS","refresh_token":"REFRESH"}"#.utf8)

        let response = try JSONDecoder().decode(MALTokenResponse.self, from: json)
        XCTAssertEqual(response, MALTokenResponse(tokenType: "Bearer", expiresIn: 2_415_600,
                                                  accessToken: "ACCESS", refreshToken: "REFRESH"))
    }

    func testExpiryComesFromTheRuntimeValueRatherThanAHardCodedLifetime() {
        let received = Date(timeIntervalSince1970: 1_000_000)
        let response = MALTokenResponse(tokenType: "Bearer", expiresIn: 3600,
                                        accessToken: "A", refreshToken: "R")

        let credential = MALCredential(response: response, receivedAt: received)
        XCTAssertEqual(credential.expiresAt, received.addingTimeInterval(3600))
    }

    func testRefreshIsDueBeforeTheTokenActuallyExpires() {
        let expiry = Date(timeIntervalSince1970: 1_000_000)
        let credential = MALCredential(tokenType: "Bearer", accessToken: "A",
                                       refreshToken: "R", expiresAt: expiry)

        XCTAssertFalse(credential.needsRefresh(at: expiry.addingTimeInterval(-3600)))
        XCTAssertTrue(credential.needsRefresh(at: expiry.addingTimeInterval(-60)))
        XCTAssertTrue(credential.needsRefresh(at: expiry))
    }

    func testCredentialDebugDescriptionCarriesNoSecret() {
        let credential = MALCredential(tokenType: "Bearer", accessToken: "SECRET-ACCESS",
                                       refreshToken: "SECRET-REFRESH", expiresAt: Date())
        XCTAssertFalse(credential.debugDescription.contains("SECRET-ACCESS"))
        XCTAssertFalse(credential.debugDescription.contains("SECRET-REFRESH"))
    }

    // MARK: - Session

    private func makeSession() -> MALOAuthSession {
        MALOAuthSession(configuration: Self.config, state: "state-123", verifier: "verifier-abc")
    }

    func testSessionAcceptsTheFirstValidCallback() throws {
        let session = makeSession()
        let url = try XCTUnwrap(URL(string: "mangareader://oauth/mal?code=abc&state=state-123"))

        XCTAssertEqual(session.complete(with: url), .code("abc"))
        XCTAssertTrue(session.isFinished)
        XCTAssertEqual(session.exchange(code: "abc"),
                       .authorizationCode(code: "abc", verifier: "verifier-abc"))
    }

    func testSessionRejectsADuplicateCompletion() throws {
        let session = makeSession()
        let url = try XCTUnwrap(URL(string: "mangareader://oauth/mal?code=abc&state=state-123"))

        XCTAssertEqual(session.complete(with: url), .code("abc"))
        XCTAssertEqual(session.complete(with: url), .rejected,
                       "a second callback is not a second authorization")
    }

    func testSessionRejectsACallbackArrivingAfterCancellation() throws {
        let session = makeSession()
        XCTAssertEqual(session.cancel(), .cancelled)

        let url = try XCTUnwrap(URL(string: "mangareader://oauth/mal?code=abc&state=state-123"))
        XCTAssertEqual(session.complete(with: url), .rejected)
    }

    func testSessionCancellationIsItselfNotRepeatable() {
        let session = makeSession()
        XCTAssertEqual(session.cancel(), .cancelled)
        XCTAssertEqual(session.cancel(), .rejected)
    }

    func testAnUnrelatedCallbackDoesNotEndTheSession() throws {
        let session = makeSession()
        let foreign = try XCTUnwrap(URL(string: "otherapp://oauth/mal?code=abc&state=state-123"))
        XCTAssertEqual(session.complete(with: foreign), .rejected)
        XCTAssertFalse(session.isFinished, "the real redirect may still be coming")

        let real = try XCTUnwrap(URL(string: "mangareader://oauth/mal?code=abc&state=state-123"))
        XCTAssertEqual(session.complete(with: real), .code("abc"))
    }

    func testSessionAuthorizationURLMatchesThePureBuilder() {
        let session = makeSession()
        XCTAssertEqual(session.authorizationURL,
                       MALOAuth.authorizationURL(configuration: Self.config,
                                                 state: "state-123",
                                                 verifier: "verifier-abc"))
    }
}
