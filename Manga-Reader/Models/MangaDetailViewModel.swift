//
//  MangaDetailViewModel.swift
//  Manga-Reader
//
//  Created by Elias Magdaleno on 11/13/25.
//

import Foundation
@MainActor
final class MangaDetailViewModel: ObservableObject{
    
    let manga: Manga

    /// The source this manga came from. Defaults to the registry's resolution by
    /// `manga.sourceId`; injectable for tests.
    private let source: MangaSource

    @Published var authors: [String] = []
    @Published var description: String = ""
    @Published var tags: [String] = []
    @Published var detailTags: [Tag] = []
    @Published var contentRating: String? = nil
    @Published var chapters: [Chapter] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    
    init(manga: Manga, source: MangaSource? = nil){
        self.manga = manga
        self.source = source ?? SourceRegistry.shared.source(for: manga)
    }
    
    func load() {
        Task{
            await loadAsync()
        }
    }
    
    /// Internal (not private) so tests can await it deterministically instead of racing
    /// the fire-and-forget `Task` in `load()`.
    func loadAsync() async {
        isLoading = true
        errorMessage = nil
        do {
            let detail = try await source.mangaDetail(id: manga.id)
            self.description = detail.description
            self.authors = detail.authors
            self.detailTags = detail.tags
            self.tags = detail.tags.map(\.name)
            self.contentRating = detail.contentRating

            self.chapters = try await source.chapters(mangaId: manga.id)
        }
        catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false

    }
}
