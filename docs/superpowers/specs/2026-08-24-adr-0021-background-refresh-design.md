# ADR-0021 — Background Library refresh and new-chapter notifications — Design

- **Date:** 2026-08-24
- **ADR:** `docs/adr/0021-background-library-refresh-and-new-chapter-notifications.md` (Accepted 2026-08-24)
- **UI contract:** `docs/superpowers/specs/2026-08-24-home-library-updates-design.md`
- **Issue:** #92
- **Plan:** `docs/superpowers/plans/2026-08-24-adr-0021-background-refresh.md`

## Context

ADR-0021 is accepted and the Home/Library UI contract is merged. **Nothing is implemented.** This
document turns the two into a buildable design: the types, the seams, the persistence, and the
tests. Where ADR-0021 already decided something, this document does not re-decide it — it names the
code that carries the decision.

What exists to build on:

- `LibraryStore.refresh()` (`Manga-Reader/Services/LibraryStore.swift:277-322`) now routes per-item
  to the Source named by `LibraryItem.sourceId`, through an injectable `SourceRegistry` seam
  (`registryOverride`, `init(defaults:works:registry:)`), with a MangaDex fallback for `nil`/
  unregistered ids and a bounded `maxConcurrent = 4` task group. PR #86. ADR-0021's "network checks
  remain Listing-specific" is exactly this routing, lifted from `LibraryItem` to `ListingKey`.
- `WorkStore` (`Manga-Reader/Services/WorkStore.swift`) owns Works, the `ListingKey → WorkID` index,
  merge aliasing, and a debounced JSON save under Application Support. `Work.listings` is the list of
  `ListingKey`s ADR-0021 says to check.
- `MetadataUpgradeQueue` (`Manga-Reader/Services/MetadataUpgradeQueue.swift`) is the only
  self-starting work in the app and the closest precedent worth copying: injected `now`/`sleep`,
  a `DrainStep` enum describing one turn of the loop so the loop is testable without a clock, a
  persisted attempt memory with backoff, `start()`/`stop()`/`flush()` driven from `scenePhase`
  (`Manga_ReaderApp.swift:132-159`), and construction in `AppComposition`.
- The app has **no** `BGTaskScheduler` registration, no `UIBackgroundModes`, no notification
  entitlement, and no `UNUserNotificationCenter` use. `Info.plist` exists and is hand-maintained
  (`Manga-Reader/Info.plist`) alongside `GENERATE_INFOPLIST_FILE = YES`.

The gap between ADR and code is four things: a **chapter frontier** that survives string chapter
numbers; a **per-Work update state** that persists baselines; a **coordinator** that folds
Listing-level results into Work-level events; and a **scheduler + notifier** pair that the rest of
the app can be tested without.

## Decisions

These are implementation decisions ADR-0021 explicitly left open.

### 1. The frontier is a set of parsed ordinals, not a scalar

`LibraryItem.chapterNumbers` is `[String]`, and sources publish `"7"`, `"7.5"`, `"07"`, `"Extra"`,
`""`. A scalar max cannot distinguish "chapter 8 released" from "chapter 7.5 was backfilled" from
"the source relabeled 7 as 07". So the persisted frontier is **the set of parsed ordinals ever
observed**, plus the max, and an event fires only for ordinals that are both new to the set **and
strictly greater than the persisted max**. Backfilled older chapters join the set silently; a
relabeling that parses to an already-known ordinal is a no-op.

Unparseable numbers (`"Extra"`, `""`, `"Oneshot"`) are kept in a separate `unnumbered: Set<String>`
raw-string bucket and **never** advance the frontier or emit an event. ADR-0021's hazard list
requires fixtures for exactly these cases; §"Testing" pins them.

Rejected: comparing raw `[String]` set counts (a removal followed by an addition nets to zero, and a
renumbering looks like a release). Rejected: `Double(numberString)` alone (loses `"7-8"` and orders
`"10"` before `"9"` only by accident of parsing, and silently maps everything unparseable to `nil`
with no record that it was seen).

