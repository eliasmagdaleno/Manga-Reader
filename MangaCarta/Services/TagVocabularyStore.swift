//
//  TagVocabularyStore.swift
//  MangaCarta
//
//  Slice 1 of ADR-0011: AniList's 425-tag vocabulary, cached.
//
//  `category` is a property of a tag *name*, globally — not a fact about any Work — so
//  `RankedTag` stays `(name, rank)` and categories are looked up here at read time.
//  Persisting them inside every `MetadataSnapshot` would duplicate 425 strings across the
//  store and create a migration trap with no exit: `isStale` returns `false` forever for
//  `.finished` Works, so every already-upgraded Work would drop out of pair seeding
//  permanently.
//
//  In `Caches/` by ADR-0007's placement test — *can you delete this file and lose nothing
//  but time?* One 27 KB request rebuilds it.
//

import Foundation

/// One tag in AniList's vocabulary. Decoded straight off `MediaTagCollection`, so the
/// property names are the wire names.
struct TagVocabularyEntry: Codable, Equatable {
    let name: String
    /// e.g. `Theme-Fantasy`, `Technical`, `Cast-Main Cast`. Optional because AniList's
    /// schema allows it, not because we have seen one missing.
    let category: String?
    /// One of the 8 structurally-spoiling tags (Reincarnation, Time Skip, …). Suppressed
    /// from *reason strings* only, never from seeding.
    let isGeneralSpoiler: Bool
    let isAdult: Bool
}

/// A fetched vocabulary plus the three questions seeding and reason strings ask of it.
struct TagVocabulary: Codable, Equatable {
    /// Thirty days. Deliberately *not* the 14 days everything else in this subsystem uses:
    /// that number means "a negative answer is worth re-asking eventually", and this is not
    /// a negative answer. ADR-0011 measured the category counts unmoved across three days.
    static let ttl: TimeInterval = 30 * 24 * 60 * 60

    let fetchedAt: Date
    let entries: [TagVocabularyEntry]

    /// Lowercased so a name that arrives with different casing still resolves — AniList is
    /// both sides of this comparison today, but a MangaDex name can land on the ranked axis
    /// with `rank == nil`, and a silently-uncategorized tag is a seeding bug.
    private var byName: [String: TagVocabularyEntry] {
        Dictionary(entries.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }

    func isFresh(now: Date = Date()) -> Bool {
        now.timeIntervalSince(fetchedAt) < Self.ttl
    }

    /// `nil` for a tag the vocabulary has never heard of. Callers excluding categories must
    /// treat that as "not excluded" — the exclusion set is a deny list, so an unknown tag
    /// stays seedable rather than silently disappearing.
    func category(of name: String) -> String? {
        byName[name.lowercased()]?.category
    }

    func isGeneralSpoiler(_ name: String) -> Bool {
        byName[name.lowercased()]?.isGeneralSpoiler ?? false
    }

    func isAdult(_ name: String) -> Bool {
        byName[name.lowercased()]?.isAdult ?? false
    }
}

/// Owns the cached vocabulary and the one request that fills it.
///
/// An `actor` rather than `@MainActor`: its only caller is a `CandidateProvider` running
/// off the main thread during a rail build, and the cache must not be re-fetched by two
/// concurrent pools.
actor TagVocabularyStore {
    /// Injectable so tests never touch the network. The shipped wiring passes a closure
    /// that goes through `AniListRateLimiter` — ADR-0011 amends "one owner of the client"
    /// to **one owner of the rate limiter**, and this request spends from the same budget.
    typealias Fetch = () async throws -> [TagVocabularyEntry]

    /// `Caches/`, which is evictable: losing this costs one request, and the read-through
    /// pool it feeds is rebuilt on the next rail build.
    static func cachesDirectory() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    private let directory: URL
    private let fetch: Fetch
    private var cached: TagVocabulary?
    private var loaded = false

    private var fileURL: URL { directory.appendingPathComponent("anilist-tag-vocabulary.json") }

    init(directory: URL = TagVocabularyStore.cachesDirectory(), fetch: @escaping Fetch) {
        self.directory = directory
        self.fetch = fetch
    }

    /// The vocabulary, fetching only when what we hold is missing or past its TTL.
    ///
    /// Returns `nil` only when there is *nothing* to answer with. ADR-0011's
    /// skip-rather-than-degrade rule applies to that case: generation is skipped entirely
    /// rather than seeded with categories unknown, because unfiltered seeding is
    /// specifically the "recommend me webtoons and Male Protagonist" failure.
    func vocabulary(now: Date = Date()) async -> TagVocabulary? {
        loadIfNeeded()
        if let cached, cached.isFresh(now: now) { return cached }

        do {
            let entries = try await fetch()
            let vocabulary = TagVocabulary(fetchedAt: now, entries: entries)
            cached = vocabulary
            save(vocabulary)
            return vocabulary
        } catch {
            // A stale vocabulary beats none — categories move on the order of years, and an
            // AniList outage should not take the rail down for the rest of the session.
            // Nothing is written on failure: an empty vocabulary cached for thirty days
            // would read as "AniList has no tags".
            return cached
        }
    }

    /// What is on disk right now, **without ever awaiting a fetch** — stale or `nil`.
    ///
    /// `vocabulary()` above awaits the network whenever the cache is absent *or* past its
    /// 30-day TTL, which is right for its caller and wrong for the rail: it would stall
    /// Home behind a 27 KB request and a limiter slot, on the cold-launch-after-eviction
    /// case `Caches/` placement deliberately accepts. Read-through means nothing if the
    /// read blocks.
    ///
    /// **Staleness is fine for this consumer; absence is not.** Categories move on the
    /// order of years and an unknown tag stays seedable by the deny-list rule, so a
    /// 40-day-old vocabulary is a non-event — while a missing one triggers ADR-0011's
    /// skip-rather-than-degrade rule.
    func cachedVocabulary() -> TagVocabulary? {
        loadIfNeeded()
        return cached
    }

    /// Brings the cache up to date in the background, if it needs it. Fire-and-forget:
    /// the caller gets no result and does not wait, because whatever it is doing this
    /// build is being done with `cachedVocabulary()` already.
    ///
    /// Deliberately *not* deduped against a concurrent refresh the way the pool store's
    /// task is — `vocabulary()` is idempotent, at most one extra 27 KB request is at
    /// stake, and the TTL closes the window after the first success.
    func refreshIfNeeded(now: Date = Date()) {
        loadIfNeeded()
        if let cached, cached.isFresh(now: now) { return }
        Task { _ = await self.vocabulary(now: now) }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let vocabulary = try? JSONDecoder().decode(TagVocabulary.self, from: data) else { return }
        cached = vocabulary
    }

    private func save(_ vocabulary: TagVocabulary) {
        guard let data = try? JSONEncoder().encode(vocabulary) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
