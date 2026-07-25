//
//  ReaderView.swift
//  Manga-Reader
//
//  Chapter reader with three reading modes:
//    • Left → Right  — paged, western order (swipe left to advance).
//    • Right → Left  — paged, manga order (swipe right to advance).
//    • Webtoon       — continuous vertical scroll (manhwa / long-strip).
//
//  Paged pages zoom through the UIScrollView-backed `ZoomableContainer`
//  (native pinch / pan physics, double-tap zooms into the tapped point). The
//  chosen mode is persisted so it carries across chapters. Page URLs come from the manga's
//  own `MangaSource` (resolved via `SourceRegistry`), which for MangaDex hits the
//  At-Home server.
//

import SwiftUI

// MARK: - Reading mode

enum ReadingMode: String, CaseIterable, Identifiable {
    case leftToRight, rightToLeft, vertical

    var id: String { rawValue }

    var label: String {
        switch self {
        case .leftToRight: return "Left to Right"
        case .rightToLeft: return "Right to Left"
        case .vertical:    return "Webtoon (Vertical)"
        }
    }

    var symbol: String {
        switch self {
        case .leftToRight: return "arrow.right"
        case .rightToLeft: return "arrow.left"
        case .vertical:    return "arrow.down"
        }
    }

    var isPaged: Bool { self != .vertical }
}

// MARK: - Reader

struct ReaderView: View {
    let manga: Manga
    let initialPage: Int
    let chapters: [Chapter]

    init(manga: Manga, chapter: Chapter, initialPage: Int = 0, chapters: [Chapter] = []) {
        self.manga = manga
        self.initialPage = initialPage
        self.chapters = chapters
        _currentChapter = State(initialValue: chapter)
        _startPageRequest = State(initialValue: .exact(initialPage))
    }

    enum StartPageRequest {
        case exact(Int)
        case last
    }

    @AppStorage("readingMode") private var mode: ReadingMode = .rightToLeft
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var history: HistoryStore

    @State private var currentChapter: Chapter
    @State private var loadedChapters: [Chapter]? = nil
    @State private var startPageRequest: StartPageRequest
    @State private var pages: [URL] = []
    @State private var currentPage = 0
    @State private var furthestPage = 0
    @State private var hasRecordedProgress = false
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var showChrome = false

    private var effectiveChapters: [Chapter] { loadedChapters ?? chapters }

    private var nextChapter: Chapter? {
        let chaps = effectiveChapters
        guard !chaps.isEmpty else { return nil }
        let sorted = chaps.sorted { (Double($0.number) ?? 0) < (Double($1.number) ?? 0) }
        guard let idx = sorted.firstIndex(where: { $0.id == currentChapter.id }) else { return nil }
        let nextIdx = idx + 1
        return sorted.indices.contains(nextIdx) ? sorted[nextIdx] : nil
    }

    private var previousChapter: Chapter? {
        let chaps = effectiveChapters
        guard !chaps.isEmpty else { return nil }
        let sorted = chaps.sorted { (Double($0.number) ?? 0) < (Double($1.number) ?? 0) }
        guard let idx = sorted.firstIndex(where: { $0.id == currentChapter.id }) else { return nil }
        let prevIdx = idx - 1
        return sorted.indices.contains(prevIdx) ? sorted[prevIdx] : nil
    }

    var body: some View {
        ZStack {
            Ink.background.ignoresSafeArea()

            if let errorMessage {
                errorState(errorMessage)
            } else if isLoading && pages.isEmpty {
                loadingState
            } else {
                content
            }
        }
        .overlay(alignment: .top) {
            if showChrome { topBar.transition(.move(edge: .top).combined(with: .opacity)) }
        }
        .overlay(alignment: .bottom) {
            if showChrome && mode.isPaged && !pages.isEmpty {
                pageIndicator.transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .statusBarHidden(!showChrome)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task { await loadAndBegin() }
    }

    private func loadAndBegin() async {
        if effectiveChapters.isEmpty {
            let src = SourceRegistry.shared.source(for: manga)
            if let fetched = try? await src.chapters(mangaId: manga.id) {
                loadedChapters = fetched
            }
        }
        
        await load()
        guard !pages.isEmpty else { return }
        
        let start: Int
        switch startPageRequest {
        case .exact(let p): start = min(max(p, 0), pages.count - 1)
        case .last: start = pages.count - 1
        }
        
        currentPage = start
        advanceProgress(to: start)
    }

    private func loadNextChapter() async {
        guard let next = nextChapter else { return }
        currentChapter = next
        pages = []
        startPageRequest = .exact(0)
        currentPage = 0
        furthestPage = 0
        hasRecordedProgress = false
        await loadAndBegin()
    }

    private func loadPreviousChapter() async {
        guard let prev = previousChapter else { return }
        currentChapter = prev
        pages = []
        startPageRequest = .last
        currentPage = 0
        furthestPage = 0
        hasRecordedProgress = false
        await loadAndBegin()
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            InkNotice(message)
            Button {
                Task { await loadAndBegin() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Ink.seal)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Ink.sealSoft))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Ink.seal, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        }
        .padding(Gutter.page)
    }

