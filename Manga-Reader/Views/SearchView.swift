//
//  SearchView.swift
//  Manga-Reader
//

import SwiftUI

struct SearchView: View {
    @State private var query = ""

    var body: some View {
        NavigationStack {
            InkEmptyState(
                symbol: "magnifyingglass",
                title: "Search the library",
                message: "Find manga by title, author, or tag. Full search is coming soon."
            )
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Titles, authors, tags")
        }
    }
}

#Preview {
    SearchView()
}
