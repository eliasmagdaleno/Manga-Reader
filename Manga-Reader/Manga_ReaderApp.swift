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
    @StateObject private var engine: RecommendationEngine

    init() {
        let lib = LibraryStore()
        let hist = HistoryStore()
        let ts = TasteProfileStore()
        _library = StateObject(wrappedValue: lib)
        _history = StateObject(wrappedValue: hist)
        _taste = StateObject(wrappedValue: ts)
        _engine = StateObject(wrappedValue: RecommendationEngine(history: hist, library: lib, profileStore: ts))
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
                .environmentObject(engine)
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}
