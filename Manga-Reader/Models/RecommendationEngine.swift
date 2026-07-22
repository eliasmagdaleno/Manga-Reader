//
//  RecommendationEngine.swift
//  Manga-Reader
//
//  Orchestrates the "For You" rail: builds a TasteProfile from reading history,
//  asks a CandidateProvider for ranked candidates, mixes in seeded exploration so
//  the rail moves between sessions, and back-fills tags for older reads. MangaDex-only.
//

import SwiftUI

/// Small seedable PRNG (SplitMix64) so exploration is deterministic within a session
/// yet reshuffles when reseeded. SystemRandomNumberGenerator can't be seeded.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

@MainActor
final class RecommendationEngine: ObservableObject {
    @Published private(set) var recommendations: [ScoredManga] = []

    private let history: HistoryStore
    private let library: LibraryStore
    private let profileStore: TasteProfileStore
    private let mangaDexSource: MangaSource
    private let makeProvider: (MangaSource) -> CandidateProvider
    private let now: () -> Date

    private let minTaggedManga = 3
    private let poolLimit = 40
    private let coreFraction = 0.8
    private let backfillBatch = 8

    private var seed: UInt64
    private var loadTask: Task<Void, Never>?
    private var loadedOnce = false

    init(history: HistoryStore,
         library: LibraryStore,
         profileStore: TasteProfileStore,
         mangaDexSource: MangaSource = MangaDexSource(),
         makeProvider: @escaping (MangaSource) -> CandidateProvider = { @MainActor source in
             CompositeCandidateProvider(
                 tag: TagCandidateProvider(source: source),
                 mal: MALCandidateProvider(similar: MoreLikeThisProvider()))
         },
         now: @escaping () -> Date = Date.init,
         seed: UInt64? = nil) {
        self.history = history
        self.library = library
        self.profileStore = profileStore
        self.mangaDexSource = mangaDexSource
        self.makeProvider = makeProvider
        self.now = now
        self.seed = seed ?? UInt64.random(in: .min ... .max)
    }

    /// Build once per Home appearance (cheap no-op if already built this session).
    func load() {
        guard !loadedOnce else { return }
        loadedOnce = true
        loadTask?.cancel()
        loadTask = Task { await rebuild() }
    }

    /// Pull-to-refresh: reseed exploration and rebuild.
    func refresh() async {
        seed = UInt64.random(in: .min ... .max)
        loadTask?.cancel()
        await rebuild()
    }

    func markNotInterested(_ manga: Manga) {
        profileStore.markNotInterested(mangaId: manga.id)
        recommendations.removeAll { $0.manga.id == manga.id }
    }

    func markMoreLikeThis(_ manga: Manga) {
        profileStore.markMoreLikeThis(mangaId: manga.id)
        Task { await rebuild() }
    }

    private func rebuild() async {
        scheduleBackfill()   // fills future builds; never blocks this one

        guard let (profile, excluding) = profileAndExclusions() else {
            recommendations = []
            return
        }
        let pool = (try? await makeProvider(mangaDexSource)
            .candidates(for: profile, excluding: excluding, limit: poolLimit)) ?? []
        guard !Task.isCancelled else { return }
        recommendations = compose(pool: pool)
    }

    /// The full ranked recommendation pool as plain `Manga`, WITHOUT the rail's
    /// exploration reshuffle — the "See all" grid wants the straight ranking. Empty
    /// during cold-start, exactly like the rail.
    func rankedRecommendations(limit: Int = 100) async -> [Manga] {
        guard let (profile, excluding) = profileAndExclusions() else { return [] }
        let pool = (try? await makeProvider(mangaDexSource)
            .candidates(for: profile, excluding: excluding, limit: limit)) ?? []
        return pool.map(\.manga)
    }

    /// Builds the taste profile and the exclusion set (read ∪ saved ∪ not-interested),
    /// or nil when there isn't enough signal (cold-start). Shared by the rail and the grid.
    private func profileAndExclusions() -> (TasteProfile, Set<String>)? {
        let savedIds = Set(library.items.map(\.id))
        // LibraryItem carries no malId/description/status/year — synthesize a minimal
        // Manga per saved item so TasteProfile.build can materialize seeds for it.
        let libraryManga = library.items.map { item in
            Manga(id: item.id, sourceId: item.sourceId ?? "mangadex", title: item.title,
                 description: "", status: "unknown", year: nil, coverURL: item.coverURL, malId: nil)
        }
        let profile = TasteProfile.build(history: history.entries,
                                         savedIds: savedIds,
                                         tagCache: profileStore.tagCache,
                                         moreLikeThis: Set(profileStore.moreLikeThis),
                                         now: now(),
                                         libraryItems: libraryManga)
        guard profile.taggedMangaCount >= minTaggedManga, !profile.isEmpty else { return nil }
        let readIds = Set(history.entries.map(\.mangaId))
        return (profile, readIds.union(savedIds).union(profileStore.notInterested))
    }

    /// Mostly top matches, plus a seeded sample from the lower-ranked tail (adjacent
    /// interests), then a seeded shuffle — stable within a session, fresh across them.
    func compose(pool: [ScoredManga], railSize: Int = 20) -> [ScoredManga] {
        guard pool.count > railSize else { return pool }
        var rng = SeededRNG(seed: seed)
        let coreCount = Int(Double(railSize) * coreFraction)
        let core = Array(pool.prefix(coreCount))
        let tail = Array(pool.suffix(from: coreCount))
        let explore = Array(tail.shuffled(using: &rng).prefix(railSize - coreCount))
        var combined = core + explore
        combined.shuffle(using: &rng)
        return combined
    }

    private func scheduleBackfill() {
        // Only MangaDex reads (nil sourceId = legacy MangaDex) can be back-filled here.
        let readIds = history.entries
            .filter { ($0.sourceId ?? "mangadex") == "mangadex" }
            .map(\.mangaId)
        let missing = profileStore.mangaIdsMissingTags(readIds: readIds)
        guard !missing.isEmpty else { return }
        Task { await backfill(ids: Array(missing.prefix(backfillBatch))) }
    }

    /// Best-effort: fetch detail for a few read manga and cache their tags. Per-item
    /// failures are swallowed (matches LibraryStore.refresh).
    func backfill(ids: [String]) async {
        for id in ids {
            if let detail = try? await mangaDexSource.mangaDetail(id: id) {
                profileStore.recordTags(mangaId: id, tags: detail.tags)
            }
        }
    }
}
