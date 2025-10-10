//
//  ContentView.swift
//  Manga-Reader
//
//  Created by Elias Magdaleno on 5/31/24.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tabs = .home
    
    enum Tabs: Equatable, Hashable, Identifiable  {
        case home
        case bookmarks
        case search
        case settings
        
        var id: Self { self }
    }
    
    var body: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem {
                        Label("Home", systemImage: "house")
                    }
                    .tag(Tabs.home)
                BookmarksView()
                    .tabItem {
                        Label("Bookmarks", systemImage: "bookmark")
                    }
                    .tag(Tabs.bookmarks)
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
                        Label("Bookmarks", systemImage: "bookmark")
                    }
                    .tag(Tabs.bookmarks)
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
}

#Preview {
    ContentView()
}
