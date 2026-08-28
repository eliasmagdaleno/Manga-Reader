# ADR-0021 Tasks 1–7 implemented; Task 8 next

Date: 2026-08-28  
Repository: `/Users/eliasmagdaleno/Manga-Reader`  
Issue: GitHub #92  
Plan: `docs/superpowers/plans/2026-08-24-adr-0021-background-refresh.md`  
Spec: `docs/superpowers/specs/2026-08-24-adr-0021-background-refresh-design.md`

## Status: consumed 2026-08-28

Task 8 is implemented and verified. `Manga-ReaderUITests/UpdatesUITests.swift` plus the DEBUG-only
`UpdatesUITestFixture` / `UpdatesUITestSource` in `Manga_ReaderApp.swift` cover all five surfaces;
5/5 UI tests pass on iPhone 17 Pro with screenshot attachments, the full `Manga-ReaderTests` run is
green, and strict SwiftLint reports zero violations. Nothing is committed yet.

## Original resume instructions (done)

Implement Task 8: deterministic seeded-simulator UI verification for the update surfaces. Add launch
arguments that seed update state without live network requests, then add XCUITests with screenshot
attachments for:

1. no saved Works;
2. saved Work with “Not checked yet”;
3. foreground refresh completion announcement/status;
4. selected Library “Updates” filter;
5. Settings notification authorization row.

Use the iPhone 17 Pro simulator. Parallel testing is now explicitly enabled in `CLAUDE.md`; do not
restore `-parallel-testing-enabled NO`.

Before Task 8, inspect the current UI-test launch-argument and fixture patterns in
`Manga-ReaderUITests/`, `Manga-ReaderTests/SimulatorSeed.swift`, and
`Manga-ReaderTests/SimulatorSeedFixture.swift`. The plan specifically prohibits a live refresh as a
test signal. Re-run a red UI test before treating it as product evidence.

## Implemented

### Tasks 1–3: domain, persistence, refresh pipeline

- `Models/ChapterFrontier.swift`: exact decimal chapter ordinals, silent baseline, backfill handling,
  stable Codable frontier.
- `Services/UpdateTuning.swift`: centralized freshness, scheduling, deadline, backoff, cap, and Home
  limit constants.
- `Services/UpdateStateStore.swift`: durable `updates.json`, newly-discovered state, mute state,
  per-listing backoff, refresh cursor, merge reconciliation, forget behavior, eager loading.
- `Services/LibraryRefreshCoordinator.swift`: Work/listing refresh pipeline, four-request concurrency,
  source-safe routing, baseline/dedupe/cap behavior, cancellation-safe cursor checkpoints, foreground
  lifecycle ownership.
- `LibraryStore` delegates pull-to-refresh through the coordinator and applies refreshed chapter lists.
- `SourceRegistry.sourceForRefresh(sourceId:)` preserves per-listing source routing.

### Tasks 4–6: background execution, notifications, composition

- `Services/UpdateScheduler.swift`: `BGTaskScheduler` adapter, idempotent registration, earliest begin
  requests, expiration cancellation, resubmit-before-run, completion and flush semantics.
- `Info.plist`: background fetch mode and
  `Elias-Magdaleno.Manga-Reader.libraryRefresh` identifier.
- `Services/UpdateNotifier.swift`: authorization-gated scheduling, stable per-Work identifiers,
  grouping, adult-title suppression, mute/global-toggle suppression, contextual authorization API,
  merge-aware Work routing, pending-notification cancellation.
- `AppComposition` constructs one shared update store, coordinator, notifier, and scheduler.
- `Manga_ReaderApp` registers the scheduler in `init`, runs foreground healing on launch/activation,
  cancels before background flush, persists update state, and requests the next background run.
- `WorkStore.swift` is intentionally untouched.

### Task 7: presentation and UI

