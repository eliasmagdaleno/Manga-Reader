# Manga Reader

A native iOS manga reader built with SwiftUI, powered by the [MangaDex](https://mangadex.org) API. No third-party dependencies — pure SwiftUI and Foundation.

<p align="center">
  <img src="docs/screenshots/home-light.png" width="45%" alt="Home screen, light mode" />
  <img src="docs/screenshots/home-dark.png" width="45%" alt="Home screen, dark mode" />
</p>

## Features

- **Browse** popular titles, recently updated chapters, and newly added manga, pulled live from MangaDex
- **Read** chapters in three modes — left-to-right, right-to-left (manga order), and webtoon-style continuous vertical scroll — with pinch-to-zoom and double-tap-to-zoom on paged pages
- **Library** — save manga on-device and revisit them later
- **Light / dark mode**, with a system, light, or dark override in Settings
- **"Ink & Seal"** design language — a print-inspired visual identity: warm paper / near-black ink surfaces, a single vermilion seal accent, serif display type, and monospaced metadata stamps

## Architecture

MVVM over a stateless API layer:

```
MangaDexAPI (networking)  →  @MainActor ObservableObject view models  →  SwiftUI views
```

- **`Models/MangaDexAPI.swift`** — the entire networking layer: a namespace of `static` async methods over one generic `request<T: Decodable>` helper, plus the app's domain types (`Manga`, `MangaUpdate`, `Chapter`, …). Handles retry-on-429, typed errors, and cover-art prefetching for every manga query.
- **`Models/*ViewModel.swift`** — `@MainActor` view models exposing `@Published` state, wrapping the API's `async` calls.
- **`Services/LibraryStore.swift`** — a small `UserDefaults`-backed store for saved-to-library manga.
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

Early WIP. Home is fully built out; Search, Bookmarks/Library, and Settings are in progress. See `CLAUDE.md` for a more detailed breakdown of current state and conventions.

## Acknowledgments

Manga metadata and cover art courtesy of the [MangaDex API](https://api.mangadex.org/docs/). This project is not affiliated with or endorsed by MangaDex.
