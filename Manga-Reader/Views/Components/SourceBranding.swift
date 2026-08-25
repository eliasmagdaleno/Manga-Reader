//
//  SourceBranding.swift
//  Manga-Reader
//
//  Visual identity for sources: the logo (bundled asset per source id, with a
//  monogram-seal fallback), the Home chip bar that switches the browse source,
//  and the small logo+name stamp used on the detail screen.
//

import SwiftUI
import UIKit

// MARK: - Logo

/// A source's logo mark. Looks up "SourceLogo-<id>" in the asset catalog and
/// falls back to a seal-tinted serif monogram for sources without a bundled logo.
struct SourceLogoView: View {
    let sourceID: String
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let image = UIImage(named: "SourceLogo-\(sourceID)") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                RoundedRectangle(cornerRadius: size * 0.25)
                    .fill(Ink.sealSoft)
                    .frame(width: size, height: size)
                    .overlay(
                        Text(sourceID.prefix(1).uppercased())
                            .font(.inkDisplay(size * 0.62))
                            .foregroundStyle(Ink.seal)
                    )
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Chip bar (Home source switcher)

/// The Home source switcher: one chip per visible source, logo + name, with the
/// active source seal-tinted. Replaces the old toolbar menu so the sources are
/// always visible and one tap away.
struct SourceChipBar: View {
    let sources: [any MangaSource]
    let activeID: String
    var accessibilityVerb = "Browse"
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sources, id: \.id) { source in
                    chip(for: source)
                }
            }
            .padding(.horizontal, Gutter.page)
        }
    }

    private func chip(for source: any MangaSource) -> some View {
        let active = source.id == activeID
        return Button {
            onSelect(source.id)
        } label: {
            HStack(spacing: 6) {
                SourceLogoView(sourceID: source.id, size: 16)
                    .grayscale(active ? 0 : 1)
                    .opacity(active ? 1 : 0.7)
                Text(source.name.uppercased())
                    .font(.inkMono(10, weight: .bold))
                    .tracking(0.8)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .foregroundStyle(active ? Ink.seal : Ink.secondary)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(active ? Ink.sealSoft : Ink.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(active ? Ink.seal : Ink.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel("\(accessibilityVerb) \(source.name)")
        .accessibilityInputLabels([source.name, "\(accessibilityVerb) \(source.name)"])
        .accessibilityValue(active ? "Selected" : "Not selected")
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}

// MARK: - Source stamp (detail screen)

/// Logo + name in the metadata-stamp voice, for the detail screen's stamp row.
struct SourceStamp: View {
    let sourceID: String
    let name: String

    var body: some View {
        HStack(spacing: 5) {
            SourceLogoView(sourceID: sourceID, size: 13)
            Text(name.uppercased())
                .font(.inkMono(10, weight: .semibold))
                .tracking(0.5)
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(Ink.seal)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Ink.sealSoft)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Source: \(name)")
    }
}
