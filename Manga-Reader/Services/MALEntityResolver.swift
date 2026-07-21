//
//  MALEntityResolver.swift
//  Manga-Reader
//
//  Resolves a Manga (any source) to a canonical MyAnimeList id. Fast path: a Manga that
//  already carries `malId` (MangaDex) returns it for free. Otherwise consult the cache,
//  then fall back to a title search + pure MALTitleMatcher. Precision-biased and
//  non-throwing: an ordinary no-match returns nil (the caller omits the title); a
//  transient MAL error also returns nil but is NOT cached, so an outage can't poison the
//  cache for the full miss TTL.
//

import Foundation

@MainActor
final class MALEntityResolver {
    private let store: EntityResolutionStore
    private let matcher: MALTitleMatcher

    init(store: EntityResolutionStore, matcher: MALTitleMatcher = .init()) {
        self.store = store
        self.matcher = matcher
    }

    /// The canonical MAL id for `manga`, or nil if none can be found with confidence.
    func malId(for manga: Manga) async -> Int? {
        // 1. Fast path — the source already told us (MangaDex via links.mal). No caching
        //    needed: it's free on every call.
        if let known = manga.malId { return known }

        // 2. Cache — a live entry answers without network.
        if let cached = store.resolution(sourceId: manga.sourceId, mangaId: manga.id),
           cached.isFresh() {
            if case .resolved(let id) = cached { return id }
            return nil   // fresh miss — don't re-hit MAL yet
        }

        // 3. Fuzzy — search MAL by title and match. A thrown/absent result is a transient
        //    failure: return nil WITHOUT recording a miss (only a real "candidates but no
        //    match" is worth caching).
        let results: [MyAnimeListManga]
        do {
            results = try await MyAnimeListAPI.searchManga(title: manga.title)
        } catch {
            return nil
        }

        let candidates = results.map { MALCandidate(malId: $0.id, titles: $0.allTitles) }
        switch matcher.decide(sourceTitle: manga.title, candidates: candidates) {
        case .matched(let id):
            store.record(sourceId: manga.sourceId, mangaId: manga.id, .resolved(malId: id))
            return id
        case .noMatch:
            store.record(sourceId: manga.sourceId, mangaId: manga.id, .unresolved(checkedAt: Date()))
            return nil
        }
    }
}
