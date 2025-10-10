//
//  MangaRail.swift
//  Manga-Reader
//
//  Created by Elias Magdaleno on 10/8/25.
//

import SwiftUI // Import SwiftUI to build views

// A horizontal, scrollable rail that renders a list of manga as cards.
// It expects `Manga` to already include `coverURL`.
struct MangaRail: View {     // Define the reusable rail component
    let items: [Manga]       // Store the list of manga to display

    var body: some View {    // Describe the rail UI
        ScrollView(.horizontal, showsIndicators: false) { // Enable horizontal scrolling, hide scrollbar
            HStack(spacing: 12) { // Place cards in a row with spacing between them
                ForEach(items, id: \.id) { manga in // Iterate using each manga's stable id
                    MangaCoverCard(                 // Reuse the card for each manga
                        title: manga.title,         // Pass the display title
                        coverURL: manga.coverURL    // Pass the prebuilt cover URL from the model
                    )
                }
            }
            .padding(.horizontal, 16) // Add side padding so cards aren't glued to the edges
        }
        .frame(maxWidth: .infinity, alignment: .leading) // Let the rail take full width of the screen
    }
}
