//
//  ReaderView.swift
//  Manga-Reader
//
//  Vertically-scrolling chapter reader. Loads page image URLs from the MangaDex
//  At-Home server and renders them top-to-bottom on an ink surface.
//

import SwiftUI

struct ReaderView: View {
    let chapterId: String

    @State private var pages: [URL] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if isLoading {
                    loadingState
                }
                if let errorMessage {
                    InkNotice(errorMessage)
                        .padding(Gutter.page)
                }
                ForEach(Array(pages.enumerated()), id: \.element) { index, url in
                    pageView(url: url, index: index)
                }

                if !pages.isEmpty && !isLoading {
                    endMark
                }
            }
        }
        .background(Ink.background)
        .navigationTitle("Reader")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func pageView(url: URL, index: Int) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let img):
                img.resizable().scaledToFit().frame(maxWidth: .infinity)
            case .empty:
                Screentone()
                    .frame(height: 460)
                    .overlay(
                        // Monospaced page counter while the page loads.
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
