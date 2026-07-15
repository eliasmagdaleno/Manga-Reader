//
//  SourceRegistry.swift
//  Manga-Reader
//
//  The single place that knows which manga sources exist and which one is "active" for
//  browsing. ViewModels and Services resolve their source through here instead of
//  referencing a concrete API. Today there is exactly one source (MangaDex); this is the
//  seam that multi-source support grows into.
//

import Foundation
import Combine

@MainActor
final class SourceRegistry: ObservableObject {
    /// App-wide shared instance. Tests construct their own with injected sources instead.
    static let shared = SourceRegistry()

    /// All sources compiled into the app.
    @Published private(set) var sources: [MangaSource]

    /// The source used for browsing feeds (Home rails, search). Persisted across launches.
    @Published var activeSourceID: String {
        didSet { UserDefaults.standard.set(activeSourceID, forKey: Self.activeKey) }
    }

    private static let activeKey = "source.activeID"

    /// - Parameter sources: Sources to register. Defaults to the app's built-in set.
    ///   Injectable so tests can supply mock sources.
    init(sources: [MangaSource] = [MangaDexSource()]) {
        precondition(!sources.isEmpty, "SourceRegistry requires at least one source")
        self.sources = sources
        // Restore the persisted active source if it still exists; otherwise fall back to the first.
        let stored = UserDefaults.standard.string(forKey: Self.activeKey)
        self.activeSourceID = sources.contains(where: { $0.id == stored }) ? stored! : sources[0].id
    }

    /// The currently-active browsing source (never nil — falls back to the first source).
    var active: MangaSource {
        source(id: activeSourceID) ?? sources[0]
    }

    /// Look up a source by its stable id (e.g. a manga's `sourceId`). Nil if not registered.
    func source(id: String) -> MangaSource? {
        sources.first { $0.id == id }
    }

    /// The source a given manga came from, falling back to the active source if that
    /// source isn't registered. Use this for a manga's detail / chapters / pages.
    func source(for manga: Manga) -> MangaSource {
        source(id: manga.sourceId) ?? active
    }
}
