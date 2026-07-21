# MyAnimeList Read-Only Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a read-only MyAnimeList API client (`Models/MyAnimeListAPI.swift`) that can search manga by title and fetch a manga's detail — including related manga and recommendations — plus a throwaway debug screen to verify it against the real API.

**Architecture:** A namespace struct mirroring `MangaDexAPI`'s existing shape (static async methods over a private generic `request<T: Decodable>` helper), reading a MAL Client ID out of the app's Info.plist (sourced from a gitignored `Secrets.xcconfig`) and sending it as an `X-MAL-CLIENT-ID` header. No shared code with `MangaDexAPI` — the auth header and error type genuinely differ.

**Tech Stack:** Swift, Foundation (`URLSession`, `Codable`), SwiftUI (debug screen only), XCTest.

Full design context: `docs/superpowers/specs/2026-07-20-mal-client-design.md`.

## Global Constraints

- No third-party dependencies — pure SwiftUI + Foundation (project-wide rule).
- iOS 17.5+ deployment target.
- `Secrets.xcconfig` must never be committed to git — it's already gitignored; do not
  remove it from `.gitignore` and never paste the actual Client ID value into any file
  that gets committed (including this plan or its task outputs).
- Testing convention for this project: unit-test decode/pure logic; verify live
  behavior manually. There is no network-mocking harness for `MangaDexAPI` and this
  client follows the same split — no live-network stub tests.
- `Models/` and `Services/` are Xcode synchronized root groups (new files auto-compile,
  no `project.pbxproj` edits needed). `Views/` is **not** synchronized — new files there
  need manual `PBXFileReference` / `PBXBuildFile` / group / Sources-phase edits.
- No iPhone 16 simulator is installed on this machine — every `xcodebuild` command must
  target **iPhone 17** and pass `-parallel-testing-enabled NO` (parallel test clones
  slow this machine badly; one simulator, run serially).

---

### Task 1: Wire `Secrets.xcconfig` into the Xcode build settings

**Files:**
- Modify: `Manga-Reader.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: an Info.plist key `MALClientID`, readable at runtime via
  `Bundle.main.object(forInfoDictionaryKey: "MALClientID") as? String`. Task 3's
  `MyAnimeListAPI.request` depends on this key existing.

- [ ] **Step 1: Add a `PBXFileReference` for `Secrets.xcconfig`**

In `Manga-Reader.xcodeproj/project.pbxproj`, find the end of the `PBXFileReference`
section:

```
		ADEF83D32E8F32B300CF2434 /* SettingsView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SettingsView.swift; sourceTree = "<group>"; };
/* End PBXFileReference section */
```

Replace with:

```
		ADEF83D32E8F32B300CF2434 /* SettingsView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SettingsView.swift; sourceTree = "<group>"; };
		AD1157092EA0000300CF2434 /* Secrets.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Secrets.xcconfig; sourceTree = "<group>"; };
/* End PBXFileReference section */
```

- [ ] **Step 2: Add it to the top-level project group so it's visible in Xcode**

Find:

```
		ADE549182C0A9CCA007AE172 = {
			isa = PBXGroup;
			children = (
				ADE549232C0A9CCA007AE172 /* Manga-Reader */,
				ADE549342C0A9CCD007AE172 /* Manga-ReaderTests */,
				ADE5493E2C0A9CCD007AE172 /* Manga-ReaderUITests */,
				ADE549222C0A9CCA007AE172 /* Products */,
			);
			sourceTree = "<group>";
		};
```

Replace with:

```
		ADE549182C0A9CCA007AE172 = {
			isa = PBXGroup;
			children = (
				ADE549232C0A9CCA007AE172 /* Manga-Reader */,
				AD1157092EA0000300CF2434 /* Secrets.xcconfig */,
				ADE549342C0A9CCD007AE172 /* Manga-ReaderTests */,
				ADE5493E2C0A9CCD007AE172 /* Manga-ReaderUITests */,
				ADE549222C0A9CCA007AE172 /* Products */,
			);
			sourceTree = "<group>";
		};
