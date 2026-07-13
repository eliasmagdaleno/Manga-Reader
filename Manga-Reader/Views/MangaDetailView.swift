//
//  MangaDetailView.swift
//  Manga-Reader
//

import SwiftUI

struct MangaDetailView: View {
    let manga: Manga
    @StateObject private var vm: MangaDetailViewModel
    @EnvironmentObject private var library: LibraryStore
    @State private var synopsisExpanded = false

    init(manga: Manga) {
        self.manga = manga
        _vm = StateObject(wrappedValue: MangaDetailViewModel(manga: manga))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Gutter.section) {
                hero
                libraryButton
                if !vm.tags.isEmpty { tags }
                if !vm.description.isEmpty || vm.isLoading { description }
                chapters
            }
            .padding(.bottom, 40)
        }
        .background(Ink.background)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.load() }
    }

    // MARK: Hero — blurred backdrop, floating cover plate, title block.

    private var hero: some View {
        ZStack(alignment: .bottom) {
            // Ambient backdrop from the cover itself.
            AsyncImage(url: manga.coverURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Ink.surfaceAlt
            }
            .frame(height: 300)
            .clipped()
            .blur(radius: 28)
            .opacity(0.55)
            .overlay(
                LinearGradient(
                    colors: [Ink.background.opacity(0), Ink.background],
                    startPoint: .top, endPoint: .bottom
                )
            )

            HStack(alignment: .bottom, spacing: 16) {
                // Cover plate.
                AsyncImage(url: manga.coverURL) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    case .empty: CoverPlaceholder(showsSpinner: true)
                    default: CoverPlaceholder()
                    }
                }
                .frame(width: 132, height: 188)
                .clipShape(RoundedRectangle(cornerRadius: Gutter.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Gutter.cardRadius)
                        .strokeBorder(Ink.hairline, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)

                VStack(alignment: .leading, spacing: 8) {
                    Text(manga.title)
                        .font(.inkDisplay(26))
                        .foregroundStyle(Ink.primary)
                        .lineLimit(3)

                    if !vm.authors.isEmpty {
                        Text(vm.authors.joined(separator: " · "))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Ink.seal)
                            .lineLimit(2)
                    }

                    HStack(spacing: 6) {
                        if let year = manga.year {
                            InkStamp(text: String(year))
                        }
                        InkStamp(text: manga.status.uppercased())
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Gutter.page)
            .padding(.bottom, 24)
        }
    }

    // MARK: Add to Library

    private var libraryButton: some View {
        let inLibrary = library.contains(manga.id)
        return Button {
            withAnimation(.snappy(duration: 0.2)) { library.toggle(manga) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: inLibrary ? "checkmark" : "plus")
                Text(inLibrary ? "In Library" : "Add to Library")
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(inLibrary ? Ink.seal : Color.white)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(inLibrary ? Ink.sealSoft : Ink.seal)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Ink.seal, lineWidth: inLibrary ? 1.5 : 0)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Gutter.page)
    }

    // MARK: Tags

    private var tags: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Ink.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(Ink.surface)
                        )
                        .overlay(Capsule().strokeBorder(Ink.hairline, lineWidth: 1))
                }
            }
            .padding(.horizontal, Gutter.page)
        }
    }

    // MARK: Description

    private var description: some View {
        VStack(alignment: .leading, spacing: 10) {
            InkSectionHeader("Synopsis", eyebrow: "About")
            VStack(alignment: .leading, spacing: 8) {
                Text(vm.description.isEmpty ? "No synopsis available." : vm.description)
                    .font(.body)
                    .foregroundStyle(Ink.secondary)
                    .lineSpacing(3)
                    .lineLimit(synopsisExpanded ? nil : 4)

                // Only offer the toggle when the text is long enough to clip.
                if vm.description.count > 220 {
                    Button {
                        withAnimation(.snappy(duration: 0.22)) { synopsisExpanded.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Text(synopsisExpanded ? "Show less" : "Show more")
                            Image(systemName: synopsisExpanded ? "chevron.up" : "chevron.down")
                        }
                        .font(.inkMono(11, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(Ink.seal)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Gutter.page)
        }
    }

    // MARK: Chapters

    private var chapters: some View {
        VStack(alignment: .leading, spacing: 12) {
            InkSectionHeader("Chapters", eyebrow: "\(vm.chapters.count) available")

            if let error = vm.errorMessage, vm.chapters.isEmpty {
                InkNotice(error)
                    .padding(.horizontal, Gutter.page)
            } else if vm.chapters.isEmpty {
                Text(vm.isLoading ? "Loading chapters…" : "No chapters yet.")
                    .font(.footnote)
                    .foregroundStyle(Ink.tertiary)
                    .padding(.horizontal, Gutter.page)
            } else {
                VStack(spacing: 0) {
                    ForEach(vm.chapters) { chapter in
                        NavigationLink {
                            ReaderView(chapterId: chapter.id)
                        } label: {
                            chapterRow(chapter)
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(Ink.hairline)
                            .padding(.leading, Gutter.page)
                    }
                }
            }
        }
    }

    private func chapterRow(_ chapter: Chapter) -> some View {
        HStack(spacing: 14) {
            // Monospaced chapter stamp, like a spine number.
            Text("CH·\(chapter.number)")
                .font(.inkMono(12, weight: .semibold))
                .foregroundStyle(Ink.seal)
                .frame(minWidth: 62, alignment: .leading)

            Text(chapter.title?.isEmpty == false ? chapter.title! : "Chapter \(chapter.number)")
                .font(.subheadline)
                .foregroundStyle(Ink.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Ink.tertiary)
        }
        .padding(.horizontal, Gutter.page)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
