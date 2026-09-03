//
//  MALAuthenticatedClient.swift
//  MangaCarta
//
//  The three authenticated MAL operations this app needs: who is signed in, what one title's
//  list status is, and advancing that title's progress. Deliberately narrow — there is no
//  whole-list endpoint here, because nothing in this design imports a list.
//
//  The read-only, client-id-only `MyAnimeListAPI` used by discovery and resolution is
//  untouched and stays the path for unauthenticated calls.
//

import Foundation

/// MAL's own reference contradicts itself on whether the list-status setter is `PATCH` or
/// `PUT`. **`PATCH` is the answer**, measured on 2026-08-24 against a real list entry: it was
/// accepted, the value landed, and the entry's `status` survived the write untouched. The verb
/// stays configurable only so a future contract change can be tested the same way.
///
/// See the Task 11 section of
/// `docs/superpowers/research/2026-08-21-mal-oauth-and-manga-progress-api.md`.
enum MALListUpdateVerb: String, Sendable {
    case patch = "PATCH"
    case put = "PUT"
}

/// The signed-in account, as far as this app cares.
struct MALUserIdentity: Equatable, Codable, Sendable {
    let id: Int
    let name: String
    /// Presentation-only, and absent whenever MAL sends nothing usable — a missing avatar is
    /// never a reason to fail a sign-in.
    let pictureURL: URL?
}

/// One title's entry on the signed-in user's list. Only the fields this app reads or
/// preserves are modelled; everything else MAL returns is left alone.
struct MALListStatus: Equatable, Sendable {
    let status: String
    let numChaptersRead: Int
}

/// The minimal write. `status` is sent only when the title is being added — an existing
/// entry's `reading`/`completed`/`on_hold`/`dropped`/`plan_to_read` must survive a progress
/// update untouched.
struct MALListStatusUpdate: Sendable {
    let status: String?
    let numChaptersRead: Int

    init(status: String? = nil, numChaptersRead: Int) {
        self.status = status
        self.numChaptersRead = numChaptersRead
    }
}

/// Why a request did not deliver, in the terms the outbox's retry policy is written in.
///
/// No case carries a response body: these values are persisted with queued items and shown in
/// Settings, and a raw MAL body is neither safe nor useful there.
enum MALRequestFailure: Error, Equatable, LocalizedError {
    /// The caller went away. Not an attempt, and never counted as one.
    case cancelled
    /// Worth trying again later. `retryAfter` is a server-supplied delay in seconds when MAL
    /// sent a usable one — it usually does not.
    case transient(retryAfter: TimeInterval?)
    /// Refresh could not produce a working token. The user must sign in again.
    case reauthorizationRequired
    /// This title's request will keep failing; block the item and carry on with the others.
    case permanentItem(status: Int)
    /// An account or service-policy refusal. MAL uses 403 for more than one condition and
    /// publishes no way to tell them apart, so nothing is discarded on its account.
    case accountBlocked
    /// A status or body this app does not understand. Retained and backed off rather than
    /// retried tightly, because a tight loop on an unknown is how a client gets banned.
    case unknown(status: Int?)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "The MyAnimeList request was cancelled."
        case .transient:
            return "MyAnimeList could not be reached. This will be retried."
        case .reauthorizationRequired:
            return "Please sign in to MyAnimeList again."
        case .permanentItem:
            return "MyAnimeList rejected this title's update."
        case .accountBlocked:
            return "MyAnimeList declined the request for this account."
        case .unknown:
            return "MyAnimeList returned an unexpected response."
        }
    }
}

struct MALAuthenticatedClient: Sendable {
    static let baseURL = URL(string: "https://api.myanimelist.net/v2")!

    private let tokens: MALTokenManager
    private let transport: any MALHTTPTransport
    private let updateVerb: MALListUpdateVerb

    init(tokens: MALTokenManager,
         transport: any MALHTTPTransport,
         updateVerb: MALListUpdateVerb = .patch) {
        self.tokens = tokens
        self.transport = transport
        self.updateVerb = updateVerb
    }

    // MARK: Operations

    func currentUser() async throws -> MALUserIdentity {
        try await perform(
            makeRequest: { Self.identityRequest() },
            decode: Self.decodeIdentity
        )
    }

