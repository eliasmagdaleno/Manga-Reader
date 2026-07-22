//
//  MoreLikeThisProvider.swift
//  Manga-Reader
//
//  Turns a Manga into a list of openable MangaDex "More Like This" titles, sourced from
//  MyAnimeList's per-title recommendations. Orchestration only: forward-resolve → MAL
//  detail → top-N recommendations → reverse-resolve each back to a MangaDex Manga, in
//  recommendation-weight order. The decision logic lives in pure helpers (MoreLikeThis,
//  MALTitleMatcher); this is the thin, live-verified network glue (the codebase has no
//  network-mock harness). Non-throwing: any failure degrades to fewer/zero cards.
//

import Foundation

@MainActor
final class MoreLikeThisProvider {
    private let store: EntityResolutionStore
    private let resolver: MALEntityResolver
    private let matcher: MALTitleMatcher

    init(store: EntityResolutionStore = .shared,
         resolver: MALEntityResolver? = nil,
         matcher: MALTitleMatcher = .init()) {
        self.store = store
        self.resolver = resolver ?? MALEntityResolver(store: store)
        self.matcher = matcher
    }

    /// The top `limit` recommendations by weight (descending). Pure — no network. Marked
    /// `nonisolated` so it's callable synchronously without hopping to the main actor
    /// (it touches no actor-isolated state); tests call it directly.
    nonisolated static func topRecommendations(_ recs: [MyAnimeListMangaDetail.Recommendation],
                                   limit: Int) -> [MyAnimeListMangaDetail.Recommendation] {
        Array(recs.sorted { $0.numRecommendations > $1.numRecommendations }.prefix(limit))
    }

    /// Up to `limit` openable MangaDex titles similar to `manga`, in MAL-recommendation
    /// order. Empty when `manga` has no MAL match, MAL returns no recommendations, or none
    /// reverse-resolve. Never throws — network failures degrade to fewer/zero cards.
    func recommendations(for manga: Manga, limit: Int = 8) async -> [Manga] {
        guard let malId = await resolver.malId(for: manga) else { return [] }
        guard let detail = try? await MyAnimeListAPI.mangaDetail(id: malId) else { return [] }
        let recs = Self.topRecommendations(detail.recommendations ?? [], limit: limit)
        guard !recs.isEmpty else { return [] }

        // Partition into fresh cache hits (batch-fetch later) and misses (live search).
        var resolvedIds: [Int: String] = [:]     // malId -> MangaDex id, from fresh cache hits
        var toSearch: [MyAnimeListManga] = []     // recs needing a live search
        for rec in recs {
            if let cached = store.reverseResolution(malId: rec.node.id), cached.isFresh() {
                if case .resolved(let mdId) = cached { resolvedIds[rec.node.id] = mdId }
                // A fresh .unresolved miss: skip entirely (don't re-search yet).
            } else {
                toSearch.append(rec.node)
            }
        }

        // Live search + reverse-resolve the misses; records the cache outcomes.
        let freshlyResolved = await reverseResolveViaSearch(toSearch)   // [malId: Manga]
        for (recMalId, m) in freshlyResolved { resolvedIds[recMalId] = m.id }

        // Full `Manga` values we already have (from the live searches), keyed by id.
        let searchedById = Dictionary(freshlyResolved.values.map { ($0.id, $0) },
                                      uniquingKeysWith: { first, _ in first })

        // Batch-fetch the MangaDex ids we know but don't yet have a full Manga for
        // (cache-hit ids). One request, covers included.
        let idsNeedingFetch = Array(Set(resolvedIds.values.filter { searchedById[$0] == nil }))
        var fetchedById: [String: Manga] = [:]
        if !idsNeedingFetch.isEmpty,
           let fetched = try? await MangaDexAPI.fetchMangaByIdsWithCovers(ids: idsNeedingFetch) {
            fetchedById = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }

        // Reassemble in recommendation (weight) order; drop self; de-dupe by id.
        var out: [Manga] = []
        var seen = Set<String>()
        for rec in recs {
            guard let mdId = resolvedIds[rec.node.id],
                  let resolved = searchedById[mdId] ?? fetchedById[mdId],
                  resolved.id != manga.id,
                  seen.insert(resolved.id).inserted else { continue }
            out.append(resolved)
        }
        return out
    }

    /// Search MangaDex for each rec's title and reverse-resolve to a confident Manga
    /// (bounded concurrency, cap 4 — the pattern established for LibraryStore.refresh).
    /// Records `.resolved`/`.unresolved` in the reverse cache; a THROWN search records
    /// nothing (transient — don't poison the cache), mirroring MALEntityResolver.
    private func reverseResolveViaSearch(_ nodes: [MyAnimeListManga]) async -> [Int: Manga] {
        guard !nodes.isEmpty else { return [:] }
        let matcher = self.matcher
        let maxConcurrent = 4

        // (malId, resolved Manga?, didSearch) — didSearch == false means the search threw.
        let results: [(Int, Manga?, Bool)] = await withTaskGroup(
            of: (Int, Manga?, Bool).self
        ) { group in
            var iterator = nodes.makeIterator()

            func addNext() {
                guard let node = iterator.next() else { return }
                group.addTask {
                    do {
                        let candidates = try await MangaDexAPI.searchManga(title: node.title)
                        let match = MoreLikeThis.pickMatch(targetMalId: node.id,
                                                           malTitle: node.title,
                                                           candidates: candidates,
                                                           matcher: matcher)
                        return (node.id, match, true)
                    } catch {
                        return (node.id, nil, false)   // transient — cache nothing
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
        for (recMalId, manga, didSearch) in results {
            if let manga {
                store.recordReverse(malId: recMalId, .resolved(mangaDexId: manga.id))
                resolved[recMalId] = manga
            } else if didSearch {
                store.recordReverse(malId: recMalId, .unresolved(checkedAt: Date()))
            }   // !didSearch → record nothing
        }
        return resolved
    }
}
