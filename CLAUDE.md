# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Native SwiftUI iOS app (a MangaDex reader client). No third-party dependencies or
package manager — pure SwiftUI + Foundation. Xcode project only (no SPM/CocoaPods).

- Scheme / target: `Manga-Reader`
- Deployment target: iOS 17.5 (some UI branches on `#available(iOS 18.0, *)`)
- Test targets: `Manga-ReaderTests` (unit), `Manga-ReaderUITests` (UI)

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

MVVM over a stateless API layer. Data flows: `MangaDexAPI` (network) → `@MainActor`
`ObservableObject` view models → SwiftUI views.

- **`Models/MangaDexAPI.swift`** — the entire networking layer in one file. `MangaDexAPI`
  is a namespace struct of `static` async methods over a single generic
  `request<T: Decodable>(endpoint:queryItems:)` helper (uses `.convertFromSnakeCase`).
  It also defines the app's domain types (`Manga`, `MangaUpdate`) and all the private
  `Decodable` wire types (`MangaData`, `MangaAttributes`, `ChapterData`, etc.).
  Raw API payloads are converted to domain types via `toManga(id:relationships:)`.
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

`Models/`, `Services/`, and `Components/` are Xcode 16 **synchronized root groups**
(`PBXFileSystemSynchronizedRootGroup`) — new files dropped in them are compiled
automatically. **`Views/` is NOT synchronized:** new files there must be added to
`project.pbxproj` explicitly (a `PBXFileReference`, a `PBXBuildFile`, a child entry in the
`Views` `PBXGroup`, and an entry in the target's `Sources` build phase). Adding the file
in Xcode does this for you; when editing `pbxproj` by hand, mirror an existing `Views`
file across all four sections.

## Current state (early WIP)

The app builds, but much is still stubbed:

- `SearchView`, `BookmarksView`, and `SettingsView` are placeholder "Hello, World!" stubs.
- Only the Home tab has a `NavigationStack`, so detail/reader navigation works only from
  Home. The other tabs will need their own `NavigationStack` when built out.
- The detail/reader path (`MangaDetailView` → `ReaderView`) is functional but minimal —
  no reading progress, bookmarks, or persistence yet.
