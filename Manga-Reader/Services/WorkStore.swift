//
//  WorkStore.swift
//  Manga-Reader
//
//  The local, app-owned catalog of Works (ADR-0002, shaped by ADR-0007).
//
//  Deliberately unlike every other store in this app: there is **no public
//  dictionary**. `EntityResolutionStore` and `TasteProfileStore` both expose
//  `@Published private(set) var cache`, but Work lookups have to follow merge
//  aliases, and an accessor callers can bypass is an accessor callers will bypass.
//

import Foundation

@MainActor
final class WorkStore: ObservableObject {
    private var works: [WorkID: Work] = [:]
    private var listingIndex: [ListingKey: WorkID] = [:]
    /// External id → Work. Keyed by a `"provider:value"` string so one flat index
    /// covers every provider. Because the Work id is opaque, **this index — not the
    /// id's spelling — is what makes arriving at the same Work twice converge.**
    private var externalIdIndex: [String: WorkID] = [:]
    /// Merged-away Work id → its survivor. Grows by one entry per merge and is never
    /// pruned: that is the point.
    private var aliases: [WorkID: WorkID] = [:]

    private let directory: URL
    private let saveDebounce: TimeInterval
    private var loaded = false
    private var dirty = false
    private var saveTask: Task<Void, Never>?

    /// The store's own file. Application Support, not `Caches/`: this is
    /// authoritative user data, and losing it orphans history and manual links.
    /// (Chapter counts are the opposite — disposable, and live in their own cache.)
    /// `nonisolated` so it can be used as a default argument, which is evaluated
    /// outside the actor.
    nonisolated static func applicationSupportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private var fileURL: URL { directory.appendingPathComponent("works.json") }

    init(directory: URL = WorkStore.applicationSupportDirectory(),
         saveDebounce: TimeInterval = 1.0) {
        self.directory = directory
        self.saveDebounce = saveDebounce
    }

    // MARK: - Lookup

    /// The only way to get a Work. Follows merge aliases, so a stale id returns the
    /// Work it was merged into rather than nil. There is deliberately no public
    /// dictionary to read around this.
    func work(_ id: WorkID) -> Work? {
        loadIfNeeded()
        return resolve(id).flatMap { works[$0] }
    }

    /// Follows the alias chain to the live Work id.
    private func resolve(_ id: WorkID) -> WorkID? {
        var current = id
        // Chains are short in practice, but the walk is bounded anyway: this runs on
        // every lookup on the main actor, so a cycle would hang the UI rather than
        // merely return a wrong answer.
        for _ in 0...32 {
            if works[current] != nil { return current }
            guard let next = aliases[current] else { return nil }
            current = next
        }
        return nil
    }

    func workId(for listing: ListingKey) -> WorkID? {
        loadIfNeeded()
        return listingIndex[listing]
    }

    func workId(externalId ids: ExternalIDs) -> WorkID? {
        loadIfNeeded()
        return Self.indexKeys(for: ids).lazy.compactMap { self.externalIdIndex[$0] }.first
    }

    // MARK: - Minting

    /// Creates a Work from a Listing, or returns the existing one.
    ///
    /// **Synchronous, local, network-free** — this sits on the path where the user
    /// just opened a chapter, so it cannot block the reader and must work offline.
    /// It also never *guesses*: two Listings converge only on an external id both
    /// already carry, never on a similar title. Title matching is resolution's job,
    /// and it is precision-biased for a reason (ADR-0005).
    func mint(from listing: Manga) -> WorkID {
        loadIfNeeded()
        defer { markDirty() }
        let key = ListingKey(listing)
        let ids = ExternalIDs(mal: listing.malId, anilist: nil)

        // Already minted from this exact Listing.
        if let existing = listingIndex[key] {
            absorb(ids, into: existing, title: listing.title)
            return existing
        }
        // Known under an external id this Listing publishes — the free dedupe path.
        if let existing = workId(externalId: ids) {
            link(key, to: existing, title: listing.title)
            absorb(ids, into: existing, title: listing.title)
            return existing
        }

        var work = Work(id: WorkID(),
                        displayTitle: listing.title,
                        knownTitles: [],
                        externalIds: ids,
                        listings: [key],
                        snapshot: nil)
        work.noteTitle(listing.title)
        works[work.id] = work
        listingIndex[key] = work.id
        reindexExternalIds(of: work.id)
        return work.id
    }

    // MARK: - Metadata snapshots

    /// The provisional tier: a snapshot built from the Listing's own tags. Costs no
    /// request — MangaDex's tags arrive with the detail fetch the UI already makes —
    /// so the recommender has signal from launch, before any provider is queried.
    func applyProvisionalSnapshot(tags: [Tag], to id: WorkID, now: Date = Date()) {
        loadIfNeeded()
        defer { markDirty() }
        guard let resolved = resolve(id), var work = works[resolved] else { return }
        work.snapshot = MetadataSnapshot(
            provider: .mangadex,
            fetchedAt: now,
            genres: tags.map { QueryableTag(name: $0.name, group: $0.group) },
            tags: [],                       // MangaDex publishes no per-title rank.
            publicationStatus: .unknown,
            chapterTotal: nil)
        works[resolved] = work
    }

