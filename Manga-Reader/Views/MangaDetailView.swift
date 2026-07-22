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
    @EnvironmentObject private var tasteProfile: TasteProfileStore
    @StateObject private var moreLikeThis = MoreLikeThisViewModel()
    @State private var synopsisExpanded = false
    @State private var chaptersDescending = true
    @State private var isSelecting = false
    @State private var selectedChapterIDs: Set<String> = []
    @State private var showingWebPage = false

    init(manga: Manga) {
        self.manga = manga
        _vm = StateObject(wrappedValue: MangaDetailViewModel(manga: manga))
    }

    /// The registered source this manga came from (nil if its source was unregistered).
    private var mangaSource: MangaSource? {
        SourceRegistry.shared.source(id: manga.sourceId)
    }

    private var mangaWebURL: URL? {
        mangaSource?.webURL(forManga: manga.id)
    }

    /// This manga's source when it can browse by genre — otherwise nil, so the genre
    /// chips render as plain, non-tappable metadata.
    private var tagBrowseSource: MangaSource? {
        guard let mangaSource, mangaSource.supportsTagBrowse else { return nil }
        return mangaSource
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Gutter.section) {
                hero
                actionRow
                if !vm.tags.isEmpty { tags }
                if !vm.description.isEmpty || vm.isLoading { description }
                chapters
                if !moreLikeThis.items.isEmpty { moreLikeThisRail }
            }
            .padding(.bottom, 40)
        }
        .background(Ink.background)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.load() }
        .task { await moreLikeThis.load(for: manga) }
        .onChange(of: vm.detailTags) { _, tags in
            guard manga.sourceId == "mangadex", !tags.isEmpty else { return }
            tasteProfile.recordTags(mangaId: manga.id, tags: tags)
        }
        // Hide the tab bar while selecting so the bottom-bar batch actions
        // (Select All / Mark Read / Mark Unread) aren't obscured behind it.
        .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
        .toolbar {
            if isSelecting {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button(allChaptersSelected ? "Deselect All" : "Select All") {
                        withAnimation(.snappy(duration: 0.2)) {
                            selectedChapterIDs = allChaptersSelected ? [] : Set(vm.chapters.map(\.id))
                        }
                    }
                    Spacer()
                    Button("Mark Unread") { markSelected(read: false) }
                        .disabled(selectedChapterIDs.isEmpty)
                    Button("Mark Read") { markSelected(read: true) }
                        .disabled(selectedChapterIDs.isEmpty)
                        .fontWeight(.semibold)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let url = mangaWebURL {
                    Button {
                        showingWebPage = true
                    } label: {
                        Image(systemName: "safari")
                    }
                    .accessibilityLabel("Open on \(mangaSource?.name ?? "web")")
                    .sheet(isPresented: $showingWebPage) {
                        SafariView(url: url)
                            .ignoresSafeArea()
                    }
                }
            }
        }
    }

    // MARK: Hero — cover plate on flat paper: title, authors, metadata stamps.

    private var hero: some View {
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
            .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 8) {
                Text(manga.title)
                    .font(.inkDisplay(26))
                    .foregroundStyle(Ink.primary)
                    .lineLimit(4)
                    .minimumScaleFactor(0.6)

                if !vm.authors.isEmpty {
                    Text(vm.authors.joined(separator: " · "))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Ink.seal)
                        .lineLimit(2)
                }

                // Source first — "where is this from" leads the stamp row.
                // The scroll area escapes the trailing page margin so chips run
                // to the screen edge, matching the genre row below.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        SourceStamp(sourceID: manga.sourceId,
                                    name: mangaSource?.name ?? manga.sourceId)
                        if let year = manga.year {
                            InkStamp(text: String(year))
                        }
                        InkStamp(text: manga.status.uppercased())
                        if let rating = vm.contentRating, !rating.isEmpty {
                            InkStamp(text: rating.uppercased(), tinted: true)
                        }
                    }
                    .padding(.trailing, Gutter.page)
                }
                .padding(.trailing, -Gutter.page)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Gutter.page)
        .padding(.top, 12)
    }

    // MARK: Actions — one primary (Continue), one compact library toggle.

    @ViewBuilder private var actionRow: some View {
        let entry = history.latestEntry(forManga: manga.id)
        let action = resumeAction(entry: entry, chapters: vm.chapters)
        HStack(spacing: 10) {
            if let action {
                continueLink(action, progress: continueProgress(action: action, entry: entry))
                libraryToggle
            } else if vm.isLoading {
                // Chapters still loading — placeholder keeps the layout stable.
                HStack(spacing: 8) {
                    ProgressView().tint(Ink.seal)
                    Text("Start Reading")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(Ink.tertiary)
                .background(RoundedRectangle(cornerRadius: 12).fill(Ink.sealSoft.opacity(0.5)))
                libraryToggle
            } else {
                // No readable chapters — the library toggle gets its words back.
                Button {
                    withAnimation(.snappy(duration: 0.2)) { library.toggle(manga) }
                } label: {
                    let inLibrary = library.contains(manga.id)
                    HStack(spacing: 8) {
                        Image(systemName: inLibrary ? "bookmark.fill" : "bookmark")
                        Text(inLibrary ? "In Library" : "Add to Library")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(inLibrary ? Ink.seal : Color.white)
                    .background(RoundedRectangle(cornerRadius: 12).fill(inLibrary ? Ink.sealSoft : Ink.seal))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Gutter.page)
    }

    /// The reader's furthest progress through the resume chapter, 0...1, or nil
    /// when the action isn't a mid-chapter continue.
    private func continueProgress(action: ResumeAction, entry: ReadingEntry?) -> Double? {
        guard case .cont(_, let page) = action,
              let entry, entry.pageCount > 0 else { return nil }
        return min(1, Double(page + 1) / Double(entry.pageCount))
    }

    private func continueLink(_ action: ResumeAction, progress: Double?) -> some View {
        NavigationLink {
            ReaderView(manga: manga, chapter: action.chapter, initialPage: action.startPage)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Ink.seal)

                // A thin ink-fill rule showing how far into the chapter you are.
                if let progress {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.white.opacity(0.18))
                            .overlay(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.9))
                                    .frame(width: geo.size.width * progress)
                            }
                            .frame(height: 2)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }

                // Centered label with a start marker; the page stamp rides inline.
                HStack(spacing: 7) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(action.label)
                        .lineLimit(1)
                    if case .cont(_, let page) = action {
                        Text("· p.\(page + 1)")
                            .font(.inkMono(11, weight: .semibold))
                            .opacity(0.85)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var libraryToggle: some View {
        let inLibrary = library.contains(manga.id)
        return Button {
            withAnimation(.snappy(duration: 0.2)) { library.toggle(manga) }
        } label: {
            Image(systemName: inLibrary ? "bookmark.fill" : "bookmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Ink.seal)
                .frame(width: 50, height: 50)
                .background(RoundedRectangle(cornerRadius: 12).fill(inLibrary ? Ink.sealSoft : Ink.surface))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(inLibrary ? Ink.seal : Ink.hairline, lineWidth: inLibrary ? 1.5 : 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(inLibrary ? "Remove from Library" : "Add to Library")
    }

    // MARK: Tags

    private var tags: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.tags, id: \.self) { tag in
                    if let source = tagBrowseSource {
                        NavigationLink {
                            CategoryGridView(title: tag, pagedFetch: { limit, offset in
                                try await source.mangaByTag(tag: tag, limit: limit, offset: offset)
                            })
                        } label: {
                            chip(tag, interactive: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Browse \(tag)")
                    } else {
                        chip(tag, interactive: false)
                    }
                }
            }
            .padding(.horizontal, Gutter.page)
        }
    }

    /// A single genre chip. Interactive chips (source supports tag browse) read as
    /// tappable in the seal voice; plain chips are quiet metadata. Mono + uppercase
    /// keeps every chip the same height regardless of the tag's length.
    @ViewBuilder
    private func chip(_ tag: String, interactive: Bool) -> some View {
        Text(tag.uppercased())
            .font(.inkMono(10, weight: .medium))
            .tracking(0.5)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(interactive ? Ink.seal : Ink.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(interactive ? Ink.sealSoft : Ink.surface))
            .overlay(Capsule().strokeBorder(interactive ? Ink.seal : Ink.hairline, lineWidth: 1))
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

    // MARK: More Like This — MAL-sourced cross-source recommendations, bottom of page.

    private var moreLikeThisRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            InkSectionHeader("More Like This", eyebrow: "Similar titles")
            MangaRail(items: moreLikeThis.items)
        }
        .accessibilityIdentifier("moreLikeThisSection")
    }

    // MARK: Chapters

    private var chapters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                InkSectionHeader("Chapters", eyebrow: "\(vm.chapters.count) available")
                Spacer()
                if isSelecting {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            isSelecting = false
                            selectedChapterIDs.removeAll()
                        }
                    } label: {
                        Text("CANCEL")
                            .font(.inkMono(11, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(Ink.seal)
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 16) {
                        if !vm.chapters.isEmpty {
                            Button {
                                withAnimation(.snappy(duration: 0.2)) { isSelecting = true }
                            } label: {
                                Text("SELECT")
                                    .font(.inkMono(11, weight: .semibold))
                                    .tracking(0.5)
                                    .foregroundStyle(Ink.seal)
                            }
                            .buttonStyle(.plain)
                        }
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
                    }
                }
            }
            .padding(.trailing, Gutter.page)

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
                        if isSelecting {
                            Button {
                                toggleSelection(chapter.id)
                            } label: {
                                ChapterRow(chapter: chapter, selecting: true,
                                           selected: selectedChapterIDs.contains(chapter.id))
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink {
                                ReaderView(manga: manga, chapter: chapter)
                            } label: {
                                ChapterRow(chapter: chapter)
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
                        }
                        Divider().overlay(Ink.hairline)
                            .padding(.leading, Gutter.page)
                    }
                }
            }
        }
    }

    private var allChaptersSelected: Bool {
        !vm.chapters.isEmpty && selectedChapterIDs.count == vm.chapters.count
    }

    private func toggleSelection(_ id: String) {
        if selectedChapterIDs.contains(id) {
            selectedChapterIDs.remove(id)
        } else {
            selectedChapterIDs.insert(id)
        }
    }

    private func markSelected(read: Bool) {
        let chapters = vm.chapters.filter { selectedChapterIDs.contains($0.id) }
        if read {
            history.markRead(manga: manga, chapters: chapters)
        } else {
            history.markUnread(manga: manga, chapters: chapters)
        }
        withAnimation(.snappy(duration: 0.2)) {
            isSelecting = false
            selectedChapterIDs.removeAll()
        }
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
        case .cont(let c, _):        return "Continue · Ch \(c.number)"
        case .next(let c):           return "Start Ch \(c.number)"
        case .reread(let c, _):      return "Read Again · Ch \(c.number)"
        }
    }
}
