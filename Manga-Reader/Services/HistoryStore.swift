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
    var sourceId: String? = nil   // nil = saved before multi-source; treat as MangaDex
}

/// A chapter the user explicitly marked as read (or that was read but whose
/// history entry was cleared). Kept separate from `ReadingEntry` so a manual
/// mark never pollutes the chronological reading log.
struct ReadMark: Codable, Hashable {
    let mangaId: String
    let chapterId: String
    let chapterNumber: String
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [ReadingEntry] = []
    @Published private(set) var readMarks: [ReadMark] = []

    private let key = "history.entries"
    private let marksKey = "history.readMarks"
    private let defaults: UserDefaults
    private let cap = 500
    /// Reading is a commitment, so it mints a Work (ADR-0007). Optional because
    /// history predates the Work store and most tests have no interest in it; the
    /// app wires it in `Manga_ReaderApp`.
    private let works: WorkStore?

    init(defaults: UserDefaults = .standard, works: WorkStore? = nil) {
        self.defaults = defaults
        self.works = works
        load()
    }

    /// Record progress. If the newest entry (the current session) is the same
    /// manga + chapter, update it in place; otherwise (including re-opening a
    /// chapter read previously) prepend a brand-new entry so the log stays a
    /// full chronological history of reading sessions.
    func record(manga: Manga, chapter: Chapter, page: Int, pageCount: Int) {
        // Reading is the strongest commitment signal there is. Minting is local and
        // network-free, so it is safe on this path — it runs on every page turn.
        _ = works?.mint(from: manga)

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
                             pageCount: pageCount, updatedAt: Date(),
                             sourceId: manga.sourceId),
                at: 0
            )
        }
        if entries.count > cap { entries.removeLast(entries.count - cap) }
        save()
    }

    func latestEntry(forManga id: String) -> ReadingEntry? {
        entries.first { $0.mangaId == id }
    }

    /// Newest history entry for a specific chapter, if any. Drives the "Page: N"
    /// resume label on a chapter row.
    func entry(forChapter chapterId: String) -> ReadingEntry? {
        entries.first { $0.chapterId == chapterId }
    }

    /// Chapter numbers considered read for a manga — opened (has a history
    /// entry) or manually marked. Single source of truth shared by the chapter
    /// rows and `LibraryStore` badge reconciliation.
    func readChapterNumbers(forManga id: String) -> Set<String> {
        var numbers = Set(entries.filter { $0.mangaId == id }.map(\.chapterNumber))
        numbers.formUnion(readMarks.filter { $0.mangaId == id }.map(\.chapterNumber))
        return numbers
    }

    // MARK: Read / unread

    /// True if the chapter has been opened (has a history entry) or manually
    /// marked read.
    func isRead(chapterId: String) -> Bool {
        entries.contains { $0.chapterId == chapterId } ||
        readMarks.contains { $0.chapterId == chapterId }
    }

    func markRead(manga: Manga, chapter: Chapter) {
        guard !readMarks.contains(where: { $0.chapterId == chapter.id }) else { return }
        readMarks.append(ReadMark(mangaId: manga.id, chapterId: chapter.id,
                                  chapterNumber: chapter.number))
        save()
    }

    /// Clear read state: drop the manual mark and any history entries for the
    /// chapter, so "opened" no longer counts it as read.
    func markUnread(manga: Manga, chapter: Chapter) {
        readMarks.removeAll { $0.chapterId == chapter.id }
        entries.removeAll { $0.chapterId == chapter.id }
        save()
    }

    func toggleRead(manga: Manga, chapter: Chapter) {
        if isRead(chapterId: chapter.id) {
            markUnread(manga: manga, chapter: chapter)
        } else {
            markRead(manga: manga, chapter: chapter)
        }
    }

    /// Mark multiple chapters read in one save. Skips chapters already marked
    /// (mirrors the single-chapter `markRead`'s idempotency).
    func markRead(manga: Manga, chapters: [Chapter]) {
        var existing = Set(readMarks.map(\.chapterId))
        for chapter in chapters where !existing.contains(chapter.id) {
            readMarks.append(ReadMark(mangaId: manga.id, chapterId: chapter.id,
                                      chapterNumber: chapter.number))
            existing.insert(chapter.id)
        }
        save()
    }

    /// Mark multiple chapters unread in one save: drops both manual marks and
    /// any history entries for exactly the given chapters, leaving others untouched.
    func markUnread(manga: Manga, chapters: [Chapter]) {
        let ids = Set(chapters.map(\.id))
        readMarks.removeAll { ids.contains($0.chapterId) }
        entries.removeAll { ids.contains($0.chapterId) }
        save()
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
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: key)
        }
        if let marks = try? JSONEncoder().encode(readMarks) {
            defaults.set(marks, forKey: marksKey)
        }
    }

    private func load() {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ReadingEntry].self, from: data) {
            entries = decoded
        }
        if let data = defaults.data(forKey: marksKey),
           let decoded = try? JSONDecoder().decode([ReadMark].self, from: data) {
            readMarks = decoded
        }
    }
}
