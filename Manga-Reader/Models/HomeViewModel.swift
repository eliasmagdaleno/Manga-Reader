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

    /// Injected source for tests; nil means "track the registry's active source".
    private let sourceOverride: MangaSource?
    /// The source these browse feeds come from — resolved at read time so a Settings
    /// switch re-sources Home without an app relaunch.
    var source: MangaSource { sourceOverride ?? SourceRegistry.shared.active }
    /// The source id the current feed arrays were loaded from (nil before first load).
    private var loadedSourceID: String?

    init(source: MangaSource? = nil) {
        self.sourceOverride = source
    }

    func loadHome() {
        // Clear stale feeds when the active source changed since the last load, so the
        // previous source's rails don't linger while the new one fetches.
        let activeID = source.id
        if let loaded = loadedSourceID, loaded != activeID {
            popular = []; latestUpdates = []; newTitles = []
            errorMessage = nil
        }
        loadedSourceID = activeID
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
            async let popularTask: [Manga] = source.popular(limit: 20, offset: 0)
            async let updatesTask: [MangaUpdate] = source.latestUpdates(limitTitles: 20, language: "en")
            async let newTitlesTask: [Manga] = source.newTitles(limit: 20, offset: 0)
            
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
                let items = try await source.popular(limit: limit, offset: offset)
                self.popular = items
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    func reloadLatestUpdates(limit: Int = 20, lang: String = "en") {
        Task {
            do {
                let items = try await source.latestUpdates(limitTitles: limit, language: lang)
                self.latestUpdates = items
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    func reloadNewTitles(limit: Int = 20, offset: Int = 0) {
        Task {
            do {
                let items = try await source.newTitles(limit: limit, offset: offset)
                self.newTitles = items
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }
        
}
