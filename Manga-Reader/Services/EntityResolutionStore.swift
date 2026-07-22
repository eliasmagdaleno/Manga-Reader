//
//  EntityResolutionStore.swift
//  Manga-Reader
//
//  Caches cross-source → MyAnimeList id resolutions so we don't re-run the fuzzy match
//  (or re-hit MAL) every time a detail page opens. Hits are cached indefinitely — a
//  manga's MAL id is stable; misses carry a timestamp and are re-attempted after a TTL,
//  so a title MAL adds later, or an improved matcher, eventually gets another chance.
//  UserDefaults-backed, mirroring HistoryStore / LibraryStore / TasteProfileStore.
//

import SwiftUI

/// The cached outcome of resolving one source manga to a MAL id.
enum MALResolution: Codable, Equatable {
    case resolved(malId: Int)          // Cached indefinitely.
    case unresolved(checkedAt: Date)   // A miss; re-attempt once older than `missTTL`.

    /// Whether this entry should still be trusted (vs. re-attempted). Hits are always
    /// fresh; a miss is fresh until it passes the TTL. `now` is injectable for tests.
    func isFresh(now: Date = Date()) -> Bool {
        switch self {
        case .resolved:
            return true
        case .unresolved(let checkedAt):
            return now.timeIntervalSince(checkedAt) < EntityResolutionStore.missTTL
        }
    }
}

/// The cached outcome of reverse-resolving a MAL id to a MangaDex manga id.
enum ReverseResolution: Codable, Equatable {
    case resolved(mangaDexId: String)   // Cached indefinitely.
    case unresolved(checkedAt: Date)    // A miss; re-attempt once older than `missTTL`.

    /// Whether this entry should still be trusted (vs. re-attempted). Hits are always
    /// fresh; a miss is fresh until it passes the TTL. Mirrors `MALResolution.isFresh`.
    func isFresh(now: Date = Date()) -> Bool {
        switch self {
        case .resolved:
            return true
        case .unresolved(let checkedAt):
            return now.timeIntervalSince(checkedAt) < EntityResolutionStore.missTTL
        }
    }
}

@MainActor
final class EntityResolutionStore: ObservableObject {
    /// Source-qualified key ("{sourceId}:{mangaId}") → outcome.
    @Published private(set) var cache: [String: MALResolution] = [:]

    /// MAL id (as `String(malId)`) → reverse-resolution outcome.
    @Published private(set) var reverseCache: [String: ReverseResolution] = [:]

    /// App-wide instance so the forward and reverse caches persist across detail-page
    /// opens. Tests still construct isolated instances via `init(defaults:)`.
    static let shared = EntityResolutionStore()

    /// How long a miss is trusted before it's re-attempted.
    nonisolated static let missTTL: TimeInterval = 14 * 24 * 60 * 60   // 14 days

    private let cacheKey = "entityResolution.cache"
    private let reverseCacheKey = "entityResolution.reverseCache"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func resolution(sourceId: String, mangaId: String) -> MALResolution? {
        cache[Self.key(sourceId, mangaId)]
    }

    func record(sourceId: String, mangaId: String, _ resolution: MALResolution) {
        cache[Self.key(sourceId, mangaId)] = resolution
        save()
    }

    func reverseResolution(malId: Int) -> ReverseResolution? {
        reverseCache[String(malId)]
    }

    func recordReverse(malId: Int, _ resolution: ReverseResolution) {
        reverseCache[String(malId)] = resolution
        save()
    }

    private static func key(_ sourceId: String, _ mangaId: String) -> String {
        "\(sourceId):\(mangaId)"
    }

    private func save() {
        if let data = try? JSONEncoder().encode(cache) { defaults.set(data, forKey: cacheKey) }
        if let data = try? JSONEncoder().encode(reverseCache) { defaults.set(data, forKey: reverseCacheKey) }
    }

    private func load() {
        if let data = defaults.data(forKey: cacheKey),
           let value = try? JSONDecoder().decode([String: MALResolution].self, from: data) {
            cache = value
        }
        if let data = defaults.data(forKey: reverseCacheKey),
           let value = try? JSONDecoder().decode([String: ReverseResolution].self, from: data) {
            reverseCache = value
        }
    }
}
