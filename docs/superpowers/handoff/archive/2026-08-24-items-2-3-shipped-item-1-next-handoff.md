# Handoff — Items 2 and 3 shipped; item 1 is the only thing left in Claude's lane

Session of 2026-08-24 (late evening). Continues
`2026-08-24-task-12-verified-claude-priorities-handoff.md`, which queued three items for this
lane. **Two are merged. The third turned out to rest on a false premise and was closed out by
correcting the record instead.** One item remains.

## Repository state

- Branch `main`, HEAD **`21d4e2a`** — `Correct the UI-test env-var claim and document the
  live-write gate (#87)`.
- PRs **#86** and **#87** merged; no open PRs, no open issues in this lane. Both branches
  deleted locally and on the remote.
- Codex still has **23 uncommitted files** on `main`. As of 22:17 that tree **compiles**
  (`** BUILD SUCCEEDED **`) — see *Codex's lane* below, this changed during the session.

## What shipped

### #86 — `LibraryStore.refresh()` asks each item's own source (was item 2)

`refresh()` resolved `SourceRegistry.shared.active` once and asked that one source for **every**
saved item's id, ignoring each `LibraryItem.sourceId`. With MangaDex active and Junjou Romantica
(WeebCentral) saved, pull-to-refresh sent a WeebCentral slug to the MangaDex API; the request
failed, `refresh()` is best-effort, so the item silently kept stale `chapterNumbers` and its
unread badge never moved.

Items are now paired with their own source **up front on the main actor**, before the task group
starts. That shape is forced, not stylistic: the nested `addNext()` inside `withTaskGroup` is
nonisolated and cannot call the `@MainActor` registry. A nil `sourceId` means MangaDex, matching
`HistoryView:146` and `BookmarksView:235`; only an *unregistered* id falls through to `active`.

`LibraryStore` now takes an injectable `SourceRegistry`, matching the `sourceOverride` seam the
view models already use.

**Red was proven, not assumed.** With the seam in place but the old `active` lookup restored,
`testRefreshAsksEachItemsOwnSource` fails exactly as the bug describes — MangaDex asked for
`["md-1", "wc-1"]`, WeebCentral for `[]`. Full suite after the fix: **572 tests, 2 skipped,
0 failures**.

### #87 — the item-3 premise was wrong (was item 3)

The previous handoff recorded that **`xcodebuild` cannot pass an environment variable to a UI
test in this project**, and concluded `testLiveHorimiyaCompletionPushesProgress` could only be
armed from an Xcode scheme. It also proposed moving the gate to a marker file.

**That is false.** Measured with a throwaway probe test that dumped the runner's
`ProcessInfo.processInfo.environment`:

| Invocation | Reaches `ProcessInfo`? |
|---|---|
| shell `MAL_LIVE_WRITE=1` | no |
| shell `TEST_RUNNER_MAL_LIVE_WRITE=1` | **yes**, as `MAL_LIVE_WRITE` |
| `xcodebuild … TEST_RUNNER_MAL_LIVE_WRITE=1` (build-setting argument) | no |

Confirmed under both `test` and `test-without-building`. It must be a **shell** variable;
`xcodebuild` strips the `TEST_RUNNER_` prefix on the way in. The third row is the trap — it
looks like the documented mechanism and silently does nothing, and is the likely source of the
original mismeasurement.

So **no marker file was needed.** The gate keeps its `XCTSkipUnless`, now documents the working
invocation, and its skip message names the prefixed variable. The two handoffs and the plan that
carried the false claim were corrected in place — struck through with the measurement table
rather than silently rewritten, so it does not get re-derived a third time.

**The live test was not run.** It writes to a real MyAnimeList account and needs explicit
approval plus the read/restore harness. The mechanism is proven by the probe, not by firing the
write. Verified only that the gate still **fails closed**: without the variable it skips.

Also re-confirmed the plan's foreground-retry claim on its own evidence — it could not be
confirmed retroactively before, because `testSignOutClearsTheAccountAndItsQueue` runs last
alphabetically and clears the outbox. Ran `testForegroundingRetriesQueuedWork` alone (passed,
125.7s) and read the outbox immediately: `retryCount: 2`, `userID: 1000001`,
`desiredProgress: 97`, `failure: "transient"`. `userID 1000001` is the stand-in, so the real
account was never involved.

## The one item left: the Settings screenshots don't show what they're named for

Unchanged from the previous handoff, and still worth doing.

`51-offline-queued`, `52-offline-queued-after-relaunch`, `62-sync-off-nothing-queued`,
`65-sync-on-queued`, `71-queued-before-signout` and `81-queued` all capture Settings **scrolled
to the top**, with the MyAnimeList section cut off behind the tab bar. The queue line is never
visible in any of them.

The assertions are still real evidence — they read the element's `value` out of the hierarchy,
and the relaunch check compares two values for equality. So the *claims* hold. But the
screenshots are worthless as artifacts, and they are exactly what a reviewer would look at.