**Mitigation for the unproven case — `maxNotifiedChaptersPerWork = 12`.** This scheme is a bet, and
its known failure mode is a source renumbering a long run at once: every shifted chapter parses as a
new ordinal above the max, and a 100-chapter series would emit a 100-chapter event. The frontier
still absorbs all of them (state stays correct, and the next run is quiet), but the **event** is
capped: an `UpdateEvent` reports at most `maxNotifiedChaptersPerWork` and its copy degrades to
`"Many new chapters of X"` at the cap. The cap is why the bet is takeable without proving it first —
it turns the worst case from a hundred lock-screen notifications into one wrong notification. It is
not a correctness fix and must not be read as one; ADR-0021's revisit trigger for frontier
representation still stands.

### 2. Update state is a separate store keyed by `WorkID`, not a field on `Work`

`Work` is the identity/metadata record and `WorkStore` merges Works, which would silently merge two
notification baselines. Update state lives in `UpdateStateStore` — its own Application Support JSON
file — keyed by `WorkID`, and it subscribes to merge by exposing an explicit `merge(loser:into:)`
that takes the **union** of known ordinals and the **max** of the two maxima, so a merge can never
manufacture a "new chapter" event.

Rejected: putting `frontier`/`baselineAt`/`muted` on `Work`. It would grow the golden-tested
recommendation snapshot for reasons unrelated to recommendations, and `WorkStore.merge` has no
notion of "do not treat the loser's chapters as newly discovered".

### 3. `LibraryRefreshCoordinator` is the one pipeline; foreground and background both call it

ADR-0021 requires activation refresh to "heal skipped or failed work" using "the same source-aware
refresh pipeline". One type therefore owns: building the priority queue, checking Listings,
folding results, emitting events. The *callers* differ only in a `RefreshBudget` value
(`.background(deadline:)` vs `.foreground`) and in whether an interactive Cloudflare challenge is
permitted.

`LibraryStore.refresh()` stays as-is and keeps powering pull-to-refresh, but it is re-pointed at the
coordinator so there is exactly one place that talks to Sources for update purposes. Its existing
per-item `chapterNumbers` write remains — the Library grid still reads it.

### 4. `BGTaskScheduler` and `UNUserNotificationCenter` sit behind protocols

Neither works in a unit test and neither is safe to call from a Swift Testing suite. Two narrow
protocols (`BackgroundTaskScheduling`, `NotificationScheduling`) with production adapters and test
fakes keep every decision — cadence requests, baseline suppression, one-notification-per-Work,
adult copy, authorization branches — unit-testable. This mirrors the `SourceRegistry` seam PR #86
added to `LibraryStore`.

### 5. Presentation is a pure function over three stores

The UI contract's view-facing model is produced by a **pure, non-observable** mapping
(`LibraryUpdatesPresentation.summaries(works:library:history:updates:now:)`) rather than by view
code reaching into stores. That is what makes the contract's prohibitions ("must not consult the
globally active browse source", "must not equate `newly discovered` with `isRead`") enforceable by a
test rather than by review.

### 6. Merge effects are *derived* from `WorkStore`, not pushed to `UpdateStateStore`

`WorkStore.merge` collapses two Works, which would otherwise leave two update records for one Work.
The obvious fix is a `didMerge` callback on `WorkStore`. **Rejected.** `WorkStore` is golden-tested
and deliberately narrow, and a notification hook would give it a reason to change that has nothing to
do with Works.

It is not needed, because **the merge is already observable in `WorkStore`'s public API**:
`merge(_:into:)` *aliases* the loser rather than erasing it (`WorkStore.swift:268-297`), the alias
chain is persisted (`Persisted.aliases`), and `work(_:)` follows it — so a stale id keeps resolving to
the survivor forever. `UpdateStateStore` can therefore reconcile by asking, for each `WorkID` it holds
state under, `works.work(id)?.id`:

- returns the **same** id → still live, nothing to do;
- returns a **different** id → that key was merged away; fold its state into the survivor's
  (`known` union, `max` greater, `newlyDiscovered` union, `isMuted` either, per-Listing state by most
  recent success) and drop the loser key;
- returns **nil** → the Work is gone entirely; drop the key.

The fold rule is the same one a callback would have applied, so a merge still cannot manufacture an
event. `LibraryRefreshCoordinator.run` calls `updates.reconcileMerges(using: works)` **before** its
first fetch, which is what closes the only window that matters: `allWorkIds()` returns live ids only,
so between a merge and a reconcile the survivor would be checked against its own narrower frontier and
could emit chapters the merged-away record already knew. Reconciliation is in-memory, main-actor, and
O(records) with no network, so running it at the top of every pass is affordable.