```

- [ ] **Step 3: Point the app target's Debug config at `Secrets.xcconfig` and add the Info.plist key**

Find the block starting with `ADE549462C0A9CCD007AE172 /* Debug */ = {` (this is the
**app target's** Debug config — confirm by checking it contains
`ASSETCATALOG_COMPILER_APPICON_NAME`, not `BUNDLE_LOADER`):

```
		ADE549462C0A9CCD007AE172 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_ASSET_PATHS = "\"Manga-Reader/Preview Content\"";
				DEVELOPMENT_TEAM = V2BG9SHQYS;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = "Elias-Magdaleno.Manga-Reader";
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Debug;
		};
```

Replace with (adds `baseConfigurationReference` and `INFOPLIST_KEY_MALClientID`):

```
		ADE549462C0A9CCD007AE172 /* Debug */ = {
			isa = XCBuildConfiguration;
			baseConfigurationReference = AD1157092EA0000300CF2434 /* Secrets.xcconfig */;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_ASSET_PATHS = "\"Manga-Reader/Preview Content\"";
				DEVELOPMENT_TEAM = V2BG9SHQYS;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_MALClientID = "$(MAL_CLIENT_ID)";
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = "Elias-Magdaleno.Manga-Reader";
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Debug;
		};
```

- [ ] **Step 4: Do the same for the Release config**

Find the block starting with `ADE549472C0A9CCD007AE172 /* Release */ = {` (the app
target's Release config — same field set as Debug above, `name = Release;`) and apply
the identical two additions: `baseConfigurationReference = AD1157092EA0000300CF2434 /* Secrets.xcconfig */;`
right after `isa = XCBuildConfiguration;`, and
`INFOPLIST_KEY_MALClientID = "$(MAL_CLIENT_ID)";` inside `buildSettings`, alongside the
other `INFOPLIST_KEY_*` entries.

- [ ] **Step 5: Verify the build settings resolve correctly**

Run:

```bash
xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Verify the Info.plist key actually made it into the built app**

```bash
BUILT_APP=$(find ~/Library/Developer/Xcode/DerivedData -type d -name "Manga-Reader.app" \
  -path "*Debug-iphonesimulator*" -print -quit)
/usr/libexec/PlistBuddy -c "Print :MALClientID" "$BUILT_APP/Info.plist"
```

Expected: prints a non-empty string matching the value in your local
`Secrets.xcconfig` (do not paste the actual value anywhere it could get committed —
just confirm it's non-empty and matches).

- [ ] **Step 7: Confirm `Secrets.xcconfig` is still untracked by git**

```bash
git status --short
git check-ignore -v Secrets.xcconfig
```

Expected: `git status` shows no `Secrets.xcconfig` entry; `check-ignore` prints the
`.gitignore` rule matching it.

- [ ] **Step 8: Commit**

```bash
git add Manga-Reader.xcodeproj/project.pbxproj
git commit -m "Wire Secrets.xcconfig into build settings for MAL_CLIENT_ID"
```

---

### Task 2: MAL DTOs + error type, with fixture-decode tests

**Files:**
- Create: `Manga-Reader/Models/MyAnimeListAPI.swift`
- Test: `Manga-ReaderTests/Manga_ReaderTests.swift` (append methods to the
  `Manga_ReaderTests` class, immediately before its closing `}` — currently the last
  line of the file)

**Interfaces:**
- Consumes: nothing.
- Produces (for Task 3 to build networking on top of, and for the debug screen to
  render): `MyAnimeListManga` (`id: Int`, `title: String`, `mainPicture:
  MainPicture?`), `MyAnimeListMangaDetail` (`id`, `title`, `synopsis: String?`,
  `mainPicture`, `genres: [Genre]?`, `relatedManga: [Relation]?`, `recommendations:
  [Recommendation]?`), `MyAnimeListSearchResponse` (`data: [Entry]`, `Entry.node:
  MyAnimeListManga`), `MyAnimeListError` (`.missingClientID`, `.invalidURL`,
  `.invalidResponse`, `.httpStatus(Int)`, `.rateLimited`).

Note: the design spec sketched the search wrapper as a `private struct SearchResponse`.
It's declared **internal** here (`MyAnimeListSearchResponse`, no `private`) instead —
`@testable import` only elevates `internal` symbols to test-visible, never `private`
ones across files, and the whole point of this task is a decode test that exercises the
`node`-unwrapping. Everything else matches the spec as designed.

- [ ] **Step 1: Write the failing decode tests**

Append to `Manga-ReaderTests/Manga_ReaderTests.swift`, right before the class's final
closing `}`:

```swift
    // MARK: - MyAnimeListAPI DTOs

    func testMyAnimeListSearchResponseDecodesAndUnwrapsNode() throws {
        let json = """
        {
          "data": [
            {
              "node": {
                "id": 2,
                "title": "Berserk",
                "main_picture": {
                  "medium": "https://example.com/berserk_m.jpg",
                  "large": "https://example.com/berserk_l.jpg"
                }
              }
            },
            {
              "node": { "id": 401, "title": "Berserk: The Prototype" }
            }
          ]
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(MyAnimeListSearchResponse.self, from: json)
        XCTAssertEqual(response.data.map(\.node.id), [2, 401])
        XCTAssertEqual(response.data[0].node.title, "Berserk")
        XCTAssertEqual(response.data[0].node.mainPicture?.medium,
                       "https://example.com/berserk_m.jpg")
        XCTAssertNil(response.data[1].node.mainPicture)
    }

    func testMyAnimeListMangaDetailDecodesRelatedAndRecommendations() throws {
        let json = """
        {
          "id": 2,
          "title": "Berserk",
          "synopsis": "Guts, a former mercenary...",
          "main_picture": {
            "medium": "https://example.com/berserk_m.jpg",
            "large": "https://example.com/berserk_l.jpg"
          },
          "genres": [
            {"id": 1, "name": "Action"},
            {"id": 8, "name": "Drama"}
          ],
          "related_manga": [
            {
              "node": {"id": 401, "title": "Berserk: The Prototype"},
              "relation_type": "prequel",
              "relation_type_formatted": "Prequel"
            }
          ],
          "recommendations": [
            {
              "node": {"id": 656, "title": "Vagabond"},
              "num_recommendations": 42
            }
          ]
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let detail = try decoder.decode(MyAnimeListMangaDetail.self, from: json)
        XCTAssertEqual(detail.title, "Berserk")
        XCTAssertEqual(detail.genres?.map(\.name), ["Action", "Drama"])
        XCTAssertEqual(detail.relatedManga?.first?.node.title, "Berserk: The Prototype")
        XCTAssertEqual(detail.relatedManga?.first?.relationTypeFormatted, "Prequel")
        XCTAssertEqual(detail.recommendations?.first?.node.title, "Vagabond")
        XCTAssertEqual(detail.recommendations?.first?.numRecommendations, 42)
    }

    func testMyAnimeListMangaDetailDecodesWithoutOptionalRelations() throws {
        let json = """
        {
          "id": 977,
          "title": "One-Off Oneshot",
          "synopsis": null,
          "main_picture": null,
          "genres": null
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let detail = try decoder.decode(MyAnimeListMangaDetail.self, from: json)
        XCTAssertEqual(detail.id, 977)
        XCTAssertEqual(detail.title, "One-Off Oneshot")
        XCTAssertNil(detail.synopsis)
        XCTAssertNil(detail.genres)
        XCTAssertNil(detail.relatedManga)
        XCTAssertNil(detail.recommendations)
    }

    func testMyAnimeListErrorDescriptions() {
        XCTAssertEqual(MyAnimeListError.missingClientID.errorDescription,
                       "Missing MyAnimeList API client ID. Set MAL_CLIENT_ID in Secrets.xcconfig.")
        XCTAssertEqual(MyAnimeListError.httpStatus(404).errorDescription,
                       "MyAnimeList request failed with HTTP status 404.")
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO test \
  -only-testing:Manga-ReaderTests/Manga_ReaderTests/testMyAnimeListErrorDescriptions
```

Expected: **build failure** — `MyAnimeListManga`/`MyAnimeListMangaDetail`/
`MyAnimeListSearchResponse`/`MyAnimeListError` are not defined yet.

- [ ] **Step 3: Create `Manga-Reader/Models/MyAnimeListAPI.swift` with the DTOs and error type**

```swift
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
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO test \
  -only-testing:Manga-ReaderTests/Manga_ReaderTests/testMyAnimeListSearchResponseDecodesAndUnwrapsNode \
  -only-testing:Manga-ReaderTests/Manga_ReaderTests/testMyAnimeListMangaDetailDecodesRelatedAndRecommendations \
  -only-testing:Manga-ReaderTests/Manga_ReaderTests/testMyAnimeListMangaDetailDecodesWithoutOptionalRelations \
  -only-testing:Manga-ReaderTests/Manga_ReaderTests/testMyAnimeListErrorDescriptions
```

Expected: `** TEST SUCCEEDED **`, all four tests pass.

- [ ] **Step 5: Commit**

```bash
git add Manga-Reader/Models/MyAnimeListAPI.swift Manga-ReaderTests/Manga_ReaderTests.swift
git commit -m "Add MyAnimeList DTOs + error type with fixture-decode tests"
```

---

### Task 3: `MyAnimeListAPI` networking + temporary debug screen

**Files:**
- Modify: `Manga-Reader/Models/MyAnimeListAPI.swift`
- Create: `Manga-Reader/Views/MyAnimeListDebugView.swift`
- Modify: `Manga-Reader/Views/SettingsView.swift`
- Modify: `Manga-Reader.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `MyAnimeListManga`, `MyAnimeListMangaDetail`, `MyAnimeListSearchResponse`,
  `MyAnimeListError` from Task 2.
- Produces: `MyAnimeListAPI.searchManga(title: String, limit: Int = 10) async throws ->
  [MyAnimeListManga]` and `MyAnimeListAPI.mangaDetail(id: Int) async throws ->
  MyAnimeListMangaDetail` — the two methods entity resolution (a future spec) will call.

No new automated tests in this task: per the Global Constraints, this codebase has no
network-mocking harness, so the networking layer's correctness is verified live through
the debug screen below — that live run *is* this task's test cycle.

- [ ] **Step 1: Add networking methods to `Models/MyAnimeListAPI.swift`**

Append inside a new `struct MyAnimeListAPI { ... }` at the bottom of the file (after the
DTOs from Task 2):

```swift
struct MyAnimeListAPI {                              // Namespace-style struct for static helpers.
    static let baseURL = "https://api.myanimelist.net/v2"

    /// Shared decoder (snake_case → camelCase), same strategy as MangaDexAPI's.
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    /// Search MAL by title. What cross-source entity resolution will call for sources
    /// with no direct MAL id (MangaDex usually has one already via external links).
    static func searchManga(title: String, limit: Int = 10) async throws -> [MyAnimeListManga] {
        let response: MyAnimeListSearchResponse = try await request(
            path: "/manga",
            queryItems: [
                URLQueryItem(name: "q", value: title),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "fields", value: "alternative_titles,main_picture"),
            ]
        )
        return response.data.map(\.node)
    }

    /// Fetch a manga's detail by MAL id, including the two fields a future
    /// "More Like This" UI will consume: related manga and recommendations.
    static func mangaDetail(id: Int) async throws -> MyAnimeListMangaDetail {
        try await request(
            path: "/manga/\(id)",
            queryItems: [
                URLQueryItem(name: "fields",
                             value: "alternative_titles,synopsis,main_picture,genres,related_manga,recommendations"),
            ]
        )
    }

    /// Generic GET + JSON decode helper for MAL endpoints.
    /// - Note: MAL is known to soft rate-limit (HTTP 429). On a 429 we retry once,
    ///         honoring the `Retry-After` header, before giving up — same behavior as
    ///         MangaDexAPI.request.
    private static func request<T: Decodable>(path: String,
                                               queryItems: [URLQueryItem]) async throws -> T {
        guard var comps = URLComponents(string: baseURL + path) else {
            throw MyAnimeListError.invalidURL
        }
        comps.queryItems = queryItems
        guard let url = comps.url else {
            throw MyAnimeListError.invalidURL
        }
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "MALClientID") as? String,
              !clientID.isEmpty else {
            throw MyAnimeListError.missingClientID
        }
        var req = URLRequest(url: url)
        req.setValue(clientID, forHTTPHeaderField: "X-MAL-CLIENT-ID")

        for attempt in 0..<2 {                                   // Initial try + one retry on 429.
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw MyAnimeListError.invalidResponse
            }
            if http.statusCode == 429, attempt == 0 {
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 1
                try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
                continue
            }
            guard (200...299).contains(http.statusCode) else {
                throw MyAnimeListError.httpStatus(http.statusCode)
            }
            return try decoder.decode(T.self, from: data)
        }
        throw MyAnimeListError.rateLimited
    }
}
```

- [ ] **Step 2: Build to confirm the networking code compiles**

```bash
xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Create the throwaway debug screen**

