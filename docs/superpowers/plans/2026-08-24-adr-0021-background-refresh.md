# ADR-0021 Background Library Refresh & New-Chapter Notifications — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship ADR-0021 phase one — best-effort background Library refresh with local
new-chapter notifications, plus the Home/Library Updates surfaces the merged UI contract
describes — on top of the per-source `LibraryStore.refresh()` routing PR #86 landed.

**Architecture:** A pure `ChapterFrontier` value type turns string chapter numbers into
release-vs-backfill evidence. `UpdateStateStore` persists one baseline/frontier/mute record per
`WorkID` in its own Application Support JSON. `LibraryRefreshCoordinator` is the single refresh
pipeline — foreground activation, background task, and pull-to-refresh all call it — folding
Listing-specific network results into Work-level events. `UpdateScheduler` and `UpdateNotifier` wrap
`BGTaskScheduler` and `UNUserNotificationCenter` behind protocols so every decision stays unit
testable. `LibraryUpdatesPresentation` is a pure mapping over the four stores that the Home and
Library views consume.

**Tech Stack:** SwiftUI, Foundation, BackgroundTasks, UserNotifications. No third-party deps. Xcode
project (no SPM). iOS 17.5 deployment target.

**Spec:** `docs/superpowers/specs/2026-08-24-adr-0021-background-refresh-design.md`
**ADR:** `docs/adr/0021-background-library-refresh-and-new-chapter-notifications.md`
**UI contract:** `docs/superpowers/specs/2026-08-24-home-library-updates-design.md`
**Issue:** #92

---

## Global Constraints

- **No third-party dependencies.** Pure SwiftUI + Foundation + Apple frameworks only.
- **App sources live under `MangaCarta/…` from the repo root** — e.g.
  `MangaCarta/Services/UpdateStateStore.swift`. (Older plans in this directory say
  `MangaCarta/MangaCarta/…`; that is stale — verify with `ls` before trusting either.)
- **`Models/`, `Services/`, and `Views/Components/` are Xcode synchronized groups** — new files
  auto-compile, no `project.pbxproj` edit. **`Views/` and `MangaCartaTests/` are NOT** — a new file
  in either needs the four-part wiring, done with `xcp add-file` (see CLAUDE.md).
- **`project.pbxproj` can change under you at any moment while Xcode has the project open.** Check
  `git diff --stat` immediately before every `git add`, not right after `xcp`, and
  `git checkout` unrelated churn.
- **Build/test on the iPhone 17 Pro simulator** with **`-parallel-testing-enabled NO`**:
  ```sh
  xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -parallel-testing-enabled NO test
  ```
  That device holds the seeded fixture (13 MangaDex titles + 1 WeebCentral); another device gets an
  empty library.
- **Never erase the simulator.** Its app container is a fixture (`works.json` has been destroyed this
  way before). Check the container before any destructive simulator action.
- **`BGTaskScheduler.register` must be called before the app finishes launching** — that means
  `MangaCartaApp.init`, not `.task` and not `onChange(of: scenePhase)`.
- **Background code paths cannot show UI.** No interactive Cloudflare challenge, no permission
  prompt, no alert may originate from a background run.
- **SourceKit/LSP false alarms** ("No such module 'XCTest'", "Cannot find type 'Manga' in scope") are
  indexer noise. Judge correctness ONLY by the `xcodebuild` run.
- **Wait on `.agy_review_running`** before building — a burst of commits gets one review.
- End commit messages with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- **Do not open a PR or merge without asking the user.**

## File Structure

```
MangaCarta/
  Models/
    ChapterFrontier.swift                  NEW  (synchronized — no pbxproj edit)
    LibraryUpdatesPresentation.swift       NEW  (synchronized)
  Services/
    UpdateStateStore.swift                 NEW  (synchronized)
    LibraryRefreshCoordinator.swift        NEW  (synchronized)
    UpdateScheduler.swift                  NEW  (synchronized)
    UpdateNotifier.swift                   NEW  (synchronized)
    UpdateTuning.swift                     NEW  (synchronized — every tunable, one file)
    AppComposition.swift                   MODIFY
    LibraryStore.swift                     MODIFY (re-point refresh at the coordinator)
    WorkStore.swift                        UNCHANGED — merges are derived, never pushed (Task 2)
  Views/
    Components/UpdatesHeader.swift         NEW  (synchronized — under Views/, still auto-compiled)
    Components/WorkUpdateRow.swift         NEW  (synchronized)
    HomeView.swift                         MODIFY
    BookmarksView.swift                    MODIFY (Library — Updates filter)
    SettingsView.swift                     MODIFY
    ChapterListView.swift                  MODIFY (clear newlyDiscovered)
  MangaCartaApp.swift                    MODIFY
  Info.plist                               MODIFY
MangaCartaTests/                         NEW files need `xcp add-file`
  ChapterFrontierTests.swift
  UpdateStateStoreTests.swift
  LibraryRefreshCoordinatorTests.swift
  UpdateNotifierTests.swift
  LibraryUpdatesPresentationTests.swift
```

