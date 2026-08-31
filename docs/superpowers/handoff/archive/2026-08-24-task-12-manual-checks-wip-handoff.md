# Handoff — PR #84 merged; Task 12's manual checks half-built

> Resolved later on 2026-08-24 on `task-12-manual-checks`. The shared driver was pinned to
> Chainsaw Man chapter 97 because chapters 230–232 had empty at-home payloads; repeat runs now
> reset the chapter through its real **Mark as unread** action. All five checks passed, including
> a persisted foreground retry-count advance from 1 to 2. This file remains the original WIP
> handoff and the debugging context it captured.

Session of 2026-08-24 (late afternoon). **Work is uncommitted on `main`** — five modified
files, no branch, no commit. Branch them before doing anything else.

## Done and durable

- **PR #84 merged** (squash, `d4e4157`), branch deleted, **Issue #81 auto-closed**. Local
  `main` is up to date. CI was green on the final commit.
- **Auto-merge enabled** on the repo (`allow_auto_merge: true`), at the user's request. The
  earlier failure of `gh pr merge --auto` was this setting being off; that command works now.

## Task 12: one of three remaining boxes verified

`testSignedOutReadingIsUnchanged` **passes**, and the two claims were checked separately:

- The screenshots were inspected, not just the checkmark.
- `mal-progress-outbox.json` was still `{"version":1,"deferred":[],"ready":[]}` with an
  **unchanged mtime** after the run — signed-out reading queued nothing.

The other two boxes (the five-part exercise, and the already-satisfied commit/push/PR line)
are **not** ticked in `docs/superpowers/plans/2026-08-21-mal-oauth-progress.md`. Nothing in
that plan file was edited this session.

## What is uncommitted, and why

| File | Change |
|---|---|
| `Services/MALTokenClient.swift` | `MALOfflineTransport` (DEBUG) — always throws `URLError(.notConnectedToInternet)` |
| `Services/AppComposition.swift` | `-uitest-mal-offline` swaps it in **for the authenticated client only** |
| `Views/BookmarksView.swift` | `.accessibilityIdentifier("libraryCoverCard")` on the grid's NavigationLink |
| `Views/ReaderView.swift` | `readerPageIndicator` identifier; `Close reader` label + `readerCloseButton` id |
| `Manga-ReaderUITests/…` | five new tests + a shared reader driver |

The reader's close button had **no accessibility label at all** — a real VoiceOver defect,
since the reader hides both bars and that button is the only way out. Worth keeping
regardless of the tests.

## The safety argument for the new tests

They run on the seeded stand-in account, and **two independent things** keep them off a real
MyAnimeList list: the seeded credential is the string `uitest-access` (cannot authenticate,
user id `1_000_001` vs the real `10146880`), and `-uitest-mal-offline` means no request leaves
the process. Only `testForegroundingRetriesQueuedWork` is weaker than its name: it proves the
retry *fires*, not that it *delivers* — the stand-in credential cannot deliver by
construction. Delivery through that same drain is what the live Horimiya run already proved.

## Resume here

`testSignedOutReadingIsUnchanged` passes. The other four have **never been run green**:
`testOfflineCompletionQueuesAndSurvivesRelaunch`,
`testDisablingSyncStopsQueueingAndReenablingResumes`,
`testSignOutClearsTheAccountAndItsQueue`, `testForegroundingRetriesQueuedWork`.

The current failure is in the **shared driver**, so it blocks all four: after switching the
library tap from a normalized coordinate to `card.tap()`, the run reaches Chainsaw Man's
detail page but then fails `"the reader should load pages"` — `readerPageIndicator` never
appears within 30s. Unknown whether the chapter tap missed, the chapter genuinely failed to
load, or the chrome-reveal tap loop is the problem. **Dump `app.debugDescription` at that
assertion first**; that is what diagnosed every previous step here.

```sh
xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO -derivedDataPath <dd> -resultBundlePath <r>.xcresult \
  test -only-testing:Manga-ReaderUITests/Manga_ReaderUITests/testSignedOutReadingIsUnchanged
```

## Gotchas found this session

**~~`xcodebuild` cannot pass an environment variable to a UI test here.~~ WRONG — corrected
2026-08-24 (evening).** It can. A shell `TEST_RUNNER_MAL_LIVE_WRITE=1` reaches the runner as
`MAL_LIVE_WRITE`; `xcodebuild` strips the `TEST_RUNNER_` prefix on the way in. Re-measured
with a throwaway probe test that dumped `ProcessInfo.processInfo.environment`:

| Invocation | Reached `ProcessInfo`? |
|---|---|
| shell `MAL_LIVE_WRITE=1` | no |
| shell `TEST_RUNNER_MAL_LIVE_WRITE=1` | **yes**, as `MAL_LIVE_WRITE` |
| `xcodebuild … TEST_RUNNER_MAL_LIVE_WRITE=1` (build-setting argument) | no |

Confirmed with both `test` and `test-without-building`. The middle row is the one that works,
and it is a *shell* variable — passing the same string as an xcodebuild build-setting argument
does **not** work, which is the likely source of the original mismeasurement.

So no marker file is needed, and `XCTSkipUnless` gates are usable from the CLI after all.
`testLiveHorimiyaCompletionPushesProgress` keeps its gate and now documents this invocation.
The reason the *other* live UI tests stay ungated is unchanged and still stands on its own:
**CI runs `-only-testing:Manga-ReaderTests`**, so the UI target never runs there.

**~~Therefore `testLiveHorimiyaCompletionPushesProgress` cannot currently be armed from the
CLI.~~ Also wrong**, and for the same reason — it arms fine with the `TEST_RUNNER_` prefix
above. Its live leg was still verified by hand rather than by running that test, and failing
closed remains the right behaviour for a gate that writes to a real account.

**Do not tap library cards by normalized coordinate.** The grid re-lays out as covers stream
in, so a coordinate computed from the matched frame lands on whichever cell has moved into
that spot. A passing run opened **Made in Abyss** while the test believed it had opened
Chainsaw Man, and asserted nothing that could notice. The driver now taps the element and
asserts the opened title.

**The library's first card is Junjou Romantica on WeebCentral** — a second source's detail
page, which is the inherited-source trap behind Issue #81. The driver names its title
(`manualCheckTitle = "Chainsaw Man"`) rather than taking whatever is first.

**The reader restores the last-read position**, so an already-read chapter opens *on* its
final page and a forward probe advances into the next chapter. The driver probes backwards,
walks to page 1, then reads forward — a real traversal regardless of prior state.

**The app data container changed twice more this session** (`67859B35` → `302874AE`).
Re-resolve `get_app_container` every time. The fixture is intact (`works.json`, 19662 bytes);
a copy of Application Support + Preferences is in this session's scratchpad, which will not
survive.
