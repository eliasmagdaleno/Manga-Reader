//
//  MangaDexAPI.swift
//  Manga-Reader
//
//  Created by Elias Magdaleno on 10/8/25.
//

import Foundation

// MARK: - Public Types (used by Views / ViewModels)

/// A lightweight representation of a manga item that ALWAYS carries a cover URL if available.
struct Manga: Identifiable {                        // Conform to Identifiable so SwiftUI lists work nicely.
    let id: String                                  // The MangaDex UUID for the manga.
    let title: String                               // Display title (prefer English; fallback to first available).
    let description: String                         // Short description (English if available).
    let status: String                              // e.g., ongoing, completed (may be "unknown").
    let year: Int?                                  // Optional year of publication.
    let coverURL: URL?                              // ✅ Pre-built cover URL (nil if none).
}

/// A small item representing “latest updates” (which chapter just arrived for a manga).
struct MangaUpdate: Identifiable {                  // Helper type for Latest Updates rails.
    let id: String                                  // Use `chapterId` as unique ID for the update item.
    let chapterId: String                           // The chapter we’ll open for reading.
    let manga: Manga                                // The associated manga (with cover).
    var title: String { manga.title }               // Convenience for UI bindings.
    init(chapterId: String, manga: Manga) {         // Convenience initializer for clarity.
        self.id = chapterId
        self.chapterId = chapterId
        self.manga = manga
    }
}

// MARK: - Internal API Plumbing

/// Sizes for the cover image helper (MangaDex serves 256/512 JPEG variants automatically).
enum CoverSize {                                    // Choose which resolution to use for thumbnails.
    case w256                                       // 256px wide JPEG.
    case w512                                       // 512px wide JPEG (good default for cards).
    case original                                   // Original upload (larger; avoid for grids).
}

/// Relationship object used by MangaDex to attach related resources (e.g. cover_art).
struct MDRelationship: Decodable {                  // Decode relationship entries from API.
    let id: String                                  // Related object ID (e.g., cover_art id).
    let type: String                                // Relationship type (e.g., "cover_art", "author").
    let attributes: MDCoverAttributes?              // Attributes; for cover_art we care about fileName.
}

/// Attributes that appear on a cover_art relationship.
struct MDCoverAttributes: Decodable {               // Decode the nested attributes for cover_art.
    let fileName: String?                           // Actual file name on uploads (e.g., "abcd123.png").
}

/// Top-level list response for /manga.
struct MangaListResponse: Decodable {               // Decode array-style responses.
    let data: [MangaData]                           // The list of manga entries.
}

/// One manga item from /manga (with attributes + relationships).
struct MangaData: Decodable {                       // Represents a single manga entry in list responses.
    let id: String                                  // Manga ID.
    let attributes: MangaAttributes                 // Title/description/etc.
    let relationships: [MDRelationship]?            // ✅ Includes cover_art when requested via includes[].
}

/// Raw attributes for a manga from the API.
struct MangaAttributes: Decodable {                 // Raw payload we convert into our Manga struct.
    let title: [String: String]                     // Title in multiple locales; e.g., ["en": "Name"].
    let description: [String: String]?              // Optional descriptions per locale.
    let status: String?                             // Ongoing/Completed/etc. (may be missing).
    let year: Int?                                  // Optional publication year.

