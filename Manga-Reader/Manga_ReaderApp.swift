//
//  Manga_ReaderApp.swift
//  Manga-Reader
//
//  Created by Elias Magdaleno on 5/31/24.
//

import SwiftUI

@main
struct Manga_ReaderApp: App {
    // Persisted appearance choice; drives the whole app's color scheme.
    @AppStorage(appearanceStorageKey) private var appearanceRaw = AppearanceMode.system.rawValue

    @Environment(\.scenePhase) private var scenePhase

    // App-wide stores + the recommendation engine, all owned here so the engine shares
    // the exact same store instances the rest of the app writes to.
    @StateObject private var library: LibraryStore
    @StateObject private var history: HistoryStore
    @StateObject private var taste: TasteProfileStore
    @StateObject private var works: WorkStore
    @StateObject private var engine: RecommendationEngine
    /// Owned here so it lives as long as the app and shares the one `WorkStore`, but
    /// deliberately **not** put in the environment: it publishes nothing, so a view that
    /// could reach it could only misuse it (ADR-0010).
    @StateObject private var queue: MetadataUpgradeQueue

    /// The AniList pool's two caches (ADR-0011). Owned here, not built inside
    /// `makeProvider`, because both are **actors whose state must outlive a rail build**:
    /// `AniListPoolStore` holds the in-flight refresh and the superseded-seeds guard, and a
    /// fresh instance per rebuild would mean no refresh is ever "in flight", the dedupe
    /// slice 3 tested would be silently dead, and the pool would never warm. Plain
    /// properties rather than `@StateObject` — neither publishes anything, so a view that
    /// could reach one could only misuse it (ADR-0010).
    private let vocabularyStore: TagVocabularyStore
    private let poolStore: AniListPoolStore

    init() {
        // Built first: the three commitment paths below (read, save, feedback) all
        // mint into it, so they must share this one instance (ADR-0007).
        let wk = WorkStore()
        let lib = LibraryStore(works: wk)
        let hist = HistoryStore(works: wk)
        let ts = TasteProfileStore()

        // One limiter, passed explicitly rather than left to `MetadataUpgradeQueue`'s
        // default argument. ADR-0011 amends ADR-0007's "one owner of the client" to **one
        // owner of the rate limiter**, and that claim is only true by construction if
        // every AniList caller is handed the same instance. The queue and the pool draw on
        // the same 30/min budget.
        let anilist = AniListAPI()
        let limiter = AniListRateLimiter()
        let upgrades = MetadataUpgradeQueue(works: wk, anilist: anilist, rateLimiter: limiter)

        let vocab = TagVocabularyStore(fetch: { try await limiter.run { try await anilist.tagVocabulary() } })
        let pool = AniListPoolStore()
        self.vocabularyStore = vocab
        self.poolStore = pool
        _library = StateObject(wrappedValue: lib)
        _history = StateObject(wrappedValue: hist)
        _taste = StateObject(wrappedValue: ts)
        _works = StateObject(wrappedValue: wk)
        _queue = StateObject(wrappedValue: upgrades)
        // The engine pushes, the queue never pulls: pulling would mean the queue
        // building a profile, and building one mints Works (ADR-0009).
        // The third pool (ADR-0011 slice 4). `makeProvider` runs on every rail build, so the
        // provider *struct* is rebuilt each time — that is fine and deliberate, it is a few
        // closures over two actor references. Only the actors need identity, and they are
        // captured from above.
        _engine = StateObject(wrappedValue: RecommendationEngine(
            history: hist, library: lib, profileStore: ts, workStore: wk,
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
            pushPriority: { upgrades.setPriority($0) }))
    }

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Ink.seal)
                .environmentObject(library)
                .environmentObject(history)
                .environmentObject(taste)
                .environmentObject(works)
                .environmentObject(engine)
                .preferredColorScheme(appearance.colorScheme)
                // `onChange` does not fire for the initial value, so launch needs its
                // own start. `start()` is idempotent, so the `.active` case below
                // arriving first, later, or not at all is all the same.
                .task {
                    queue.start()
                    // Collapses the AniList pool's cold start from three rail builds to
                    // two. Without it: build 1 finds no vocabulary and returns `[]` before
                    // seeding at all, build 2 seeds but misses the pool, build 3 finally
                    // has one — and since `load()` is once-per-session, "build" means app
                    // launch. This is an optimization on top of the provider's own kick,
                    // never a replacement for it: that one is the correctness path for a
                    // `Caches/` eviction mid-session, and `refreshIfNeeded` is idempotent,
                    // so both firing is a no-op. Fire-and-forget, so it never blocks Home —
                    // the concern `TagVocabularyStore.cachedVocabulary` is written against.
                    await vocabularyStore.refreshIfNeeded()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                queue.start()
            case .background:
                // Stop before flushing: cancellation is what guarantees no attempt
                // record is written after `queue.flush()` has already run.
                queue.stop()
                // `WorkStore` debounces its saves, and `mint` runs on every page turn —
                // so a reading session that ends by backgrounding the app would otherwise
                // lose whatever the pending timer hadn't written yet (ADR-0007).
                works.flush()
                queue.flush()
                // Same reason, one layer up: reading position is throttled while scrolling,
                // and a webtoon session that ends by backgrounding would lose the last
                // couple of seconds of it (ADR-0014).
                history.flush()
            default:
                // `.inactive` is NOT a stop signal (ADR-0010). It arrives for a
                // notification banner or the app switcher, and tearing the pass down
                // several times a minute would lose the skip set for no reason.
                break
            }
        }
    }
}
