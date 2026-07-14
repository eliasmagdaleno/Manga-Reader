//
//  MangaDetailView.swift
//  Manga-Reader
//

import SwiftUI

struct MangaDetailView: View {
    let manga: Manga
    @StateObject private var vm: MangaDetailViewModel
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var history: HistoryStore
    @State private var synopsisExpanded = false
    @State private var chaptersDescending = true

    init(manga: Manga) {
        self.manga = manga
        _vm = StateObject(wrappedValue: MangaDetailViewModel(manga: manga))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Gutter.section) {
                hero
                libraryButton
                resumeButton
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
                        if let rating = vm.contentRating, !rating.isEmpty {
                            InkStamp(text: rating.uppercased(), tinted: true)
                        }
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
                Image(systemName: inLibrary ? "bookmark.fill" : "bookmark")
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

    // MARK: Resume / Continue reading

    @ViewBuilder private var resumeButton: some View {
        if let action = resumeAction(entry: history.latestEntry(forManga: manga.id),
                                     chapters: vm.chapters) {
            NavigationLink {
                ReaderView(manga: manga, chapter: action.chapter, initialPage: action.startPage)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "book.pages")
                    Text(action.label)
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(Ink.seal)
                .background(RoundedRectangle(cornerRadius: 12).fill(Ink.sealSoft))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Ink.seal, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Gutter.page)
        } else if vm.isLoading {
            // Chapters still loading — show a disabled placeholder so layout is stable.
            HStack(spacing: 8) {
                ProgressView().tint(Ink.seal)
                Text("Start Reading")
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(Ink.tertiary)
            .background(RoundedRectangle(cornerRadius: 12).fill(Ink.sealSoft.opacity(0.5)))
            .padding(.horizontal, Gutter.page)
        }
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
            HStack {
                InkSectionHeader("Chapters", eyebrow: "\(vm.chapters.count) available")
                Spacer()
                Button {
                    withAnimation(.snappy(duration: 0.2)) { chaptersDescending.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(chaptersDescending ? "NEWEST" : "OLDEST")
                    }
                    .font(.inkMono(11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Ink.seal)
                }
                .buttonStyle(.plain)
                .padding(.trailing, Gutter.page)
            }

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
                    ForEach(sortChapters(vm.chapters, descending: chaptersDescending)) { chapter in
                        NavigationLink {
                            ReaderView(manga: manga, chapter: chapter)
                        } label: {
                            chapterRow(chapter)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            let read = history.isRead(chapterId: chapter.id)
                            Button {
                                history.toggleRead(manga: manga, chapter: chapter)
                            } label: {
                                Label(read ? "Mark as unread" : "Mark as read",
                                      systemImage: read ? "circle" : "checkmark.circle")
                            }
                        }
                        Divider().overlay(Ink.hairline)
                            .padding(.leading, Gutter.page)
                    }
                }
            }
        }
    }

    private func chapterRow(_ chapter: Chapter) -> some View {
        // Show a resume marker only while a chapter is genuinely mid-read; that
        // chapter stays highlighted (your current spot). Finished/opened
        // chapters that aren't mid-read are dimmed.
        let progress = history.entry(forChapter: chapter.id)
        let inProgress = progress.map { $0.pageCount > 0 && $0.page < $0.pageCount - 1 } ?? false
        let dimmed = history.isRead(chapterId: chapter.id) && !inProgress

        return HStack(spacing: 14) {
            // Monospaced chapter stamp, like a spine number.
            Text("CH·\(chapter.number)")
                .font(.inkMono(12, weight: .semibold))
                .foregroundStyle(dimmed ? Ink.tertiary : Ink.seal)
                .frame(minWidth: 62, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(chapter.title?.isEmpty == false ? chapter.title! : "Chapter \(chapter.number)")
                    .font(.subheadline)
                    .foregroundStyle(dimmed ? Ink.tertiary : Ink.primary)
                    .lineLimit(1)

                if inProgress, let p = progress {
                    Text("Page: \(p.page + 1)")
                        .font(.inkMono(11, weight: .semibold))
                        .foregroundStyle(Ink.seal)
                }
            }

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

private extension ResumeAction {
    var chapter: Chapter {
        switch self {
        case .start(let c), .next(let c), .cont(let c, _), .reread(let c, _): return c
        }
    }
    var startPage: Int {
        switch self {
        case .start, .next, .reread: return 0
        case .cont(_, let p): return p
        }
    }
    var label: String {
        switch self {
        case .start:                 return "Start Reading"
        case .cont(let c, let p):    return "Continue Ch \(c.number) · p.\(p + 1)"
        case .next(let c):           return "Start Ch \(c.number)"
        case .reread(let c, _):      return "Read Again · Ch \(c.number)"
        }
    }
}
