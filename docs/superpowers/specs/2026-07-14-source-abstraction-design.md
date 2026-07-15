# Source Abstraction Layer — Design

Date: 2026-07-14

## Context

The app is a single-source MangaDex reader. Every layer is hard-wired to MangaDex: the
`Manga` domain type, the `MangaDexAPI` static methods, cover-URL building, and every
ViewModel/Service that calls `MangaDexAPI.*` directly.

The larger goal is a **multi-source manga reader** (MangaDex + comix.to + others),
eventually with MyAnimeList tracking and reading-taste data visualization. That vision is
**five independent subsystems**, built in order, each with its own spec:

1. **Source abstraction** ← *this spec*
2. Multi-source (add source #2)
3. Search (cross-source)
4. MyAnimeList tracking
5. Discovery + data-viz

**Why this first:** building search or a second source against `MangaDexAPI` directly
would mean rewriting them later. Abstracting the source layer now — with MangaDex as
source #1 — unblocks everything downstream. This is a **behavior-preserving refactor plus
the seam**: no user-visible change, one source, all current features work exactly as
before.

## Decisions

- Sources are **native Swift compiled into the app** for now. A downloadable JS/WASM
  extension runtime is a later, separate subsystem — and the app can't ship on the App
  Store regardless, so that constraint doesn't bind us.
- The `MangaSource` protocol is designed **bridge-friendly**: pure data in/out,
  serializable `Int`/`String`/Codable domain types across the source boundary, no
  Swift-only constructs. A future dynamic-extension runtime can conform to the same
  contract without a redesign.

## Design

### 1. `MangaSource` protocol — `Models/MangaSource.swift` (new)

Mirrors the current `MangaDexAPI` surface exactly (same params) so the refactor is
mechanical and behavior-preserving. All params are `Int`/`String`; all return values are
existing value/Codable domain types.

```swift
protocol MangaSource {
    var id: String { get }      // stable, e.g. "mangadex"
    var name: String { get }    // display name

    func search(title: String, limit: Int, offset: Int) async throws -> [Manga]
    func popular(limit: Int, offset: Int) async throws -> [Manga]
    func newTitles(limit: Int, offset: Int) async throws -> [Manga]
    func latestUpdates(limitTitles: Int, language: String) async throws -> [MangaUpdate]
    func mangaDetail(id: String) async throws -> MangaDetail
    func chapters(mangaId: String) async throws -> [Chapter]
    func pageURLs(chapterId: String, preferDataSaver: Bool) async throws -> [URL]
}

enum SourceError: LocalizedError { case unsupported(String) }
```

**Optional capabilities:** a protocol extension provides default implementations of the
"feed" methods (`newTitles`, `latestUpdates`) that `throw SourceError.unsupported(...)`,
so a future source lacking a feed only implements what it supports. MangaDex implements
all of them.

### 2. `MangaDexSource` — `Models/MangaDexSource.swift` (new)

Thin adapter: `struct MangaDexSource: MangaSource` with `id = "mangadex"`,
`name = "MangaDex"`, each method delegating to the existing `MangaDexAPI` static method.
`MangaDexAPI` stays as the networking implementation (decoding, 429 retry, pagination,
cover-URL building all unchanged).

### 3. `Manga` gains `sourceId` — `Models/MangaDexAPI.swift` (modify)

Add `let sourceId: String` to `Manga` (IDs are only unique *within* a source). Stamp it
in `MangaAttributes.toManga(...)` as `"mangadex"`. Migration-safe: `Manga` is never
persisted (only `LibraryItem`/`ReadingEntry`/`ReadMark` are), so no stored data breaks.

### 4. `SourceRegistry` — `Services/SourceRegistry.swift` (new)

The seam multi-source will grow into. Small and trivially correct with one source:

```swift
@MainActor final class SourceRegistry: ObservableObject {
    static let shared = SourceRegistry()
    @Published private(set) var sources: [MangaSource]
    @Published var activeSourceID: String   // persisted to UserDefaults
    var active: MangaSource { source(id: activeSourceID) ?? sources[0] }
    func source(id: String) -> MangaSource? { sources.first { $0.id == id } }
    init(sources: [MangaSource] = [MangaDexSource()]) { ... }  // injectable for tests
}
```

### 5. Rewire call sites (behavior-preserving)

Replace every `MangaDexAPI.*` call outside `MangaDexAPI.swift` with a source call.
Resolve the source correctly:

- **Browsing feeds** (Home popular/new/latest) → `SourceRegistry.shared.active`.
- **A specific manga's** detail / chapters / pages → `SourceRegistry.shared.source(id:
  manga.sourceId) ?? .active` (correct in a multi-source world; identical now).

| File | Change |
|------|--------|
| `Models/HomeViewModel.swift` | inject `source` via init default; swap 5 call sites |
| `Views/HomeView.swift` | inline `fetch:` closures → `SourceRegistry.shared.active` |
| `Models/MangaDetailViewModel.swift` | resolve source from `manga.sourceId`; injectable for tests |
| `Views/ReaderView.swift` | `pageURLs` via the reading manga's source |
| `Services/LibraryStore.swift` | `fetchChapters` via `SourceRegistry.shared.active` |

**No `project.pbxproj` editing needed:** the three new files land in `Models/` and
`Services/`, which are Xcode synchronized root groups (auto-compiled).

## Explicitly deferred (YAGNI)

- Search UI (step 3) — `search` is in the protocol but no UI is built now.
- A second source implementation (step 2).
- Dynamic JS/WASM extension runtime + package/repo format (later subsystem).
- Namespacing persisted keys by source (optional defaulted `sourceId` on
  `LibraryItem`/`ReadingEntry`) — do it when source #2 lands.
- MyAnimeList tracking; discovery + data-viz; multi-source aggregation on Home.

## Testing

- `MockSource: MangaSource` returning canned data.
- `SourceRegistry`: `active` and `source(id:)` resolution, including fallback.
- `MangaDetailViewModel`: loads detail + chapters through an injected `MockSource`.
- `Manga.sourceId == "mangadex"` on the `MangaDexAPI` decode path.
- Existing `MangaDexAPI` decoding tests stay green.

## Verification (end-to-end)

1. Build for iPhone 17 simulator.
2. Run unit tests — existing + new all pass.
3. Drive the real app (XCUITest + screenshots): Home rails load, tap a manga → detail
   loads, open a chapter → reader pages load, save to Library + refresh badge works.
