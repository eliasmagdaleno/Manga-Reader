//
//  ContentView.swift
//  Manga-Reader
//
//  Created by Elias Magdaleno on 5/31/24.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tabs = .home
    @StateObject private var webViewService = WebViewService.shared

    enum Tabs: Equatable, Hashable, Identifiable  {
        case home
        case bookmarks
        case history
        case search
        case settings

        var id: Self { self }
    }

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                TabView(selection: $selectedTab) {
                    HomeView()
                        .tabItem {
                            Label("Home", systemImage: "house")
                        }
                        .tag(Tabs.home)
                    BookmarksView()
                        .tabItem {
                            Label("Library", systemImage: "books.vertical")
                        }
                        .tag(Tabs.bookmarks)
                    HistoryView()
                        .tabItem {
                            Label("History", systemImage: "clock.arrow.circlepath")
                        }
                        .tag(Tabs.history)
                    SearchView()
                        .tabItem {
                            Label("Search", systemImage: "magnifyingglass")
                        }
                        .tag(Tabs.search)
                    SettingsView()
                        .tabItem {
                            Label("Settings", systemImage: "gear")
                        }
                        .tag(Tabs.settings)
                }
                .tabViewStyle(.sidebarAdaptable)
            } else {
                TabView(selection: $selectedTab) {
                    HomeView()
                        .tabItem {
                            Label("Home", systemImage: "house")
                        }
                        .tag(Tabs.home)
                    BookmarksView()
                        .tabItem {
                            Label("Library", systemImage: "books.vertical")
                        }
                        .tag(Tabs.bookmarks)
                    HistoryView()
                        .tabItem {
                            Label("History", systemImage: "clock.arrow.circlepath")
                        }
                        .tag(Tabs.history)
                    SearchView()
                        .tabItem {
                            Label("Search", systemImage: "magnifyingglass")
                        }
                        .tag(Tabs.search)
                    SettingsView()
                        .tabItem {
                            Label("Settings", systemImage: "gear")
                        }
                        .tag(Tabs.settings)
                }
                .tabViewStyle(.automatic)
            }
        }
        .sheet(isPresented: $webViewService.isChallengeActive,
               onDismiss: { webViewService.cancelChallenge() }) {
            CloudflareChallengeView()
        }
    }
}

#Preview {
    ContentView()
}
