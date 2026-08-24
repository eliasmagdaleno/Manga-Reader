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

    /// The MyAnimeList account, and the progress subsystem behind it. The account store is
    /// observable and belongs in the environment for Settings; the coordinator and the
    /// outbox are not — they publish nothing, and a view that could reach them could only
    /// misuse them (ADR-0010). They are held here so they live for the app's lifetime.
    let account: MALAccountStore
    let malProgress: MALProgressCoordinator
    let malOutbox: MALProgressOutbox

    /// The redirect this app registers with MyAnimeList. One spelling, used by both the
    /// authorization URL and the token exchange; MAL matches it exactly.
    static let malRedirectURI = "mangareader://oauth/mal"

    /// MAL's own reference contradicts itself on `PATCH` versus `PUT` for the list-status
    /// setter, and picking one is Task 11's live verification against a known entry. This
    /// is the single point that changes when that lands — nothing else names a verb.
    static let malUpdateVerb: MALListUpdateVerb = .patch

    /// The three injected seams below all default to the production object. They exist so a
    /// test can build **this** graph — not a hand-rolled imitation of it — without a
    /// Keychain, an AniList request, or a MyAnimeList search.
    init(defaults: UserDefaults = .standard,
         directory: URL = WorkStore.applicationSupportDirectory(),
         malCredentials: MALCredentialStore? = nil,
         anilist injectedAniList: AniListAPI? = nil,
         malResolver: MALEntityResolver? = nil) {
        // Built first: the three commitment paths below (read, save, feedback) all
        // mint into it, so they must share this one instance (ADR-0007).
        let wk = WorkStore(directory: directory)
        let lib = LibraryStore(defaults: defaults, works: wk)

        // The MyAnimeList stack, built before `HistoryStore` because the history store takes
        // the completion sink at construction. Nothing here touches the network until the
        // user signs in: the account restores from what is already on disk, and the drain
        // only runs once `start()` is called with a signed-in account.
        let outbox = MALProgressOutbox(directory: directory)
        let malConfiguration = MALOAuthConfiguration(
            clientID: (Bundle.main.object(forInfoDictionaryKey: "MALClientID") as? String) ?? "",
            redirectURI: Self.malRedirectURI)
        let malTransport = MALURLSessionTransport()
        let credentials = malCredentials ?? MALCredentialStore(
            dataStore: MALKeychainCredentialDataStore(),
            markerStore: MALUserDefaultsInstallationMarkerStore(defaults: defaults))
        let tokenClient = MALTokenClient(configuration: malConfiguration, transport: malTransport)
        let tokens = MALTokenManager(client: tokenClient, store: credentials)
        let malClient = MALAuthenticatedClient(tokens: tokens, transport: malTransport,
                                               updateVerb: Self.malUpdateVerb)
        // **Retry now** has to reach a coordinator that does not exist yet, and the
        // coordinator needs the account store — so the button goes through a box that is
        // filled in a few lines below. Weak, so the graph holds no cycle.
        let drain = MALDrainHandle()
        let accountStore = MALAccountStore(
            configuration: malConfiguration,
            presenter: MALWebAuthPresenter(),
            tokenClient: tokenClient,
            credentials: credentials,
            preferences: MALUserDefaultsAccountPreferenceStore(defaults: defaults),
            outbox: outbox,
            // The identity read for a token that is not in the manager yet — see
            // `MALAuthenticatedClient.currentUser(accessToken:transport:)`.
            fetchIdentity: { token in
                try await MALAuthenticatedClient.currentUser(accessToken: token,
                                                             transport: malTransport)
            },
            retryDelivery: { drain.coordinator?.retryNow() })
        let malProgress = MALProgressCoordinator(
            outbox: outbox,
            client: malClient,
            account: accountStore,
            // The coordinator never resolves anything itself; it only reads what the Work
            // already knows, and waits for the queue's signal otherwise.
            malID: { wk.work($0)?.externalIds.mal })
        drain.coordinator = malProgress

        // The completion sink. Synchronous and network-free by contract — it writes the
        // completed chapter to the outbox and returns.
        let hist = HistoryStore(defaults: defaults, works: wk,
                                chapterCompleted: { [weak malProgress] completion in
                                    malProgress?.chapterCompleted(completion)
                                })
        let ts = TasteProfileStore(defaults: defaults)

        // One limiter, passed explicitly rather than left to `MetadataUpgradeQueue`'s
        // default argument. ADR-0011 amends ADR-0007's "one owner of the client" to **one
        // owner of the rate limiter**, and that claim is only true by construction if
        // every AniList caller is handed the same instance. The queue and the pool draw on
        // the same 30/min budget.
        let anilist = injectedAniList ?? AniListAPI()
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
        // The metadata → progress edge. The queue gains no progress dependency: it announces
        // a Work whose external ids it just learned, and the coordinator decides what that
        // is worth (Task 9 of the MAL plan).
        let upgrades = MetadataUpgradeQueue(works: wk, anilist: anilist, rateLimiter: limiter,
                                            resolver: malResolver, memory: memory,
                                            workMetadataChanged: { [weak malProgress] id in
                                                malProgress?.workMetadataChanged(id)
                                            })

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
        self.account = accountStore
        self.malProgress = malProgress
        self.malOutbox = outbox
    }
}


/// The one indirection in this file: `MALAccountStore`'s **Retry now** needs the
/// coordinator, and the coordinator needs the account store. Weak on purpose — the
/// composition owns the coordinator, and this must not be a second owner.
@MainActor
final class MALDrainHandle {
    weak var coordinator: MALProgressCoordinator?
}