- `Models/LibraryUpdatesPresentation.swift`: freshness derivation and stable Work summaries. Unread
  chapters and newly discovered chapters remain separate. Sorting is newest discovery then title;
  Home is capped at five. Output is independent of `SourceRegistry.active`.
- `Views/Components/UpdatesHeader.swift`: literal Updates heading, unread/freshness status, 44-point
  disabled-while-refreshing control, accessibility label and identifier.
- `Views/Components/WorkUpdateRow.swift`: accessible title/unread row and restrained `NEW` seal.
- `HomeView`: update section above recommendations, preserved content while refreshing, five-item
  limit, “View all N updates,” partial-source recovery message, completion announcement.
- `BookmarksView`: labelled “Updates” filter with selected shape/stroke state, not color alone.
- `SettingsView`: in-app update state, current system notification state, global notification toggle,
  and Open System Settings recovery action.
- `MangaDetailView` and `ChapterListView`: clear newly discovered state on view without modifying
  `isRead` or read marks.
- `Manga_ReaderApp` injects the shared `UpdateStateStore` into SwiftUI.

## Tests and verification

New suites/files:

- `ChapterFrontierTests.swift`
- `UpdateStateStoreTests.swift`
- `LibraryRefreshCoordinatorTests.swift`
- `UpdateSchedulerTests.swift`
- `UpdateNotifierTests.swift`
- `LibraryUpdatesPresentationTests.swift`

Latest combined parallel regression command:

```sh
xcodebuild -scheme Manga-Reader \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test \
  -only-testing:Manga-ReaderTests/ChapterFrontierTests \
  -only-testing:Manga-ReaderTests/UpdateStateStoreTests \
  -only-testing:Manga-ReaderTests/LibraryRefreshCoordinatorTests \
  -only-testing:Manga-ReaderTests/UpdateNotifierTests \
  -only-testing:Manga-ReaderTests/UpdateSchedulerTests \
  -only-testing:Manga-ReaderTests/LibraryUpdatesPresentationTests \
  -only-testing:Manga-ReaderTests/AppCompositionTests/testUpdateSubsystemObjectsAreSharedInstances \
  -only-testing:Manga-ReaderTests/Manga_ReaderTests/testRefreshAsksEachItemsOwnSource
```

Result: `** TEST SUCCEEDED **`; 47 Swift Testing tests across six suites passed in 0.048 seconds,
with the selected XCTest checks also included. The Task 7 presentation/notifier run passed 14/14.

Also verified:

- iPhone 17 Pro simulator build succeeds;
- strict SwiftLint reports zero violations;
- `git diff --check` is clean;
- `plutil -lint Manga-Reader/Info.plist` succeeds;
- `git diff -- Manga-Reader/Services/WorkStore.swift` is empty.

Existing unrelated Swift 6 actor-isolation warnings still appear in MAL/resolver/recommendation code.
Do not expand this task to fix them.

## Working tree and project-file cautions

All current modified/untracked files belong to this implementation; nothing has been committed.
Preserve them. New test files were added with `xcp`; Models, Services, and Components are synchronized
groups. Check `git diff --stat` immediately before staging because Xcode may rewrite
`project.pbxproj` while open.

`CLAUDE.md` was intentionally changed so `AGENTS.md` (its symlink) now allows and prefers parallel
testing on the M5 MacBook.

## Known follow-up checks

- Task 8 should verify whether the Home status branches and Settings authorization row read well at
  accessibility text sizes, not merely that they exist.
- The system notification permission prompt must remain contextual and one-shot. The notifier API and
  unit test exist; do not introduce an unconditional launch prompt.
- Notifications route to the Work/detail surface, never directly to a chapter.
- `newlyDiscovered` clearing must never mark chapters read.
- No commit, PR, merge, or issue close has been authorized yet.

## Orca handoff status

The Orca app opened, but `orca worktree current --json` immediately failed with
`runtime_unavailable`. No new terminal, agent, or worktree was created, and ownership was not
transferred. This Markdown file is the authoritative handoff until Orca is restarted and stable.
