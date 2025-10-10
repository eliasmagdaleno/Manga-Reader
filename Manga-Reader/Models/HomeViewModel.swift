//
//  HomeViewModel.swift
//  Manga-Reader
//
//  Created by Elias Magdaleno on 10/8/25.
//

import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var popular: [Manga] = []
    @Published var latestUpdates: [MangaUpdate] = []
    @Published var newTitles: [Manga] = []
    
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    
    func loadHome() {
        Task {
            await loadHomeAsync()
                
        }
    }
    
    func refresh(){
        loadHome()
    }
    
    private func loadHomeAsync() async {
        isLoading = true
        errorMessage = nil
        do {
            async let popularTask: [Manga] = MangaDexAPI.fetchPopular(limit: 20)
            async let updatesTask: [MangaUpdate] = MangaDexAPI.fetchLatestUpdates(limitTitles: 20, translatedLang: "en")
            async let newTitlesTask: [Manga] = MangaDexAPI.fetchNewTitles(limit: 20)
            
            self.popular = try await popularTask
            self.latestUpdates = try await updatesTask
            self.newTitles = try await newTitlesTask
        }
        catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    func reloadPopular(limit: Int = 20, offset: Int = 0) {
        Task {
            do {
                let items = try await MangaDexAPI.fetchPopular(limit: limit, offset: offset)
                self.popular = items
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    func reloadLatestUpdates(limit: Int = 20, lang: String = "en") {
        Task {
            do {
                let items = try await MangaDexAPI.fetchLatestUpdates(limitTitles: limit, translatedLang: lang)
                self.latestUpdates = items
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    func reloadNewTitles(limit: Int = 20, offset: Int = 0) {
        Task {
            do {
                let items = try await MangaDexAPI.fetchNewTitles(limit: limit, offset: offset)
                self.newTitles = items
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }
        
}
