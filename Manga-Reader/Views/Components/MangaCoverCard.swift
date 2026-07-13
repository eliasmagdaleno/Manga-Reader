//
//  MangaCoverCard.swift
//  Manga-Reader
//
//  A cover card in the "Ink & Seal" voice: hairline-framed art (like a printed
//  plate), a serif title, and a monospaced metadata stamp.
//

import SwiftUI

struct MangaCoverCard: View {
    let title: String          // Title shown under the cover
    let coverURL: URL?         // Remote cover URL (may be nil)
    var stamp: String? = nil   // Optional metadata stamp, e.g. "CH·012" or "NEW"
    var stampTinted = false    // Draw the stamp in the seal color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Framed cover plate.
            AsyncImage(url: coverURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    CoverPlaceholder()
                case .empty:
                    CoverPlaceholder(showsSpinner: true)
                @unknown default:
                    CoverPlaceholder()
                }
            }
            .frame(width: Gutter.coverWidth, height: Gutter.coverHeight)
            .clipShape(RoundedRectangle(cornerRadius: Gutter.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Gutter.cardRadius)
                    .strokeBorder(Ink.hairline, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.10), radius: 6, x: 0, y: 3)

            // Title — always reserves two lines so the stamp below aligns
            // across cards regardless of how long each title is.
            Text(title)
                .font(.system(.footnote, design: .serif).weight(.semibold))
                .foregroundStyle(Ink.primary)
                .lineLimit(2, reservesSpace: true)

            // Metadata stamp.
            if let stamp {
                InkStamp(text: stamp, tinted: stampTinted)
            }
        }
        .frame(width: Gutter.coverWidth, alignment: .leading)
    }
}