    private func toggleChrome() {
        withAnimation(.snappy(duration: 0.22)) { showChrome.toggle() }
    }

    private func advanceProgress(to index: Int) {
        guard !pages.isEmpty, index >= 0, index < pages.count else { return }
        guard index > furthestPage || !hasRecordedProgress else { return }
        furthestPage = max(furthestPage, index)
        hasRecordedProgress = true
        history.record(manga: manga, chapter: currentChapter, page: furthestPage, pageCount: pages.count)
    }

    // MARK: Content per mode

    @ViewBuilder private var content: some View {
        switch mode {
        case .vertical:
            verticalReader
        case .leftToRight, .rightToLeft:
            pagedReader
        }
    }

    private var pagedReader: some View {
        TabView(selection: $currentPage) {
            ForEach(pageOrder, id: \.self) { index in
                if index == -1, let prev = previousChapter {
                    InterstitialPage(chapter: prev, isNext: false)
                        .tag(index)
                } else if index >= 0, index < pages.count {
                    ZoomablePage(url: pages[index], index: index, currentIndex: currentPage,
                                 onTap: toggleChrome)
                        .tag(index)
                } else if index == pages.count, let next = nextChapter {
                    InterstitialPage(chapter: next, isNext: true)
                        .tag(index)
                } else {
                    Color.clear
                        .tag(index)
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        .id(mode)
        .onChange(of: currentPage) { _, newValue in
            if newValue >= 0, newValue < pages.count {
                advanceProgress(to: newValue)
            } else if newValue == pages.count + 1 {
                Task { await loadNextChapter() }
            } else if newValue == -2 {
                Task { await loadPreviousChapter() }
            }
        }
    }

    private var pageOrder: [Int] {
        let prevExtra = previousChapter != nil ? 2 : 0
        let nextExtra = nextChapter != nil ? 2 : 0
        let count = pages.count + nextExtra
        let range = -prevExtra..<count
        return mode == .rightToLeft ? Array(range.reversed()) : Array(range)
    }

    private var verticalReader: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, url in
                        WebtoonPage(url: url, index: index)
                            .id(index)
                            .onAppear { advanceProgress(to: index) }
                    }
                    if !pages.isEmpty && !isLoading {
                        if let next = nextChapter {
                            InterstitialPage(chapter: next, isNext: true)
                                .frame(height: UIScreen.main.bounds.height * 0.8)
                            
                            Color.clear.frame(height: 50)
                                .onAppear {
                                    Task { await loadNextChapter() }
                                }
                        } else {
                            endMark
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: toggleChrome)
            }
            .ignoresSafeArea()
            .onChange(of: pages.count) { _, count in
                guard count > 0, initialPage > 0 else { return }
                proxy.scrollTo(min(initialPage, count - 1), anchor: .top)
            }
        }
    }

    // MARK: Chrome

