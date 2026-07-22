//
//  ChapterRow.swift
//  Manga-Reader
//
//  One chapter row, shared by the detail-page preview and the full ChapterListView.
//  Reads read/progress state from HistoryStore. `selecting` shows the selection circle
//  (and hides the trailing chevron); `selected` fills it.
//

import SwiftUI

struct ChapterRow: View {
    let chapter: Chapter
    var selecting: Bool = false
    var selected: Bool = false
    @EnvironmentObject private var history: HistoryStore

    var body: some View {
        // Show a resume marker only while a chapter is genuinely mid-read; that
        // chapter stays highlighted (your current spot). Finished/opened
        // chapters that aren't mid-read are dimmed.
        let progress = history.entry(forChapter: chapter.id)
        let inProgress = progress.map { $0.pageCount > 0 && $0.page < $0.pageCount - 1 } ?? false
        let dimmed = history.isRead(chapterId: chapter.id) && !inProgress

        return HStack(spacing: 14) {
            if selecting {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(selected ? Ink.seal : Ink.tertiary)
            }

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
                } else if let date = chapter.date {
                    Text(date.formatted(.dateTime.month().day().year()))
                        .font(.inkMono(11, weight: .medium))
                        .foregroundStyle(dimmed ? Ink.tertiary : Ink.secondary)
                }
            }

            Spacer(minLength: 8)

            if !selecting {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Ink.tertiary)
            }
        }
        .padding(.horizontal, Gutter.page)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