Create `Manga-Reader/Views/MyAnimeListDebugView.swift`:

```swift
//
//  MyAnimeListDebugView.swift
//  Manga-Reader
//
//  Throwaway verification screen for the read-only MAL client. Delete once the real
//  "More Like This" UI (a later spec) ships.
//

import SwiftUI

struct MyAnimeListDebugView: View {
    @State private var query = ""
    @State private var results: [MyAnimeListManga] = []
    @State private var detail: MyAnimeListMangaDetail?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        List {
            Section("Search") {
                TextField("Title", text: $query)
                    .onSubmit { search() }
                Button("Search") { search() }
                    .disabled(query.isEmpty || isLoading)
            }

            if let errorMessage {
                Section("Error") {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }

            if !results.isEmpty {
                Section("Results") {
                    ForEach(results, id: \.id) { manga in
                        Button(manga.title) { loadDetail(id: manga.id) }
                    }
                }
            }

            if let detail {
                Section("Detail") {
                    Text(detail.title).font(.headline)
                    if let synopsis = detail.synopsis {
                        Text(synopsis).font(.footnote)
                    }
                    if let genres = detail.genres, !genres.isEmpty {
                        Text("Genres: " + genres.map(\.name).joined(separator: ", "))
                            .font(.footnote)
                    }
                    if let related = detail.relatedManga, !related.isEmpty {
                        Text("Related").font(.subheadline.bold())
                        ForEach(related, id: \.node.id) { rel in
                            Text("\(rel.relationTypeFormatted): \(rel.node.title)")
                                .font(.footnote)
                        }
                    }
                    if let recs = detail.recommendations, !recs.isEmpty {
                        Text("Recommendations").font(.subheadline.bold())
                        ForEach(recs, id: \.node.id) { rec in
                            Text("\(rec.node.title) (\(rec.numRecommendations))")
                                .font(.footnote)
                        }
                    }
                }
            }
        }
        .navigationTitle("MAL Debug")
    }

    private func search() {
        errorMessage = nil
        detail = nil
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                results = try await MyAnimeListAPI.searchManga(title: query)
            } catch {
                errorMessage = error.localizedDescription
                results = []
            }
        }
    }

    private func loadDetail(id: Int) {
        errorMessage = nil
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                detail = try await MyAnimeListAPI.mangaDetail(id: id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack { MyAnimeListDebugView() }
}
```

