//
//  MALOAuth.swift
//  MangaCarta
//
//  Pure OAuth values for MyAnimeList: PKCE, the authorization URL, callback
//  validation, and token-request encoding. Deliberately free of SwiftUI and of
//  any network or Keychain dependency so all of it is testable in isolation.
//

import Foundation

/// PKCE values for MyAnimeList.
///
/// MAL documents **only** `plain` — the challenge *is* the verifier, with no SHA-256
/// transform. That is weaker than `S256` and is not our choice; sending `S256` against the
/// published contract fails. Revisit if MAL ever documents it.
enum MALPKCE {
    /// MAL requires 43–128 characters. 64 random bytes rendered as unreserved characters
    /// sits comfortably inside that window.
    static let verifierByteCount = 64

    /// The unreserved set from RFC 3986, which is exactly what PKCE permits in a verifier.
    private static let alphabet = Array(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Randomness is injected so tests can pin exact output; production passes a
    /// cryptographically secure generator.
    static func makeVerifier(randomBytes: (Int) -> Data) -> String {
        let bytes = randomBytes(verifierByteCount)
        // Modulo bias across a 64-character alphabet and 256 byte values is negligible
        // here (256 is exactly 4 × 64, so the mapping is uniform).
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    /// Under `plain`, the challenge is the verifier verbatim.
    static func challenge(for verifier: String) -> String { verifier }
}

/// The non-secret client configuration. There is no `clientSecret` field on purpose:
/// the MAL client is App Type `ios` and is issued no secret (verified 2026-08-21), and a
/// secret bundled in an app binary would not be confidential anyway.
struct MALOAuthConfiguration: Equatable {
    let clientID: String
    let redirectURI: String
}

/// What a redirect back into the app turned out to mean.
enum MALOAuthOutcome: Equatable {
    /// A usable authorization code, on a callback whose state matched.
    case code(String)
    /// The user declined. Not an error: nothing is broken and nothing should be reported.
    case cancelled
    /// A standard OAuth error the server chose to name.
    case failed(code: String, description: String?)
    /// Not our callback, or not trustworthy: wrong URL, absent or mismatched state, or no
    /// code. Deliberately carries no detail — there is nothing here worth acting on, and a
    /// mismatched state is precisely the case where the payload cannot be trusted.
    case rejected
}

enum MALOAuth {
    static func authorizationURL(configuration: MALOAuthConfiguration,
                                 state: String,
                                 verifier: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "myanimelist.net"
        components.path = "/v1/oauth2/authorize"
        // `redirect_uri` is optional while exactly one URI is registered, but it is sent
        // explicitly so behaviour does not change if a second is ever added.
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "code_challenge", value: MALPKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "plain")
        ]
        // Force-unwrap is safe: every component above is a literal or a caller-supplied
        // string, and URLComponents percent-encodes the values.
        return components.url!
    }

    static func outcome(for url: URL,
                        configuration: MALOAuthConfiguration,
                        expectedState: String) -> MALOAuthOutcome {
        guard let expected = URLComponents(string: configuration.redirectURI),
              let actual = URLComponents(url: url, resolvingAgainstBaseURL: false),
              actual.scheme == expected.scheme,
              actual.host == expected.host,
              actual.path == expected.path else { return .rejected }

        let items = Dictionary(
            (actual.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { first, _ in first })

        // State is checked before anything else is read: without it, none of the rest of
        // the query is known to have come from the authorization we started.
        guard items["state"] == expectedState else { return .rejected }

        if let error = items["error"], !error.isEmpty {
            return error == "access_denied"
                ? .cancelled
                : .failed(code: error, description: items["error_description"])
        }

        guard let code = items["code"], !code.isEmpty else { return .rejected }
        return .code(code)
    }
}

// MARK: - Token requests

/// A form-encoded POST to MAL's single token endpoint. Both the authorization-code exchange
/// and the refresh use the same URL and content type, differing only in `grant_type` and the
/// parameters that grant needs.
enum MALTokenRequest: Equatable {
    case authorizationCode(code: String, verifier: String)
    case refresh(refreshToken: String)

    static let endpoint = URL(string: "https://myanimelist.net/v1/oauth2/token")!

