//
//  MangaSource.swift
//  Manga-Reader
//
//  The source-abstraction seam. Everything the app does to browse and read manga
//  goes through a `MangaSource`, not a concrete API. MangaDex is source #1
//  (`MangaDexSource`); more sources plug in by conforming to this protocol.
//
//  Designed to be BRIDGE-FRIENDLY: every parameter is an `Int`/`String` and every
//  return value is a value/Codable domain type, with no Swift-only constructs crossing
//  the source boundary. This keeps the door open for a future dynamic-extension runtime
//  (JS/WASM) whose sources could conform to the same contract via a bridge.
//

import Foundation

/// A browsable, readable manga source (MangaDex, and later others).
protocol MangaSource {
    /// Stable identifier persisted in `Manga.sourceId` and `SourceRegistry` (e.g. "mangadex").
    var id: String { get }
    /// Human-readable name for pickers/UI (e.g. "MangaDex").
    var name: String { get }
    /// Whether this source serves adult content. Gated behind a Settings toggle.
    var isNSFW: Bool { get }

    /// Search the source by title. Results carry `coverURL` and `sourceId`.
    func search(title: String, limit: Int, offset: Int) async throws -> [Manga]
    /// A "popular" browse feed (rating-ordered on MangaDex).
    func popular(limit: Int, offset: Int) async throws -> [Manga]
    /// A "newest titles" browse feed (creation-ordered on MangaDex). Optional capability.
    func newTitles(limit: Int, offset: Int) async throws -> [Manga]
    /// A "latest updates" feed (recent chapters → unique manga). Optional capability.
    func latestUpdates(limitTitles: Int, language: String) async throws -> [MangaUpdate]
    /// Enriched metadata for a single manga.
    func mangaDetail(id: String) async throws -> MangaDetail
    /// The readable chapter list for a manga.
    func chapters(mangaId: String) async throws -> [Chapter]
    /// The per-page image URLs for a chapter.
    func pageURLs(chapterId: String, preferDataSaver: Bool) async throws -> [URL]
}

/// Errors common to the source layer (distinct from a source's own transport errors).
enum SourceError: LocalizedError {
    /// The source does not implement an optional capability (carries the capability name).
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let capability):
            return "This source doesn't support \(capability)."
        }
    }
}

// MARK: - Optional capabilities

/// Default implementations for feed methods a source may not offer. A source that lacks
/// a "new titles" or "latest updates" feed simply doesn't implement these and callers get
/// a clear `SourceError.unsupported` instead of a crash. MangaDex overrides all of them.
extension MangaSource {
    var isNSFW: Bool { false }

    func newTitles(limit: Int, offset: Int) async throws -> [Manga] {
        throw SourceError.unsupported("newTitles")
    }

    func latestUpdates(limitTitles: Int, language: String) async throws -> [MangaUpdate] {
        throw SourceError.unsupported("latestUpdates")
    }
}
