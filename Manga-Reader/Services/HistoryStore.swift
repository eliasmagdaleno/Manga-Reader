//
//  HistoryStore.swift
//  Manga-Reader
//
//  Chronological reading history + per-manga resume position. Backed by
//  UserDefaults. Powers both the detail "Continue" button and the History tab.
//

import SwiftUI

/// One logged reading position. A continuous session (the chapter being
/// recorded is already the newest entry) updates that entry in place;
/// re-opening a chapter later — after other reading has happened — creates a
/// brand-new entry so the log is a full chronological history.
struct ReadingEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let mangaId: String
    let mangaTitle: String
    let coverURL: URL?
    let chapterId: String
    let chapterNumber: String
    var page: Int
    var pageCount: Int
    var updatedAt: Date
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [ReadingEntry] = []

    private let key = "history.entries"
    private let defaults: UserDefaults
    private let cap = 500

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// Record progress. If the newest entry (the current session) is the same
    /// manga + chapter, update it in place; otherwise (including re-opening a
    /// chapter read previously) prepend a brand-new entry so the log stays a
    /// full chronological history of reading sessions.
    func record(manga: Manga, chapter: Chapter, page: Int, pageCount: Int) {
        if var first = entries.first, first.mangaId == manga.id, first.chapterId == chapter.id {
            first.page = max(first.page, page)   // furthest page reached
            first.pageCount = pageCount
            first.updatedAt = Date()
            entries[0] = first
        } else {
            entries.insert(
                ReadingEntry(id: UUID(), mangaId: manga.id, mangaTitle: manga.title,
                             coverURL: manga.coverURL, chapterId: chapter.id,
                             chapterNumber: chapter.number, page: page,
                             pageCount: pageCount, updatedAt: Date()),
                at: 0
            )
        }
        if entries.count > cap { entries.removeLast(entries.count - cap) }
        save()
    }

    func latestEntry(forManga id: String) -> ReadingEntry? {
        entries.first { $0.mangaId == id }
    }

    func delete(_ entry: ReadingEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ReadingEntry].self, from: data)
        else { return }
        entries = decoded
    }
}
