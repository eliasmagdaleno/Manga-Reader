# Unread chapter badge + chapter multiselect

## Problem

The library "NEW · N" badge currently means "new since you last opened this
manga": `LibraryStore.markCaughtUp(_:)` zeroes the whole count the moment you
open *any* chapter of that manga, even if you only read one of five new
chapters. There's also no way to mark multiple chapters read/unread at once,
or to mark an entire chapter list read in one action.

## Goals

1. The library badge should always read as "total unread chapters" for that
   manga, decrementing by exactly one whenever a specific chapter's read
   state changes — not zeroing out on any chapter open.
2. Add multiselect to the chapter list in `MangaDetailView` to mark multiple
   chapters read or unread at once.
3. Support marking an entire manga's chapter list read in one action (via
   multiselect's "Select All" + "Mark Read", not a separate always-visible
   button).

## Non-goals

- No changes to `HistoryStore`'s existing single-chapter `isRead` /
  `markRead` / `markUnread` / `toggleRead` semantics (a chapter counts as
  "read" once it has a history entry — even a single page in — or a manual
  `ReadMark`). This spec reuses that definition; it does not redefine what
  "read" means.
- No changes to reading-progress tracking, resume/continue logic, or the
  History tab.

## Section 1: Unread badge — data model

Replace "new since baseline" tracking on `LibraryItem` with a stored,
deduped chapter-number list. The badge count becomes a live computation
against `HistoryStore`, not a persisted counter that's imperatively
decremented.

```swift
struct LibraryItem: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let coverURL: URL?
    var chapterNumbers: [String]?   // deduped numbers from last refresh; nil = never refreshed
}

extension LibraryItem {
    func unreadCount(readNumbers: Set<String>) -> Int {
        guard let chapterNumbers else { return 0 }
        return chapterNumbers.filter { !readNumbers.contains($0) }.count
    }
}
```

Changes:

- **Remove** `lastSeenReadableAt`, `latestReadableAt`, `newChapterCount` from
  `LibraryItem`, and `LibraryStore.markCaughtUp(_:)` entirely — there is no
  "caught up" concept anymore, just a live unread count.
- **Remove** the call site `library.markCaughtUp(manga.id)` in
  `ReaderView.swift` (around line 103) — no replacement needed. Reading a
  chapter already writes a `HistoryStore` entry, and the badge recomputes
  live from that on next render.
- `LibraryStore.refresh(history:)` switches from `MangaDexAPI.recentChapters`
  (single page, newest 100, English-only) to `MangaDexAPI.fetchChapters`
  (the same fully-paginated, deduped-by-number call the detail view already
  uses) for each saved manga, storing the resulting chapter numbers on
  `chapterNumbers`. This trades more network calls per library refresh for
  correctness on long-running series (>100 English chapters).
- `RecentChapter`, `MangaDexAPI.recentChapters(mangaId:)`, and the free
  `newChapterCount(_:since:excludingNumbers:)` function in `MangaDexAPI.swift`
  become dead code and are deleted, along with their unit tests in
  `MangaCartaTests.swift`.
- `BookmarksView` computes
  `item.unreadCount(readNumbers: history.readChapterNumbers(forManga: item.id))`
  per card at render time and shows `"UNREAD · N"` (in place of
  `"NEW · N"`) when the count is > 0. Because `library` and `history` are
  both `@EnvironmentObject`s the view already observes, any read/unread
  change (finishing a chapter, multiselect mark-read, mark-all) triggers a
  re-render with the correct count automatically — no manual decrement
  bookkeeping is needed anywhere.
- `chapterNumbers == nil` (never refreshed — freshly added to the library,
  or a pre-migration persisted item from before this change) means no
  badge is shown until the next refresh populates real data. This avoids a
  false "everything unread" flash and doubles as the migration path for
  existing installs' persisted `LibraryItem` JSON (missing the new key
  decodes to `nil` since the field is `Optional`).

## Section 2: Chapter list multiselect + mark-all-as-read

New state on `MangaDetailView`:

```swift
@State private var isSelecting = false
@State private var selectedChapterIDs: Set<String> = []
```

**Entering/exiting selection:** a "Select" text button sits next to the
NEWEST/OLDEST sort toggle in the Chapters header. Tapping it sets
`isSelecting = true`. While selecting, the same button reads "Cancel" and
tapping it clears `selectedChapterIDs` and sets `isSelecting = false`.

**Row behavior while selecting:** each chapter row shows a leading checkbox
(`checkmark.circle.fill` when selected / `circle` when not). Tapping a row
toggles its id in `selectedChapterIDs` instead of pushing `ReaderView` — the
row's `NavigationLink` is swapped for a plain `Button` conditionally on
`isSelecting`. The existing per-row context menu (mark read/unread) remains
available when not selecting.

**Selection toolbar:** while `isSelecting`, a bottom bar shows:

- **Select All / Deselect All** — a single toggle button whose label depends
  on whether every currently-loaded chapter is already selected. This is the
  only path to "mark all as read": Select → Select All → Mark Read.
- **Mark Read** and **Mark Unread** — disabled when `selectedChapterIDs` is
  empty. On tap: resolve the selected ids back to `Chapter` values from
  `vm.chapters`, call the new batch `HistoryStore` method, then clear
  `selectedChapterIDs` and set `isSelecting = false`.

**New batch API on `HistoryStore`** (single `save()` call instead of N):

```swift
func markRead(manga: Manga, chapters: [Chapter]) {
    let existing = Set(readMarks.map(\.chapterId))
    for chapter in chapters where !existing.contains(chapter.id) {
        readMarks.append(ReadMark(mangaId: manga.id, chapterId: chapter.id,
                                   chapterNumber: chapter.number))
    }
    save()
}

func markUnread(manga: Manga, chapters: [Chapter]) {
    let ids = Set(chapters.map(\.id))
    readMarks.removeAll { ids.contains($0.chapterId) }
    entries.removeAll { ids.contains($0.chapterId) }
    save()
}
```

The existing single-chapter `markRead` / `markUnread` / `toggleRead` are
unchanged and keep serving the per-row context menu; these are additive
overloads for the batch case.

## Testing

- Unit tests for `LibraryItem.unreadCount(readNumbers:)`: nil
  `chapterNumbers` → 0; empty `readNumbers` → full count; all numbers in
  `readNumbers` → 0; mixed → correct partial count.
- Unit tests for `HistoryStore.markRead(manga:chapters:)` /
  `markUnread(manga:chapters:)`: marks all given chapters, is idempotent on
  repeat calls, doesn't touch unrelated chapters/manga.
- Remove/replace the now-obsolete `newChapterCount(...)` free-function tests
  and the `LibraryItem.newChapterCount` / `lastSeenReadableAt` nil-on-init
  assertions in `MangaCartaTests.swift`.
- UI test (or manual verification per `docs/superpowers/.../ui-verification`
  convention): enter selection mode, select two chapters, Mark Read, confirm
  checkmarks/dimming update and the library badge count drops by 2; Select
  All + Mark Read drives the badge to 0.
