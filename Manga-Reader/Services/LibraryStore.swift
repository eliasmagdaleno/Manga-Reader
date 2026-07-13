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
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var items: [LibraryItem] = []

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
