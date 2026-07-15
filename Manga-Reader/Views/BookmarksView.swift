//
//  BookmarksView.swift
//  Manga-Reader
//
//  The "Library" tab: manga the reader has saved. Renders saved items as a grid
//  and falls back to a themed empty state when nothing is saved yet.
//

import SwiftUI

struct BookmarksView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var history: HistoryStore

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Gutter.rail), count: 3)

    var body: some View {
        NavigationStack {
            Group {
                if library.items.isEmpty {
                    InkEmptyState(
                        symbol: "books.vertical",
                        title: "Your library is empty",
                        message: "Tap Add to Library on any title to keep it here for quick access."
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: Gutter.section) {
                            ForEach(library.items) { item in
                                let unread = item.unreadCount(readNumbers: history.readChapterNumbers(forManga: item.id))
                                NavigationLink(destination: MangaDetailView(manga: item.asManga)) {
                                    MangaCoverCard(
                                        title: item.title,
                                        coverURL: item.coverURL,
                                        stamp: unread > 0 ? "UNREAD · \(unread)" : nil,
                                        stampTinted: true,
                                        fill: true
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Gutter.page)
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                    }
                    .background(Ink.background)
                    .refreshable { await library.refresh() }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await library.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(library.isRefreshing || library.items.isEmpty)
                }
            }
        }
    }
}

private extension LibraryItem {
    /// A minimal `Manga` for navigation; the detail view refetches full data by id.
    var asManga: Manga {
        Manga(id: id, sourceId: sourceId ?? MangaDexSource.sourceID, title: title,
              description: "", status: "unknown", year: nil, coverURL: coverURL)
    }
}

#Preview {
    BookmarksView()
        .environmentObject(LibraryStore())
}
