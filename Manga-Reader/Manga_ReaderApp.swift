//
//  Manga_ReaderApp.swift
//  Manga-Reader
//
//  Created by Elias Magdaleno on 5/31/24.
//

import SwiftUI

@main
struct Manga_ReaderApp: App {
    // Persisted appearance choice; drives the whole app's color scheme.
    @AppStorage(appearanceStorageKey) private var appearanceRaw = AppearanceMode.system.rawValue

    // App-wide stores + the recommendation engine, all owned here so the engine shares
    // the exact same store instances the rest of the app writes to.
    @StateObject private var library: LibraryStore
    @StateObject private var history: HistoryStore
    @StateObject private var taste: TasteProfileStore
    @StateObject private var works: WorkStore
    @StateObject private var engine: RecommendationEngine

    init() {
        // Built first: the three commitment paths below (read, save, feedback) all
        // mint into it, so they must share this one instance (ADR-0007).
        let wk = WorkStore()
        let lib = LibraryStore(works: wk)
        let hist = HistoryStore(works: wk)
        let ts = TasteProfileStore()
        _library = StateObject(wrappedValue: lib)
        _history = StateObject(wrappedValue: hist)
        _taste = StateObject(wrappedValue: ts)
        _works = StateObject(wrappedValue: wk)
        _engine = StateObject(wrappedValue: RecommendationEngine(history: hist, library: lib,
                                                                profileStore: ts, workStore: wk))
    }

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Ink.seal)
                .environmentObject(library)
                .environmentObject(history)
                .environmentObject(taste)
                .environmentObject(works)
                .environmentObject(engine)
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}