Confirm the Library screen's real filename before Task 7 — `Views/BookmarksView.swift` is the
Library today, but check rather than assume.

---

## Task 1: `ChapterFrontier` — the pure release-vs-backfill core

The whole feature's correctness sits here, and it needs no stores, no network, and no simulator.
Build it first and test it hard. `Models/` is synchronized; the test file is not — use `xcp`.

**Files:**
- Create: `MangaCarta/Models/ChapterFrontier.swift`
- Create: `MangaCartaTests/ChapterFrontierTests.swift` (+ `xcp add-file --targets MangaCartaTests`)

**Interfaces:**
- Produces: `ChapterOrdinal` (`Hashable, Comparable, Codable`, `static func parse(_:) -> Self?`),
  `ChapterFrontier` (`Codable, Equatable`, `mutating func absorb(_:) -> [ChapterOrdinal]`,
  `mutating func seed(_:)`, `var known/max/unnumbered`). Consumed by Tasks 2, 3, 6.
- Consumes: nothing.

- [ ] **Step 1: Write the failing tests first (TDD).** One `@Test` per ADR-0021 hazard, named for the
  hazard, not for the method:
  - `"7"` then `"8"` → one release.
  - `"7"` then `"7.5"` → one release (decimal above the max).
  - `"8"` then `"7.5"` → **zero** releases (backfill below the max, joins `known`).
  - `"07"` after `"7"` → zero releases (zero-padding is the same chapter).
  - `"7v2"`, `"7-8"` → parse to 7.
  - `"Extra"`, `""`, `"Oneshot"` → land in `unnumbered`, never advance `max`, never emit.
  - A list that *shrinks* (source removed a chapter) emits nothing and does not lower `max`.
  - `seed` over 100 chapters emits nothing and sets `max` to the highest.
  - Codable round-trip preserves `known`, `max`, and `unnumbered` exactly.
- [ ] **Step 2: Implement `ChapterOrdinal.parse`.** Trim whitespace; take the leading run matching
  `[0-9]+(\.[0-9]+)?`; return `nil` if that run is empty. Back `value` with `Decimal` (not `Double`)
  so `7.5` and `0.1` compare and encode exactly. `Comparable` compares `value` only.
- [ ] **Step 3: Implement `absorb`.** Parse each raw number; unparseable ones go to `unnumbered` and
  are excluded from the return. Compute `released = parsed.filter { !known.contains($0) && (max == nil || $0 > max!) }`.
  Insert all parsed into `known`. Raise `max` to the new maximum. Return `released` sorted ascending.
  **`max` never decreases.**
- [ ] **Step 4: Implement `seed`.** Same folding, discard the return. Explicitly `@discardableResult`-free
  so a caller cannot accidentally treat a first observation as releases.
- [ ] **Step 5:** `xcodebuild … test -only-testing:MangaCartaTests/ChapterFrontierTests`. All green
  before moving on.

---

## Task 2: `UpdateStateStore` — persisted baselines, mute, and backoff

**Files:**
- Create: `MangaCarta/Services/UpdateStateStore.swift`
- Create: `MangaCarta/Services/UpdateTuning.swift`
- Create: `MangaCartaTests/UpdateStateStoreTests.swift` (+ `xcp`)
- **Do not modify `WorkStore.swift`.** See Step 7.

**Interfaces:**
- Consumes: `ChapterFrontier` (Task 1), `WorkID`/`ListingKey` (`Models/Work.swift`), `WorkStore`
  (read-only: `work(_:)`).
- Produces: `@MainActor final class UpdateStateStore: ObservableObject` with `WorkUpdateState`,
  `ListingCheckState`. Consumed by Tasks 3, 5, 6, 7.

