//
//  MetadataUpgradeQueue.swift
//  Manga-Reader
//
//  ADR-0008 (policy), ADR-0009 (construction), ADR-0010 (the loop and its wiring).
//

import Foundation

@MainActor
final class MetadataUpgradeQueue: ObservableObject {
    typealias Sleep = (TimeInterval) async throws -> Void

    /// What one turn of the loop did. `run` branches only on `.idle`.
    enum DrainStep: Equatable {
        case upgraded(WorkID)
        case failed(WorkID)
        case idle
    }

    private let works: WorkStore
    private let anilist: AniListAPI
    private let rateLimiter: AniListRateLimiter
    private let resolver: MALEntityResolver
    private let memory: UpgradeAttemptMemory
    private let idleInterval: TimeInterval
    private let now: () -> Date
    private let sleep: Sleep

    init(works: WorkStore,
         anilist: AniListAPI = AniListAPI(),
         rateLimiter: AniListRateLimiter = AniListRateLimiter(),
         // Nil-defaulted rather than defaulted to the real thing: both are `@MainActor`,
         // and a default argument is evaluated in a nonisolated context.
         resolver: MALEntityResolver? = nil,
         memory: UpgradeAttemptMemory? = nil,
         idleInterval: TimeInterval = 60,
         now: @escaping () -> Date = Date.init,
         sleep: @escaping Sleep = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) {
        self.works = works
        self.anilist = anilist
        self.rateLimiter = rateLimiter
        // `.shared` is deliberate and load-bearing: `EntityResolutionStore` reads
        // UserDefaults once in `init` and never reloads, so any other instance is frozen
        // at launch and the resolver's free cache fast path silently dies (ADR-0010).
        self.resolver = resolver ?? MALEntityResolver(store: .shared)
        self.memory = memory ?? UpgradeAttemptMemory()
        self.idleInterval = idleInterval
        self.now = now
        self.sleep = sleep
    }

    /// The last engagement-weight map the recommender pushed (ADR-0009). **Replaces**
    /// rather than merges: the map is complete for every Work with reading history, so a
    /// Work dropping out of it means its history is gone and it belongs in the tail.
    private var priority: [WorkID: Double] = [:]

    func setPriority(_ weights: [WorkID: Double]) { priority = weights }

    // MARK: - Lifecycle

    /// `internal` so tests can await the loop's completion; nothing in the app reads it.
    private(set) var loopTask: Task<Void, Never>?

