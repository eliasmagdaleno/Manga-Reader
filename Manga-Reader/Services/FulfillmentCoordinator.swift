//
//  FulfillmentCoordinator.swift
//  Manga-Reader
//
//  ADR-0004's "optimistic render, then reconcile". Counting a Work's Listings means
//  asking every candidate source for a chapter list — N round-trips where the
//  slowest source (a Cloudflare/WebView fetch) sets the wait. Neither pure strategy
//  is acceptable: eager background counting burns network, battery and rate limit on
//  works the user never opens; lazy counting puts a spinner in front of every detail
//  page.
//
//  So: choose from cached counts and render at once, then refresh in the background
//  and update the picker if a better Listing appears. **First paint never blocks on
//  N sources.**
//

import Foundation

@MainActor
final class FulfillmentCoordinator: ObservableObject {

    private let works: WorkStore
    private let registry: SourceRegistry
    private let counts: ListingCountCache
    private let preferences: SourcePreferenceStore

    init(works: WorkStore,
         registry: SourceRegistry,
         counts: ListingCountCache,
         preferences: SourcePreferenceStore) {
        self.works = works
        self.registry = registry
        self.counts = counts
        self.preferences = preferences
    }

    /// The Listing to open: the reader's pick for this Work when they made one, and
    /// the top of the ranking otherwise.
    ///
    /// A pick whose source is no longer registered — extension removed, adult gating
    /// switched off — falls back to the ranking rather than stranding the Work on a
    /// dead end. The pin is deliberately **left in place**: the source may come back,
    /// and silently discarding a stated preference because something was temporarily
    /// unavailable is how an app loses a user's settings.
    func chosenListing(for workID: WorkID, now: Date = Date()) -> ListingKey? {
        let ranked = candidates(for: workID, now: now)
        if let pinned = preferences.choice(for: workID),
           ranked.contains(where: { $0.key == pinned }) {
            return pinned
        }
        return ranked.first?.key
    }

    /// A Work's Listings, best first. **Cache-only and synchronous** — this is the
    /// call the detail page paints from, so it must never touch the network.
    ///
    /// Listings whose source is no longer registered are dropped: an unregistered
    /// source cannot fulfill anything, and offering it would be offering a dead end.
    func candidates(for workID: WorkID, now: Date = Date()) -> [ListingCandidate] {
        guard let work = works.work(workID) else { return [] }

        let candidates = work.listings.compactMap { key -> ListingCandidate? in
            guard let index = registry.sources.firstIndex(where: { $0.id == key.sourceId })
            else { return nil }
            return ListingCandidate(key: key,
                                    chapterCount: counts.count(for: key, now: now),
                                    registrationIndex: index)
        }

        return FulfillmentRouter.rank(candidates,
                                      referenceTotal: referenceTotal(for: work),
                                      preferredSourceId: preferences.primarySourceId)
    }

    /// Counts every Listing the cache has no current answer for, and records what
    /// comes back. The background half of the optimistic render.
    ///
    /// Listings already counted inside the TTL are skipped without a request — the
    /// whole reason the cache exists. Sources are asked **concurrently**, because
    /// the wait is otherwise the sum of N sources rather than the slowest one.
    ///
    /// A source that throws stays *uncounted* rather than being recorded as zero.
    /// A timeout, a Cloudflare challenge and a site redesign all look like this, and
    /// none of them is evidence that a Listing has no chapters — recording a zero
    /// would bury that source in the ranking for a full TTL on the strength of an
    /// outage.
    func reconcile(_ workID: WorkID, now: Date = Date()) async {
        guard let work = works.work(workID) else { return }

        let uncounted = work.listings.filter { counts.count(for: $0, now: now) == nil }
        guard !uncounted.isEmpty else { return }

        // Resolved on the main actor before the group starts, the same way
        // `LibraryStore.refresh` does it — the tasks capture a source, not the
        // registry.
        let pending: [(key: ListingKey, source: MangaSource)] = uncounted.compactMap { key in
            registry.source(id: key.sourceId).map { (key, $0) }
        }

        let counted: [(ListingKey, Int)] = await withTaskGroup(
            of: (ListingKey, Int)?.self
        ) { group in
            for (key, source) in pending {
                group.addTask {
                    guard let chapters = try? await source.chapters(mangaId: key.mangaId)
                    else { return nil }
                    return (key, FulfillmentRouter.distinctChapterCount(chapters))
                }
            }

            var out: [(ListingKey, Int)] = []
            while let result = await group.next() {
                if let result { out.append(result) }
            }
            return out
        }

        for (key, count) in counted {
            counts.record(count, for: key, now: now)
        }
        objectWillChange.send()
    }

    /// The provider's chapter total, and only when it is real. Providers report a
    /// total once a series has *finished*; an ongoing series reports `nil`, which is
    /// exactly the case where sources diverge on how current they are (ADR-0004
    /// verified this live — One Piece is `RELEASING` with `chapters: null`).
    private func referenceTotal(for work: Work) -> Int? {
        guard let snapshot = work.snapshot,
              snapshot.publicationStatus == .finished else { return nil }
        return snapshot.chapterTotal
    }
}