    /// Converts API attributes into our app’s `Manga` while attaching a prebuilt cover URL.
    /// - Parameters:
    ///   - id: The manga ID (UUID string).
    ///   - relationships: Relationship array to locate cover_art.fileName.
    func toManga(id: String, relationships: [MDRelationship]?) -> Manga {
        // 1) Prefer English title; if missing, fallback to any available locale; or "Unknown".
        let resolvedTitle = title["en"] ?? title.values.first ?? "Unknown"
        // 2) Prefer English description; fallback to empty string if none.
        let resolvedDescription = description?["en"] ?? ""
        // 3) Resolve status (fallback to "unknown" for consistency).
        let resolvedStatus = status ?? "unknown"
        // 4) Try to extract the cover filename from relationships (type == "cover_art").
        let fileName = relationships?
            .first(where: { $0.type == "cover_art" && $0.attributes?.fileName != nil })?
            .attributes?.fileName
        // 5) Build a thumbnail URL (512px) if we found a filename; otherwise nil.
        let cover = fileName.flatMap { mangaCoverURL(mangaId: id, fileName: $0, size: .w512) }
        // 6) Produce our finalized Manga value with the pre-attached cover URL.
        return Manga(
            id: id,
            title: resolvedTitle,
            description: resolvedDescription,
            status: resolvedStatus,
            year: year,
            coverURL: cover
        )
    }
}

// MARK: - Chapter payloads (used for Latest Updates and reading)

/// Top-level list response for /chapter.
struct ChapterListResponse: Decodable {             // Decode list of chapters.
    let data: [ChapterData]                         // The array of chapter entries.
    let total: Int                                  // Total matching chapters (for pagination).
}

/// One chapter entry from /chapter (we only parse what we need).
struct ChapterData: Decodable {                     // Represents a single chapter in list responses.
    let id: String                                  // Chapter ID.
    let attributes: ChapterAttributes               // Time/number/title/etc.
    let relationships: [MDRelationship]?            // Include "manga" relation if requested.
}

/// Raw attributes for a chapter (we focus on timing + metadata).
struct ChapterAttributes: Decodable {               // Minimal set for sorting/filters.
    let chapter: String?                            // Chapter number as string (may be nil).
    let title: String?                              // Optional chapter title.
    let translatedLanguage: String?                 // e.g., "en".
    let publishAt: String?                          // Publish timestamp as ISO string.
    let readableAt: String?                         // Readable timestamp (often used for sorting).
}

// MARK: - Reading (at-home) payloads

/// Response for /at-home/server/{chapterId}.
struct AtHomeServer: Decodable {                    // Needed to build page image URLs.
    let baseUrl: String                             // Temporary base URL for this chapter’s images.
}

/// Chapter pages data (hash + file names).
struct ChapterPagesResponse: Decodable {            // Holds base + chapter payload to build image URLs.
    let baseUrl: String                             // Base host to prepend.
    let chapter: ChapterPagesData                   // Hash + file arrays.
}

/// Nested chapter images payload (full vs data-saver).
struct ChapterPagesData: Decodable {                // The per-chapter arrays of image file names.
    let hash: String                                // Folder component for this chapter on the CDN.
    let data: [String]                              // Full-quality image files.
    let dataSaver: [String]                         // Reduced-size image files.
}

// MARK: - Detail + Chapter domain types (used by MangaDetailView / MangaDetailViewModel)

/// A single readable chapter for the detail screen's chapter list.
struct Chapter: Identifiable, Equatable {           // Identifiable so SwiftUI ForEach works directly.
    let id: String                                  // Chapter UUID (used to open the reader).
    let number: String                              // Chapter number as displayed (e.g., "12").
    let title: String?                              // Optional chapter title.
}

extension ChapterAttributes {                       // Convert raw chapter attributes → domain `Chapter`.
    /// Builds a `Chapter` from decoded attributes plus the chapter id from its container.
    func toChapter(id: String) -> Chapter {
        Chapter(id: id, number: chapter ?? "?", title: title)
    }
}

/// Enriched manga metadata shown on the detail screen.
struct MangaDetail {                                // Plain value type consumed by the detail view model.
    let description: String                         // English description (falls back to any locale).
    let authors: [String]                           // Author + artist names (deduped, order preserved).
    let tags: [String]                              // Genre/theme tag names (English preferred).
}

// MARK: - Detail wire types (/manga/{id})

/// Top-level response for the single-manga endpoint `/manga/{id}`.
struct MangaDetailResponse: Decodable {             // Object (not array) response wrapper.
    let data: MangaDetailData                       // The single manga payload.

