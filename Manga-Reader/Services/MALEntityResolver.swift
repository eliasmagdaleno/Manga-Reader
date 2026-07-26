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
    /// The MAL search, injected. `MyAnimeListAPI` is `static` all the way down onto
    /// `URLSession.shared`, so without a seam here nothing past the cache branch is
    /// testable. `AniListAPI` solved the same problem with an injectable `Transport`;
    /// this puts the seam at the resolver instead, to keep the change local.
    typealias Search = (String) async throws -> [MALCandidate]

    private let store: EntityResolutionStore
    private let matcher: MALTitleMatcher
    private let search: Search
    /// How many of a Work's known titles get their own MAL search. Bounds the fan-out
    /// for a heavily-merged Work; in practice an unresolved Work has one or two titles,
    /// so this rarely binds (ADR-0009).
    private let titleSearchLimit: Int

    static let liveSearch: Search = { title in
        try await MyAnimeListAPI.searchManga(title: title)
            .map { MALCandidate(malId: $0.id, titles: $0.allTitles) }
    }

    init(store: EntityResolutionStore,
         matcher: MALTitleMatcher = .init(),
         titleSearchLimit: Int = 3,
         search: @escaping Search = MALEntityResolver.liveSearch) {
        self.store = store
        self.matcher = matcher
        self.titleSearchLimit = titleSearchLimit
        self.search = search
    }

    /// The canonical MAL id for a **Work**, or nil if nothing matched with confidence.
    ///
    /// Unlike `malId(for manga:)` this **throws**, because its caller writes attempt
    /// memory and ADR-0008 gives the two failures different records: a real miss is
    /// `.unmatched(knownTitlesCount)`, a transient failure is recorded as nothing at all.
    /// An `Int?` cannot carry that distinction, so `nil` means "searched, nothing cleared
    /// the threshold" and a throw means "don't remember this".
    ///
    /// Nothing is written to `EntityResolutionStore`: its cache is keyed
    /// `sourceId:mangaId`, and a Work-level answer has no single Listing to key on. It is
    /// still *read* below — a hit recorded by a detail-page open is a valid answer for any
    /// Work containing that Listing, and costs no request.
    func malId(for work: Work) async throws -> Int? {
        if let known = work.externalIds.mal { return known }

        for key in work.listings {
            if case .resolved(let id) = store.resolution(sourceId: key.sourceId,
                                                         mangaId: key.mangaId) {
                return id
            }
        }

        // One search per known title, unioned into ONE candidate pool. Deliberately not
        // one match per title: a maximum across independent ranked lists has no runner-up,
        // so it would route around the ambiguity guard (ADR-0008).
        var pool: [Int: MALCandidate] = [:]
        var failure: Error?
        for title in work.knownTitles.prefix(titleSearchLimit) {
            do {
                // First spelling wins; MAL returns the same title set for a given id, so
                // later duplicates carry no new matcher fuel.
                for candidate in try await search(title) where pool[candidate.malId] == nil {
                    pool[candidate.malId] = candidate
                }
            } catch {
                failure = error
            }
        }

        // Sorted by id because dictionary iteration order is randomized per process, and
        // the matcher's sort is not stable — without this, tied candidates could resolve
        // differently between launches.
        let candidates = pool.values
            .sorted { $0.malId < $1.malId }
            .map { (id: $0.malId, titles: $0.titles) }

        // Matching is free, so it uses *every* known title even though only the first few
        // were searched.
        if let matched = matcher.bestMatch(sourceTitles: work.knownTitles,
                                           candidates: candidates) {
            return matched
        }
        // A match stands on its own — the searches that failed could only have added
        // candidates, which the ambiguity guard would treat as evidence *against*. A miss
        // computed from incomplete evidence is not trustworthy, so it is not reported as
        // one: `.unmatched` is fingerprinted on title count and would otherwise sit stale
        // for the full TTL on the strength of one network blip.
        if let failure { throw failure }
        return nil
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
        let candidates: [MALCandidate]
        do {
            candidates = try await search(manga.title)
        } catch {
            return nil
        }

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