- [ ] **Step 0: `UpdateTuning`.** Create it first, exactly as spec §Decisions.7 lists it, with the
  header comment saying plainly that **none of these values has been measured on a device** and that
  ADR-0021 already names the revisit trigger. Every later task reads its thresholds from here — no
  literal `6 * 60 * 60` anywhere else in the diff.
- [ ] **Step 1: Copy `WorkStore`'s persistence shape, not a new one.** Same
  `WorkStore.applicationSupportDirectory()`, file `updates.json`, same debounced `markDirty()` /
  `saveTask` / `flush()` pattern, same injectable `directory` so a test writes to a temp dir. Read
  `WorkStore.swift:374-433` and mirror it deliberately.
- [ ] **Step 2: Model the state** exactly as the spec's §Design.2 declares (`WorkUpdateState`,
  `ListingCheckState`). Persist as `[WorkID: WorkUpdateState]` via a `Persisted` struct with an array
  payload — `WorkID` is not a `String` key, so a bare dictionary will not encode to sane JSON.
- [ ] **Step 3: `absorb(workId:listing:rawNumbers:now:) -> [ChapterOrdinal]`.** If
  `!hasBaseline`: `seed`, set `hasBaseline = true`, set `lastSuccessfulCheck`, return `[]`. Else
  `absorb`, union the result into `newlyDiscovered`, set `newestDiscoveryAt` when non-empty, set
  `lastSuccessfulCheck`, clear that Listing's failure counters, return the result.
- [ ] **Step 4: `recordFailure(workId:listing:now:)`.** Increment `consecutiveFailures`, set
  `lastFailure`, and set `blockedUntil = now + min(pow(2, failures) * UpdateTuning.backoffBase,
  UpdateTuning.backoffCeiling)`. Per Listing, never per Source.
- [ ] **Step 5: `clearNewlyDiscovered(_:)`, `setMuted(_:workId:)`, `forget(_:)`.** `forget` deletes
  the record entirely — ADR-0021 requires removal from Library to drop notification state so that
  re-adding re-baselines. It resolves the id through `WorkStore` first, so forgetting a merged-away id
  forgets the survivor's record. It must also return the pending-notification identifier so Task 5 can
  cancel it.
- [ ] **Step 6: `reconcileMerges(using works: WorkStore)`.** For each `WorkID` this store holds state
  under, ask `works.work(id)?.id`. Same id → live, skip. Different id → that key was merged away: fold
  its record into the survivor's (`known`/`unnumbered`/`newlyDiscovered` union, `max` the greater,
  `hasBaseline` either, `isMuted` either, per-Listing state by most recent success) and drop the loser
  key. `nil` → drop the key. **The fold must never produce releases** — assert it. Must be idempotent.
- [ ] **Step 7: Do NOT add a `didMerge` closure to `WorkStore`.** This was considered and rejected —
  spec §Decisions.6 has the full comparison. The short version, and the comment to put on
  `reconcileMerges`: `WorkStore.merge` *aliases* the loser rather than erasing it
  (`WorkStore.swift:268-297`), the alias chain is persisted, and `work(_:)` follows it — so the merge
  is already fully observable through the store's existing public API, and pushing a callback would
  give a golden-tested store a reason to change that has nothing to do with Works. **The one condition
  that would revive the closure is `WorkStore` pruning aliases**; say so in the comment, because if
  that ever happens this whole mechanism dies silently.
- [ ] **Step 8: Tests** — baseline suppression, second-run emission, forget-then-re-add re-baselines,
  mute retains state, backoff doubles and expires, JSON round-trip, and a fresh store on an empty
  directory behaves as "no state" rather than crashing. Plus, against a **real** `WorkStore` that has
  actually merged two Works (not a fake): reconciliation unions correctly, emits nothing, drops the
  loser key, is idempotent, and drops a key whose Work no longer resolves.

---

## Task 3: `LibraryRefreshCoordinator` — the one pipeline

The largest task. It is the piece ADR-0021's "same source-aware refresh pipeline" sentence names, and
the piece PR #86's per-source routing exists to make correct.

**Files:**
- Create: `MangaCarta/Services/LibraryRefreshCoordinator.swift`
- Create: `MangaCartaTests/LibraryRefreshCoordinatorTests.swift` (+ `xcp`)

