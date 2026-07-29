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

    /// Where the pager should open once pages arrive.
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
    @Published private(set) var landingPage = 0

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

    private func advance(to chapter: Chapter, landing: Landing) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // Nothing is mutated until this returns. A failure below therefore leaves the
            // chapter being read exactly as it was, and surfaces as a banner over it
            // rather than replacing it with an error screen.
            let fetched = try await fetchPages(for: chapter)

            currentChapter = chapter
            pages = fetched
            landingPage = Self.landingIndex(landing, pageCount: fetched.count)
            prefetch(fetched, source.imagePrefetchConcurrency)
        } catch {
            errorMessage = error.localizedDescription
            failureIsTransient = isTransientFailure(error)
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
}
