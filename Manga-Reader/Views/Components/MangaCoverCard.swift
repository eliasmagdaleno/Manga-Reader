//
//  MangaCoverCard.swift
//  Manga-Reader
//
//  Created by Elias Magdaleno on 10/8/25.
//

import SwiftUI // Import SwiftUI so we can build views

// A small card that shows a manga's cover image and its title.
struct MangaCoverCard: View { // Define the reusable card component
    let title: String         // Store the title text shown under the image
    let coverURL: URL?        // Store the remote URL for the cover image (may be nil)

    var body: some View {     // Describe the UI for this card
        VStack(alignment: .leading, spacing: 8) { // Stack image above text with some spacing
            AsyncImage(url: coverURL) { phase in  // Load the remote image asynchronously
                switch phase {                    // Handle loading states (success/failure/empty)
                case .success(let image):         // If the image loaded successfully
                    image
                        .resizable()              // Allow resizing to fit our frame
                        .scaledToFill()           // Fill the frame while preserving aspect ratio
                        .frame(width: 120, height: 160) // Set the card's image size
                        .clipped()                // Clip any overflow outside the frame
                        .cornerRadius(10)         // Round the corners for a card-like look

                case .failure:                    // If the image failed to load
                    Rectangle()                   // Show a gray placeholder rectangle
                        .fill(.gray.opacity(0.2)) // Use a subtle gray color
                        .frame(width: 120, height: 160) // Match the intended image size
                        .cornerRadius(10)         // Keep the same rounded shape

                case .empty:                      // While the image is still loading
                    ZStack {                      // Layer a spinner on top of a placeholder
                        Rectangle()
                            .fill(.gray.opacity(0.1))    // Very light background
                            .frame(width: 120, height: 160) // Same frame as final image
                            .cornerRadius(10)            // Same rounded corners
                        ProgressView()                   // System loading spinner
                    }

                @unknown default:                // Future-proof against new AsyncImage cases
                    EmptyView()                  // Fallback to showing nothing
                }
            }

            Text(title)                           // Render the manga's title below the image
                .font(.footnote)                  // Use a small, caption-like font
                .lineLimit(2)                     // Limit to two lines to keep cards compact
        }
        .frame(width: 120, alignment: .leading)   // Fix the overall card width for rail alignment
    }
}