- [ ] **Step 4: Add a `#if DEBUG` row in Settings to reach it**

In `Manga-Reader/Views/SettingsView.swift`, find the "About" section block and the
outer `VStack`'s closing brace right after it:

```swift
                    VStack(alignment: .leading, spacing: 14) {
                        InkSectionHeader("About", eyebrow: "Info")
                        VStack(spacing: 0) {
                            aboutRow("Sources", registry.sources.map(\.name).joined(separator: " · "))
                            Divider().overlay(Ink.hairline).padding(.leading, Gutter.page)
                            aboutRow("Version", "0.1 · WIP")
                        }
                        .background(RoundedRectangle(cornerRadius: 14).fill(Ink.surface))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Ink.hairline, lineWidth: 1))
                        .padding(.horizontal, Gutter.page)
                    }
                }
                .padding(.top, 4)
```

Replace with:

```swift
                    VStack(alignment: .leading, spacing: 14) {
                        InkSectionHeader("About", eyebrow: "Info")
                        VStack(spacing: 0) {
                            aboutRow("Sources", registry.sources.map(\.name).joined(separator: " · "))
                            Divider().overlay(Ink.hairline).padding(.leading, Gutter.page)
                            aboutRow("Version", "0.1 · WIP")
                        }
                        .background(RoundedRectangle(cornerRadius: 14).fill(Ink.surface))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Ink.hairline, lineWidth: 1))
                        .padding(.horizontal, Gutter.page)
                    }

                    #if DEBUG
                    VStack(alignment: .leading, spacing: 14) {
                        InkSectionHeader("Debug", eyebrow: "Dev")
                        NavigationLink("MyAnimeList Client") {
                            MyAnimeListDebugView()
                        }
                        .font(.subheadline)
                        .foregroundStyle(Ink.primary)
                        .padding(.horizontal, Gutter.page)
                        .padding(.vertical, 15)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Ink.surface))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Ink.hairline, lineWidth: 1))
                        .padding(.horizontal, Gutter.page)
                    }
                    #endif
                }
                .padding(.top, 4)
```

