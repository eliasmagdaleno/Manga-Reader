//
//  ChapterListView.swift
//  Manga-Reader
//
//  The full chapter list for a manga: newest/oldest sort toggle + multi-select
//  batch actions (mark read/unread). Pushed from the detail page's "Show all N
//  chapters" affordance; the detail page itself shows only a short preview.
//

import SwiftUI

struct ChapterListView: View {
    let manga: Manga
    let chapters: [Chapter]
    @EnvironmentObject private var history: HistoryStore
    @State private var descending = true
    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sortChapters(chapters, descending: descending)) { chapter in
                    if isSelecting {
                        Button {
                            toggleSelection(chapter.id)
                        } label: {
                            ChapterRow(chapter: chapter, selecting: true,
                                       selected: selectedIDs.contains(chapter.id))
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink {
                            // The row advertises a saved position (ChapterRow's resume marker),
                            // so tapping it has to honour one — ADR-0014 decision 11.
                            ReaderView(manga: manga, chapter: chapter,
                                       initialPosition: history.entry(forChapter: chapter.id)?.position,
                                       chapters: chapters)
                        } label: {
                            ChapterRow(chapter: chapter)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            let read = history.isRead(chapterId: chapter.id)
                            Button {
                                history.toggleRead(manga: manga, chapter: chapter)
                            } label: {
                                Label(read ? "Mark as unread" : "Mark as read",
                                      systemImage: read ? "circle" : "checkmark.circle")
                            }
                            
                            Button {
                                let sorted = sortChapters(chapters, descending: descending)
                                if let idx = sorted.firstIndex(where: { $0.id == chapter.id }) {
                                    history.markRead(manga: manga, chapters: Array(sorted[idx...]))
                                }
                            } label: {
                                Label("Mark all below as read", systemImage: "arrow.down.to.line")
                            }
                        }
                    }
                    Divider().overlay(Ink.hairline)
                        .padding(.leading, Gutter.page)
                }
            }
            .padding(.vertical, 8)
        }
        .background(Ink.background)
        .navigationTitle("Chapters")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isSelecting {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            isSelecting = false
                            selectedIDs.removeAll()
                        }
                    } label: {
                        Text("CANCEL")
                            .font(.inkMono(11, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(Ink.seal)
                    }
                } else {
                    HStack(spacing: 16) {
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { isSelecting = true }
                        } label: {
                            Text("SELECT")
                                .font(.inkMono(11, weight: .semibold))
                                .tracking(0.5)
                                .foregroundStyle(Ink.seal)
                        }
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { descending.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.arrow.down")
                                Text(descending ? "NEWEST" : "OLDEST")
                            }
                            .font(.inkMono(11, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(Ink.seal)
                        }
                    }
                }
            }
            if isSelecting {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button(allSelected ? "Deselect All" : "Select All") {
                        withAnimation(.snappy(duration: 0.2)) {
                            selectedIDs = allSelected ? [] : Set(chapters.map(\.id))
                        }
                    }
                    Spacer()
                    Button("Mark Unread") { markSelected(read: false) }
                        .disabled(selectedIDs.isEmpty)
                    Button("Mark Read") { markSelected(read: true) }
                        .disabled(selectedIDs.isEmpty)
                        .fontWeight(.semibold)
                }
            }
        }
        .accessibilityIdentifier("chapterListScreen")
    }

    private var allSelected: Bool {
        !chapters.isEmpty && selectedIDs.count == chapters.count
    }

    private func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func markSelected(read: Bool) {
        let picked = chapters.filter { selectedIDs.contains($0.id) }
        if read {
            history.markRead(manga: manga, chapters: picked)
        } else {
            history.markUnread(manga: manga, chapters: picked)
        }
        withAnimation(.snappy(duration: 0.2)) {
            isSelecting = false
            selectedIDs.removeAll()
        }
    }
}
