//
//  AniListPoolStore.swift
//  Manga-Reader
//
//  Slice 3 of ADR-0011: the read-through cache behind the AniList pool.
//
//  The rule this type exists to enforce is that **the rail never waits**. Reads answer
//  from what is on disk — empty on a cold miss — and a refresh runs in the background, so
//  the pool appears on the *next* rail build. That delay is invisible because `compose`
//  already reshuffles with a per-session seed: a pool arriving one build later is
//  indistinguishable from exploration, and `load()` fires on every Home appearance.
//
//  An `actor`, not a `@MainActor` class like the app's other stores: a 40-title JSON
//  encode/decode has no business on the main actor, and `CandidateProvider` is not
//  main-actor-bound. `TagVocabularyStore`'s plain-class shape was rejected as the model
//  because that store *awaits* its fetch — right for its one caller on a cold path, and
//  exactly what this design exists not to do.
//

import Foundation

actor AniListPoolStore {
    /// Builds a fresh record for these seeds, or `nil` if it could not. Injected rather
    /// than implemented here so the store owns caching and nothing else — the fan-out,
    /// the abort rule and the resolution budget belong to the provider.
    typealias Refresh = ([TagPair]) async -> AniListPoolRecord?

    /// `Caches/` by ADR-0007's placement test: delete this and lose nothing but time.
    /// In-memory-only was rejected — it would mean no AniList pool on the first Home
    /// appearance of every cold launch, which is the most common Home appearance there is.
    static func cachesDirectory() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    private let directory: URL
    private var cached: AniListPoolRecord?
    private var loaded = false

    /// The refresh currently running, and the seeds it is running for. `load()` fires on
    /// every Home appearance, so without this two appearances two seconds apart kick two
    /// independent 5-query refreshes for the same seeds — 10 requests against a 30/min
    /// budget. Handing the second caller the *same* task is the fix, and it needs actor
    /// isolation to be race-free.
    private var inFlight: (seeds: [TagPair], task: Task<Void, Never>)?

    private var fileURL: URL { directory.appendingPathComponent("anilist-pool.json") }

    init(directory: URL = AniListPoolStore.cachesDirectory()) {
        self.directory = directory
    }

    /// The pool for these seeds if we hold a fresh one, else `nil`. **Never fetches.**
    func pool(seeds: [TagPair], now: Date = Date()) -> AniListPoolRecord? {
        loadIfNeeded()
        guard let cached, cached.matches(seeds: seeds), cached.isFresh(now: now) else {
            return nil
        }
        return cached
    }

    /// Kicks a background refresh when what we hold does not answer for `seeds`, and
    /// returns immediately. Idempotent while one is in flight for the same seeds.
    ///
    /// The task is **unstructured and created inside the actor**, so it does not inherit
    /// the rail build's cancellation: read-through means nothing if the refresh dies with
    /// the caller that triggered it.
    @discardableResult
    func refreshIfNeeded(seeds: [TagPair],
                         now: Date = Date(),
                         using refresh: @escaping Refresh) -> Task<Void, Never>? {
        loadIfNeeded()
        if let cached, cached.matches(seeds: seeds), cached.isFresh(now: now) { return nil }
        let canonical = AniListPoolRecord.canonical(seeds)
        if let inFlight, inFlight.seeds == canonical { return inFlight.task }

        // A **strong** capture, deliberately. `[weak self]` would let a refresh finish into
        // a deallocated store and silently drop the result it just spent five AniList
        // requests on — the opposite of the rule this type exists for, since the refresh is
        // supposed to outlive the rail build that triggered it. The reference cycle it
        // creates (store → inFlight task → store) is temporary: `finish` clears `inFlight`.
        let task = Task {
            let record = await refresh(canonical)
            await self.finish(seeds: canonical, record: record)
        }
        inFlight = (canonical, task)
        return task
    }

    /// Writes the result of a refresh, if there was one. A `nil` record means the refresh
    /// aborted — all five pair queries must complete without throwing or nothing is
    /// written, because an entry keyed on five pairs but built from three is lying about
    /// its own key. The previous entry stands and the next Home appearance retries.
    /// A refresh whose seeds are **no longer the ones in flight** is discarded, not
    /// written. Taste can shift while five queries are outstanding: `refreshIfNeeded`
    /// then replaces `inFlight` with the new seeds, and without this guard the older
    /// refresh — which may well finish last — would land on disk *after* the newer one and
    /// overwrite a correct pool with a superseded one. Self-healing on the next Home
    /// appearance, but it costs a whole refresh to heal.
    private func finish(seeds: [TagPair], record: AniListPoolRecord?) {
        guard inFlight?.seeds == seeds else { return }
        inFlight = nil
        guard let record else { return }
        cached = record
        save(record)
    }

    /// One entry, not a dictionary keyed by seed set. A previous seed set's pool is dead
    /// weight the moment taste shifts — the key exists to *invalidate*, not to archive.
    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        // A corrupt or undecodable file is a miss, matching `TagVocabularyStore`.
        guard let data = try? Data(contentsOf: fileURL),
              let record = try? JSONDecoder().decode(AniListPoolRecord.self, from: data) else { return }
        cached = record
    }

    private func save(_ record: AniListPoolRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
