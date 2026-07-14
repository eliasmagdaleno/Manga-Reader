//
//  LibraryStore.swift
//  Manga-Reader
//
//  A lightweight, persisted "Library" of saved manga. Stores just enough
//  (id, title, cover) to render cards and re-open detail, backed by UserDefaults.
//

import SwiftUI

/// A saved manga snapshot. Kept small and Codable for on-device persistence.
struct LibraryItem: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let coverURL: URL?
    var lastSeenReadableAt: String?   // caught-up marker; advances only on read
    var latestReadableAt: String?     // newest chapter seen at last refresh
    var newChapterCount: Int?         // badge count (nil/0 = no badge)
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var items: [LibraryItem] = []
    @Published private(set) var isRefreshing = false

    private let key = "library.items"

    init() { load() }

    func contains(_ id: String) -> Bool {
        items.contains { $0.id == id }
    }

    /// Add the manga if absent, remove it if already saved.
    func toggle(_ manga: Manga) {
        if contains(manga.id) {
            items.removeAll { $0.id == manga.id }
        } else {
            items.insert(
                LibraryItem(id: manga.id, title: manga.title, coverURL: manga.coverURL),
                at: 0
            )
        }
        save()
    }

    /// Refresh every saved manga's latest-chapter info concurrently and recompute
    /// new-chapter badges. Best-effort: per-item failures are ignored.
    func refresh(history: HistoryStore) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let current = items
        let results: [(String, [RecentChapter])] = await withTaskGroup(
            of: (String, [RecentChapter])?.self
        ) { group in
            for item in current {
                group.addTask {
                    guard let recent = try? await MangaDexAPI.recentChapters(mangaId: item.id) else { return nil }
                    return (item.id, recent)
                }
            }
            var out: [(String, [RecentChapter])] = []
            for await result in group { if let result { out.append(result) } }
            return out
        }

        var updated = items
        for (id, recent) in results {
            guard let idx = updated.firstIndex(where: { $0.id == id }) else { continue }
            let latest = recent.first?.readableAt
            if updated[idx].lastSeenReadableAt == nil {
                // First-ever refresh: establish baseline, no false "new".
                updated[idx].lastSeenReadableAt = latest
                updated[idx].latestReadableAt = latest
                updated[idx].newChapterCount = 0
            } else {
                updated[idx].latestReadableAt = latest
                updated[idx].newChapterCount = newChapterCount(
                    recent, since: updated[idx].lastSeenReadableAt,
                    excludingNumbers: history.readChapterNumbers(forManga: id))
            }
        }
        items = updated
        save()
    }

    /// Mark a manga caught-up (called when the reader opens one of its chapters):
    /// advance the baseline to the newest known chapter and clear the badge.
    func markCaughtUp(_ id: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].lastSeenReadableAt = items[idx].latestReadableAt ?? items[idx].lastSeenReadableAt
        items[idx].newChapterCount = 0
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([LibraryItem].self, from: data)
        else { return }
        items = decoded
    }
}