**Interfaces:**
- Consumes: `WorkStore` (`allWorkIds()`, `work(_:)`), `LibraryStore` (`items`), `HistoryStore`
  (`latestEntry(forManga:)`), `UpdateStateStore` (Task 2), `SourceRegistry`
  (`source(id:)`, `active`), `MangaSource.chapters(mangaId:)`.
- Produces: `RefreshBudget`, `UpdateEvent`, `RefreshStep`, `func run(budget:) async -> [UpdateEvent]`,
  `func step() async -> RefreshStep`. Consumed by Tasks 4, 5, 6, 7.

- [ ] **Step 1: Constructor with every dependency injected**, including `now: () -> Date` and the
  `SourceRegistry` — copy `MetadataUpgradeQueue.init`'s style, including its comment about why
  `@MainActor` dependencies are nil-defaulted rather than default-argument-constructed.
- [ ] **Step 2: Build the priority queue** as a private `func queue(now:) -> [WorkID]`, rebuilt each
  run, never persisted:
  1. unfinished Works (`snapshot?.publicationStatus != .finished`) whose `lastSuccessfulCheck` is
     older than the freshness target, oldest first;
  2. Works read in the last 14 days (`HistoryStore`) or present in a Library collection;
  3. the remainder in round-robin order starting at the **persisted cursor**, wrapping.
  Dedupe across tiers preserving first appearance. Engagement facts come from the existing stores —
  do not invent a second definition (ADR-0021 hazard).
- [ ] **Step 3: `step()` — one Work.** Resolve `Work.listings`; drop Listings whose `blockedUntil >
  now`; if none remain return `.skipped`. Route each remaining Listing through
  `registry.source(id: key.sourceId) ?? mangaDexFallback` — the same fallback expression
  `LibraryStore.refresh()` uses at `LibraryStore.swift:287-290`, extracted so the two cannot drift.
  Fetch concurrently, capped at 4, with a task group shaped like the one already in
  `LibraryStore.refresh()`.
- [ ] **Step 4: Fold results.** Every success → `updates.absorb(...)`. Every failure →
  `updates.recordFailure(...)`; a failure is **unknown**, never evidence of no change. Then:
  all-failed → `.failed` (no event); no baseline before this run → `.baselined` (no event); non-empty
  union of released ordinals → `.advanced(workId, count:)` and one `UpdateEvent`; else `.unchanged`.
- [ ] **Step 4b: Cap the event, not the frontier.** The frontier absorbs every ordinal, but
  `UpdateEvent.newChapterCount` is clamped to `UpdateTuning.maxNotifiedChaptersPerWork` with
  `didExceedCap = true` above it. This is the mitigation for the renumbering failure mode
  (spec §Decisions.1) — comment it as such, so a later reader does not "simplify" it away as a stray
  magic number.
- [ ] **Step 5: `run(budget:)`.** Call `updates.reconcileMerges(using: works)` **before the first
  fetch** — that is what closes the window where a survivor would be checked against its own narrower
  frontier and emit chapters the merged-away record already knew. Then loop `step()` until the queue is spent, `Task.isCancelled`, the
  `deadline` is within a safety margin (2s), or `maxWorks` is reached. **Persist the cursor before
  returning on every path**, including cancellation — that is what makes a background run resumable
  rather than restarting at the first title.
- [ ] **Step 6: Keep `LibraryStore.refresh()` working.** Re-point it to call the coordinator and then
  write each item's `chapterNumbers` from the fetched chapters, so the Library grid is unchanged and
  there is exactly one place that talks to Sources for update purposes. The PR #86 regression test
  (per-item routing) must still pass untouched — if it needs editing, the refactor is wrong.
