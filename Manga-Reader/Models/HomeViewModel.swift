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
    /// The in-flight full-home load. Superseded loads are cancelled so a slow fetch from
    /// a previously-active source can never clobber the rails after a source switch.
    private var loadTask: Task<Void, Never>?

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
        loadTask?.cancel()
        loadTask = Task {
            await loadHomeAsync()
        }
    }

    func refresh() {
        loadHome()
    }

    private func loadHomeAsync() async {
        guard !Task.isCancelled else { return }
        isLoading = true
        errorMessage = nil
        do {
            async let popularTask: [Manga] = source.popular(limit: 20, offset: 0)
            async let updatesTask: [MangaUpdate] = source.latestUpdates(limitTitles: 20, language: "en")
            async let newTitlesTask: [Manga] = source.newTitles(limit: 20, offset: 0)

            let popular = try await popularTask
            let updates = try await updatesTask
            let newTitles = try await newTitlesTask
            // A superseded load must never write: a newer loadHome() owns the state now.
            guard !Task.isCancelled else { return }
            self.popular = popular
            self.latestUpdates = updates
            self.newTitles = newTitles
        } catch is CancellationError {
            // Superseded, not failed — don't surface cancellation as an error.
            return
        } catch {
            guard !Task.isCancelled else { return }
            self.errorMessage = error.localizedDescription
        }
        if !Task.isCancelled { isLoading = false }
    }

    func reloadPopular(limit: Int = 20, offset: Int = 0) {
        let expectedID = source.id
        Task {
            do {
                let items = try await source.popular(limit: limit, offset: offset)
                guard self.source.id == expectedID else { return }
                self.popular = items
            } catch is CancellationError {
            } catch {
                guard self.source.id == expectedID else { return }
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func reloadLatestUpdates(limit: Int = 20, lang: String = "en") {
        let expectedID = source.id
        Task {
            do {
                let items = try await source.latestUpdates(limitTitles: limit, language: lang)
                guard self.source.id == expectedID else { return }
                self.latestUpdates = items
            } catch is CancellationError {
            } catch {
                guard self.source.id == expectedID else { return }
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func reloadNewTitles(limit: Int = 20, offset: Int = 0) {
        let expectedID = source.id
        Task {
            do {
                let items = try await source.newTitles(limit: limit, offset: offset)
                guard self.source.id == expectedID else { return }
                self.newTitles = items
            } catch is CancellationError {
            } catch {
                guard self.source.id == expectedID else { return }
                self.errorMessage = error.localizedDescription
            }
        }
    }

}