The alternative was written up because it deserved to be, and the honest comparison is:

| | derive (chosen) | `didMerge` closure |
| --- | --- | --- |
| `WorkStore` change | none | a stored closure + a call site, in a golden-tested store |
| Correctness window | closed by reconciling before the first fetch | closed immediately |
| Failure if forgotten | reconcile skipped → survivor re-baselines or double-counts once | callback unwired → same, silently and permanently |
| Cost per refresh | one dictionary lookup per state record | zero |
| What it cannot observe | *when* a merge happened — and nothing here is time-sensitive | — |

There is no fact the closure would carry that the alias chain does not already record. If a future
change makes `WorkStore` prune aliases, this argument dies with it — and *that* is the concrete
condition that would justify revisiting the closure. Pin it in a comment on `reconcileMerges`.

### 7. Tunables live in one place, and their values are unmeasured

Every threshold this feature invents — freshness window, background cadence request, run deadline,
per-run Work budget, backoff ceiling, notification cap — is a **placeholder chosen by judgment, not
by measurement**, and they are gathered into a single `UpdateTuning` namespace so they can be found,
changed, and eventually measured together rather than hunted through five files.

```swift
enum UpdateTuning {
    static let freshWindow: TimeInterval = 6 * 60 * 60        // "checked recently"
    static let staleAfter: TimeInterval = 24 * 60 * 60        // "last checked yesterday"
    static let backgroundRequestInterval: TimeInterval = 4 * 60 * 60
    static let backgroundRunDeadline: TimeInterval = 25       // of ~30s granted
    static let backgroundMaxWorks = 20
    static let backoffBase: TimeInterval = 15 * 60
    static let backoffCeiling: TimeInterval = 6 * 60 * 60
    static let maxNotifiedChaptersPerWork = 12
    static let homeSummaryLimit = 5
}
```

**None of these values has been measured on a device.** They are deliberately not worth more design
effort before the feature runs against a real Library, and ADR-0021 already names the trigger:
if background runs regularly expire before meaningful coverage, or source rate limits reject the
cadence, revisit queue size, per-source backoff, and freshness targets *using measured device data*.
Treat a change to any of these as cheap; treat a claim that one of them is correct as unsupported.

## Design

### 1. `Models/ChapterFrontier.swift` (new, pure)

```swift
/// A chapter number parsed into something orderable. `raw` is retained so a
/// relabeling ("07" → "7") is recognised as the same chapter.
struct ChapterOrdinal: Hashable, Comparable, Codable {
    let value: Decimal      // 7, 7.5; parsed from the leading numeric run
    static func parse(_ raw: String) -> ChapterOrdinal?
}

/// Everything a Work's frontier needs to persist.
struct ChapterFrontier: Codable, Equatable {
    private(set) var known: Set<ChapterOrdinal>
    private(set) var max: ChapterOrdinal?
    private(set) var unnumbered: Set<String>

    /// Folds an observation in. Returns the ordinals that are BOTH new to `known`
    /// AND strictly greater than the previous `max` — i.e. releases, not backfill.
    mutating func absorb(_ rawNumbers: [String]) -> [ChapterOrdinal]

    /// First-observation seeding: absorbs everything and returns nothing.
    /// This is ADR-0021's "first successful observation establishes a baseline".
    mutating func seed(_ rawNumbers: [String])
}
```

`parse` rules, pinned: trim; take the leading run matching `[0-9]+(\.[0-9]+)?`; reject if that run is
empty; ignore anything after it (`"7-8"` → 7, `"7v2"` → 7). `Decimal` not `Double` so `7.5` and
`0.1` compare exactly and encode stably in JSON.

### 2. `Services/UpdateStateStore.swift` (new, `@MainActor`, `ObservableObject`)

```swift
struct ListingCheckState: Codable, Equatable {
    var lastSuccess: Date?
    var lastFailure: Date?
    var consecutiveFailures: Int
    var blockedUntil: Date?      // backoff; ADR-0021 hazard "blocked source needs backoff"
}

struct WorkUpdateState: Codable, Equatable {
    var frontier: ChapterFrontier
    var hasBaseline: Bool
    var newlyDiscovered: Set<ChapterOrdinal>   // cleared by viewing the chapter list
    var newestDiscoveryAt: Date?
    var lastSuccessfulCheck: Date?
    var isMuted: Bool
    var listings: [ListingKey: ListingCheckState]
}
```

