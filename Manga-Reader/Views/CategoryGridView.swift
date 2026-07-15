//
//  CategoryGridView.swift
//  Manga-Reader
//
//  A full-screen 3-wide grid for a Home category (e.g. "Popular"), pushed onto
//  the Home navigation stack when the user taps "See all". Reuses
//  `MangaCoverCard` in fill mode, mirroring the Library grid.
//

import SwiftUI

struct CategoryGridView: View {
    let title: String
    let fetch: (() async throws -> [Manga])?

    @State private var items: [Manga]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var loadedOnce = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Gutter.rail), count: 3)

    init(title: String, initialItems: [Manga] = [], fetch: (() async throws -> [Manga])? = nil) {
        self.title = title
        self.fetch = fetch
        _items = State(initialValue: initialItems)
    }

    var body: some View {
        ScrollView {
            if let errorMessage, items.isEmpty {
                InkNotice(errorMessage)
                    .padding(Gutter.page)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: Gutter.section) {
                    ForEach(items) { manga in
                        NavigationLink(destination: MangaDetailView(manga: manga)) {
                            MangaCoverCard(
                                title: manga.title,
                                coverURL: manga.coverURL,
                                stamp: manga.year.map { String($0) },
                                fill: true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Gutter.page)
                .padding(.top, 8)
                .padding(.bottom, 32)

                if isLoading && items.isEmpty {
                    ProgressView().tint(Ink.seal)
                        .padding(.vertical, 40)
                }
            }
        }
        .background(Ink.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Single larger fetch on first appearance; keep any seeded items
            // visible while it loads so the transition is smooth.
            guard !loadedOnce, let fetch else { return }
            loadedOnce = true
            isLoading = true
            do { items = try await fetch() }
            catch { errorMessage = error.localizedDescription }
            isLoading = false
        }
    }
}