    /// Converts the raw API payload into our `MangaDetail` domain value.
    func toDomain() -> MangaDetail {
        let attrs = data.attributes
        // Prefer English description; fall back to any locale; else empty.
        let description = attrs.description?["en"] ?? attrs.description?.values.first ?? ""
        // Collect author + artist names from relationships, dedupe while preserving order.
        var seen = Set<String>()
        let authors = (data.relationships ?? [])
            .filter { $0.type == "author" || $0.type == "artist" }
            .compactMap { $0.attributes?.name }
            .filter { seen.insert($0).inserted }
        // Resolve each tag's name (English preferred, else first available locale).
        let tags = (attrs.tags ?? []).compactMap { $0.attributes.name["en"] ?? $0.attributes.name.values.first }
        return MangaDetail(description: description, authors: authors, tags: tags)
    }
}

/// The single manga object inside a detail response.
struct MangaDetailData: Decodable {                 // Mirrors `MangaData` but with tags + author names.
    let id: String                                  // Manga ID.
    let attributes: MangaDetailAttributes           // Title/description/tags.
    let relationships: [MDDetailRelationship]?      // author/artist relations (names) when included.
}

/// Attributes for the detail endpoint (adds `tags` on top of the basic fields).
struct MangaDetailAttributes: Decodable {           // Detail-specific attribute payload.
    let title: [String: String]                     // Localized titles.
    let description: [String: String]?              // Localized descriptions.
    let tags: [MDTag]?                              // Genre/theme tags.
}

/// A MangaDex tag entry with a localized name.
struct MDTag: Decodable {                            // Wraps a tag's attributes.
    let attributes: MDTagAttributes                 // Holds the localized name dictionary.
}

/// Localized name payload for a tag.
struct MDTagAttributes: Decodable {                 // e.g., name == ["en": "Action"].
    let name: [String: String]                      // Tag name per locale.
}

/// Relationship on the detail endpoint that can carry an author/artist name.
struct MDDetailRelationship: Decodable {            // Separate from `MDRelationship` (which carries cover attrs).
    let id: String                                  // Related object ID.
    let type: String                                // e.g., "author", "artist".
    let attributes: MDAuthorAttributes?             // Author/artist attributes (name).
}

/// Attributes carrying an author/artist display name.
struct MDAuthorAttributes: Decodable {              // Decoded when includes[]=author/artist is requested.
    let name: String?                               // Person's display name.
}

// MARK: - Core API Client

/// Errors surfaced by the MangaDex client. `LocalizedError` so `errorMessage`
/// bindings show something meaningful instead of a generic URLError string.
enum MangaDexError: LocalizedError {
    case invalidURL                                 // Could not build a request URL.
    case invalidResponse                            // Response was not an HTTPURLResponse.
    case httpStatus(Int)                            // Non-2xx status (carries the code).
    case rateLimited                                // Still 429 after retrying.

    var errorDescription: String? {
        switch self {
        case .invalidURL:            return "Could not build a valid request URL."
        case .invalidResponse:       return "The server returned an unexpected response."
        case .httpStatus(let code):  return "Request failed with HTTP status \(code)."
        case .rateLimited:           return "Too many requests. Please try again in a moment."
        }
    }
}

struct MangaDexAPI {                                // Namespace-style struct for static helpers.
    static let baseURL = "https://api.mangadex.org" // Base REST API URL.