Persisted as `updates.json` under `WorkStore.applicationSupportDirectory()`, with the same
debounced-save + `flush()` shape `WorkStore` uses (and the same `scenePhase == .background` flush,
for the same reason ADR-0007 gives).

API: `state(for:)`, `absorb(workId:listing:rawNumbers:now:) -> [ChapterOrdinal]`,
`recordFailure(workId:listing:now:)`, `clearNewlyDiscovered(workId:)`, `setMuted(_:workId:)`,
`forget(workId:)` (removal from Library — ADR-0021 requires deleting notification state **and**
cancelling pending notifications; it resolves through `WorkStore` first so removing a merged-away id
forgets the survivor's record), `reconcileMerges(using: WorkStore)` (§Decisions.6), `flush()`.

Backoff: `blockedUntil = now + min(2^consecutiveFailures * UpdateTuning.backoffBase,
UpdateTuning.backoffCeiling)`, per **Listing**, not per Source, so one dead slug does not stall a
whole Source.

### 3. `Services/LibraryRefreshCoordinator.swift` (new, `@MainActor`)

```swift
enum RefreshBudget { case foreground, background(deadline: Date, maxWorks: Int) }

struct UpdateEvent: Equatable {         // one per Work per run — never per Listing
    let workId: WorkID
    let title: String
    /// Capped at `UpdateTuning.maxNotifiedChaptersPerWork` (§Decisions.1). The frontier
    /// still absorbed every ordinal; this is only what the user is told.
    let newChapterCount: Int
    let didExceedCap: Bool
    let isAdult: Bool
}

enum RefreshStep: Equatable {           // one turn of the loop, like DrainStep
    case advanced(WorkID, count: Int)
    case baselined(WorkID)
    case unchanged(WorkID)
    case failed(WorkID)
    case skipped(WorkID)                 // every Listing in backoff
    case exhausted                       // budget or queue spent
}

func run(budget: RefreshBudget) async -> [UpdateEvent]
func step() async -> RefreshStep         // the unit tests drive this
```

Per Work: take `Work.listings`, drop Listings whose `blockedUntil > now`, check each through
`registry.source(id:)` with the same MangaDex fallback `LibraryStore.refresh()` uses, concurrency
capped at 4. Fold every **success** into the frontier; a failure records backoff and is *unknown*.
If every Listing failed → `.failed`, no event. If the Work has no baseline → `seed`, `.baselined`,
no event. Otherwise the returned ordinals, if any, become one `UpdateEvent`.

**Priority queue** (ADR-0021's three tiers), rebuilt each run from live facts, never persisted as a
list — only the round-robin *cursor* is persisted:

1. `snapshot.publicationStatus != .finished` and `lastSuccessfulCheck` older than the freshness
   target;
2. Works with a `HistoryStore` entry in the last 14 days, or in a Library collection;
3. everything else, starting at the persisted cursor and wrapping.

Engagement facts come from `HistoryStore.latestEntry(forManga:)` and `LibraryStore.items` — ADR-0021
forbids inventing a second definition of engagement.

`run` calls `updates.reconcileMerges(using: works)` before its first fetch (§Decisions.6).

Cancellation: `run` checks `Task.isCancelled` and the `deadline` between Works and persists the
cursor before returning, so the expiration handler's cancel leaves a resumable state.

### 4. `Services/UpdateScheduler.swift` (new)

```swift
protocol BackgroundTaskScheduling {
    func register(identifier: String, handler: @escaping (BGTaskLike) -> Void) -> Bool
    func submit(identifier: String, earliestBeginDate: Date) throws
    func cancel(identifier: String)
}
```

Identifier `Elias-Magdaleno.Manga-Reader.libraryRefresh`. Registration happens in
`Manga_ReaderApp.init` (before the scene is created — `BGTaskScheduler` requires it), and a request
is submitted on `.background` with `earliestBeginDate = now + UpdateTuning.backgroundRequestInterval`,
re-submitted at the *start* of each handler so the chain never dies. The handler sets
`expirationHandler` to cancel the coordinator's task, runs `coordinator.run(budget: .background(...))`
with `UpdateTuning.backgroundRunDeadline` and `UpdateTuning.backgroundMaxWorks`, schedules
notifications, then `setTaskCompleted(success:)`.

Product copy says "a few times a day", never a time. UI never claims a cadence.

### 5. `Services/UpdateNotifier.swift` (new)

```swift
protocol NotificationScheduling {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async -> Bool
    func add(_ request: UNNotificationRequest) async
    func removePending(withIdentifiers: [String])
}
```

- **Read authorization every time** before scheduling (ADR-0021: it can change outside the app).
- One request per Work per run; identifier `"work-\(workId.raw.uuidString)"` so a second run
  replaces rather than stacks; `threadIdentifier = "library-updates"` for the single iOS group.
- Copy: `"3 new chapters of Dandadan"` / `"1 new chapter of Dandadan"`, degrading to
  `"Many new chapters of Dandadan"` when `didExceedCap` (§Decisions.1).
- Adult Works get `"A followed title has new chapters"` and **no** cover attachment. Adult-ness is
  derived from `MangaSource.isNSFW` on **any** linked Listing, and the derivation deliberately
  **errs toward over-suppression**: a Work linked to one adult Listing is treated as adult even if
  the user reads it elsewhere. The asymmetry is the reason — this string renders on a lock screen in
  public, so a missed title badge is a cheap error and adult content on a shared surface is not.
  Suppressed here means suppressed in *copy only*; the notification still delivers and still deep
  links, per ADR-0021's rejection of suppressing adult notifications entirely.
- `userInfo["workId"]` drives the deep link; the response handler routes to the Work's chapter list
  with `newlyDiscovered` emphasised — it never opens a chapter.
- Muted Works are folded and stored but not scheduled.

Authorization is requested **after the first save**, once, from a contextual explainer sheet, and a
`hasRequestedNotificationAuthorization` preference prevents re-prompting after denial.

### 6. `Models/LibraryUpdatesPresentation.swift` (new, pure)

```swift
enum UpdateFreshness: Equatable { case notChecked, refreshing, fresh, stale, partialFailure }

struct WorkUpdateSummary: Identifiable, Equatable {
    let id: WorkID
    let displayManga: Manga
    let unreadChapterCount: Int
    let newlyDiscoveredCount: Int
    let newestDiscoveryAt: Date?
    let lastSuccessfulCheck: Date?
    let freshness: UpdateFreshness
    let recoverySummaries: [String]
    let isMuted: Bool
}

enum LibraryUpdatesPresentation {
    static func summaries(...) -> [WorkUpdateSummary]      // sorted: newest discovery, then title
}
// Thresholds come from `UpdateTuning` (§Decisions.7) — the UI contract requires the
// "recently" threshold to be centralised and testable, and this is where it is centralised.

```

`unreadChapterCount` = frontier ordinals not in `HistoryStore.readChapterNumbers(forManga:)`;
`newlyDiscoveredCount` = `state.newlyDiscovered.count`. They are separate, as the UI contract
requires. `freshness` is derived: no baseline → `.notChecked`; store refreshing → `.refreshing`; any
Listing with `consecutiveFailures > 0` → `.partialFailure`; `lastSuccessfulCheck` within
`UpdateTuning.freshWindow` → `.fresh`; else `.stale`.

### 7. Views

- `Views/Components/UpdatesHeader.swift` — title, total unread, relative freshness, 44pt refresh
  button, disabled while refreshing, `.accessibilityLabel` spelling out state.
- `HomeView` — an Updates section above recommendations, at most `homeSummaryLimit` Works, then
  "View all N updates". Hidden entirely when there are no saved Works or no updates.
- Library — an `Updates` filter chip beside All and collections, selected state carried by shape +
  label, not vermilion alone.
- `SettingsView` — in-app Updates state, system authorization state, global notifications toggle,
  and an Open System Settings action when authorization is unavailable.
- `MangaDetailView` / `ChapterListView` — viewing the chapter list calls
  `updates.clearNewlyDiscovered(workId:)`; `isRead` is untouched.

### 8. Project wiring

- `Info.plist` gains `BGTaskSchedulerPermittedIdentifiers` (the one identifier) and
  `UIBackgroundModes` = `fetch`. No entitlement file is needed — local notifications require none.
- `AppComposition` gains `updates: UpdateStateStore`, `refresh: LibraryRefreshCoordinator`,
  `notifier: UpdateNotifier`, `scheduler: UpdateScheduler`, all injectable for the composition test.
- `Manga_ReaderApp`: register in `init`; `.active` → `refresh.run(budget: .foreground)` and
  `updates` healing; `.background` → `updates.flush()` and `scheduler.submit(...)`.

## Data flow

```
scenePhase .active ─┐
BGAppRefreshTask ───┼─→ LibraryRefreshCoordinator.run(budget:)
pull-to-refresh ────┘        │
                             ├─ priority queue over WorkStore.allWorkIds() (cursor persisted)
                             ├─ per Work: Work.listings → SourceRegistry.source(id:) → chapters()
                             ├─ per success: UpdateStateStore.absorb → [ChapterOrdinal]
                             ├─ per failure: UpdateStateStore.recordFailure (backoff, unknown)
                             └─→ [UpdateEvent] ─→ UpdateNotifier (auth-gated, mute-gated, 1/Work)
                                          │
UpdateStateStore ─┬─→ LibraryUpdatesPresentation.summaries ─→ Home Updates / Library Updates filter
WorkStore ────────┤
LibraryStore ─────┤
HistoryStore ─────┘
```

## Testing

Unit (Swift Testing, `Manga-ReaderTests`, no network):

- `ChapterFrontierTests` — the ADR's hazard fixtures, each its own case: decimals (`7.5` after `7`
  is a release; `7.5` after `8` is backfill), zero-padding (`07` == `7`), `"7v2"`, `"7-8"`,
  unparseable (`"Extra"`, `""`, `"Oneshot"` never advance), removal (a shrinking list emits
  nothing), late translation, and a full 100-chapter seed emitting zero events.
- `UpdateStateStoreTests` — baseline suppression; second run emits; removal forgets; re-add
  re-baselines; mute keeps state and suppresses only delivery; backoff grows and expires; round-trips
  through JSON. **Merge reconciliation:** after a real `WorkStore.merge`, `reconcileMerges` folds the
  loser's record into the survivor's by union/max, drops the loser key, emits nothing, and is
  idempotent when run twice; a `WorkID` whose Work no longer resolves at all is dropped.
- The cap: a Work that gains 100 ordinals in one run absorbs all 100 into the frontier, reports
  `newChapterCount == UpdateTuning.maxNotifiedChaptersPerWork` with `didExceedCap`, and is silent on
  the next run.
- `LibraryRefreshCoordinatorTests` — with stub `MangaSource`s in a stub `SourceRegistry`: one
  Listing failing while another succeeds still advances the Work; all Listings failing emits no
  event and records `.failed`; the WeebCentral-among-MangaDex mix routes per Listing; one Work
  produces one event for three new chapters; cancellation mid-queue persists the cursor and the next
  run resumes rather than restarting; a fully backed-off Work yields `.skipped`.
- `UpdateNotifierTests` — denied authorization schedules nothing but state still advances; adult copy
  omits the title (including for a Work whose *other* Listing is non-adult — over-suppression is the
  intended behaviour, so it is asserted, not tolerated); the capped event's copy; one identifier per
  Work replaces rather than stacks; grouping identifier set; muted Works are skipped.
- `LibraryUpdatesPresentationTests` — the three freshness boundaries; `newlyDiscovered` and unread
  diverge (viewing clears one, not the other); Home limit of 5 with a correct "View all N"; sort
  order; and a test asserting summaries are unchanged when `SourceRegistry.active` changes.
- `AppCompositionTests` — the new objects are wired once and shared.

UI (`Manga-ReaderUITests`, iPhone 17 Pro, seeded fixture): the empty state, "Not checked yet",
a refresh that announces completion, the Updates filter's selected state, and the Settings
authorization row — each with a screenshot attachment, per the repo's UI-verification convention.

## Explicitly deferred (YAGNI)

- Server-side polling and APNs. ADR-0021 rejects it for phase one and names the revisit trigger.
- Cross-device baseline sync and cross-device notification dedupe.
- Per-Source cadence tuning from measured device data.
- Notification actions ("Mark read", "Mute") on the delivered notification.
- A dedicated Updates navigation destination separate from the Library filter — the UI contract says
  prefer the existing Library topology until real content ranges prove it insufficient.
- Widgets and Live Activities.
