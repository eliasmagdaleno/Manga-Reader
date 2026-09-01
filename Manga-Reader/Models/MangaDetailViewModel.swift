//
//  MangaDetailViewModel.swift
//  Manga-Reader
//
//  Created by Elias Magdaleno on 11/13/25.
//

import Foundation
@MainActor
final class MangaDetailViewModel: ObservableObject {

    let manga: Manga

    /// The source currently being fulfilled from. Starts as this manga's own source and
    /// moves when the reader picks another (ADR-0004); injectable for tests.
    private var source: MangaSource

    /// Which Listing chapters are being loaded from. Distinct from `manga`, which stays put:
    /// ADR-0001 makes the **Work** the manga and a Listing only one source's copy of it, so
    /// switching source changes where chapters come from, not what the reader is looking at.
    @Published private(set) var activeListing: ListingKey

    @Published var authors: [String] = []
    @Published var description: String = ""
    @Published var tags: [String] = []
    @Published var detailTags: [Tag] = []
    @Published var contentRating: String? = nil
    @Published var chapters: [Chapter] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil

    init(manga: Manga, source: MangaSource? = nil) {
        self.manga = manga
        self.source = source ?? SourceRegistry.shared.source(for: manga)
        self.activeListing = ListingKey(manga)
    }

    /// Points this page at another of the Work's Listings. The caller reloads.
    ///
    /// An unregistered source is **refused rather than half-applied**: pointing the page at
    /// a source it cannot reach would empty the chapter list, which reads as the manga
    /// having no chapters rather than as the source being unavailable.
    func retarget(to listing: ListingKey, using registry: SourceRegistry = .shared) {
        guard let source = registry.source(id: listing.sourceId) else { return }
        self.source = source
        self.activeListing = listing
    }

    func load() {
        Task {
            await loadAsync()
        }
    }

    /// Internal (not private) so tests can await it deterministically instead of racing
    /// the fire-and-forget `Task` in `load()`.
    func loadAsync() async {
        isLoading = true
        errorMessage = nil
        do {
            let detail = try await source.mangaDetail(id: activeListing.mangaId)
            self.description = detail.description
            self.authors = detail.authors
            self.detailTags = detail.tags
            self.tags = detail.tags.map(\.name)
            self.contentRating = detail.contentRating

            self.chapters = try await source.chapters(mangaId: activeListing.mangaId)
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false

    }
}
