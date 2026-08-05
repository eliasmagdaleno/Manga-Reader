//
//  MALReverseResolver.swift
//  Manga-Reader
//
//  The one implementation of MAL-id → openable MangaDex `Manga` reverse resolution.
//  Two callers need it — `MoreLikeThisProvider.recommendations(for:)` (MAL's per-title
//  recommendations) and the AniList ranked pool (ADR-0011) — and they must not each own
//  a copy, because the *cache-write discipline* below is the kind of rule a second
//  implementation gets subtly wrong:
//
//      confident match      → record .resolved
//      searched, no match   → record .unresolved(checkedAt:)
//      search THREW         → record NOTHING
//
//  That last line is the load-bearing one. A transient network failure recorded as
//  `.unresolved` would poison `EntityResolutionStore` against that title for the whole
//  miss TTL, for a reason that had nothing to do with the title.
//
//  Ordering is deliberately NOT here. The two callers order their results differently —
//  MAL-recommendation order with self dropped, versus the pool's own ranking — so this
//  returns an unordered `[malId: Manga]` map and each caller arranges it. Folding the
//  orderings in would mean a flag parameter (ADR-0011).
//
//  Network reaches this type through two injected closures rather than direct
//  `MangaDexAPI` statics — the `MetadataUpgradeQueue.Sleep` / `AniListCandidateProvider
//  .Resolve` pattern. The defaults are the real endpoints, so no call site changes; the
//  point is that the cache-write discipline above is finally testable without a network.
//

import Foundation

@MainActor
final class MALReverseResolver {
    /// MangaDex title search — the fan-out, one call per unresolved id.
    typealias Search = @Sendable (String) async throws -> [Manga]
    /// Batch id fetch, covers included — one call for every cache hit combined.
    typealias FetchByIds = @Sendable ([String]) async throws -> [Manga]

    /// What reverse resolution actually needs: a MAL id to confirm against, and a title
    /// to search MangaDex with. Not `MyAnimeListManga` — the AniList pool's candidates
    /// arrive from AniList and only ever carried an `idMal`.
    struct ReverseTarget: Sendable, Equatable {
        let malId: Int
        let title: String
    }

    private let store: EntityResolutionStore
    private let matcher: MALTitleMatcher
    private let search: Search
    private let fetchByIds: FetchByIds

    init(store: EntityResolutionStore = .shared,
         matcher: MALTitleMatcher = .init(),
         search: @escaping Search = { try await MangaDexAPI.searchManga(title: $0) },
         fetchByIds: @escaping FetchByIds = {
             try await MangaDexAPI.fetchMangaByIdsWithCovers(ids: $0)
         }) {
        self.store = store
        self.matcher = matcher
        self.search = search
        self.fetchByIds = fetchByIds
    }

    /// Reverse-resolve `targets` to openable MangaDex titles, keyed by `malId`. Never
    /// throws — a failure degrades to fewer entries, never to an error the caller has to
    /// surface. Absent keys mean "not resolved", which is the *normal* case: AniList's and
    /// MAL's catalogues are both wider than MangaDex's.
    func resolve(_ targets: [ReverseTarget]) async -> [Int: Manga] {
        // Partition: fresh cache hits (one batch fetch later) versus misses (live search).
        var resolvedIds: [Int: String] = [:]     // malId -> MangaDex id, from fresh hits
        var toSearch: [ReverseTarget] = []
        for target in targets {
            if let cached = store.reverseResolution(malId: target.malId), cached.isFresh() {
                if case .resolved(let mdId) = cached { resolvedIds[target.malId] = mdId }
                // A fresh .unresolved miss: skip entirely (don't re-search yet).
            } else {
                toSearch.append(target)
            }
        }

        var out = await searchAndRecord(toSearch)

        // Batch-fetch the ids we know but hold no full `Manga` for — the cache hits, plus
        // nothing else, since a live search already returned full values.
        let searchedIds = Set(out.values.map(\.id))
        let idsNeedingFetch = Array(Set(resolvedIds.values.filter { !searchedIds.contains($0) }))
        if !idsNeedingFetch.isEmpty, let fetched = try? await fetchByIds(idsNeedingFetch) {
            let byId = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for (malId, mdId) in resolvedIds where out[malId] == nil {
                if let manga = byId[mdId] { out[malId] = manga }
            }
        }
        return out
    }

    /// The AniList pool's shape (ADR-0011): take the head `limit` Works that carry both a
    /// MAL id and a title, and resolve those. Works missing either are dropped here rather
    /// than at the call site, so "which titles get searched" stays one decision in one
    /// place.
    ///
    /// **Residual:** `AniListWork.knownTitles` carries romaji/english/native/synonyms but
    /// only the primary reaches `MoreLikeThis.pickMatch`, which takes a single title.
    /// Widening the matcher would change matching behaviour, so it stays parked
    /// (ADR-0011); the strong arm — an exact `malId` hit among the search candidates —
    /// does not depend on the title anyway.
    func resolve(works: [AniListWork], limit: Int) async -> [Int: Manga] {
        await resolve(works.prefix(limit).compactMap { work in
            guard let malId = work.malId, let title = work.knownTitles.first else { return nil }
            return ReverseTarget(malId: malId, title: title)
        })
    }

    /// Search MangaDex for each target's title, pick a confident match, and record the
    /// outcome (bounded concurrency, cap 4 — the pattern established for
    /// `LibraryStore.refresh`). See the cache-write discipline in the file header.
    private func searchAndRecord(_ targets: [ReverseTarget]) async -> [Int: Manga] {
        guard !targets.isEmpty else { return [:] }
        let matcher = self.matcher
        let search = self.search
        let maxConcurrent = 4

        // (malId, resolved Manga?, didSearch) — didSearch == false means the search threw.
        let results: [(Int, Manga?, Bool)] = await withTaskGroup(
            of: (Int, Manga?, Bool).self
        ) { group in
            var iterator = targets.makeIterator()

            func addNext() {
                guard let target = iterator.next() else { return }
                group.addTask {
                    do {
                        let candidates = try await search(target.title)
                        let match = MoreLikeThis.pickMatch(targetMalId: target.malId,
                                                           malTitle: target.title,
                                                           candidates: candidates,
                                                           matcher: matcher)
                        return (target.malId, match, true)
                    } catch {
                        return (target.malId, nil, false)   // transient — cache nothing
                    }
                }
            }

            for _ in 0..<maxConcurrent { addNext() }

            var out: [(Int, Manga?, Bool)] = []
            while let result = await group.next() {
                out.append(result)
                addNext()
            }
            return out
        }

        var resolved: [Int: Manga] = [:]
        for (malId, manga, didSearch) in results {
            if let manga {
                store.recordReverse(malId: malId, .resolved(mangaDexId: manga.id))
                resolved[malId] = manga
            } else if didSearch {
                store.recordReverse(malId: malId, .unresolved(checkedAt: Date()))
            }   // !didSearch → record nothing
        }
        return resolved
    }
}