**This is the second time this trap has been hit** — the afternoon handoff already recorded
that asserting the header was `isHittable` stopped scrolling with the card still behind the tab
bar. Fix it at the source, in a helper the checks share, so it cannot regress a third time.

### What I confirmed before stopping

- **`attach` is one four-line helper** at `Manga-ReaderUITests/Manga_ReaderUITests.swift:281`,
  and it already takes the `XCUIApplication` as a parameter. A scroll-into-view step belongs
  either inside it or in a wrapper beside it — one edit, not six.
- **All six named screenshots do exist.** `52-offline-queued-after-relaunch` attaches the
  `relaunched` app instance rather than `app`, which is why a naive grep for `attach(app,` finds
  only five. Any shared helper has to take the app as a parameter for that reason.
- The nine Settings-area attach sites are at lines **1060, 1099, 1110, 1118, 1132, 1158, 1174,
  1204, 1215**. Only the six above are cut off; `60-sync-disabled`, `63-sync-reenabled`,
  `72-after-signout` and `82-after-foreground` were not part of the complaint — **check them
  rather than assuming**, since the same helper will change all nine.
- `syncQueue(in:)` at line 1220 matches `app.descendants(matching: .any)["Sync queue"]`
  deliberately — SwiftUI projects the combined element as a `StaticText` on the current runtime,
  and that is not a semantic contract. **Don't narrow it back to a type** while writing the
  scroll helper.

**Do not gate the scroll on `isHittable`** — that is the exact mistake that produced this bug
the first time. `isHittable` is true while the element sits behind the tab bar.

### Scope, and why it is probably safe now

Item 1 looks **confined to `Manga-ReaderUITests/`**, which Codex is not touching. The earlier
handoff warned items 1–2 collided with Codex's view files, but the `ReaderView` changes it
mentioned (`readerCloseButton`, `readerPageIndicator`) are already-shipped production edits, not
pending work. Confirm that before starting; if the helper turns out to need a production
accessibility identifier, that lands in Codex's files and the collision is back.

## Codex's lane — this changed during the session

**Codex is active, not stalled.** At 21:55 its tree had not been touched since 18:23 and did
**not** compile; by 22:17 it had resumed and fixed it. Do not carry the "Codex is stuck" reading
from the previous handoff forward — re-check mtimes before concluding anything.

What it did in that window:

- **Fixed a real compile break in `HomeView.swift`.** A `? :` returned `VStackLayout` on one
  branch and `ZStackLayout` on the other inside a single `AnyLayout(...)`. Each branch is now
  wrapped in its own `AnyLayout`, so both sides share a type. Correct fix.
- Recaptured `iphone-axxxl-dark-fixed.png` at an accessibility text size — same piece of work,
  a Home section-header collision at large text.
- Wrote `.impeccable/audit/2026-08-24-native-ui-audit.md`, scoring the UI **17/20**.

**It is mid-sequence, not finished.** The audit's own findings name three follow-up commands
(`$impeccable audit`, `$impeccable adapt`, `$impeccable clarify`), and all 23 files are still
uncommitted. The view files are still live — leave them alone.

**Its whole lane is still uncommitted on `main`**, which is how the last three sessions have
started. That is now a standing risk, not an observation: ADR-0021, `PRODUCT.md`, `DESIGN.md`,
the glossary addition, the `.impeccable/` audit and the view-file pass are one `git checkout`
away from being lost.

## Gotchas

**Build in a worktree while Codex is mid-pass.** Both PRs this session were built and verified
in a clean worktree off the merge base, because `main`'s working tree did not compile at the
time. It compiles now, but Codex is still editing it — if you must build against `main`, pass a
separate `-derivedDataPath` so you do not collide with Codex's own build.

**The worktree needs `Secrets.xcconfig` copied in.** A fresh `git worktree add` fails with
`Unable to open base configuration reference file` until you copy it from the main checkout. It
is untracked, so it does not come along. Delete it again before committing.

**A new test class in `Manga-ReaderUITests` needs no `pbxproj` edit** if you append to an
existing file, but watch for name collisions — `RecordingSource` already exists in
`Manga_ReaderTests.swift`, and a second one fails the build with `invalid redeclaration`.

**`gh pr merge --delete-branch` fails while a worktree holds the branch.** Remove the worktree
first, or delete the branch by hand afterwards.

## Still-standing warnings from the previous handoff

These were not revisited and remain true:

- **Do not tap library cards by normalized coordinate.** The grid re-lays out as covers stream
  in; a passing run once opened Made in Abyss believing it was Chainsaw Man.
- **The reader restores the last-read position**, so an already-read chapter opens on its final
  page and a forward probe advances into the next chapter.
- **Re-resolve `get_app_container` every time** — the id changed four times in one session.
- **CI does not run the UI target** (`-only-testing:Manga-ReaderTests`), so a rename that drops
  `readerPageIndicator`, `readerCloseButton` or `libraryCoverCard` takes all five Task 12 checks
  down at once and CI will not notice. Re-run the five after Codex's pass lands.