    /// Shared decoder (snake_case → camelCase). Reused across requests so we don't
    /// re-allocate a decoder and re-set its strategy on every call.
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    /// Generic GET + JSON decode helper for MangaDex endpoints.
    /// - Parameters:
    ///   - endpoint: Path beginning with '/', e.g., "/manga".
    ///   - queryItems: Optional query parameters.
    /// - Returns: Decoded value of type T.
    /// - Note: MangaDex rate-limits aggressively (HTTP 429). On a 429 we retry once,
    ///         honoring the `Retry-After` header, before giving up.
    static func request<T: Decodable>(endpoint: String,
                                      queryItems: [URLQueryItem]? = nil) async throws -> T {
        guard var comps = URLComponents(string: baseURL + endpoint) else {
            throw MangaDexError.invalidURL                       // Malformed base + path.
        }
        comps.queryItems = queryItems                           // Attach query parameters if provided.
        guard let url = comps.url else {                        // Ensure we produced a valid URL.
            throw MangaDexError.invalidURL                      // Throw if URL is malformed.
        }
        var req = URLRequest(url: url)                          // Create a URLRequest for custom headers.
        req.setValue("MangaReader-iOS/1.0 (https://github.com/eliasmagdaleno/Manga-Reader)",
                     forHTTPHeaderField: "User-Agent")          // Identify the client to the API.

        for attempt in 0..<2 {                                   // Initial try + one retry on 429.
            let (data, resp) = try await URLSession.shared.data(for: req) // Perform async GET request.
            guard let http = resp as? HTTPURLResponse else {    // Expect an HTTP response.
                throw MangaDexError.invalidResponse
            }
            if http.statusCode == 429, attempt == 0 {           // Rate limited: back off and retry once.
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 1
                try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
                continue
            }
            guard (200...299).contains(http.statusCode) else {  // Validate we got a 2xx response.
                throw MangaDexError.httpStatus(http.statusCode) // Surface the actual status code.
            }
            return try decoder.decode(T.self, from: data)       // Decode into the requested generic type.
        }
        throw MangaDexError.rateLimited                          // Both attempts hit the rate limit.
    }

    /// Maps a `/manga` list response into domain `Manga` values (cover URL attached).
    private static func mangaList(from res: MangaListResponse) -> [Manga] {
        res.data.map { $0.attributes.toManga(id: $0.id, relationships: $0.relationships) }
    }

    // MARK: - High-level API: Manga Lists (ALWAYS with covers)

    // NOTE: Every /manga query below injects `includes[]=cover_art` so that the resulting `Manga`
    //       instances always have `coverURL` filled in (when available).

    /// Searches manga by title and returns `Manga` items carrying `coverURL`.
    static func searchManga(title: String, limit: Int = 20, offset: Int = 0) async throws -> [Manga] {
        // Build our query: search by title, include cover_art, and paginate.
        let items = [
            URLQueryItem(name: "title", value: title),              // Search term.
            URLQueryItem(name: "includes[]", value: "cover_art"),   // ✅ Ask for cover relationships.
            URLQueryItem(name: "limit", value: String(limit)),      // Page size.
            URLQueryItem(name: "offset", value: String(offset))     // Skip for pagination.
        ]
        // Call /manga and decode the list response.
        let res: MangaListResponse = try await MangaDexAPI.request(endpoint: "/manga", queryItems: items)
        // Map raw entries → our `Manga` model with coverURL already attached.
        return mangaList(from: res)
    }

    /// Fetches newly created manga (Newest first) with cover URLs.
    static func fetchNewTitles(limit: Int = 20, offset: Int = 0) async throws -> [Manga] {
        let items = [
            URLQueryItem(name: "order[createdAt]", value: "desc"),  // Sort by newest creation date.
            URLQueryItem(name: "includes[]", value: "cover_art"),   // ✅ Include cover data.
            URLQueryItem(name: "limit", value: String(limit)),      // Page size.
            URLQueryItem(name: "offset", value: String(offset))     // Pagination offset.
        ]
        let res: MangaListResponse = try await MangaDexAPI.request(endpoint: "/manga", queryItems: items)
        return mangaList(from: res)
    }

    /// Fetches highly-rated manga (Popular approximation) with cover URLs.
    static func fetchPopular(limit: Int = 20, offset: Int = 0) async throws -> [Manga] {
        let items = [
            URLQueryItem(name: "order[rating]", value: "desc"),     // Sort by rating, highest first.
            URLQueryItem(name: "includes[]", value: "cover_art"),   // Include cover data.
            URLQueryItem(name: "limit", value: String(limit)),      // Page size.
            URLQueryItem(name: "offset", value: String(offset))     // Pagination offset.
        ]
        let res: MangaListResponse = try await MangaDexAPI.request(endpoint: "/manga", queryItems: items)
        return mangaList(from: res)
    }

