//
//  MALTokenClient.swift
//  Manga-Reader
//
//  The network half of MAL OAuth: one small transport seam plus the request/response
//  handling around MAL's single token endpoint. Nothing here persists or caches — that is
//  `MALTokenManager`'s job — so this stays a pure function of (request, scripted response).
//

import Foundation
import os

/// The seam that keeps `URLSession` out of the tests, shared by the token and API clients. Deliberately narrow: one request in,
/// data and an `HTTPURLResponse` out, so a test can script a status code and a body.
protocol MALHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Production adapter. A non-HTTP response cannot happen against an `https` URL, but it is
/// reported rather than force-unwrapped.
struct MALURLSessionTransport: MALHTTPTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MALTokenError.transportFailure
        }
        return (data, http)
    }
}

/// Everything token acquisition can go wrong with, in terms callers can act on.
///
/// No case carries a token, a refresh token, or a response body: these values reach logs and
/// error UI, and a token in either is a leak.
enum MALTokenError: Error, Equatable, LocalizedError {
    /// The request never reached MAL, or the reply was not HTTP.
    case transportFailure
    /// MAL answered, but not with a token set this app can use.
    case malformedResponse
    /// `expires_in` was absent, zero, or negative — a token that is dead on arrival.
    case invalidExpiry
    /// MAL refused. `code` is the OAuth `error` field when it named one.
    case server(status: Int, code: String?)
    /// The new token set could not be persisted, so it was not adopted.
    case persistenceFailed
    /// There is no stored credential; the account is signed out.
    case signedOut

    /// A refusal the same refresh token will keep earning. Retrying cannot help, so the
    /// stored credential is worthless and the account must sign in again.
    var isPermanent: Bool {
        switch self {
        case let .server(status, _):
            return status == 400 || status == 401 || status == 403
        case .signedOut:
            return true
        case .transportFailure, .malformedResponse, .invalidExpiry, .persistenceFailed:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .transportFailure:
            return "MyAnimeList could not be reached. Please try again."
        case .malformedResponse, .invalidExpiry:
            return "MyAnimeList returned an unexpected sign-in response."
        case .server:
            return "MyAnimeList refused the sign-in. Please sign in again."
        case .persistenceFailed:
            return "The MyAnimeList sign-in could not be saved securely."
        case .signedOut:
            return "You are not signed in to MyAnimeList."
        }
    }
}

/// Performs a token exchange or refresh and turns the reply into a `MALCredential`.
struct MALTokenClient: Sendable {
    private let configuration: MALOAuthConfiguration
    private let transport: any MALHTTPTransport
    /// Injected so expiry is computed against a pinned clock in tests.
    private let now: @Sendable () -> Date

    init(
        configuration: MALOAuthConfiguration,
        transport: any MALHTTPTransport,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.configuration = configuration
        self.transport = transport
        self.now = now
    }

#if DEBUG
    private static let contractLog = Logger(subsystem: "Elias-Magdaleno.Manga-Reader",
                                            category: "mal.contract")
#endif

    func fetch(_ request: MALTokenRequest) async throws -> MALCredential {
        let (data, response) = try await send(request)

        guard (200..<300).contains(response.statusCode) else {
            throw MALTokenError.server(status: response.statusCode,
                                       code: Self.errorCode(in: data))
        }

        guard let token = try? JSONDecoder().decode(MALTokenResponse.self, from: data) else {
            throw MALTokenError.malformedResponse
        }
        // A refresh replaces both tokens; half a set is unusable, so it is not adopted.
        guard !token.accessToken.isEmpty, !token.refreshToken.isEmpty else {
            throw MALTokenError.malformedResponse
        }
        guard token.expiresIn > 0 else { throw MALTokenError.invalidExpiry }

#if DEBUG
        // Task 11 needs the real `expires_in`, and MAL's own docs contradict themselves about
        // it. Only the integer seconds and the token type are emitted — never a token, a code,
        // or a verifier — and only in DEBUG, so nothing of this reaches a release build.
        // `.notice`, not `.debug`: debug records live in a memory buffer that `log show`
        // cannot read back, so a debug-level probe is unrecoverable after the fact.
        MALTokenClient.contractLog.notice(
            "MAL token response: type=\(token.tokenType, privacy: .public) expires_in=\(token.expiresIn, privacy: .public)s")
#endif

        return MALCredential(response: token, receivedAt: now())
    }

    private func send(_ request: MALTokenRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request.urlRequest(configuration: configuration))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as MALTokenError {
            throw error
        } catch {
            // Anything else is a network fault. The underlying error is dropped rather than
            // wrapped: it is of no use to a caller and its description is unbounded.
            throw MALTokenError.transportFailure
        }
    }

    /// MAL names its refusals in an `error` field. Only that field is read — the rest of an
    /// error body is not something to carry around.
    private static func errorCode(in data: Data) -> String? {
        struct Body: Decodable { let error: String? }
        guard let body = try? JSONDecoder().decode(Body.self, from: data),
              let code = body.error, !code.isEmpty else { return nil }
        return code
    }
}

#if DEBUG
/// A transport that always fails as if the network were gone, for the manual verification of
/// offline completion, relaunch persistence, and foreground retry.
///
/// It exists because those checks need MyAnimeList to be *unreachable* while MangaDex stays
/// reachable — the reader still has to load pages to complete a chapter. Blocking the host at
/// the machine level would break both and needs root; this breaks exactly one dependency.
///
/// `AppComposition` gives it only to the authenticated client, never to `MALTokenClient`, so a
/// simulated outage cannot push a real signed-in account toward reauthorization.
struct MALOfflineTransport: MALHTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(.notConnectedToInternet)
    }
}
#endif