    /// Ordered so the encoded body is deterministic and therefore assertable.
    func parameters(configuration: MALOAuthConfiguration) -> [(String, String)] {
        switch self {
        case let .authorizationCode(code, verifier):
            // `redirect_uri` is sent because the authorization request sent it; MAL requires
            // the two to match exactly. No `client_secret`: this client is issued none.
            return [("client_id", configuration.clientID),
                    ("grant_type", "authorization_code"),
                    ("code", code),
                    ("redirect_uri", configuration.redirectURI),
                    ("code_verifier", verifier)]
        case let .refresh(refreshToken):
            return [("client_id", configuration.clientID),
                    ("grant_type", "refresh_token"),
                    ("refresh_token", refreshToken)]
        }
    }

    func formBody(configuration: MALOAuthConfiguration) -> Data {
        let encoded = parameters(configuration: configuration)
            .map { "\(Self.formEncode($0.0))=\(Self.formEncode($0.1))" }
            .joined(separator: "&")
        return Data(encoded.utf8)
    }

    func urlRequest(configuration: MALOAuthConfiguration) -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded",
                         forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(configuration: configuration)
        return request
    }

    /// Percent-encodes everything outside RFC 3986's unreserved set. Spaces become `%20`
    /// rather than `+`; `%20` is valid in a form body and avoids the `+`/space ambiguity.
    private static func formEncode(_ value: String) -> String {
        let unreserved = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }
}

/// MAL's token response. `scope` is absent from the documented payload, so it is not decoded.
struct MALTokenResponse: Decodable, Equatable {
    let tokenType: String
    let expiresIn: Int
    let accessToken: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

/// What gets persisted after a successful exchange or refresh.
///
/// Expiry is computed from the runtime `expires_in` — MAL's own documentation contradicts
/// itself on token lifetime (one hour in the overview table, ~28 days in the sample
/// response), so nothing here may be hard-coded.
struct MALCredential: Equatable {
    let tokenType: String
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    init(tokenType: String, accessToken: String, refreshToken: String, expiresAt: Date) {
        self.tokenType = tokenType
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    init(response: MALTokenResponse, receivedAt: Date) {
        self.init(tokenType: response.tokenType,
                  accessToken: response.accessToken,
                  refreshToken: response.refreshToken,
                  expiresAt: receivedAt.addingTimeInterval(TimeInterval(response.expiresIn)))
    }

    /// A refresh is due before the token actually dies, so an in-flight request cannot land
    /// on the far side of the expiry.
    static let refreshMargin: TimeInterval = 5 * 60

    func needsRefresh(at now: Date) -> Bool {
        now.addingTimeInterval(Self.refreshMargin) >= expiresAt
    }

    /// Never interpolate the tokens. This exists so a `print` of a credential cannot leak one.
    var debugDescription: String {
        "MALCredential(tokenType: \(tokenType), expiresAt: \(expiresAt))"
    }
}

// MARK: - Session

/// One authorization attempt, holding the `state` and verifier the callback must be judged
/// against, and — unlike the pure `MALOAuth.outcome` — remembering that the attempt is over.
///
/// Both a duplicate callback and a callback arriving after the user cancelled must be
/// rejected: the code in either one is not evidence of a live authorization we are waiting on.
final class MALOAuthSession {
    private enum Phase {
        case waiting
        case finished
    }

    let configuration: MALOAuthConfiguration
    let state: String
    let verifier: String
    private var phase: Phase = .waiting

    init(configuration: MALOAuthConfiguration, state: String, verifier: String) {
        self.configuration = configuration
        self.state = state
        self.verifier = verifier
    }

    var authorizationURL: URL {
        MALOAuth.authorizationURL(configuration: configuration, state: state, verifier: verifier)
    }

    var isFinished: Bool { phase == .finished }

    /// Marks the attempt over without a callback — the user dismissed the sheet.
    func cancel() -> MALOAuthOutcome {
        guard phase == .waiting else { return .rejected }
        phase = .finished
        return .cancelled
    }

    /// Judges a redirect. The first terminal answer is the only one; anything later is
    /// `.rejected`.
    func complete(with url: URL) -> MALOAuthOutcome {
        guard phase == .waiting else { return .rejected }
        let outcome = MALOAuth.outcome(for: url,
                                       configuration: configuration,
                                       expectedState: state)
        // A rejected callback is not our callback, so it does not end the attempt — the real
        // redirect may still be coming.
        if outcome != .rejected { phase = .finished }
        return outcome
    }

    /// The exchange to run for a code this session accepted.
    func exchange(code: String) -> MALTokenRequest {
        .authorizationCode(code: code, verifier: verifier)
    }
}