    /// The identity read for a token that is not in the token manager yet — during sign-in,
    /// where the account's own MAL id is exactly what is still unknown. It therefore has no
    /// refresh-and-retry: a token seconds old has nothing to refresh from.
    static func currentUser(
        accessToken: String,
        transport: any MALHTTPTransport
    ) async throws -> MALUserIdentity {
        var request = identityRequest()
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await transport.send(request)
        } catch is CancellationError {
            throw MALRequestFailure.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw MALRequestFailure.cancelled
        } catch {
            throw MALRequestFailure.transient(retryAfter: nil)
        }
        guard (200..<300).contains(response.statusCode) else { throw failure(for: response) }
        do {
            return try decodeIdentity(data)
        } catch {
            throw MALRequestFailure.unknown(status: response.statusCode)
        }
    }

    private static func identityRequest() -> URLRequest {
        URLRequest(url: staticURL("users/@me", query: ["fields": "name,picture"]))
    }

    private static func decodeIdentity(_ data: Data) throws -> MALUserIdentity {
        let payload = try JSONDecoder().decode(MALUserPayload.self, from: data)
        return MALUserIdentity(id: payload.id,
                               name: payload.name,
                               pictureURL: pictureURL(payload.picture))
    }

    /// The one title's entry, or `nil` when the signed-in user does not have it listed.
    func listStatus(mangaID: Int) async throws -> MALListStatus? {
        try await perform(
            makeRequest: { URLRequest(url: url("manga/\(mangaID)", query: ["fields": "my_list_status"])) },
            decode: { data in
                try JSONDecoder().decode(MALMangaPayload.self, from: data).myListStatus?.value
            }
        )
    }

    /// Advances one title's progress and returns the entry MAL reports afterwards, so the
    /// caller can confirm the value actually landed before considering the work delivered.
    func updateProgress(
        mangaID: Int,
        update: MALListStatusUpdate
    ) async throws -> MALListStatus {
        try await perform(
            makeRequest: {
                var request = URLRequest(url: url("manga/\(mangaID)/my_list_status"))
                request.httpMethod = updateVerb.rawValue
                request.setValue("application/x-www-form-urlencoded",
                                 forHTTPHeaderField: "Content-Type")
                request.httpBody = Self.formBody(for: update)
                return request
            },
            decode: { data in
                try JSONDecoder().decode(MALListStatusPayload.self, from: data).value
            }
        )
    }

    // MARK: Request plumbing

    /// Runs a request with a bearer token, and on a 401 refreshes once and retries once.
    /// A second 401 — or a refresh that fails — is `reauthorizationRequired`; retrying past
    /// that only burns requests against a token that will not come back.
    private func perform<T>(
        makeRequest: () -> URLRequest,
        decode: (Data) throws -> T
    ) async throws -> T {
        var token = try await currentToken()
        var hasRetried = false

        while true {
            var request = makeRequest()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await send(request)

            if response.statusCode == 401, !hasRetried {
                token = try await refreshedToken(replacing: token)
                hasRetried = true
                continue
            }

            guard (200..<300).contains(response.statusCode) else {
                throw Self.failure(for: response)
            }
            do {
                return try decode(data)
            } catch {
                throw MALRequestFailure.unknown(status: response.statusCode)
            }
        }
    }

    private func currentToken() async throws -> String {
        do {
            return try await tokens.accessToken()
        } catch is CancellationError {
            throw MALRequestFailure.cancelled
        } catch {
            throw MALRequestFailure.reauthorizationRequired
        }
    }

    private func refreshedToken(replacing stale: String) async throws -> String {
        do {
            return try await tokens.accessToken(replacing: stale)
        } catch is CancellationError {
            throw MALRequestFailure.cancelled
        } catch {
            throw MALRequestFailure.reauthorizationRequired
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch is CancellationError {
            throw MALRequestFailure.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw MALRequestFailure.cancelled
        } catch let error as MALRequestFailure {
            throw error
        } catch {
            // Every other transport error is a connectivity fault: retryable, and carrying no
            // delay because the failure came from this side of the wire.
            throw MALRequestFailure.transient(retryAfter: nil)
        }
    }

    private static func failure(for response: HTTPURLResponse) -> MALRequestFailure {
        switch response.statusCode {
        case 401:
            return .reauthorizationRequired
        case 403:
            return .accountBlocked
        case 400, 404:
            return .permanentItem(status: response.statusCode)
        case 408, 429, 500..<600:
            return .transient(retryAfter: retryAfter(in: response))
        default:
            return .unknown(status: response.statusCode)
        }
    }

    /// MAL does not reliably send `Retry-After`, and when it does the value is not trusted
    /// blindly: only a positive number of seconds is honored.
    private static func retryAfter(in response: HTTPURLResponse) -> TimeInterval? {
        guard let header = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(header.trimmingCharacters(in: .whitespaces)),
              seconds > 0 else { return nil }
        return seconds
    }

    private func url(_ path: String, query: [String: String] = [:]) -> URL {
        Self.staticURL(path, query: query)
    }

    private static func staticURL(_ path: String, query: [String: String] = [:]) -> URL {
        var components = URLComponents(
            url: Self.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url!
    }

    /// Ordered so the body is deterministic and therefore assertable, and minimal so an
    /// update never overwrites a field it was not asked to change.
    private static func formBody(for update: MALListStatusUpdate) -> Data {
        var pairs: [(String, String)] = []
        if let status = update.status { pairs.append(("status", status)) }
        pairs.append(("num_chapters_read", String(update.numChaptersRead)))
        return Data(pairs.map { "\($0.0)=\($0.1)" }.joined(separator: "&").utf8)
    }

    /// MAL sends the avatar as a string that has been observed absent, null, and empty. Only
    /// an `http(s)` URL is accepted; anything else becomes no picture rather than an error.
    private static func pictureURL(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }
}

// MARK: - Payloads
//
// Top level rather than nested so the coding keys stay one nesting level deep.

private struct MALUserPayload: Decodable {
    let id: Int
    let name: String
    let picture: String?
}

private struct MALMangaPayload: Decodable {
    let myListStatus: MALListStatusPayload?

    enum CodingKeys: String, CodingKey {
        case myListStatus = "my_list_status"
    }
}

private struct MALListStatusPayload: Decodable {
    let status: String
    let numChaptersRead: Int

    enum CodingKeys: String, CodingKey {
        case status
        case numChaptersRead = "num_chapters_read"
    }

    var value: MALListStatus {
        MALListStatus(status: status, numChaptersRead: numChaptersRead)
    }
}
