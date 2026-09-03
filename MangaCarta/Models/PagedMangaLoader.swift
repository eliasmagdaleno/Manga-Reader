//
//  PagedMangaLoader.swift
//  MangaCarta
//
//  A reusable infinite-scroll pager over any `(limit, offset) -> [Manga]` fetch —
//  the state machine behind Search results and genre browsing. Follows
//  `HomeViewModel`'s conventions: superseded loads are cancelled, stale tasks
//  never write, and cancellation is not surfaced as an error.
//

import Foundation

@MainActor
final class PagedMangaLoader: ObservableObject {
    @Published private(set) var items: [Manga] = []
    /// First-page fetch in flight (grid empty or being replaced).
    @Published private(set) var isLoading = false
    /// Follow-up page fetch in flight (append at the bottom).
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false
    @Published var errorMessage: String? = nil

    let pageSize: Int

    private var offset = 0
    /// IDs already in `items`. Sources whose ordering shifts between requests
    /// (popularity-ordered feeds, for instance) can repeat entries across pages;
    /// duplicate `Identifiable` ids would break `ForEach`.
    private var seenIDs: Set<String> = []
    private var fetchPage: ((_ limit: Int, _ offset: Int) async throws -> [Manga])?
    private var loadTask: Task<Void, Never>?
    /// Bumped by every `load`/`reset`; a fetch may only write while its
    /// generation is still current.
    private var generation = 0

    init(pageSize: Int = 24) {
        self.pageSize = pageSize
    }

    /// Replace the feed: cancel any in-flight fetch, clear state, load page one.
    func load(fetch: @escaping (_ limit: Int, _ offset: Int) async throws -> [Manga]) {
        generation += 1
        let gen = generation
        loadTask?.cancel()
        fetchPage = fetch
        items = []
        seenIDs = []
        offset = 0
        hasMore = false
        errorMessage = nil
        isLoading = true
        isLoadingMore = false
        loadTask = Task { await fetchNext(gen: gen) }
    }

    /// Append the next page when `item` is near the tail of the grid
    /// (within the last three rows of a 3-up grid).
    func loadMoreIfNeeded(current item: Manga) {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        guard items.suffix(9).contains(where: { $0.id == item.id }) else { return }
        let gen = generation
        isLoadingMore = true
        loadTask = Task { await fetchNext(gen: gen) }
    }

    /// Re-attempt the page that just failed, resuming at the current `offset` rather
    /// than restarting the feed — so a transient error mid-scroll doesn't discard
    /// everything already loaded. Deliberately does NOT bump `generation`.
    func retry() {
        guard fetchPage != nil, !isLoading, !isLoadingMore else { return }
        errorMessage = nil
        if items.isEmpty { isLoading = true } else { isLoadingMore = true }
        let gen = generation
        loadTask = Task { await fetchNext(gen: gen) }
    }

    /// Clear everything (e.g. the search query became empty).
    func reset() {
        generation += 1
        loadTask?.cancel()
        fetchPage = nil
        items = []
        seenIDs = []
        offset = 0
        hasMore = false
        errorMessage = nil
        isLoading = false
        isLoadingMore = false
    }

    private func fetchNext(gen: Int) async {
        guard let fetch = fetchPage else { return }
        do {
            let page = try await fetch(pageSize, offset)
            guard gen == generation, !Task.isCancelled else { return }
            let fresh = page.filter { seenIDs.insert($0.id).inserted }
            items.append(contentsOf: fresh)
            // Always step by pageSize, never by the returned count: some sources
            // convert offset→page as `offset / limit + 1`, and only constant
            // steps land on consecutive pages.
            offset += pageSize
            // Only a genuinely empty page ends the feed. A SHORT page must not:
            // latest-updates pages in chapter space and dedupes chapters→manga, so
            // a full upstream page routinely arrives here well under `pageSize`.
            // Costs one empty request at true end-of-feed — cheaper than silently
            // truncating a feed that still had results.
            hasMore = !page.isEmpty && !fresh.isEmpty
        } catch is CancellationError {
            return
        } catch {
            guard gen == generation, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        if gen == generation {
            isLoading = false
            isLoadingMore = false
        }
    }
}
