# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Native SwiftUI iOS app (a MangaDex reader client). No third-party dependencies or
package manager — pure SwiftUI + Foundation. Xcode project only (no SPM/CocoaPods).

- Scheme / target: `Manga-Reader`
- Deployment target: iOS 17.5 (some UI branches on `#available(iOS 18.0, *)`)
- Test targets: `Manga-ReaderTests` (unit), `Manga-ReaderUITests` (UI)

## Code Review & AI Sync

After every commit, a git hook runs an automated code review using Google Antigravity (agy). 
The output of this code review is saved to `.agy_code_review.md`. 
**Claude**: Always read `.agy_code_review.md` when starting a new session or after a commit to stay in the loop regarding recent changes, errors, and architectural notes.

## Commands

Build for simulator (adjust the device name to one from `xcrun simctl list devices`):

```sh
xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Run all tests:

```sh
xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Run a single test class or method (Swift Testing / XCTest via `xcodebuild`):

```sh
xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 16' \
  test -only-testing:Manga-ReaderTests/Manga_ReaderTests/<testMethod>
```

For interactive work, opening `Manga-Reader.xcodeproj` in Xcode and using ⌘B / ⌘U is
usually faster than the CLI.

## Architecture

MVVM over a source-abstraction layer. Data flows: `MangaSource` (protocol, network) →
`@MainActor` `ObservableObject` view models → SwiftUI views. Nothing outside the source
adapters calls `MangaDexAPI` directly.

- **`Models/MangaSource.swift`** — the `MangaSource` protocol every source conforms to
  (search / popular / newTitles / latestUpdates / mangaDetail / chapters / pageURLs).
  Deliberately **bridge-friendly** (only `Int`/`String` params, value/Codable returns) so
  a future dynamic-extension runtime can conform via a bridge. `newTitles`/`latestUpdates`
  are optional capabilities with default impls that throw `SourceError.unsupported`.
- **`Services/SourceRegistry.swift`** — `@MainActor` singleton (`.shared`, injectable init)
  that owns the registered sources and the active browse source. Resolve a source with
  `active`, `source(id:)`, or `source(for: manga)` (uses `manga.sourceId`). ViewModels/
  Services fetch through this, never `MangaDexAPI`.
- **`Models/MangaDexSource.swift`** — MangaDex as source #1: a thin adapter delegating to
  the `MangaDexAPI` static methods. Owns `sourceID = "mangadex"`.
- **`Services/WebViewService.swift`** + **`Services/SourceContext.swift`** — the host
  capability layer for HTML-scraping sources. `WebViewService` (`@MainActor`, `.shared`)
  loads pages in a shared off-screen `WKWebView` (persistent data store so Cloudflare's
  `cf_clearance` survives; pinned UA), runs an injected JS script whose final expression is
  a `JSON.stringify(...)` string, and decodes it into Codable DTOs. Interactive Cloudflare
  challenges surface the WebView in a sheet (`Components/CloudflareChallengeView`, wired in
  `ContentView`); declines are sticky for 30s and task cancellation is honored. Sources
  receive it via `SourceContext` (`WebViewExtracting` protocol — mock it in tests).