- [ ] **Step 5: Add the new Views file to `project.pbxproj` (four sections)**

`Views/` is not a synchronized group, so this file needs manual wiring — mirror the
existing `HistoryView.swift` entries exactly.

**(a) PBXBuildFile** — find:

```
		AD1157092EA0000200CF2434 /* HistoryView.swift in Sources */ = {isa = PBXBuildFile; fileRef = AD1157092EA0000100CF2434 /* HistoryView.swift */; };
```

Add immediately after it:

```
		AD1157092EA0000500CF2434 /* MyAnimeListDebugView.swift in Sources */ = {isa = PBXBuildFile; fileRef = AD1157092EA0000400CF2434 /* MyAnimeListDebugView.swift */; };
```

**(b) PBXFileReference** — find:

```
		AD1157092EA0000100CF2434 /* HistoryView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = HistoryView.swift; sourceTree = "<group>"; };
```

Add immediately after it:

```
		AD1157092EA0000400CF2434 /* MyAnimeListDebugView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MyAnimeListDebugView.swift; sourceTree = "<group>"; };
```

**(c) PBXGroup (Views children)** — find:

```
		ADEF83D52E8F375100CF2434 /* Views */ = {
			isa = PBXGroup;
			children = (
				ADDACC8B2EC6AC2D0026FBAE /* MangaDetailView.swift */,
				ADDACC9A2EC6AC2D0026FBAE /* ReaderView.swift */,
				AD2219972E98A7D600F0EC25 /* Components */,
				ADEF83D12E8F32A500CF2434 /* SearchView.swift */,
				ADEF83D32E8F32B300CF2434 /* SettingsView.swift */,
				ADEF83CF2E8F329200CF2434 /* BookmarksView.swift */,
				ADEF83CD2E8F323700CF2434 /* HomeView.swift */,
				AD1157092EA0000100CF2434 /* HistoryView.swift */,
				ADCA7E102EC7000100CF2434 /* CategoryGridView.swift */,
			);
			path = Views;
			sourceTree = "<group>";
		};
```