    /// Floating top bar shown only while chrome is visible: exit + mode picker.
    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                chromeIcon("xmark", tint: Ink.primary)
            }
            Spacer()
            
            VStack(spacing: 2) {
                Text("Chapter \(currentChapter.number)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Ink.primary)
                if let title = currentChapter.title, !title.isEmpty {
                    Text(title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            Menu {
                Picker("Reading Mode", selection: $mode) {
                    ForEach(ReadingMode.allCases) { m in
                        Label(m.label, systemImage: m.symbol).tag(m)
                    }
                }
            } label: {
                chromeIcon("book.pages", tint: Ink.seal)
            }
        }
        .padding(.horizontal, Gutter.page)
        .padding(.top, 8)
    }

    private func chromeIcon(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 40, height: 40)
            .background(Circle().fill(Ink.surface.opacity(0.92)))
            .overlay(Circle().strokeBorder(Ink.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }

    private var pageIndicator: some View {
        Text("\(min(max(currentPage + 1, 1), pages.count)) · \(pages.count)")
            .font(.inkMono(12, weight: .semibold))
            .tracking(1)
            .foregroundStyle(Ink.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Ink.surface.opacity(0.9)))
            .overlay(Capsule().strokeBorder(Ink.hairline, lineWidth: 1))
            .padding(.bottom, 12)
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView().tint(Ink.seal)
            Text("Fetching pages")
                .font(.inkMono(11, weight: .medium))
                .tracking(1)
                .foregroundStyle(Ink.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // A quiet end-of-chapter marker: a seal tick and a monospaced label.
    private var endMark: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Ink.seal)
                .frame(width: 28, height: 4)
            Text("END · \(pages.count) PAGES")
                .font(.inkMono(11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Ink.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let src = SourceRegistry.shared.source(for: manga)
            pages = try await src.pageURLs(chapterId: currentChapter.id, preferDataSaver: true)
            ImageCache.shared.prefetch(pages, maxConcurrent: src.imagePrefetchConcurrency)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Zoomable page

/// A single paged image hosted inside a `ZoomableContainer`, which supplies
/// native UIScrollView pinch / pan / double-tap-to-point zoom. This view owns
/// the page content phases (image, screentone placeholder, retry) and the
/// reload token; the container resets zoom when `index` stops matching the
/// pager's `currentIndex`.
private struct ZoomablePage: View {
    let url: URL
    let index: Int
    let currentIndex: Int
    let onTap: () -> Void

    @State private var reloadToken = 0

    var body: some View {
        ZoomableContainer(
            isActive: index == currentIndex,
            contentID: "\(url.absoluteString)-\(reloadToken)",
            onSingleTap: onTap
        ) {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFit()
                case .empty:
                    Screentone()
                        .overlay(
                            Text(String(format: "%03d", index + 1))
                                .font(.inkMono(13, weight: .semibold))
                                .foregroundStyle(Ink.tertiary)
                        )
                default:
                    Screentone(opacity: 0.5)
                        .overlay(PageRetry { reloadToken += 1 })
                }
            }
            .id(reloadToken)
        }
    }
}

// MARK: - Webtoon page

/// A single page in the continuous vertical reader. Owns its own reload token
/// so a failed page can be retried independently of the rest of the strip.
private struct WebtoonPage: View {
    let url: URL
    let index: Int

    @State private var reloadToken = 0

    var body: some View {
        CachedAsyncImage(url: url) { phase in
            switch phase {
            case .success(let img):
                img.resizable().scaledToFit().frame(maxWidth: .infinity)
            case .empty:
                Screentone()
                    .frame(height: 460)
                    .overlay(
                        Text(String(format: "%03d", index + 1))
                            .font(.inkMono(13, weight: .semibold))
                            .foregroundStyle(Ink.tertiary)
                    )
            default:
                Screentone(opacity: 0.5)
                    .frame(height: 460)
                    .overlay(PageRetry { reloadToken += 1 })
            }
        }
        .id(reloadToken)
    }
}

// MARK: - Retry affordance

/// Tappable failure placeholder for a page that couldn't load. A `Button` so its
/// tap wins over the reader's chrome-toggle tap gesture.
private struct PageRetry: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 22, weight: .semibold))
                Text("RETRY")
                    .font(.inkMono(11, weight: .semibold))
                    .tracking(1.5)
            }
            .foregroundStyle(Ink.secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Interstitial Page

private struct InterstitialPage: View {
    let chapter: Chapter
    let isNext: Bool

    var body: some View {
        VStack(spacing: 24) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Ink.seal)
                .frame(width: 32, height: 4)

            VStack(spacing: 8) {
                Text(isNext ? "NEXT CHAPTER" : "PREVIOUS CHAPTER")
                    .font(.inkMono(12, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Ink.tertiary)

                Text("Chapter \(chapter.number)")
                    .font(.inkDisplay(32))
                    .foregroundStyle(Ink.primary)

                if let title = chapter.title, !title.isEmpty {
                    Text(title)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Ink.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.background)
    }
}