- **`Models/WeebCentralSource.swift`** — WeebCentral as source #2 (`sourceID =
  "weebcentral"`): server-rendered HTML scraped via per-page JS extraction scripts
  (co-located raw strings — the volatile part when the site redesigns). Browse feeds map
  to `/search/data` sort modes; unit-tested against a `MockWebView`.
- **`Models/MangaDexAPI.swift`** — the MangaDex networking implementation in one file.
  `MangaDexAPI` is a namespace struct of `static` async methods over a single generic
  `request<T: Decodable>(endpoint:queryItems:)` helper (uses `.convertFromSnakeCase`).
  It also defines the app's domain types (`Manga`, `MangaUpdate`) and all the private
  `Decodable` wire types (`MangaData`, `MangaAttributes`, `ChapterData`, etc.).
  Raw API payloads are converted to domain types via `toManga(id:relationships:)`, which
  stamps `Manga.sourceId` with the MangaDex source id.
- **`Models/*ViewModel.swift`** — `@MainActor final class ... : ObservableObject` with
  `@Published` state (`isLoading`, `errorMessage`, data arrays). They wrap the API's
  `async` methods in `Task {}` and surface errors as `errorMessage` strings.
- **`Views/`** — screens; **`Views/Components/`** — reusable cards/rails.
- **`ContentView.swift`** — root `TabView` (Home / Bookmarks / Search / Settings).

Key conventions worth preserving:

- **Covers are always prefetched.** Every `/manga` query injects
  `includes[]=cover_art`, and `MangaAttributes.toManga` pre-builds a `coverURL` so the
  `Manga` model always carries a ready-to-use cover URL for `AsyncImage`. Cover URLs are
  built by the free function `mangaCoverURL(mangaId:fileName:size:)` against
  `uploads.mangadex.org`, defaulting to the 512px JPEG variant.
- **Latest Updates is a two-step fetch:** `fetchLatestUpdates` first pulls recent
  `/chapter` entries (with `includes[]=manga`), dedupes to unique manga preserving order,
  then batch-fetches those manga by `ids[]` with covers. Reader page URLs come from
  `pageURLs(for:)` which hits `/at-home/server/{chapterId}` and composes
  `{baseUrl}/{data|data-saver}/{hash}/{file}`.

## Adding files to the project

`Models/`, `Services/`, and `Components/` are Xcode 16 **synchronized groups**
(`PBXFileSystemSynchronizedRootGroup`) — new files dropped in them are compiled
automatically. Note `Components/` is synchronized but lives **nested under `Views/`** on
disk (`Manga-Reader/Views/Components/`), so a shared UI component goes there and needs no
`project.pbxproj` edit. **`Views/` itself is NOT synchronized:** new files directly in it
must be added to
`project.pbxproj` explicitly (a `PBXFileReference`, a `PBXBuildFile`, a child entry in the
`Views` `PBXGroup`, and an entry in the target's `Sources` build phase). Adding the file
in Xcode does this for you; when editing `pbxproj` by hand, mirror an existing `Views`
file across all four sections.

## Current state

The app builds and the core reading loop is implemented:

- **Tabs:** Home, Library, History, Search, Settings. Home, Library, and History each have
  their own `NavigationStack`. `SearchView` is a debounced, source-scoped title search
  (`SearchViewModel` + a shared `PagedMangaLoader` for infinite-scroll results). Settings wires the
  appearance/dark-mode toggle plus the **source picker** ("Show adult sources" gating);
  switching sources re-sources Home immediately (in-flight loads are cancelled so a slow
  old source can't repaint the rails).
- **Recommendations:** Home shows a personalized **"For You"** rail (`RecommendationEngine` +
  `TasteProfile` + `TagCandidateProvider`, on-device, MangaDex-only) built from reading
  history; `TasteProfileStore` caches read-manga tags and Not-interested / More-like-this
  feedback. Rail #0 on Home with a "See all" grid; hidden until there's enough signal.
- **Sources:** two registered — MangaDex and WeebCentral (Cloudflare-protected HTML,
  fetched through `WebViewService`). Saved items reopen via their own source
  (`SourceRegistry.source(for:)`); the detail page shows the originating source and can
  open the manga's page in an in-app Safari sheet (`webURL(forManga:)`).
- **Reading progress & history:** `Services/HistoryStore.swift` (`@MainActor`, UserDefaults)
  is the reading-progress spine. `ReaderView(manga:chapter:initialPage:)` records the
  furthest page reached; the detail screen's "Continue" button resumes there (Netflix-style
  advance to the next chapter when the last page was finished), and the History tab is a full
  chronological log that reopens any entry at its exact page.
- **Library updates:** `LibraryStore.refresh(history:)` pulls each saved manga's latest
  chapters (`MangaDexAPI.recentChapters`) and shows a "NEW · N" badge for genuinely-new,
  unread chapters (reconciled against `HistoryStore`); pull-to-refresh + a toolbar button
  drive it, and reading clears the badge.
- **Reader:** three modes (L→R / R→L / webtoon), default right-to-left; chapter list defaults
  to newest-first with a toggle. Paged zoom is `UIScrollView`-backed
  (`Components/ZoomableContainer.swift`) for native pinch/pan physics; R→L is reversed page
  order (NOT a mirror transform — a previous mirror-based approach inverted zoomed panning).
- Design/spec/plan for the above live in `docs/superpowers/{specs,plans}/`.

Still minimal: no cross-device sync, no per-chapter read/unread marks, manual refresh only.
