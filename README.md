# Manga Reader

A native iOS manga reader built with SwiftUI, powered by the [MangaDex](https://mangadex.org) API. No third-party dependencies — pure SwiftUI and Foundation.

<p align="center">
  <img src="docs/screenshots/home-light.png" width="45%" alt="Home screen, light mode" />
  <img src="docs/screenshots/home-dark.png" width="45%" alt="Home screen, dark mode" />
</p>

## Features

- **Multi-source** — browse and read across more than one source (MangaDex plus a Cloudflare-protected, HTML-scraped site) through a common source abstraction; switch sources from Settings
- **Browse** popular titles, recently updated chapters, and newly added manga, with a personalized **"For You"** recommendation rail built on-device from your reading history
- **Search** — debounced, source-scoped title search with infinite scroll
- **Read** chapters in three modes — left-to-right, right-to-left (manga order), and webtoon-style continuous vertical scroll — with pinch-to-zoom and double-tap-to-zoom on paged pages
- **Library** — save manga on-device, see "NEW" badges for unread chapters, and revisit saved titles later
- **History** — a full chronological reading log; reopen any entry at the exact page you left off, with Netflix-style advance to the next chapter
- **Light / dark mode**, with a system, light, or dark override in Settings
- **"Ink & Seal"** design language — a print-inspired visual identity: warm paper / near-black ink surfaces, a single vermilion seal accent, serif display type, and monospaced metadata stamps

## Architecture

MVVM over a source-abstraction layer:

```
MangaSource (protocol)  →  @MainActor ObservableObject view models  →  SwiftUI views
```

- **`Models/MangaSource.swift`** — the protocol every source conforms to (search / popular / latest / manga detail / chapters / page URLs). Deliberately bridge-friendly (`Int`/`String` params, Codable returns) for future extensibility.
- **`Services/SourceRegistry.swift`** — owns the registered sources and the active browse source; view models resolve a source through here rather than calling any API directly.
- **`Models/MangaDexAPI.swift`** — the MangaDex networking layer: a namespace of `static` async methods over one generic `request<T: Decodable>` helper, plus the app's domain types (`Manga`, `MangaUpdate`, `Chapter`, …). Handles retry-on-429, typed errors, and cover-art prefetching for every manga query.
- **`Services/WebViewService.swift`** — a shared off-screen `WKWebView` that survives Cloudflare challenges and runs injected JS extraction scripts, letting HTML-scraped sources plug into the same abstraction as the API-backed one.
- **`Services/RecommendationEngine.swift`** + **`TasteProfileStore`** — an on-device "For You" rail built from tag signal in your reading history.
- **`Models/*ViewModel.swift`** — `@MainActor` view models exposing `@Published` state, wrapping the source layer's `async` calls.
- **`Services/LibraryStore.swift`** / **`HistoryStore.swift`** — `UserDefaults`-backed stores for saved manga and reading progress.
- **`Views/`** — screens; **`Views/Components/`** — the design system (`Theme.swift`, `InkComponents.swift`) and reusable cards/rails.

## Requirements

- Xcode 16+
- iOS 17.5+ (some UI paths use `#available(iOS 18.0, *)`)

## Getting started

Open `Manga-Reader.xcodeproj` in Xcode and run the `Manga-Reader` scheme (⌘R).

Or build from the command line:

```sh
xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Run the test suite:

```sh
xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## Project status

The core reading loop is complete: Home, Library, History, Search, and Settings are all built out across two sources. See `CLAUDE.md` for a detailed breakdown of current state and conventions.

## Roadmap

**Shipped:**
- Multi-source abstraction (`MangaSource` + `SourceRegistry`), with a Cloudflare-bypass WebView layer for HTML-scraped sources
- Full reading loop — three reader modes, zoom, resume/continue, reading history, library "new chapter" badges
- Cross-source search with infinite scroll
- On-device recommendation engine (MangaDex-only for now — see below)
- "Ink & Seal" design system, light/dark mode

**Next up:**
- **MyAnimeList as a canonical metadata layer** — a read-only MAL client for titles, related manga, and recommendations
- **Cross-source entity resolution** — matching a title to its MAL id (MangaDex already exposes external-id links for most entries, making this closer to free there than for HTML-scraped sources) so the app knows every registered source that carries a given manga
- **"More Like This"** — a Netflix-style tab on the manga detail page, driven by MAL relations and resolved across every source you have registered
- Extending the recommendation engine past MangaDex-only, as identity resolution allows

**Deferred:**
- Additional native sources, added opportunistically
- A hot-loadable, third-party extension/repo system (Paperback/Aidoku-style) — an interesting distribution model, but not on the critical path for the recommendation work above, so shelved for now
- MyAnimeList OAuth + push reading-progress tracking

## Acknowledgments

Manga metadata and cover art courtesy of the [MangaDex API](https://api.mangadex.org/docs/). This project is not affiliated with or endorsed by MangaDex.