- [ ] **Step 7: Tests with stub sources.** Build a `SourceRegistry` holding stub `MangaSource`s (one
  succeeding, one throwing, one slow) and assert:
  - one failing Listing + one succeeding Listing on the same Work still advances it;
  - every Listing failing emits no event and records `.failed`;
  - a WeebCentral slug is never sent to the MangaDex stub (the PR #86 property, at Work level);
  - three new chapters on one Work produce exactly **one** `UpdateEvent` with `count == 3`;
  - two Listings both reporting the same new chapter produce **one** event, not two;
  - cancellation mid-queue persists the cursor and the next `run` resumes where it stopped;
  - a Work with every Listing in backoff yields `.skipped` and costs no network call;
  - a Work merged since the last run is reconciled before any fetch, and does not emit the survivor's
    already-known chapters as new;
  - 100 new ordinals in one run yield one event with `newChapterCount == 12` and `didExceedCap`, and
    the next run is silent.

---

## Task 4: `UpdateScheduler` — BackgroundTasks, behind a protocol

**Files:**
- Create: `MangaCarta/Services/UpdateScheduler.swift`
- Modify: `MangaCarta/Info.plist`

**Interfaces:**
- Consumes: `LibraryRefreshCoordinator` (Task 3), `UpdateNotifier` (Task 5).
- Produces: `BackgroundTaskScheduling` protocol + `BGTaskSchedulerAdapter`, and `UpdateScheduler`
  with `register()`, `scheduleNext(from:)`, `handle(_:)`. Consumed by Task 6.

- [ ] **Step 1: Add the Info.plist keys.** `BGTaskSchedulerPermittedIdentifiers` = one string,
  `Elias-Magdaleno.Manga-Reader.libraryRefresh`; `UIBackgroundModes` = `<string>fetch</string>`.
  Note `GENERATE_INFOPLIST_FILE = YES` **and** an explicit `INFOPLIST_FILE` are both set — edit the
  file, not the build settings. No entitlements file: local notifications need none.
- [ ] **Step 2: Define the protocol** with `register`, `submit(identifier:earliestBeginDate:)`, and
  `cancel`, plus a `BGTaskLike` protocol exposing only `expirationHandler` and
  `setTaskCompleted(success:)`, so a fake task can drive expiration in a test.
- [ ] **Step 3: `handle(_:)`.** Re-submit the *next* request first (so a crash later in the handler
  cannot break the chain), install `expirationHandler` to cancel the run task, then
  `await coordinator.run(budget: .background(deadline: now + UpdateTuning.backgroundRunDeadline, maxWorks: UpdateTuning.backgroundMaxWorks))`, hand the events to
  the notifier, flush the stores, and `setTaskCompleted(success:)` exactly once on every path.
- [ ] **Step 4: `scheduleNext`** requests
  `earliestBeginDate = now + UpdateTuning.backgroundRequestInterval`. **This is a request, not a
  schedule** — put that in a comment, and make sure no UI string anywhere promises a cadence.
- [ ] **Step 5: Test** against a fake scheduler: registration happens once; a handled task always
  submits the next one; expiration cancels the run and still calls `setTaskCompleted`; a run with no
  events schedules no notification.

---

## Task 5: `UpdateNotifier` — authorization, copy, grouping, deep link

**Files:**
- Create: `MangaCarta/Services/UpdateNotifier.swift`
- Create: `MangaCartaTests/UpdateNotifierTests.swift` (+ `xcp`)

**Interfaces:**
- Consumes: `UpdateEvent` (Task 3), `UpdateStateStore` (Task 2), `SourceRegistry` (for `isNSFW`).
- Produces: `NotificationScheduling` protocol + `UNUserNotificationCenterAdapter`, `UpdateNotifier`
  with `schedule(_ events:) async`, `requestAuthorizationIfNeeded() async`,
  `authorizationSummary() async`. Consumed by Tasks 4, 6, 7.

- [ ] **Step 1: The protocol** — `authorizationStatus()`, `requestAuthorization()`, `add(_:)`,
  `removePending(withIdentifiers:)`. Everything else in the type is pure decision logic.
- [ ] **Step 2: `schedule`.** Read authorization **every call** (it can change outside the app —
  ADR-0021). Skip muted Works. One `UNNotificationRequest` per Work with identifier
  `"work-\(workId.raw.uuidString)"` so a later run replaces rather than stacks, and
  `threadIdentifier = "library-updates"` so several Works form one iOS group.
- [ ] **Step 3: Copy.** `"1 new chapter of \(title)"` / `"\(n) new chapters of \(title)"`, degrading
  to `"Many new chapters of \(title)"` when `didExceedCap`. If the Work is adult — **any** Listing on
  a source with `isNSFW`, and the user has not enabled adult detail — `"A followed title has new
  chapters"`, no title, no cover. The "any Listing" rule deliberately **over-suppresses**: a Work with
  one adult Listing is treated as adult even when read elsewhere, because this string renders on a
  lock screen in public and a missed title badge is a far cheaper error than adult content on a shared
  surface. Suppression is of *copy only* — the notification still delivers and still deep links.
  Put the pluralisation and the adult branch in a pure `static func body(for:)` so the tests assert
  strings, not `UNNotificationContent`.
- [ ] **Step 4: `userInfo["workId"]`** carries the Work id. Write the response handler to route to the
  Work's chapter list with newly discovered chapters emphasised — **never** open a chapter. Opening a
  notification is not evidence the reader wants to skip unread chapters.
- [ ] **Step 5: Contextual authorization.** `requestAuthorizationIfNeeded` prompts only after the
  first Library save and only once; guard with a `hasRequestedNotificationAuthorization` preference so
  denial is never re-prompted. Refresh and in-app Updates keep working when denied.
- [ ] **Step 6: Tests** — denied authorization schedules nothing while state still advances; adult
  copy omits the title, **including for a Work whose other Listing is non-adult** (over-suppression is
  intended, so assert it rather than tolerate it); capped copy at `didExceedCap`; muted Works are
  skipped; a second run for the same Work reuses the identifier;
  `forget` cancels the pending request; pluralisation at 1 and 3.

---

## Task 6: Composition and lifecycle wiring

**Files:**
- Modify: `MangaCarta/Services/AppComposition.swift`
- Modify: `MangaCarta/MangaCartaApp.swift`
- Modify: `MangaCartaTests/AppCompositionTests.swift`

- [ ] **Step 1:** Add `updates`, `refresh`, `notifier`, `scheduler` to `AppComposition`, built once and
  shared, storage injectable exactly as the existing stores are — that file exists because wiring
  claims are only true while the construction says so.
- [ ] **Step 2:** Nothing to wire for merges — `LibraryRefreshCoordinator` reconciles them itself
  (Task 3 Step 5). Confirm `WorkStore.swift` is untouched in the diff; if it isn't, Task 2 Step 7 was
  ignored.
- [ ] **Step 3:** Call `scheduler.register()` in `MangaCartaApp.init` — **not** in `.task` or
  `onChange`; `BGTaskScheduler` requires registration before launch completes.
- [ ] **Step 4:** In `onChange(of: scenePhase)` (`MangaCartaApp.swift:132-159`), follow the existing
  ordering discipline and its comments:
  - `.active`: start a foreground `refresh.run(budget: .foreground)` alongside `queue.start()`, so
    activation heals skipped and failed work.
  - `.background`: stop the foreground run **before** flushing (same reason the existing code stops
    `queue` before `queue.flush()` — cancellation is what guarantees nothing writes after the flush),
    then `updates.flush()`, then `scheduler.scheduleNext(from: now)`.
  - `.inactive` remains **not** a stop signal (ADR-0010).
- [ ] **Step 5:** Extend `AppCompositionTests` to prove the new objects are shared instances, not
  rebuilt per use.

---

## Task 7: Home and Library Updates surfaces

Implements the merged UI contract. `Views/Components/` is synchronized; the two `Views/` screens
already exist, so no `project.pbxproj` edit is needed for this task.

**Files:**
- Create: `MangaCarta/Models/LibraryUpdatesPresentation.swift`
- Create: `MangaCarta/Views/Components/UpdatesHeader.swift`, `.../WorkUpdateRow.swift`
- Create: `MangaCartaTests/LibraryUpdatesPresentationTests.swift` (+ `xcp`)
- Modify: `MangaCarta/Views/HomeView.swift`, `BookmarksView.swift` (Library), `SettingsView.swift`,
  `ChapterListView.swift`

- [ ] **Step 1: The pure presentation type first**, per spec §Design.6: `UpdateFreshness`,
  `WorkUpdateSummary`, `summaries(...)`. Thresholds come from `UpdateTuning` (Task 2 Step 0) — that is
  how the UI contract's "centralised and testable" requirement is met. It is a plain
  `enum` namespace with static funcs — **not** an `ObservableObject`, so views cannot smuggle store
  access in behind it.
- [ ] **Step 2: Tests before the views.** Assert: the three freshness boundaries; `newlyDiscovered`
  and `unreadChapterCount` diverge (clearing one leaves the other); sort is newest-discovery then
  title; five-plus-"View all N"; and — the contract's real prohibition — **summaries are byte-identical
  when `SourceRegistry.active` changes**, since views must never let the active browse source define
  personal update truth.
- [ ] **Step 3: `UpdatesHeader`** — literal title, total unread count, relative freshness ("Last
  checked yesterday", never a delivery promise), a 44pt refresh button disabled while refreshing.
  Ink & Seal tokens (`Ink`, `Gutter`, `.inkMono`), `NEW` rendered as a restrained seal.
- [ ] **Step 4: Home** — Updates section above recommendations, at most five Works, then
  "View all N updates". Each state from the UI contract gets its own branch: no saved Works (Browse +
  Search actions, no freshness claim), saved-no-baseline ("Not checked yet"), fresh-no-updates
  ("Checked recently · No new chapters", no rail), refreshing (content preserved, duplicate requests
  disabled), partial failure (known updates retained + which sources need another check).
- [ ] **Step 5: Library** — an `Updates` filter beside All and collections, labelled "Updates" and
  never a bare number, selected state not carried by vermilion alone.
- [ ] **Step 6: Settings** — in-app Updates state, system authorization state, a global notifications
  toggle, and an Open System Settings action when authorization is unavailable.
- [ ] **Step 7: Clear on view.** `ChapterListView` (and the detail preview) calls
  `updates.clearNewlyDiscovered(workId:)` on appear. **`isRead` is not touched** — `newly discovered`
  and `unread` are separate state, and `isRead` keeps its pinned meaning (read to the end, or manually
  marked).
- [ ] **Step 8: Accessibility** — spoken labels include title and unread count; refresh completion and
  recoverable errors are announced; focus stays on the refresh control for status-only changes and
  moves to an error action only when the user must intervene; Reduce Motion replaces spatial banner
  movement with opacity or nothing; accessibility text sizes stack metadata below titles.

---

## Task 8: UI verification on the seeded simulator

There is no tap tool here — drive and verify SwiftUI through XCUITest assertions with screenshot
attachments, on the iPhone 17 Pro simulator holding the fixture.

**Files:**
- Modify: `MangaCartaUITests/…` (add an updates UI test class)

- [ ] **Step 1:** Cover, each with a screenshot attachment: the no-saved-Works empty state; "Not
  checked yet"; a foreground refresh that announces completion; the Updates filter's selected state;
  the Settings authorization row.
- [ ] **Step 2:** Use launch arguments to seed deterministic update state — a live refresh against
  real sources is not a test signal.
- [ ] **Step 3:** Remember one red UI test is no signal on this repo — re-run, then check `main`
  before blaming the branch. Live-network UI tests here are known flaky.

---

## Final verification (before finishing the branch)

- [ ] Full suite green: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test`
- [ ] The PR #86 per-source routing regression test still passes **unmodified**.
- [ ] `git diff --stat` shows `MangaCarta/Services/WorkStore.swift` **unchanged**.
- [ ] No threshold literal outside `UpdateTuning.swift` (grep the diff for `60 * 60`).
- [ ] Grep the whole diff for cadence promises — no user-visible string may say "twice a day",
  "every 12 hours", or name a delivery time.
- [ ] Force-quit + relaunch on the simulator: state survives, no duplicate notification for a Work
  already alerted.
- [ ] Deny notification permission in Settings, refresh: in-app Updates still work.
- [ ] `git diff --stat` immediately before each `git add`; `git checkout` unrelated `project.pbxproj`
  churn.
- [ ] Update CLAUDE.md's "Current state": the manual-refresh / nothing-polls claim becomes false with
  this branch. Also re-grep the docs for that claim — it has rotted before.
- [ ] **Ask the user before opening a PR or merging.**

## Notes for the executor

- Tasks 1 and 2 are pure and independent of the simulator; get them fully green before touching
  anything with a lifecycle. Tasks 4 and 5 are independent of each other and can be parallelised.
- The hard part is not BackgroundTasks — it is Task 1. Every false notification this feature could
  ever send is a `ChapterFrontier` bug. The cap in Task 3 Step 4b bounds how loud such a bug can be;
  it does not make one less of a bug.
- Three decisions in this plan are deliberate *refusals* and will look like omissions to a reviewer
  who has not read the spec: no `didMerge` on `WorkStore` (§Decisions.6), no measured thresholds
  (§Decisions.7), and adult copy that over-suppresses on purpose (§Design.5). Cite the spec rather
  than re-arguing them.
- `MetadataUpgradeQueue` is the precedent for everything shaped like a loop: injected `now`/`sleep`,
  a step enum, persisted attempt memory, `start`/`stop`/`flush` from `scenePhase`. Read it before
  writing Task 3, and copy its testability rather than reinventing it.
- Where ADR-0021 or the UI contract already decided something, cite it in a comment rather than
  re-deciding it in code review.