    // MARK: - Latest Updates (chapters → enriched manga with covers)

    /// Fetches latest chapter uploads, then enriches to unique manga (with covers) for a rail.
    /// Returns a list of `MangaUpdate` items you can show on your homepage.
    /// - Parameters:
    ///   - limitTitles: How many unique manga to return.
    ///   - translatedLang: Filter chapters by language (e.g., "en").
    /// - Note: This does a two-step process:
    ///         1) Get recent chapters with `includes[]=manga`
    ///         2) Batch-fetch the unique manga by IDs with `includes[]=cover_art`
    static func fetchLatestUpdates(limitTitles: Int = 20,
                                   translatedLang: String = "en") async throws -> [MangaUpdate] {
        // 1) Ask for latest chapters, newest readable first, including manga relationship.
        let items = [
            URLQueryItem(name: "includes[]", value: "manga"),       // Include "manga" relation on chapters.
            URLQueryItem(name: "translatedLanguage[]", value: translatedLang), // Filter by language.
            URLQueryItem(name: "order[readableAt]", value: "desc"), // Newest updates first.
            URLQueryItem(name: "limit", value: "100")               // Fetch enough to dedupe.
        ]
        let chapters: ChapterListResponse = try await MangaDexAPI.request(endpoint: "/chapter", queryItems: items)

        // 2) Collect the first (newest) chapter for each unique manga ID.
        var uniqueMangaOrder: [String] = []                          // Preserve order of first-seen manga IDs.
        var newestChapterForManga: [String: String] = [:]            // Map mangaId → chapterId.
        for ch in chapters.data {                                    // Iterate newest → older.
            // Find related manga ID in relationships for this chapter.
            guard let mangaId = ch.relationships?.first(where: { $0.type == "manga" })?.id else { continue }
            // If we haven't seen this manga before, record the chapter and keep order.
            if newestChapterForManga[mangaId] == nil {
                newestChapterForManga[mangaId] = ch.id               // Save the newest chapter for this manga.
                uniqueMangaOrder.append(mangaId)                     // Remember appearance order.
                if uniqueMangaOrder.count >= limitTitles { break }   // Stop once we have enough unique manga.
            }
        }

        // 3) Enrich: fetch those manga by IDs WITH cover_art so we can build proper `Manga` objects.
        //    MangaDex supports querying multiple IDs using repeated ids[] parameters.
        let enriched = try await fetchMangaByIdsWithCovers(ids: uniqueMangaOrder)

        // 4) Build `MangaUpdate` list by pairing each enriched manga with its recorded chapterId.
        let updates: [MangaUpdate] = enriched.compactMap { manga in  // Map over enriched manga.
            guard let chId = newestChapterForManga[manga.id] else { return nil } // Find its newest chapter id.
            return MangaUpdate(chapterId: chId, manga: manga)        // Produce the update item.
        }

        return updates                                               // Return updates ready for UI.
    }

    /// Helper: batch-fetches manga by IDs with cover_art included, returning `Manga` with coverURL.
    /// - Parameter ids: Array of manga UUID strings (max 100 recommended per call).
    private static func fetchMangaByIdsWithCovers(ids: [String]) async throws -> [Manga] {
        // Build repeated ids[] query parameters along with includes[]=cover_art.
        var items: [URLQueryItem] = [URLQueryItem(name: "includes[]", value: "cover_art")] // Ask for covers.
        ids.forEach { items.append(URLQueryItem(name: "ids[]", value: $0)) }               // Add each id.
        // Call /manga with our multi-id query.
        let res: MangaListResponse = try await MangaDexAPI.request(endpoint: "/manga", queryItems: items)
        // Convert to `Manga` with coverURL attached via toManga(...).
        return mangaList(from: res)
    }
    
