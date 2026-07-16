# Chapter "Date Added" Design

Date: 2026-07-16

## Context

The detail screen's chapter list shows each chapter's number, title, and read/resume state,
but not **when the chapter was added/published**. This adds that date for every source that
exposes it. It's a general, public feature — built on `main`, covering MangaDex and
WeebCentral. private-source's date (a gallery's `upload_date` on its single synthetic chapter) is
deferred to the local-only `private-source` branch and is out of scope here.

## Grounding (current code)

- `Chapter` (`Models/MangaDexAPI.swift`): `struct Chapter: Identifiable, Equatable { id, number, title }`.
  Passed to `HistoryStore`/`LibraryStore` **by value** (fields extracted; the whole struct is
  not `Codable`-persisted), so adding a field is persistence-safe.
- MangaDex already decodes but ignores the timestamp: `ChapterAttributes` has
  `publishAt: String?` and `readableAt: String?` (ISO-8601); `toChapter(id:)` drops them.
- WeebCentral chapter rows carry a `<time datetime="…">` (ISO-8601) the current extraction
  script doesn't read.
- The app's existing date convention: History renders absolute dates with
  `.formatted(.dateTime.month().day().year())` → "Jul 12, 2026" (`Views/HistoryView.swift`).

## Decisions

- **Optional `date: Date?` on `Chapter`.** `nil` when a source doesn't provide a date; the
  row simply omits it. Keeps `Equatable`/`Identifiable` (synthesized). No persistence change.
- **Compact absolute format, matching History.** `.dateTime.month().day().year()`
  ("Jul 12, 2026"), rendered small in the app's mono/tertiary style — not relative. (The user
  chose absolute over the relative style History also uses elsewhere.)
- **Right-aligned in the row**, before the chevron (first cut; placement may be revisited
  after visual review).
- **Scope: MangaDex + WeebCentral only.** private-source deferred to its branch.

## Architecture

### 1. Model — `Chapter` gains `date: Date?`

`struct Chapter: Identifiable, Equatable { let id; let number; let title; let date: Date? }`
with an **explicit initializer defaulting `date` to `nil`**:
`init(id: String, number: String, title: String?, date: Date? = nil)`. This keeps every
existing `Chapter(id:number:title:)` call site (including the test suite) compiling unchanged;
only sources with a date pass the extra argument. A shared ISO-8601 → `Date` parse helper
(e.g. `static func parseISO8601(_:) -> Date?` using `ISO8601DateFormatter` with fractional
seconds) lives near `Chapter`/the API layer and is reused by both sources and unit-tested.

### 2. MangaDex — populate from `publishAt`

`ChapterAttributes.toChapter(id:)` parses `publishAt` (the canonical "added" date; falls back
to `readableAt` if `publishAt` is nil) into `date`. Unit-tested: a fixture `ChapterAttributes`
with a known `publishAt` → `Chapter.date` equals the parsed `Date`; nil timestamp → `nil`.

### 3. WeebCentral — populate from the row `<time datetime>`

Extend the `chaptersScript` to also read each row's `<time>` `datetime` attribute, and add a
`date: String?` field to the chapter DTO; map it through the shared ISO-8601 parser to
`Chapter.date`. Unit-tested via the existing `MockWebView` pattern: a canned chapter JSON
with a `date` string → mapped `Chapter.date`; missing/empty → `nil`. (Selector/live-HTML
confirmation of the `datetime` attribute is a live check, consistent with how WeebCentral
selectors are verified.)

### 4. UI — chapter row shows the date

In `MangaDetailView.chapterRow`, when `chapter.date != nil`, render the formatted date
right-aligned before the chevron, in `.inkMono(~11)` tertiary so it reads as metadata, not a
title competitor. Absent date → no change to the row. Sorting/selection/read-state logic is
untouched (the list still sorts by chapter number).

## Testing

- **`parseISO8601` helper** — valid ISO string (with and without fractional seconds) → `Date`;
  garbage/nil → `nil`.
- **MangaDex mapping** — `ChapterAttributes(publishAt:…).toChapter` carries the parsed date;
  nil → nil; `readableAt` fallback when `publishAt` nil.
- **WeebCentral mapping** — canned chapter JSON with/without `date` → `Chapter.date` set/nil,
  via `MockWebView`.
- Row rendering is a visual/human check (no snapshot tests in this project).

## Scope boundaries

- **This feature:** `Chapter.date`, the ISO parse helper, MangaDex + WeebCentral population,
  and the detail-row display. On `main`.
- **Deferred:** private-source's `upload_date` wiring (local-only `private-source` branch, after it merges
  this in); any sorting-by-date or "new since last visit" affordance; relative-time display.
