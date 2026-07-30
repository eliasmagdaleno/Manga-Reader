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

// MARK: - Strip measurement

/// The vertical reader's measurement cache: every realized strip's frame, the viewport,
/// and the position they imply.
///
/// **Deliberately not `ObservableObject`, and deliberately a reference** (ADR-0014
/// decision 8's amendment). Nothing on screen renders the live position — `pageIndicator`
/// is paged-only — so publishing it would re-evaluate the reader's body on every scroll
/// frame, with N anchor views per realized strip, to render nothing new. `@State` holds
/// the box and never reassigns it, so the reader never invalidates; the throttle and the
/// settle loop read it directly and always see the newest measurement.
///
/// If anything ever *does* need to render from this, that decision has to be reopened
/// rather than worked around.
final class StripMetrics {
    /// Realized strips only, in the reader's named coordinate space. **Replaced whole on
    /// every measurement, never merged**: frames are viewport-relative, so a frame from a
    /// derealized row is only valid at the scroll offset it was taken at, and a stale one
    /// can test as containing the viewport top (ADR-0014 decision 8, second amendment).
    var frames: [Int: StripFrame] = [:]
    var viewport: CGRect = .zero

    /// Last known good. A `nil` capture — nothing measured, overscroll, an undecoded strip,
    /// or the empty preference emitted when the vertical reader tears down — never clears
    /// it, because the mode switch and the exit record read it at exactly that moment.
    /// Only a chapter change clears it.
    var live: ReadingPosition?

    /// Raised by the settle loop for its duration. Gates the *record* path, not the
    /// measurement: the loop renders overshoots it then rejects, and overshoot is the only
    /// transient `record`'s max preserves. Set from commit 3.
    var isRestoring = false

    var lastFired: Date?
    var trailingArmed = false

    func resetForNewChapter() {
        frames = [:]
        live = nil
        lastFired = nil
        trailingArmed = false
    }
}

/// Per-row frames. `reduce` merges *siblings within one layout pass*; each pass starts from
/// `defaultValue`, which is what makes the value a snapshot of the currently realized rows
/// rather than an accumulation across passes.
private struct StripFramesKey: PreferenceKey {
    static let defaultValue: [Int: StripFrame] = [:]
    static func reduce(value: inout [Int: StripFrame], nextValue: () -> [Int: StripFrame]) {
        value.merge(nextValue()) { _, newer in newer }
    }
}

private struct StripViewportKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

/// The reader's scroll coordinate space. Frames measured in it are **viewport-relative** —
/// a strip's `minY` goes negative as it scrolls above the top edge — which is the whole
/// reason `frames` cannot be merged across passes.
private let readerScrollSpace = "webtoonReaderScroll"

// MARK: - Reader

struct ReaderView: View {
    let manga: Manga

    @StateObject private var vm: ReaderViewModel

    init(manga: Manga, chapter: Chapter, initialPosition: ReadingPosition? = nil,
         chapters: [Chapter] = []) {
        self.manga = manga
        _vm = StateObject(wrappedValue: ReaderViewModel(manga: manga, chapter: chapter,
                                                       chapters: chapters,
                                                       initialPosition: initialPosition
                                                           ?? ReadingPosition(page: 0)))
        _progressChapterID = State(initialValue: chapter.id)
    }

    @AppStorage("readingMode") private var mode: ReadingMode = .rightToLeft
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var history: HistoryStore

    @State private var currentPage = 0
    @State private var showChrome = false

    /// Held by `ReaderView` rather than by `verticalReader`, so the live position survives a
    /// reading-mode switch — which is what lets each mode resume from the other's notion of
    /// where the reader is (ADR-0014 decision 8's correction).
    @State private var metrics = StripMetrics()

