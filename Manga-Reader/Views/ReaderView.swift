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
    let chapter: Chapter
    let initialPage: Int

    init(manga: Manga, chapter: Chapter, initialPage: Int = 0) {
        self.manga = manga
        self.chapter = chapter
        self.initialPage = initialPage
    }

    @AppStorage("readingMode") private var mode: ReadingMode = .rightToLeft
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var history: HistoryStore

    @State private var pages: [URL] = []
    @State private var currentPage = 0
    @State private var furthestPage = 0
    @State private var hasRecordedProgress = false
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var showChrome = false

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

    /// Fetch the chapter's pages and, on success, seed reading progress. Also
    /// invoked by the retry button after a failed load.
    private func loadAndBegin() async {
        await load()
        guard !pages.isEmpty else { return }   // load failed → don't record progress
        let start = min(max(initialPage, 0), pages.count - 1)
        currentPage = start
        advanceProgress(to: start)
    }

    /// Whole-chapter failure (the page list couldn't be fetched): notice + retry.
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
        guard !pages.isEmpty else { return }
        // Only persist when reaching a new furthest page (or on the first record).
        guard index > furthestPage || !hasRecordedProgress else { return }
        furthestPage = max(furthestPage, index)
        hasRecordedProgress = true
        history.record(manga: manga, chapter: chapter, page: furthestPage, pageCount: pages.count)
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

    /// Paged reader. RTL is achieved by laying pages out in reversed order —
    /// page i+1 sits to the LEFT of page i, so the story advances with a
    /// rightward swipe — while every page (including its embedded UIScrollView
    /// zoom layer) stays in a plain, un-mirrored coordinate space. The old
    /// mirror-the-pager `scaleEffect(x: -1)` approach inverted horizontal pan
    /// translations for gestures inside the page.
    private var pagedReader: some View {
        TabView(selection: $currentPage) {
            ForEach(pageOrder, id: \.self) { index in
                ZoomablePage(url: pages[index], index: index, currentIndex: currentPage,
                             onTap: toggleChrome)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        // Rebuild the pager when the direction flips — reordering live pages
        // inside a paged TabView is glitch-prone. Selection is restored from
        // `currentPage` (tags are logical page indices in both orders).
        .id(mode)
        .onChange(of: currentPage) { _, newValue in advanceProgress(to: newValue) }
    }

    /// Layout order of the page indices: natural for LTR, reversed for RTL.
    private var pageOrder: [Int] {
        mode == .rightToLeft ? Array(pages.indices.reversed()) : Array(pages.indices)
    }

    /// Continuous vertical scroll — the webtoon / long-strip layout.
    private var verticalReader: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, url in
                        WebtoonPage(url: url, index: index)
                            .id(index)
                            .onAppear { advanceProgress(to: index) }
                    }
                    if !pages.isEmpty && !isLoading { endMark }
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
        Text("\(min(currentPage + 1, pages.count)) · \(pages.count)")
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
            pages = try await SourceRegistry.shared.source(for: manga)
                .pageURLs(chapterId: chapter.id, preferDataSaver: true)
            ImageCache.shared.prefetch(pages)   // warm the whole chapter for instant scrolling
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
        ZoomableContainer(isActive: index == currentIndex, onSingleTap: onTap) {
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
