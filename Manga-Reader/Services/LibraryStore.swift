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
    var chapterNumbers: [String]? = nil   // deduped chapter numbers from last refresh; nil = never refreshed
}

extension LibraryItem {
    /// Chapters not yet read, given this manga's read chapter numbers from `HistoryStore`.
    /// Returns 0 until the first successful refresh populates `chapterNumbers`.
    func unreadCount(readNumbers: Set<String>) -> Int {
        guard let chapterNumbers else { return 0 }
        return chapterNumbers.filter { !readNumbers.contains($0) }.count
    }
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

    /// Refresh every saved manga's full chapter-number list concurrently. Best-effort:
    /// per-item failures leave that item's existing `chapterNumbers` untouched.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let current = items
        let maxConcurrent = 4
        let results: [(String, [String])] = await withTaskGroup(
            of: (String, [String])?.self
        ) { group in
            var iterator = current.makeIterator()

            func addNext() {
                guard let item = iterator.next() else { return }
                group.addTask {
                    guard let chapters = try? await MangaDexAPI.fetchChapters(mangaId: item.id) else { return nil }
                    return (item.id, chapters.map(\.number))
                }
            }

            for _ in 0..<maxConcurrent { addNext() }

            var out: [(String, [String])] = []
            while let result = await group.next() {
                if let result { out.append(result) }
                addNext()
            }
            return out
        }

        var updated = items
        for (id, numbers) in results {
            guard let idx = updated.firstIndex(where: { $0.id == id }) else { continue }
            updated[idx].chapterNumbers = numbers
        }
        items = updated
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