    /// How often the vertical reader is allowed to hand a position to the store while
    /// scrolling. Leading edge plus one trailing fire per window (ADR-0014 decision 5).
    private let recordWindow: TimeInterval = 1

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
        // Entering a paged mode adopts the vertical reader's live position. `currentPage` is
        // otherwise assigned only in `didCompleteLoad`, so webtoon strip 5 → paged used to
        // land on the page the chapter was opened at (ADR-0014 decision 8's correction).
        .onChange(of: mode) { _, newMode in
            if newMode.isPaged, let live = metrics.live { currentPage = live.page }
        }
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
            // Strip indices overlap between chapters, so the old chapter's strip 3 would
            // otherwise answer for the new one's until the next layout pass replaced it.
            metrics.resetForNewChapter()
        }
        currentPage = vm.pagerTarget.page
        // The open-time record is what puts a chapter into History at all (`isRead` is "has
        // an entry") and what mints the Work. It has to stay: in the vertical reader,
        // opening a chapter and leaving before any measurement lands records nothing.
        recordProgress(vm.pagerTarget)
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

    /// The one door to the store. Monotonicity is the store's job now (ADR-0014 decision 3),
    /// so there is no view-side latch left — only the two things the *view* knows: that the
    /// position belongs to the chapter this view believes it is showing, and that it names a
    /// page that exists.
    private func recordProgress(_ position: ReadingPosition) {
        guard progressChapterID == vm.currentChapter.id else { return }
        guard !vm.pages.isEmpty, position.page >= 0, position.page < vm.pages.count else { return }
        history.record(manga: manga, chapter: vm.currentChapter,
                       position: position, pageCount: vm.pages.count)
    }

    // MARK: Live position (vertical mode)

    /// Called on every measurement the vertical reader reports.
    ///
    /// Two jobs, in order: keep `metrics.live` current — sticky, so a `nil` capture leaves
    /// the last known position alone — and decide whether this measurement is allowed to
    /// reach the store.
    private func measurementChanged() {
        if let position = stripPosition(frames: metrics.frames, viewport: metrics.viewport) {
            metrics.live = position
        }
        guard !metrics.isRestoring else { return }

        let now = Date()
        switch recordAction(now: now, lastFired: metrics.lastFired,
                            window: recordWindow, trailingArmed: metrics.trailingArmed) {
        case .recordNow:
            metrics.lastFired = now
            recordLivePosition()
        case .scheduleTrailing(let deadline):
            metrics.trailingArmed = true
            Task { @MainActor in
                let wait = deadline.timeIntervalSinceNow
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                metrics.trailingArmed = false
                guard !metrics.isRestoring else { return }
                metrics.lastFired = Date()
                recordLivePosition()
            }
        case .ignore:
            break
        }
    }

    /// The trailing fire deliberately outlives the view — `metrics` is a reference and
    /// `progressChapterID` reads through `@State` storage, so a tick that lands after a
    /// chapter advance is dropped by `recordProgress`'s guard rather than written against
    /// the wrong chapter (ADR-0014 decision 6).
    private func recordLivePosition() {
        guard let live = metrics.live else { return }
        recordProgress(live)
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
                recordProgress(ReadingPosition(page: newValue))
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
                    // No `onAppear` progress here any more: a row's `onAppear` fires no later
                    // than its top reaching the viewport *bottom*, so it recorded a strip the
                    // reader had not reached, and the max then made that win over the real
                    // position — resuming a full viewport ahead (ADR-0014 decision 7). In
                    // vertical mode the viewport top is the only position feed.
                    ForEach(Array(vm.pages.enumerated()), id: \.offset) { index, url in
                        WebtoonPage(url: url, index: index)
                            .id(index)
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
            .coordinateSpace(.named(readerScrollSpace))
            // The viewport, in the same space the strips report in — so its top is 0 and the
            // pure function stays general enough to test against any rectangle.
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: StripViewportKey.self,
                                           value: CGRect(origin: .zero, size: geo.size))
                }
            )
            .onPreferenceChange(StripFramesKey.self) { frames in
                metrics.frames = frames          // replaced, never merged
                measurementChanged()
            }
            .onPreferenceChange(StripViewportKey.self) { rect in
                metrics.viewport = rect
                measurementChanged()
            }
            // Covers "stop scrolling, immediately tap ✕", which the trailing fire alone
            // leaves up to a window short — a `Task`-scheduled trailing tick can outlive the
            // view, but nothing guarantees it lands before the pop. Also fires on a
            // reading-mode switch, which is the other way out of this reader.
            .onDisappear {
                guard !metrics.isRestoring else { return }
                recordLivePosition()
            }
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
                guard vm.errorMessage == nil, vm.pagerTarget.page > 0 else { return }
                // `task` starts before this view has laid out and the LazyVStack has realized
                // no rows, so `scrollTo` has nothing to aim at until a layout pass has run.
                // Guarded on a non-zero target above, so a normal chapter open never waits.
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                proxy.scrollTo(vm.pagerTarget.page, anchor: .top)
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
///
/// Also reports its own frame, which is what capture measures. The report carries whether
/// the image has decoded, because until then this is a 460pt placeholder and a fraction
/// measured against it would be *persisted* against a layout about to be replaced
/// (ADR-0014 decision 9, second amendment).
private struct WebtoonPage: View {
    let url: URL
    let index: Int

    @State private var reloadToken = 0

    var body: some View {
        CachedAsyncImage(url: url) { phase in
            strip(for: phase)
                .background(frameReporter(isDecoded: isDecoded(phase)))
        }
        .id(reloadToken)
    }

    @ViewBuilder private func strip(for phase: AsyncImagePhase) -> some View {
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

    private func isDecoded(_ phase: AsyncImagePhase) -> Bool {
        if case .success = phase { return true }
        return false
    }

    private func frameReporter(isDecoded: Bool) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: StripFramesKey.self,
                value: [index: StripFrame(rect: geo.frame(in: .named(readerScrollSpace)),
                                          isDecoded: isDecoded)]
            )
        }
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
