//
//  ReaderView.swift
//  Manga-Reader
//
//  Created by Elias Magdaleno on 11/13/25.
//

import SwiftUI

/// Vertically-scrolling chapter reader. Loads page image URLs from the MangaDex
/// At-Home server for the given chapter and renders them top-to-bottom.
struct ReaderView: View {
    let chapterId: String

    @State private var pages: [URL] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                if let errorMessage {
                    Text("Error: \(errorMessage)")
                        .foregroundStyle(.red)
                        .padding()
                }
                ForEach(pages, id: \.self) { url in
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFit().frame(maxWidth: .infinity)
                        case .empty:
                            Rectangle()
                                .fill(.gray.opacity(0.1))
                                .frame(height: 400)
                                .overlay(ProgressView())
                        default:
                            Rectangle()
                                .fill(.gray.opacity(0.2))
                                .frame(height: 400)
                        }
                    }
                }
            }
        }
        .navigationTitle("Reader")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
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
