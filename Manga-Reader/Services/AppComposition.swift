//
//  AppComposition.swift
//  Manga-Reader
//
//  The app's object graph, built in one place.
//
//  Extracted out of `Manga_ReaderApp.init` on 2026-08-08 for one reason: the wiring had no
//  test. Several of the claims this file makes are *by construction* — "one owner of the
//  rate limiter", "one owner of the attempt records" — and a claim by construction is only
//  true while the construction says so. Deleting an argument here breaks none of the 433
//  tests that existed before this file did, because every one of them builds its own graph.
//
//  Storage is injectable so a test can build the real graph against a temp directory and
//  an isolated `UserDefaults`, and then assert on behaviour rather than on shape. Production
//  passes nothing and gets the defaults each store already had.
//

import Foundation

/// The app-wide stores, the upgrade queue and the recommendation engine, wired together.
///
/// A `struct` of `let`s rather than an object: it has no behaviour of its own, and the
/// lifetimes that matter are the ones inside it (`@StateObject` in `Manga_ReaderApp`, and
/// the two actors below, which must outlive a rail build).
@MainActor
struct AppComposition {
    let library: LibraryStore
    let history: HistoryStore
    let taste: TasteProfileStore
    let works: WorkStore
    let engine: RecommendationEngine
    let queue: MetadataUpgradeQueue

    /// The one attempt memory. Exposed because it is *shared* — see `init` — and a shared
    /// instance is exactly the kind of thing a test needs to reach to prove the sharing.
    let attempts: UpgradeAttemptMemory

    /// The AniList pool's two caches (ADR-0011). Held here, not built inside `makeProvider`,
    /// because both are **actors whose state must outlive a rail build**: `AniListPoolStore`
    /// holds the in-flight refresh and the superseded-seeds guard, and a fresh instance per
    /// rebuild would mean no refresh is ever "in flight", the dedupe slice 3 tested would be
    /// silently dead, and the pool would never warm.
    let vocabularyStore: TagVocabularyStore
    let poolStore: AniListPoolStore

    init(defaults: UserDefaults = .standard,
         directory: URL = WorkStore.applicationSupportDirectory()) {
        // Built first: the three commitment paths below (read, save, feedback) all
        // mint into it, so they must share this one instance (ADR-0007).
        let wk = WorkStore(directory: directory)
        let lib = LibraryStore(defaults: defaults, works: wk)
        let hist = HistoryStore(defaults: defaults, works: wk)
        let ts = TasteProfileStore(defaults: defaults)

        // One limiter, passed explicitly rather than left to `MetadataUpgradeQueue`'s
        // default argument. ADR-0011 amends ADR-0007's "one owner of the client" to **one
        // owner of the rate limiter**, and that claim is only true by construction if
        // every AniList caller is handed the same instance. The queue and the pool draw on
        // the same 30/min budget.
        let anilist = AniListAPI()
        let limiter = AniListRateLimiter()
        // Hoisted for the same reason as the limiter directly above, and it is the same
        // claim: the queue would otherwise build its own via `memory ?? UpgradeAttemptMemory()`
        // and hold it privately, so "one owner of the attempt records" would be false by
        // construction. Two consumers now read it — the drain, deciding what to skip, and the
        // rail, deciding whether to explain itself (ADR-0015) — and if they saw different
        // records the notice would contradict the drain.
        let memory = UpgradeAttemptMemory(directory: directory)
        // `resolver: nil` leaves `MetadataUpgradeQueue` to build its own, as it always has.
        // A `VerificationSwitches` override sat here from 2026-08-11 to 2026-08-13 to
        // instrument the ADR-0019 runs; it was `#if DEBUG` and nil unless an environment
        // variable was set, and it is gone now that both runs are written up.
        let upgrades = MetadataUpgradeQueue(works: wk, anilist: anilist, rateLimiter: limiter,
                                            resolver: nil, memory: memory)

        let vocab = TagVocabularyStore(fetch: { try await limiter.run { try await anilist.tagVocabulary() } })
        let pool = AniListPoolStore()

        // The engine pushes, the queue never pulls: pulling would mean the queue
        // building a profile, and building one mints Works (ADR-0009).
        let rec = RecommendationEngine(
            history: hist, library: lib, profileStore: ts, workStore: wk,
            // The third pool (ADR-0011 slice 4). `makeProvider` runs on every rail build, so
            // the provider *struct* is rebuilt each time — that is fine and deliberate, it is
            // a few closures over two actor references. Only the actors need identity, and
            // they are captured from above.
            makeProvider: { @MainActor source in
                // One reverse resolver for both consumers, so the cache-write discipline
                // has a single implementation (ADR-0011). It needs no identity of its own —
                // all its durable state is in `EntityResolutionStore.shared` — so unlike
                // the two actors above, rebuilding it per rail build would also be correct.
                let reverse = MALReverseResolver()
                return CompositeCandidateProvider(
                    tag: TagCandidateProvider(source: source),
                    mal: MALCandidateProvider(similar: MoreLikeThisProvider(reverse: reverse)),
                    ani: AniListCandidateProvider(
                        // Hops to the `@MainActor` `WorkStore`; the provider deliberately
                        // is not main-actor-isolated. Same one-way shape as `PriorityPush`.
                        loadWorks: { await MainActor.run { wk.allWorkIds().compactMap { wk.work($0) } } },
                        vocabularyStore: vocab,
                        poolStore: pool,
                        query: { pair, limit in
                            try await limiter.run {
                                try await anilist.media(tags: [pair.a, pair.b], limit: limit)
                            }
                        },
                        resolve: { works in
                            await reverse.resolve(works: works, limit: poolResolveLimit)
                        }))
            },
            pushPriority: { upgrades.setPriority($0) },
            // The one read-only question the recommender may ask the queue's memory
            // (ADR-0015). It cannot start, stop, or steer the drain — `suppresses` only
            // answers "does an unexpired failure already rule this Work out", which is what
            // separates "not tagged yet" from "cannot be tagged". Passed the whole `Work`
            // rather than an id so the `.unmatched(knownTitlesCount:)` comparison stays
            // paired with the Work it was recorded for.
            tagBlocked: { memory.suppresses($0) })

        self.works = wk
        self.library = lib
        self.history = hist
        self.taste = ts
        self.attempts = memory
        self.queue = upgrades
        self.engine = rec
        self.vocabularyStore = vocab
        self.poolStore = pool
    }
}