    /// Idempotent, because `.active` recurs without an intervening `.background` — a
    /// dismissed notification banner is enough. Without the guard every one of those
    /// leaks another loop and the queue stops being serial by construction (ADR-0010).
    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in await self?.run() }
    }

    /// Cancels without awaiting: blocking a `scenePhase` handler on an in-flight network
    /// request would be a far worse trade than losing at most one attempt record.
    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    func flush() { memory.flush() }

    /// One branch. A tripped breaker returns `.idle` exactly as an empty scan does, so the
    /// loop never needs to know *why* it is idling (ADR-0010).
    private func run() async {
        while !Task.isCancelled {
            if await drainOnce(now: now()) == .idle {
                // `Task.sleep` throws only on cancellation, so a throw here means stop.
                do { try await sleep(idleInterval) } catch { return }
            }
        }
    }

    // MARK: - One turn of the loop

    /// Upgrades at most one Work. No sleeps of its own — the only pacing is the rate
    /// limiter's — so the whole of the queue's behaviour is testable without wall clock.
    ///
    /// `internal` rather than `private` purely so tests can call it; the app calls
    /// `start()`/`stop()`/`flush()`.
    func drainOnce(now: Date) async -> DrainStep {
        guard let work = nextCandidate(now: now) else {
            // Nothing left that this pass hasn't already tried. Ending the pass here is
            // what reopens the transiently-failed Works: they are skipped for the
            // remainder of a pass, not for the session.
            endPass()
            return .idle
        }

        let resolved: Int?
        do {
            resolved = try await resolver.malId(for: work)
        } catch {
            // Transient: record NOTHING (ADR-0008). An outage must not suppress the Work
            // for the fourteen-day TTL.
            return fail(work.id)
        }
        guard let malId = resolved else {
            // MAL had candidates and none cleared the threshold. That is an answer, and
            // it is fingerprinted on the title count so a new synonym reopens it at once.
            memory.record(.unmatched(knownTitlesCount: work.knownTitles.count), for: work.id, now: now)
            return progress(work.id)
        }

        // Written BEFORE the fetch (ADR-0009): a transient AniList failure must not
        // rewind the Work to a resolution case. This may merge, which is intended and
        // is safe precisely because no snapshot exists yet to lose.
        works.setExternalIds(ExternalIDs(mal: malId, anilist: nil), on: work.id)

        // Resolve before you remember (ADR-0010). The line above may have merged this
        // Work away; `work(_:)` follows the alias, so `live.id` is the survivor.
        guard let live = works.work(work.id) else { return .idle }

        // The merge may have answered the question already. Fetching now would spend a
        // paced request to overwrite good data with the same data.
        guard live.snapshot == nil || live.snapshot?.isStale(now: now) == true else {
            memory.forget(live.id)
            return progress(live.id)
        }

        let api = anilist
        let result: AniListWork
        do {
            result = try await rateLimiter.run { try await api.work(malId: malId) }
        } catch AniListError.notFound {
            // The one terminal AniListError. Only the TTL reopens it — re-matching yields
            // the same id forever — and it is an answer, so it does not feed the breaker.
            memory.record(.absentFromProvider(malId: malId), for: live.id, now: now)
            return progress(live.id)
        } catch {
            return fail(live.id)
        }

        // Applied either way: the AniList id and canonical titles are worth keeping even
        // when the metadata is not.
        works.apply(result, to: live.id, now: now)

        guard result.hasContent else {
            // `apply` declined to replace the snapshot, so the Work is still provisional
            // and still unconditionally stale. Same reopen condition as a missing entry,
            // so the same outcome carries it (ADR-0010).
            memory.record(.absentFromProvider(malId: malId), for: live.id, now: now)
            return progress(live.id)
        }

        memory.forget(live.id)
        return progress(live.id)
    }

    // MARK: - Pass bookkeeping

    /// Works that failed *transiently* this pass. In memory, never persisted: attempt
    /// memory is for semantic answers, and a network blip is not an answer about a Work
    /// (ADR-0010). Cancel-on-background already gives every foregrounding a clean slate.
    private var failedThisPass: Set<WorkID> = []
    private var consecutiveFailures = 0

    private func progress(_ id: WorkID) -> DrainStep {
        consecutiveFailures = 0
        return .upgraded(id)
    }

    /// Skipping for the rest of the pass is what makes forward progress structural: every
    /// turn either upgrades a Work or shrinks the eligible list, so a pass terminates.
    private func fail(_ id: WorkID) -> DrainStep {
        failedThisPass.insert(id)
        consecutiveFailures += 1
        // Three in a row means the network, not the Work. Idle now rather than spending
        // another paced request to learn the same thing.
        guard consecutiveFailures < 3 else {
            endPass()
            return .idle
        }
        return .failed(id)
    }

    private func endPass() {
        failedThisPass.removeAll()
        consecutiveFailures = 0
    }

    // MARK: - Scanning

    /// The eligible Work that should be upgraded next, or nil when there is nothing to
    /// do. A full scan per request is deliberate (ADR-0009): it is a dictionary key copy
    /// and a filter against a 2-second request floor, and re-scanning is what lets a Work
    /// minted mid-read, or a freshly pushed weight, take effect at the next request
    /// rather than the next pass (ADR-0010).
    private func nextCandidate(now: Date) -> Work? {
        works.allWorkIds()
            .filter { !failedThisPass.contains($0) }
            .compactMap { works.work($0) }
            // Staleness AND attempt memory. The store can only ever apply the first half,
            // which is why the whole predicate lives here (ADR-0009).
            .filter { $0.snapshot == nil || $0.snapshot?.isStale(now: now) == true }
            .filter { !memory.suppresses($0, now: now) }
            .min { orders($0, before: $1) }
    }

    /// Engagement weight descending, then Works with no weight at all — which means no
    /// reading history (ADR-0009's amended tail). Ties and the whole tail break on the
    /// Work id, because `allWorkIds()` order is randomized per process and an arbitrary
    /// order still has to be a *stable* one.
    private func orders(_ lhs: Work, before rhs: Work) -> Bool {
        switch (priority[lhs.id], priority[rhs.id]) {
        case let (left?, right?):
            return left == right ? lhs.id.raw.uuidString < rhs.id.raw.uuidString : left > right
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            return lhs.id.raw.uuidString < rhs.id.raw.uuidString
        }
    }
}
