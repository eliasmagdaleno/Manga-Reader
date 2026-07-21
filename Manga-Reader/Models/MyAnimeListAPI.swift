//
//  MyAnimeListAPI.swift
//  Manga-Reader
//

import Foundation

/// Errors surfaced by the MyAnimeList client. `LocalizedError` so `errorMessage`
/// bindings show something meaningful instead of a generic URLError string.
enum MyAnimeListError: LocalizedError {
    case missingClientID                            // MAL_CLIENT_ID not set (Secrets.xcconfig).
    case invalidURL                                 // Could not build a request URL.
    case invalidResponse                            // Response was not an HTTPURLResponse.
    case httpStatus(Int)                            // Non-2xx status (carries the code).
    case rateLimited                                // Still 429 after retrying.

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Missing MyAnimeList API client ID. Set MAL_CLIENT_ID in Secrets.xcconfig."
        case .invalidURL:
            return "Could not build a valid MyAnimeList request URL."
        case .invalidResponse:
            return "MyAnimeList returned an unexpected response."
        case .httpStatus(let code):
            return "MyAnimeList request failed with HTTP status \(code)."
        case .rateLimited:
            return "Too many MyAnimeList requests. Please try again in a moment."
        }
    }
}

struct MyAnimeListManga: Decodable {
    let id: Int
    let title: String
    let mainPicture: MainPicture?

    struct MainPicture: Decodable {
        let medium: String?
        let large: String?
    }
}

struct MyAnimeListMangaDetail: Decodable {
    let id: Int
    let title: String
    let synopsis: String?
    let mainPicture: MyAnimeListManga.MainPicture?
    let genres: [Genre]?
    let relatedManga: [Relation]?
    let recommendations: [Recommendation]?

    struct Genre: Decodable {
        let id: Int
        let name: String
    }

    struct Relation: Decodable {
        let node: MyAnimeListManga
        let relationType: String
        let relationTypeFormatted: String
    }

    struct Recommendation: Decodable {
        let node: MyAnimeListManga
        let numRecommendations: Int
    }
}

/// MAL wraps referenced manga in a `{node: {...}}` envelope for search results.
/// Internal (not private): the decode test in Manga_ReaderTests exercises this
/// unwrapping directly via `@testable import`, which only elevates `internal` symbols.
struct MyAnimeListSearchResponse: Decodable {
    struct Entry: Decodable {
        let node: MyAnimeListManga
    }
    let data: [Entry]
}
