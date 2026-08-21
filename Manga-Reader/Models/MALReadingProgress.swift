//
//  MALReadingProgress.swift
//  Manga-Reader
//
//  Converts source chapter labels into MyAnimeList's integer progress value.
//

import Foundation

struct ChapterCompletion {
    let manga: Manga
    let chapter: Chapter
    let workID: WorkID
    let progress: Int
    let completedAt: Date
}

enum MALChapterProgress {
    static func map(chapterNumber: String) -> Int? {
        let label = chapterNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = label.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              !parts[0].isEmpty,
              parts[0].allSatisfy(\.isNumber),
              parts.count == 1 || (!parts[1].isEmpty && parts[1].allSatisfy(\.isNumber)),
              let progress = Int(parts[0]),
              progress > 0 else { return nil }
        return progress
    }
}
