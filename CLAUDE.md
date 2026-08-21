# CLAUDE.md

Guidance for coding agents working in this repository — Claude Code and Codex alike.

**`AGENTS.md` is a symlink to this file.** One source of truth, so the two cannot drift:
edit *this* file, never a copy. (They were separate files until 2026-08-21, and the copy
had already gone stale about what `isRead` means.) If Codex ever needs genuinely different
instructions, replace the symlink with a real file at that point — not before.

## Overview

Native SwiftUI iOS app (a MangaDex reader client). No third-party dependencies or
package manager — pure SwiftUI + Foundation. Xcode project only (no SPM/CocoaPods).

- Scheme / target: `Manga-Reader`
- Deployment target: iOS 17.5 (some UI branches on `#available(iOS 18.0, *)`)
- Test targets: `Manga-ReaderTests` (unit), `Manga-ReaderUITests` (UI)

## Commands

Two non-obvious requirements apply to **every** `xcodebuild` invocation here:

- **Target the iPhone 17 Pro simulator** (`-destination 'platform=iOS Simulator,name=iPhone 17 Pro'`).
  It is also the device holding the seeded fixture (see `scripts/seed-simulator.sh`), so a
  run against a different device gets an empty library and quietly different results.
- **Always pass `-parallel-testing-enabled NO` to `test`.** Without it `xcodebuild` spawns
  cloned simulator instances, which is unwanted here.

Run a single test class or method (Swift Testing / XCTest via `xcodebuild`):

```sh
xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  test -only-testing:Manga-ReaderTests/Manga_ReaderTests/<testMethod>
```

For interactive work, opening `Manga-Reader.xcodeproj` in Xcode and using ⌘B / ⌘U is
usually faster than the CLI.

## Architecture

MVVM over a source-abstraction layer. Data flows: `MangaSource` (protocol, network) →
`@MainActor` `ObservableObject` view models → SwiftUI views. Nothing outside the source
adapters calls `MangaDexAPI` directly.

- **`Models/MangaSource.swift`** — deliberately **bridge-friendly** (only `Int`/`String`
  params, value/Codable returns) so a future dynamic-extension runtime can conform via a
  bridge. `newTitles`/`latestUpdates` are optional capabilities whose default impls throw
  `SourceError.unsupported`.
- **`Services/SourceRegistry.swift`** — owns the registered sources and the active browse
  source. ViewModels/Services fetch through this, **never** `MangaDexAPI`.
- **`Services/WebViewService.swift`** + **`Services/SourceContext.swift`** — the host
  capability layer for HTML-scraping sources. The shared off-screen `WKWebView` uses a
  **persistent** data store so Cloudflare's `cf_clearance` survives, plus a **pinned UA**;
  an injected JS script's final expression must be a `JSON.stringify(...)` string.
  Interactive Cloudflare challenges surface the WebView in a sheet; declines are sticky for
  30s and task cancellation is honored. Sources receive it via `SourceContext` — mock the
  `WebViewExtracting` protocol in tests.
- **`Models/WeebCentralSource.swift`** — the per-page JS extraction scripts are co-located
  raw strings, and they are **the volatile part** when the site redesigns.
- **`Models/MangaDexAPI.swift`** — decoding goes through one generic `request` helper using
  `.convertFromSnakeCase`. `toManga(id:relationships:)` stamps `Manga.sourceId` with the
  MangaDex source id — every conversion path must keep doing so.
- **`Models/*ViewModel.swift`** — errors surface as `errorMessage` strings, never thrown
  past the view model.

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
`project.pbxproj` edit.

**`Views/` and `Manga-ReaderTests/` are NOT synchronized** — they are plain `PBXGroup`s, so
a new file in either needs four `project.pbxproj` entries: a `PBXFileReference`, a
`PBXBuildFile`, a child entry in the group, and an entry in the target's `Sources` build
phase.

Use **`xcp`** (`brew install xcp` — XcodeProjectCLI) rather than editing by hand; it writes
all four:

```sh
xcp add-file "$PWD/Manga-Reader.xcodeproj" \
  --file "$PWD/Manga-ReaderTests/NewTests.swift" --targets Manga-ReaderTests
```

`xcp delete-file` reverses it, and **also deletes the file from disk** unless you pass
`--project-only`. `xcp list-targets Manga-Reader.xcodeproj` is a safe read-only check.
Verified 2026-07-26 with xcp 1.2.1: the added file compiled and its test ran.

**Caveat:** any `xcp` write reformats the three `PBXFileSystemSynchronizedRootGroup` entries
from one line each to multi-line — semantically identical and Xcode accepts it, but it turns a
4-line change into ~31 insertions / 3 deletions. Either keep the reformat or `git checkout`
those hunks before committing.

**The reformat can vanish on its own, which makes `git diff` right after `xcp` untrustworthy.**
If Xcode has the project open it rewrites `project.pbxproj` back to one-line form on its own
schedule — so the same `xcp add-file` shows 31 insertions immediately and 4 insertions some
minutes later, with nothing in between having touched the file. **Check `git diff --stat`
immediately before `git add`, not right after `xcp`** — and don't conclude from one clean diff
that the caveat above no longer applies.

**The rewrite is not tied to `xcp` at all.** Corrected 2026-08-08: this section used to say
"neither `xcodebuild build` nor `xcodebuild test` does this; only Xcode itself." A session that
never ran `xcp` saw `project.pbxproj` churn twice anyway — the three synchronized-group entries
collapsing from multi-line to one-line, plus a `name =` key dropped from a file reference —
during plain `xcodebuild build` / `test` runs, with Xcode open the whole time. Whether
`xcodebuild` provokes it or Xcode simply rewrote on its own schedule was **not** isolated (Xcode
was running in both cases), so the only claim worth carrying is the practical one: **if Xcode has
the project open, treat `project.pbxproj` as able to change under you at any moment, `xcp` or
not.** Check it before every `git add`, and `git checkout` the file when the churn is unrelated
to your change.

Adding the file in Xcode also does all four correctly. Hand-editing `pbxproj` is the last
resort; if you must, mirror an existing entry across all four sections.

## Current state

The app builds and the core reading loop is implemented.

- **Reader:** R→L is implemented as **reversed page order — NOT a mirror transform.** A
  previous mirror-based approach inverted zoomed panning. Paged zoom is `UIScrollView`-backed
  (`Components/ZoomableContainer.swift`) for native pinch/pan physics.
- **Read state:** per-chapter read/unread marks ship (`HistoryStore`, since 2026-07-14) —
  single and batch `markRead`/`markUnread`, mark-all-below, dimmed rows, unread badges.
  `isRead` means **read to the end, or manually marked** — `ReadingEntry.isComplete` is
  `pageCount > 0 && page >= pageCount - 1` (#65, 2026-08-20). Opening a chapter still
  records an entry, which is what mints the Work and what makes the vertical reader record
  anything at all; but an opened-and-abandoned chapter is *not* read, so it still counts
  toward the unread badge.
- Design/spec/plan for shipped work live in `docs/superpowers/{specs,plans}/`.

Still minimal: no cross-device sync; refreshing *content* is manual (pull-to-refresh only,
nothing polls for new chapters) — though `MetadataUpgradeQueue` does run on its own on
`scenePhase` becoming active.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `eliasmagdaleno/Manga-Reader`, via the `gh` CLI.
See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical roles, each label string equal to its name (`needs-triage`, `needs-info`,
`ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context. The glossary is `docs/glossary.md` — **not** `CONTEXT.md`, which does not exist
here — and decisions are the numbered ADRs in `docs/adr/`. See `docs/agents/domain.md`.
