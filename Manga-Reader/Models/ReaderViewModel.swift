//
//  ReaderViewModel.swift
//  Manga-Reader
//
//  ADR-0012. Owns everything the reader fetches; the view keeps only UI state
//  (chrome toggle, pager index, reading mode, progress recording).
//
//  `advance` is load-then-commit: it fetches into a local and assigns nothing until
//  the pages are in hand. The reader previously moved first and loaded second, so a
//  single unreadable chapter mid-series destroyed the chapter being read and left the
//  user with no action but to leave. See ADR-0012.
//

import Foundation

/// Failures the reader itself decides, as opposed to ones a source reports.
enum ReaderError: LocalizedError, ClassifiedFailure {
    /// The fetch succeeded and returned nothing readable.
    case noPages

    var errorDescription: String? {
        "This chapter has no pages to read."
    }

    /// Permanent: an empty chapter does not fill in on a second look.
    var isTransient: Bool { false }
}

@MainActor
final class ReaderViewModel: ObservableObject {

    /// Which end of a chapter a load is heading for. Doubles as the record of *which way the
    /// user was travelling*, which is what both the retreat target and the banner's wording
    /// are derived from on failure (ADR-0013).
    enum Landing: Equatable {
        case exact(Int)
        case first
        case last
    }

    @Published private(set) var currentChapter: Chapter
    @Published private(set) var chapters: [Chapter]
    @Published private(set) var pages: [URL] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var failureIsTransient = true
    @Published private(set) var isLoading = false

    /// Where the pager belongs **now**, whether or not the last load committed. On success
    /// it is the page the chapter opens at; on a failed advance it retreats into the chapter
    /// that survived, since the pager is otherwise stranded on the sentinel index that
    /// requested the missing one. See ADR-0013.
    @Published private(set) var pagerTarget = 0

    /// The generation of the most recent load to *finish* and still be current. The view
    /// repositions the pager when this changes.
    ///
    /// It cannot watch `pagerTarget` instead: `loadNext` targets page 0, so advancing from a
    /// chapter opened at page 0 gives `0 → 0`, no `onChange` fires, and the pager stays on the
    /// stale sentinel index — which immediately re-requests the next chapter. The common case
    /// is the broken one, so position needs an *event*, not a value.
    @Published private(set) var lastCompletedRequest = 0

    /// Bumped when a load is *issued*. `lastCompletedRequest` records which issued generation
    /// last completed, so the two can never disagree about what was asked for.
    private var requestGeneration = 0

    private let manga: Manga
    private let source: MangaSource
    private let initialPage: Int
    /// Injected so tests never reach the network. Production passes the real cache.
    private let prefetch: ([URL], Int) -> Void

    init(manga: Manga, chapter: Chapter, chapters: [Chapter], initialPage: Int,
         source: MangaSource? = nil,
         prefetch: (([URL], Int) -> Void)? = nil) {
        self.manga = manga
        self.currentChapter = chapter
        self.chapters = chapters
        self.initialPage = initialPage
        self.source = source ?? SourceRegistry.shared.source(for: manga)
        self.prefetch = prefetch ?? { urls, width in
            ImageCache.shared.prefetch(urls, maxConcurrent: width)
        }
    }

    /// The whole state → screen decision, in one place. See `ReaderPresentation`.
    var presentation: ReaderPresentation {
        ReaderPresentation(errorMessage: errorMessage,
                           isTransient: failureIsTransient,
                           isLoading: isLoading,
                           pageCount: pages.count)
    }

    // MARK: - Chapter neighbours

    private var sortedChapters: [Chapter] {
        chapters.sorted { (Double($0.number) ?? 0) < (Double($1.number) ?? 0) }
    }

    var nextChapter: Chapter? { neighbour(offset: 1) }
    var previousChapter: Chapter? { neighbour(offset: -1) }

    private func neighbour(offset: Int) -> Chapter? {
        let sorted = sortedChapters
        guard let idx = sorted.firstIndex(where: { $0.id == currentChapter.id }) else { return nil }
        let target = idx + offset
        return sorted.indices.contains(target) ? sorted[target] : nil
    }

