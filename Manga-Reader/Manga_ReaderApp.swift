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
    /// Observable, and injected into the environment for the Settings account section.
    @StateObject private var account: MALAccountStore

    /// Plain properties rather than `@StateObject` — neither publishes anything, so a view
    /// that could reach one could only misuse it (ADR-0010). See `AppComposition` for why
    /// they are held for the app's lifetime rather than built per rail build.
    private let vocabularyStore: TagVocabularyStore
    private let poolStore: AniListPoolStore
    /// Same reason as the two above: the coordinator publishes nothing. It is held for the
    /// app's lifetime because the drain is its own serial task, and a rebuilt coordinator
    /// would be a second one.
    private let malProgress: MALProgressCoordinator

    /// The graph itself lives in `AppComposition`, where it can be built against temp
    /// storage and asserted on. This initializer does nothing but adopt what it built.
    init() {
        let composed = AppComposition()
        self.vocabularyStore = composed.vocabularyStore
        self.poolStore = composed.poolStore
        self.malProgress = composed.malProgress
        _library = StateObject(wrappedValue: composed.library)
        _history = StateObject(wrappedValue: composed.history)
        _taste = StateObject(wrappedValue: composed.taste)
        _works = StateObject(wrappedValue: composed.works)
        _queue = StateObject(wrappedValue: composed.queue)
        _engine = StateObject(wrappedValue: composed.engine)
        _account = StateObject(wrappedValue: composed.account)
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
                .environmentObject(account)
                .preferredColorScheme(appearance.colorScheme)
                // `onChange` does not fire for the initial value, so launch needs its
                // own start. `start()` is idempotent, so the `.active` case below
                // arriving first, later, or not at all is all the same.
                .task {
                    queue.start()
                    // Rebuilds the account from disk before anything asks whether the user
                    // is signed in, then drains whatever a previous session left queued.
                    account.restore()
                    malProgress.start()
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
                malProgress.start()
            case .background:
                // Stop before flushing: cancellation is what guarantees no attempt
                // record is written after `queue.flush()` has already run.
                queue.stop()
                // Same order, same reason: the drain is stopped before the outbox is
                // flushed, so no attempt can be written after the flush has run.
                malProgress.stop()
                // `WorkStore` debounces its saves, and `mint` runs on every page turn —
                // so a reading session that ends by backgrounding the app would otherwise
                // lose whatever the pending timer hadn't written yet (ADR-0007).
                works.flush()
                queue.flush()
                // Same reason, one layer up: reading position is throttled while scrolling,
                // and a webtoon session that ends by backgrounding would lose the last
                // couple of seconds of it (ADR-0014).
                history.flush()
                malProgress.flush()
            default:
                // `.inactive` is NOT a stop signal (ADR-0010). It arrives for a
                // notification banner or the app switcher, and tearing the pass down
                // several times a minute would lose the skip set for no reason.
                break
            }
        }
    }
}
