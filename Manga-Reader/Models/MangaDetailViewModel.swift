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
    
    @Published var authors: [String] = []
    @Published var description: String = ""
    @Published var tags: [String] = []
    @Published var contentRating: String? = nil
    @Published var chapters: [Chapter] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    
    init(manga: Manga){
        self.manga = manga
    }
    
    func load() {
        Task{
            await loadAsync()
        }
    }
    
    private func loadAsync() async {
        isLoading = true
        errorMessage = nil
        do {
            let detail = try await MangaDexAPI.fetchMangaDetails(id: manga.id)
            self.description = detail.description
            self.authors = detail.authors
            self.tags = detail.tags
            self.contentRating = detail.contentRating
            
            self.chapters = try await MangaDexAPI.fetchChapters(mangaId: manga.id)
        }
        catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
            
    }
}