    // MARK: - Loading

    /// First load for this reader session: fill the chapter list if the caller had none,
    /// then open the requested chapter at the requested page.
    func begin() async {
        if chapters.isEmpty {
            chapters = (try? await source.chapters(mangaId: manga.id)) ?? []
        }
        await advance(to: currentChapter, landing: .exact(initialPage))
    }

    func retry() async {
        await advance(to: currentChapter, landing: .exact(initialPage))
    }

    func loadNext() async {
        guard let next = nextChapter else { return }
        await advance(to: next, landing: .first)
    }

    func loadPrevious() async {
        guard let previous = previousChapter else { return }
        await advance(to: previous, landing: .last)
    }

    /// One load, start to finish. Two rules run through it (ADR-0013):
    ///
    /// **Load then commit.** Nothing is assigned until the pages are in hand, so a failure
    /// leaves the chapter being read exactly as it was.
    ///
    /// **The newest request wins.** The pager stays on screen for the whole fetch now, so the
    /// user can swipe again mid-load and start a second `advance`. Whichever was issued last
    /// is the one the user wants; an older one that returns afterwards must commit nothing,
    /// report nothing, and touch neither the loading flag nor the completion marker.
    private func advance(to chapter: Chapter, landing: Landing) async {
        requestGeneration += 1
        let mine = requestGeneration
        let isCurrent = { [weak self] in mine == self?.requestGeneration }

        isLoading = true
        errorMessage = nil
        defer {
            if isCurrent() {
                isLoading = false
                // Set last, so the view sees the finished state when it reacts to this.
                lastCompletedRequest = mine
            }
        }

        do {
            let fetched = try await fetchPages(for: chapter)
            guard isCurrent() else { return }

            currentChapter = chapter
            pages = fetched
            pagerTarget = Self.landingIndex(landing, pageCount: fetched.count)
            prefetch(fetched, source.imagePrefetchConcurrency)
        } catch {
            guard isCurrent() else { return }

            errorMessage = Self.failureMessage(error, landing: landing)
            failureIsTransient = isTransientFailure(error)
            // The pager is sitting on the sentinel index that asked for the chapter that
            // isn't there. Retreat into the one that survived.
            if let retreat = Self.retreatIndex(landing, pageCount: pages.count) {
                pagerTarget = retreat
            }
        }
    }

    /// A fetch that returned nothing is a failure, not an empty success — both sources
    /// `compactMap` their page lists and can hand back `[]` without throwing.
    private func fetchPages(for chapter: Chapter) async throws -> [URL] {
        let urls = try await source.pageURLs(chapterId: chapter.id, preferDataSaver: true)
        guard !urls.isEmpty else { throw ReaderError.noPages }
        return urls
    }

    private static func landingIndex(_ landing: Landing, pageCount: Int) -> Int {
        guard pageCount > 0 else { return 0 }
        switch landing {
        case .exact(let page): return min(max(page, 0), pageCount - 1)
        case .first:           return 0
        case .last:            return pageCount - 1
        }
    }

    /// Where the pager retreats to when an advance fails, derived from the direction the user
    /// was travelling. `nil` for `.exact` — an initial load or a retry has nothing to retreat
    /// into, and its failure renders full-screen anyway.
    private static func retreatIndex(_ landing: Landing, pageCount: Int) -> Int? {
        switch landing {
        case .first: return max(pageCount - 1, 0)   // came forward; go back to where they were
        case .last:  return 0                       // came backward; the near end of the chapter
        case .exact: return nil
        }
    }

    /// The banner needs a subject. Bare `localizedDescription` is fine on a full-screen error
    /// and useless over content: the user swipes forward, is snapped back to the page they were
    /// on, and reads a sentence that never says the swipe is why. `.exact` renders full-screen,
    /// where the subject is unambiguous, so it carries no prefix.
    private static func failureMessage(_ error: Error, landing: Landing) -> String {
        let reason = readerFailureMessage(error)
        switch landing {
        case .first: return "Couldn't load the next chapter. \(reason)"
        case .last:  return "Couldn't load the previous chapter. \(reason)"
        case .exact: return reason
        }
    }
}