    static func fetchMangaDetails(id: String) async throws -> MangaDetail {
        let res: MangaDetailResponse = try await request(endpoint: "/manga/\(id)",queryItems: [
            URLQueryItem(name: "includes[]", value: "author"),
            URLQueryItem(name: "includes[]", value: "artist")
            ]
                                                         )
        return res.toDomain()
                                                         
            
    }
    
    static func fetchChapters(mangaId: String) async throws -> [Chapter] {
        // The /chapter endpoint caps `limit` at 100, so page through with offset
        // until we've collected every English chapter (guarded by a safety cap).
        let pageSize = 100
        let maxChapters = 2000
        var raw: [ChapterData] = []
        var offset = 0
        while offset < maxChapters {
            let res: ChapterListResponse = try await request(endpoint: "/chapter", queryItems: [
                URLQueryItem(name: "manga", value: mangaId),
                URLQueryItem(name: "translatedLanguage[]", value: "en"),
                URLQueryItem(name: "order[chapter]", value: "asc"),
                URLQueryItem(name: "limit", value: String(pageSize)),
                URLQueryItem(name: "offset", value: String(offset))
            ])
            raw += res.data
            offset += pageSize
            if res.data.isEmpty || offset >= res.total { break }
        }
        // Multiple scanlation groups often upload the same chapter number. Keep the
        // first occurrence of each number (unknown-numbered chapters are never merged).
        var seenNumbers = Set<String>()
        return raw
            .map { $0.attributes.toChapter(id: $0.id) }
            .filter { $0.number == "?" || seenNumbers.insert($0.number).inserted }
    }
        

    // MARK: - Reading: build page URLs for a chapter

    /// Builds the per-page image URLs for a chapter using the At-Home server.
    /// - Parameters:
    ///   - chapterId: The target chapter’s ID.
    ///   - useDataSaver: Whether to prefer data-saver images (smaller).
    /// - Returns: Array of URLs (as `URL`) you can feed to `AsyncImage`.
    static func pageURLs(for chapterId: String, useDataSaver: Bool = true) async throws -> [URL] {
        // 1) Get at-home base URL and the data/dataSaver file arrays.
        let atHome: ChapterPagesResponse = try await MangaDexAPI.request(endpoint: "/at-home/server/\(chapterId)")
        // 2) Pick the array based on data-saver preference.
        let files = useDataSaver ? atHome.chapter.dataSaver : atHome.chapter.data
        // 3) Compose each full URL: {baseUrl}/{mode}/{hash}/{file}
        let mode = useDataSaver ? "data-saver" : "data"
        let base = atHome.baseUrl
        let hash = atHome.chapter.hash
        // 4) Map file names → URL objects, dropping any malformed ones with compactMap.
        return files.compactMap { URL(string: "\(base)/\(mode)/\(hash)/\($0)") }
    }
    
    
}

// MARK: - Image URL helpers

/// Builds the canonical cover URL on uploads.mangadex.org for a given manga + filename.
/// - Parameters:
///   - mangaId: The manga’s UUID.
///   - fileName: The cover image file name from the API (e.g., "abcd123.png").
///   - size: Desired variant (256/512/original).
/// - Returns: A URL you can pass to `AsyncImage`.
func mangaCoverURL(mangaId: String, fileName: String, size: CoverSize = .w512) -> URL? {
    let base = "https://uploads.mangadex.org/covers"            // Static covers host.
    switch size {                                               // Choose variant suffix.
    case .w256:
        return URL(string: "\(base)/\(mangaId)/\(fileName).256.jpg") // 256px JPEG.
    case .w512:
        return URL(string: "\(base)/\(mangaId)/\(fileName).512.jpg") // 512px JPEG.
    case .original:
        return URL(string: "\(base)/\(mangaId)/\(fileName)")         // Original upload (PNG/JPG).
    }
}
