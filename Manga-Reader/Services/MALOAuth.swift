//
//  MALOAuth.swift
//  Manga-Reader
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
