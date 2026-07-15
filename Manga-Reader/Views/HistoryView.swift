//
//  HistoryView.swift
//  Manga-Reader
//
//  The "History" tab: a reverse-chronological log of chapters read, grouped by
//  day. Tapping a row reopens that exact chapter and page.
//

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var history: HistoryStore

    var body: some View {
        NavigationStack {
            Group {
                if history.entries.isEmpty {
                    InkEmptyState(
                        symbol: "clock.arrow.circlepath",
                        title: "No reading history",
                        message: "Chapters you read will appear here so you can pick up where you left off."
                    )
                } else {
                    List {
                        ForEach(groupedEntries, id: \.key) { group in
                            Section(group.key) {
                                ForEach(group.value) { entry in
                                    row(entry)
                                }
                                .onDelete { offsets in delete(in: group.value, at: offsets) }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Ink.background)
            .navigationTitle("History")
            .toolbar {
                if !history.entries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear", role: .destructive) { history.clear() }
                            .foregroundStyle(Ink.seal)
                    }
                }
            }
        }
    }

    private func row(_ entry: ReadingEntry) -> some View {
        NavigationLink {
            ReaderView(manga: entry.asManga, chapter: entry.asChapter, initialPage: entry.page)
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: entry.coverURL) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: CoverPlaceholder()
                    }
                }
                .frame(width: 44, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Ink.hairline, lineWidth: 1))

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.mangaTitle)
                        .font(.system(.subheadline, design: .serif).weight(.semibold))
                        .foregroundStyle(Ink.primary)
                        .lineLimit(1)
                    Text("CH·\(entry.chapterNumber) · page \(entry.page + 1)/\(max(entry.pageCount, entry.page + 1))")
                        .font(.inkMono(11, weight: .medium))
                        .foregroundStyle(Ink.seal)
                    Text(entry.updatedAt.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(Ink.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Ink.background)
    }

    /// Entries grouped by relative day, preserving recency order of groups.
    private var groupedEntries: [(key: String, value: [ReadingEntry])] {
        var order: [String] = []
        var buckets: [String: [ReadingEntry]] = [:]
        for entry in history.entries {
            let key = Self.dayLabel(entry.updatedAt)
            if buckets[key] == nil { buckets[key] = []; order.append(key) }
            buckets[key]?.append(entry)
        }
        return order.map { ($0, buckets[$0]!) }
    }

    private static func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month().day().year())
    }

    private func delete(in group: [ReadingEntry], at offsets: IndexSet) {
        for index in offsets { history.delete(group[index]) }
    }
}

private extension ReadingEntry {
    var asManga: Manga {
        Manga(id: mangaId, sourceId: sourceId ?? MangaDexSource.sourceID, title: mangaTitle, description: "", status: "unknown", year: nil, coverURL: coverURL)
    }
    var asChapter: Chapter {
        Chapter(id: chapterId, number: chapterNumber, title: nil)
    }
}

#Preview {
    HistoryView().environmentObject(HistoryStore())
}