Replace with:

```
		ADEF83D52E8F375100CF2434 /* Views */ = {
			isa = PBXGroup;
			children = (
				ADDACC8B2EC6AC2D0026FBAE /* MangaDetailView.swift */,
				ADDACC9A2EC6AC2D0026FBAE /* ReaderView.swift */,
				AD2219972E98A7D600F0EC25 /* Components */,
				ADEF83D12E8F32A500CF2434 /* SearchView.swift */,
				ADEF83D32E8F32B300CF2434 /* SettingsView.swift */,
				ADEF83CF2E8F329200CF2434 /* BookmarksView.swift */,
				ADEF83CD2E8F323700CF2434 /* HomeView.swift */,
				AD1157092EA0000100CF2434 /* HistoryView.swift */,
				ADCA7E102EC7000100CF2434 /* CategoryGridView.swift */,
				AD1157092EA0000400CF2434 /* MyAnimeListDebugView.swift */,
			);
			path = Views;
			sourceTree = "<group>";
		};
```

**(d) PBXSourcesBuildPhase (app target's Sources)** — find:

```
		ADE5491D2C0A9CCA007AE172 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				ADEF83D22E8F32A500CF2434 /* SearchView.swift in Sources */,
				ADEF83CE2E8F323700CF2434 /* HomeView.swift in Sources */,
				ADE549272C0A9CCA007AE172 /* ContentView.swift in Sources */,
				ADEF83D42E8F32B300CF2434 /* SettingsView.swift in Sources */,
				ADEF83D02E8F329200CF2434 /* BookmarksView.swift in Sources */,
				ADE549252C0A9CCA007AE172 /* Manga_ReaderApp.swift in Sources */,
				ADDACC8C2EC6AC370026FBAE /* MangaDetailView.swift in Sources */,
				ADDACC9B2EC6AC370026FBAE /* ReaderView.swift in Sources */,
				AD1157092EA0000200CF2434 /* HistoryView.swift in Sources */,
				ADCA7E112EC7000100CF2434 /* CategoryGridView.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

Replace with:

```
		ADE5491D2C0A9CCA007AE172 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				ADEF83D22E8F32A500CF2434 /* SearchView.swift in Sources */,
				ADEF83CE2E8F323700CF2434 /* HomeView.swift in Sources */,
				ADE549272C0A9CCA007AE172 /* ContentView.swift in Sources */,
				ADEF83D42E8F32B300CF2434 /* SettingsView.swift in Sources */,
				ADEF83D02E8F329200CF2434 /* BookmarksView.swift in Sources */,
				ADE549252C0A9CCA007AE172 /* Manga_ReaderApp.swift in Sources */,
				ADDACC8C2EC6AC370026FBAE /* MangaDetailView.swift in Sources */,
				ADDACC9B2EC6AC370026FBAE /* ReaderView.swift in Sources */,
				AD1157092EA0000200CF2434 /* HistoryView.swift in Sources */,
				ADCA7E112EC7000100CF2434 /* CategoryGridView.swift in Sources */,
				AD1157092EA0000500CF2434 /* MyAnimeListDebugView.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

- [ ] **Step 6: Build for the simulator**

```bash
xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Live-verify against the real MyAnimeList API**

1. Run the app on the iPhone 17 simulator (from Xcode, or `xcrun simctl install` +
   `launch` the built app from Step 6's `DerivedData` path).
2. Go to Settings → the new "Debug" section → "MyAnimeList Client".
3. Type a well-known title (e.g. "One Piece") and tap Search.
4. Confirm results render with titles (proves `searchManga` + the `node`-unwrapping
   works against the live API, not just fixtures).
5. Tap a result. Confirm the Detail section renders synopsis/genres, and — this is the
   important part — **Related** and/or **Recommendations** subsections render with
   titles and non-zero recommendation counts (proves the real API's `related_manga` and
   `recommendations` fields match the DTO shape from Task 2, which "More Like This"
   will depend on later).
6. If anything renders as an error instead, read the message: `.missingClientID` means
   Task 1's build-setting wiring didn't take effect (rebuild); an HTTP status error
   means either the Client ID is wrong or MAL's commercial-app approval hasn't cleared
   yet.

- [ ] **Step 8: Commit**

```bash
git add Manga-Reader/Models/MyAnimeListAPI.swift Manga-Reader/Views/MyAnimeListDebugView.swift \
  Manga-Reader/Views/SettingsView.swift Manga-Reader.xcodeproj/project.pbxproj
git commit -m "Add MAL networking + throwaway debug screen for live verification"
```

---

## Explicitly out of scope for this plan

Matches the design spec's deferrals: cross-source entity resolution, the "More Like
This" UI and extending the recommendation engine past MangaDex, MAL OAuth/list-tracking,
and the Paperback/Aidoku-style extension system. None of those are touched here.
