//
//  ReaderView.swift
//  Manga-Reader
//
//  Chapter reader with three reading modes:
//    • Left → Right  — paged, western order (swipe left to advance).
//    • Right → Left  — paged, manga order (swipe right to advance).
//    • Webtoon       — continuous vertical scroll (manhwa / long-strip).
//
//  Paged pages zoom through the UIScrollView-backed `ZoomableContainer` (native pinch /
//  pan physics, double-tap zooms into the tapped point). The chosen mode is persisted so
//  it carries across chapters.
//
//  Everything the reader *fetches* lives in `ReaderViewModel`; this view owns only UI
//  state — the chrome toggle, the pager index, the reading mode, and progress recording.
//  It renders `vm.presentation` rather than branching on loading/error itself, because the
//  bug that split those apart was two branches disagreeing about whether the user could
//  leave. See ADR-0012, and ADR-0013 for the wiring decisions below.
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

    @StateObject private var vm: ReaderViewModel

    init(manga: Manga, chapter: Chapter, initialPage: Int = 0, chapters: [Chapter] = []) {
        self.manga = manga
        _vm = StateObject(wrappedValue: ReaderViewModel(manga: manga, chapter: chapter,
                                                       chapters: chapters,
                                                       initialPage: initialPage))
        _progressChapterID = State(initialValue: chapter.id)
    }

    @AppStorage("readingMode") private var mode: ReadingMode = .rightToLeft
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var history: HistoryStore

    @State private var currentPage = 0
    @State private var furthestPage = 0
    @State private var hasRecordedProgress = false
    @State private var showChrome = false

    /// The chapter the progress counters above belong to. The view model commits a chapter
    /// change only on success, so a mismatch here is a reliable "we really moved".
    @State private var progressChapterID: String

    /// Which failure the user has already seen. Compared against the view model's completion
    /// marker rather than the message text, so an identical error twice in a row still shows
    /// twice. Dismissal is UI state; the model is never mutated to hide a banner (ADR-0013).
    @State private var acknowledgedRequest: Int?

    /// `showChrome` is the user's own toggle; a screen with nothing to read forces the bar
    /// visible regardless, because the only dismiss control lives in it. Derived, never
    /// assigned — see ADR-0012.
    private var chromeVisible: Bool { showChrome || vm.presentation.chromeForced }

    private var visibleBanner: String? {
        guard acknowledgedRequest != vm.lastCompletedRequest else { return nil }
        return vm.presentation.banner
    }

    var body: some View {
        ZStack {
            Ink.background.ignoresSafeArea()

            switch vm.presentation.body {
            case .error(let message, let canRetry):
                errorState(message, canRetry: canRetry)
            case .loading:
                loadingState
            case .content:
                content
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 10) {
                if chromeVisible {
                    topBar.transition(.move(edge: .top).combined(with: .opacity))
                }
                if let message = visibleBanner {
                    banner(message).transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .overlay(alignment: .bottom) {
            if chromeVisible && mode.isPaged && !vm.pages.isEmpty {
                pageIndicator.transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .statusBarHidden(!chromeVisible)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task { await vm.begin() }
        .onChange(of: vm.lastCompletedRequest) { _, _ in didCompleteLoad() }
    }

    /// Everything the view does after a load finishes, in one place and one order.
    ///
    /// The order is the point (ADR-0013): three separate `onChange` observers would leave
    /// `advanceProgress` racing the counter reset, and if it lost, page 0 of a new chapter
    /// would go unrecorded until the reader swiped. SwiftUI's observer ordering is not a
    /// documented guarantee, so this does not depend on it.
    private func didCompleteLoad() {
        if vm.currentChapter.id != progressChapterID {
            progressChapterID = vm.currentChapter.id
            furthestPage = 0
            hasRecordedProgress = false
        }
        currentPage = vm.pagerTarget
        advanceProgress(to: vm.pagerTarget)
    }

    private func errorState(_ message: String, canRetry: Bool) -> some View {
        VStack(spacing: 16) {
            InkNotice(message)

            // Retry appears only when retrying could work. The way *out* is the ✕ in the top
            // bar, which `chromeForced` guarantees is on screen whenever this state renders.
            if canRetry {
                Button {
                    Task { await vm.retry() }
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
        }
        .padding(Gutter.page)
    }

    /// Auto-dismisses as well as being tappable: requiring a tap to clear an error the user
    /// did not cause is poor manners, and swiping into the dead chapter again brings it back.
    private func banner(_ message: String) -> some View {
        ReaderBanner(message) { acknowledgeBanner() }
            .task(id: vm.lastCompletedRequest) {
                try? await Task.sleep(for: .seconds(5))
                acknowledgeBanner()
            }
    }

    private func acknowledgeBanner() {
        withAnimation(.snappy(duration: 0.22)) { acknowledgedRequest = vm.lastCompletedRequest }
    }

    private func toggleChrome() {
        withAnimation(.snappy(duration: 0.22)) { showChrome.toggle() }
    }

    private func advanceProgress(to index: Int) {
        guard !vm.pages.isEmpty, index >= 0, index < vm.pages.count else { return }
        guard index > furthestPage || !hasRecordedProgress else { return }
        furthestPage = max(furthestPage, index)
        hasRecordedProgress = true
        history.record(manga: manga, chapter: vm.currentChapter,
                       page: furthestPage, pageCount: vm.pages.count)
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
                if index == -1, let prev = vm.previousChapter {
                    InterstitialPage(chapter: prev, isNext: false)
                        .tag(index)
                } else if index >= 0, index < vm.pages.count {
                    ZoomablePage(url: vm.pages[index], index: index, currentIndex: currentPage,
                                 onTap: toggleChrome)
                        .tag(index)
                } else if index == vm.pages.count, let next = vm.nextChapter {
                    InterstitialPage(chapter: next, isNext: true)
                        .tag(index)
                } else {
                    advanceTriggerPage(at: index)
                        .tag(index)
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        .id(mode)
        .onChange(of: currentPage) { _, newValue in
            if newValue >= 0, newValue < vm.pages.count {
                advanceProgress(to: newValue)
            } else if newValue == vm.pages.count + 1 {
                Task { await vm.loadNext() }
            } else if newValue == -2 {
                Task { await vm.loadPrevious() }
            }
        }
    }

    /// The page whose only job is to *request* the adjacent chapter, and therefore the right
    /// place to report on it.
    ///
    /// `pageOrder`'s extras are 0 or 2, so this branch is reached by exactly two indices —
    /// `-2` and `pages.count + 1`, the two the pager treats as advance triggers. It used to
    /// render `Color.clear`, which was invisible only because clearing `pages` first tore the
    /// pager down and showed the full-screen spinner instead. Load-then-commit keeps the pager
    /// up, so without this the user swipes onto a blank screen for the whole fetch (ADR-0013).
    @ViewBuilder private func advanceTriggerPage(at index: Int) -> some View {
        if let chapter = index < 0 ? vm.previousChapter : vm.nextChapter {
            InterstitialPage(chapter: chapter, isNext: index > 0, isLoading: vm.isLoading)
        } else {
            Color.clear
        }
    }

    private var pageOrder: [Int] {
        let prevExtra = vm.previousChapter != nil ? 2 : 0
        let nextExtra = vm.nextChapter != nil ? 2 : 0
        let count = vm.pages.count + nextExtra
        let range = -prevExtra..<count
        return mode == .rightToLeft ? Array(range.reversed()) : Array(range)
    }

    private var verticalReader: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(vm.pages.enumerated()), id: \.offset) { index, url in
                        WebtoonPage(url: url, index: index)
                            .id(index)
                            .onAppear { advanceProgress(to: index) }
                    }
                    if !vm.pages.isEmpty && !vm.isLoading {
                        if let next = vm.nextChapter {
                            InterstitialPage(chapter: next, isNext: true)
                                .frame(height: UIScreen.main.bounds.height * 0.8)

                            Color.clear.frame(height: 50)
                                .onAppear {
                                    Task { await vm.loadNext() }
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
            // Restores position on a *commit* only. A failed advance leaves the reader at the
            // bottom of a chapter that is still fully rendered — a legitimate place to be —
            // so unlike the pager, nothing retreats here.
            //
            // `task(id:)` rather than `onChange(of:)`, because this view is mounted *late*: on
            // the first open the body is `.loading` while pages are empty, so the vertical
            // reader does not exist yet when the load completes and bumps the marker. An
            // observer would never see that change and resume silently did nothing — the whole
            // time, since the observer this replaced had the same flaw. `task(id:)` runs on
            // appearance as well as on change, which is exactly the difference. Chapter
            // advances were unaffected either way: `pages` stays populated across a commit, so
            // the reader stays mounted.
            .task(id: vm.lastCompletedRequest) {
                guard vm.errorMessage == nil, vm.pagerTarget > 0 else { return }
                // `task` starts before this view has laid out and the LazyVStack has realized
                // no rows, so `scrollTo` has nothing to aim at until a layout pass has run.
                // Guarded on a non-zero target above, so a normal chapter open never waits.
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                proxy.scrollTo(vm.pagerTarget, anchor: .top)
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
                Text("Chapter \(vm.currentChapter.number)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Ink.primary)
                if let title = vm.currentChapter.title, !title.isEmpty {
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
        Text("\(min(max(currentPage + 1, 1), vm.pages.count)) · \(vm.pages.count)")
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
            Text("END · \(vm.pages.count) PAGES")
                .font(.inkMono(11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Ink.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
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

/// The card between two chapters. Also stands in for the advance trigger page, where it
/// carries a spinner: that index is what requested the chapter being loaded (ADR-0013).
private struct InterstitialPage: View {
    let chapter: Chapter
    let isNext: Bool
    var isLoading: Bool = false

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

            if isLoading {
                VStack(spacing: 8) {
                    ProgressView().tint(Ink.seal)
                    Text("FETCHING PAGES")
                        .font(.inkMono(10, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(Ink.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.background)
    }
}
