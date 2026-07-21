//
//  PagedMangaGrid.swift
//  Manga-Reader
//
//  The shared infinite-scroll results grid: a 3-wide cover grid over a
//  `PagedMangaLoader`, appending the next page as the user nears the bottom.
//  Renders only the grid and its load-more footer — callers own the
//  surrounding ScrollView, empty states, and error notices.
//

import SwiftUI

struct PagedMangaGrid: View {
    @ObservedObject var loader: PagedMangaLoader

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Gutter.rail), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Gutter.section) {
            ForEach(loader.items) { manga in
                NavigationLink(destination: MangaDetailView(manga: manga)) {
                    MangaCoverCard(
                        title: manga.title,
                        coverURL: manga.coverURL,
                        stamp: manga.year.map { String($0) },
                        fill: true
                    )
                }
                .buttonStyle(.plain)
                .onAppear { loader.loadMoreIfNeeded(current: manga) }
            }
        }
        .padding(.horizontal, Gutter.page)

        if loader.isLoadingMore {
            ProgressView().tint(Ink.seal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        }
    }
}