    /// Upgrades a Work to a provider snapshot, **replacing** whatever was there.
    /// One authority per Work; external ids and known titles are the exceptions and
    /// accumulate.
    func apply(_ provider: AniListWork, to id: WorkID, now: Date = Date()) {
        loadIfNeeded()
        defer { markDirty() }
        guard let resolved = resolve(id), var work = works[resolved] else { return }

        // Replacement is wholesale, which can lose information -- so a snapshot with
        // nothing on the searchable axis doesn't get to discard one that has content.
        // The ids below still accumulate: learning the AniList id is worth keeping
        // even when the metadata behind it isn't.
        let hasContent = !provider.genres.isEmpty || !provider.tags.isEmpty
        if hasContent || work.snapshot == nil {
            work.snapshot = MetadataSnapshot(
                provider: .anilist,
                fetchedAt: now,
                genres: provider.genres.map { QueryableTag(name: $0) },
                tags: provider.tags,
                publicationStatus: provider.publicationStatus,
                chapterTotal: provider.chapterTotal)
        }
        work.externalIds.absorb(ExternalIDs(mal: provider.malId, anilist: provider.anilistId))
        for title in provider.knownTitles { work.noteTitle(title) }
        works[resolved] = work
        reindexExternalIds(of: resolved)
    }

    // MARK: - Linking and merging

    /// Records external ids on a Work, unioning with what's already there.
    /// Called when resolution learns an id the Listing didn't publish.
    func setExternalIds(_ ids: ExternalIDs, on id: WorkID) {
        loadIfNeeded()
        defer { markDirty() }
        guard let resolved = resolve(id) else { return }
        absorb(ids, into: resolved, title: "")
    }

    /// Collapses `loser` into `winner`, which happens whenever an external id or a
    /// manual link arrives after both Works already exist.
    ///
    /// The loser is **aliased, never erased**: its id keeps resolving to the winner
    /// forever. Cost is two ids in a dictionary; merges are rare, and the
    /// alternative — a dangling id that resolves to nil — fails silently.
    func merge(_ loser: WorkID, into winner: WorkID) {
        loadIfNeeded()
        defer { markDirty() }
        guard let loserId = resolve(loser), let winnerId = resolve(winner),
              loserId != winnerId,
              let losing = works[loserId], var surviving = works[winnerId] else { return }

        // The surviving Work keeps its own displayTitle; the loser's becomes a known
        // title. Arbitrary, but stable — and stability is the property that matters.
        surviving.noteTitle(losing.displayTitle)
        for title in losing.knownTitles { surviving.noteTitle(title) }
        surviving.externalIds.absorb(losing.externalIds)
        for key in losing.listings where !surviving.listings.contains(key) {
            surviving.listings.append(key)
        }

        works[winnerId] = surviving
        works[loserId] = nil
        aliases[loserId] = winnerId

        for key in losing.listings { listingIndex[key] = winnerId }
        reindexExternalIds(of: winnerId)
    }

    // MARK: - Private

    private func link(_ key: ListingKey, to id: WorkID, title: String) {
        guard var work = works[id] else { return }
        if !work.listings.contains(key) { work.listings.append(key) }
        work.noteTitle(title)
        works[id] = work
        listingIndex[key] = id
    }

    private func absorb(_ ids: ExternalIDs, into id: WorkID, title: String) {
        guard var work = works[id] else { return }
        work.externalIds.absorb(ids)
        work.noteTitle(title)
        works[id] = work
        reindexExternalIds(of: id)
    }

    private func reindexExternalIds(of id: WorkID) {
        guard let work = works[id] else { return }
        for key in Self.indexKeys(for: work.externalIds) {
            externalIdIndex[key] = id
        }
    }

    // MARK: - Persistence

    /// Writes immediately if there's anything pending. Call on backgrounding — a
    /// debounced save that never fires because the app was suspended is a lost write.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard dirty else { return }
        dirty = false

        let payload = Persisted(works: Array(works.values),
                                aliases: aliases.map { Persisted.Alias(from: $0.key, to: $0.value) })
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(payload).write(to: fileURL, options: .atomic)
        } catch {
            // Best-effort, matching the rest of the app's stores: a failed write
            // costs the last few mutations, and there is nothing useful to do here.
            dirty = true
        }
    }

    /// Loaded on first use rather than in `init`, so constructing the store (which
    /// happens at launch) never touches the disk.
    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true

        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Persisted.self, from: data) else { return }

        for work in payload.works { works[work.id] = work }
        for alias in payload.aliases { aliases[alias.from] = alias.to }
        for work in payload.works {
            for key in work.listings { listingIndex[key] = work.id }
            reindexExternalIds(of: work.id)
        }
    }

    private func markDirty() {
        dirty = true
        saveTask?.cancel()
        let delay = saveDebounce
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    private static func indexKeys(for ids: ExternalIDs) -> [String] {
        var keys: [String] = []
        if let mal = ids.mal { keys.append("mal:\(mal)") }
        if let anilist = ids.anilist { keys.append("anilist:\(anilist)") }
        return keys
    }
}

// MARK: - On-disk shape

/// Only Works and aliases are stored: **both indexes are rebuilt on load**, so they
/// cannot drift out of sync with the Works they point at. Aliases are pairs rather
/// than a dictionary because JSON object keys must be strings and a `WorkID` isn't
/// one. File-scope rather than nested in `WorkStore` so `Alias` stays one level deep.
private struct Persisted: Codable {
    struct Alias: Codable {
        let from: WorkID
        let to: WorkID
    }
    var works: [Work]
    var aliases: [Alias]
}
