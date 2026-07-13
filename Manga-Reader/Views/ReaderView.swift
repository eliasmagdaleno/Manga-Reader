//
//  ReaderView.swift
//  Manga-Reader
//
//  Chapter reader with three reading modes:
//    • Left → Right  — paged, western order (swipe left to advance).
//    • Right → Left  — paged, manga order (swipe right to advance).
//    • Webtoon       — continuous vertical scroll (manhwa / long-strip).
//
//  Paged pages support pinch-to-zoom and double-tap-to-zoom. The chosen mode
//  is persisted so it carries across chapters. Page URLs come from the MangaDex
//  At-Home server via `MangaDexAPI.pageURLs(for:)`.
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
    let chapterId: String

    @AppStorage("readingMode") private var mode: ReadingMode = .leftToRight
    @Environment(\.dismiss) private var dismiss

    @State private var pages: [URL] = []
    @State private var currentPage = 0
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var showChrome = false

    var body: some View {
        ZStack {
            Ink.background.ignoresSafeArea()

            if let errorMessage {
                InkNotice(errorMessage).padding(Gutter.page)
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
        .task { await load() }
    }

    private func toggleChrome() {
        withAnimation(.snappy(duration: 0.22)) { showChrome.toggle() }
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

    /// Paged reader. RTL is achieved by mirroring the pager horizontally and
    /// un-mirroring each page, so page order stays 1…n while swipe direction flips.
    private var pagedReader: some View {
        TabView(selection: $currentPage) {
            ForEach(pages.indices, id: \.self) { index in
                ZoomablePage(url: pages[index], index: index,
                             mirrored: mode == .rightToLeft, onTap: toggleChrome)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .scaleEffect(x: mode == .rightToLeft ? -1 : 1, y: 1)
        .ignoresSafeArea()
    }

    /// Continuous vertical scroll — the webtoon / long-strip layout.
    private var verticalReader: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(pages.enumerated()), id: \.element) { index, url in
                    verticalPage(url: url, index: index)
                }
                if !pages.isEmpty && !isLoading { endMark }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: toggleChrome)
        }
        .ignoresSafeArea()
    }

    private func verticalPage(url: URL, index: Int) -> some View {
        AsyncImage(url: url) { phase in
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
                    .overlay(
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Ink.tertiary)
                    )
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
            pages = try await MangaDexAPI.pageURLs(for: chapterId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Zoomable page

/// A single paged image with pinch-to-zoom, double-tap-to-zoom, and pan while
/// zoomed. `mirrored` un-flips the page for the right-to-left pager.
private struct ZoomablePage: View {
    let url: URL
    let index: Int
    let mirrored: Bool
    let onTap: () -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let maxScale: CGFloat = 4

    var body: some View {
        let base = image
            .scaleEffect(scale)
            .offset(offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)   // un-mirror for RTL pager
            .contentShape(Rectangle())
            .gesture(magnification)
            .onTapGesture(count: 2) { toggleZoom() }
            .onTapGesture(count: 1) { onTap() }
            .onDisappear { resetZoom() }

        // Pan only when zoomed — otherwise let the TabView own the swipe.
        if scale > 1 {
            base.gesture(pan)
        } else {
            base
        }
    }

    private var image: some View {
        AsyncImage(url: url) { phase in
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
                    .overlay(
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Ink.tertiary)
                    )
            }
        }
    }

    private var magnification: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, 1), maxScale)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1 { withAnimation(.snappy(duration: 0.2)) { resetZoom() } }
            }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in lastOffset = offset }
    }

    private func toggleZoom() {
        withAnimation(.snappy(duration: 0.22)) {
            if scale > 1 {
                resetZoom()
            } else {
                scale = 2.5
                lastScale = 2.5
            }
        }
    }

    private func resetZoom() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }
}
