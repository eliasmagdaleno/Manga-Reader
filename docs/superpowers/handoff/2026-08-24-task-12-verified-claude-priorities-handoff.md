# Handoff — Task 12 verified independently; three items queued for Claude

Session of 2026-08-24 (evening). This handoff covers **Claude's lane only**. Codex is
continuing its own product/design work in parallel — see *Who owns what* at the bottom before
touching anything.

## Repository state

- Branch `main`, HEAD **`13b8846`** — `Verify MAL progress lifecycle on device (#85)`.
- PR #84 and PR #85 are both merged. Issue #81 is closed. No open PRs from this lane.
- **Auto-merge is now enabled** on the repo (`allow_auto_merge: true`), so
  `gh pr merge <N> --squash --auto --delete-branch` works — it failed before because the
  repository setting was off, not because of the command.

## What was verified, and how

Codex's Task 12 work (PR #85) was checked rather than taken on trust. All of it holds:

| Claim | Evidence |
|---|---|
| Five manual checks pass | Ran all five: **426.8s, 0 failures** on the seeded iPhone 17 Pro |
| The real MAL account is untouched | `Proxylink` (10146880) still signed in, `syncEnabled` true, `automaticallyAddsTitles` true |
| Nothing was queued or lost | `mal-progress-outbox.json` empty; `works.json` intact at 19662 bytes |
| PR #85 CI green | SwiftLint + Build & unit tests both SUCCESS |

Codex correctly diagnosed the blocker the previous session left behind: **chapters 230–232 of
Chainsaw Man are listed but have no pages on MangaDex**, which is why the page indicator never
appeared. It pinned the exercise to `CH·97`. It also fixed two real defects in the driver as
first written — the Library tab preserving its `NavigationStack` across a second traversal, and
`Sync queue` being projected as a **`StaticText`**, not an `otherElement`.

**CI does not cover any of this.** The workflow runs `-only-testing:Manga-ReaderTests`, so the
UI target never runs there. The 426s run above is the only evidence these five pass, and it
lives nowhere but this document.

## Claude's queue, in priority order

### 1. The Settings screenshots do not show what they are named for

`51-offline-queued`, `52-offline-queued-after-relaunch`, `62-sync-off-nothing-queued`,
`65-sync-on-queued`, `71-queued-before-signout` and `81-queued` all capture Settings **scrolled
to the top**, with the MyAnimeList section cut off behind the tab bar. The queue line is never
visible in any of them.

The assertions are still real evidence — they read the element's value out of the hierarchy,
and the relaunch check compares the two values for equality. So the *claims* hold. But the
screenshots are worthless as artifacts, and they are exactly what a reviewer would look at.

**This is the second time this trap has been hit.** The 2026-08-24 afternoon handoff already
recorded it: "asserting the header was `isHittable` stopped scrolling with the section's card
still behind the tab bar." Fix it at the source — scroll the section into view before every
`attach`, in a helper the checks share, so it cannot regress a third time.

### 2. `LibraryStore.refresh()` asks the wrong Source

**Confirmed live**, `Manga-Reader/Services/LibraryStore.swift:277-287`: `refresh()` resolves
`SourceRegistry.shared.active` **once** and then asks that single Source for **every** saved
item's id, ignoring the `sourceId` each item carries.

The seeded library has one WeebCentral title (Junjou Romantica) among 13 MangaDex ones, so
pull-to-refresh is already asking MangaDex for a WeebCentral id today. This is a shipped bug,
not a hypothetical — and it is the premise ADR-0021 builds on, so it wants fixing before any
background-refresh work lands on top of it.

### 3. Two verification gates that cannot actually be armed

**`xcodebuild` cannot pass an environment variable to a UI test in this project.** Neither a
shell `FOO=1` nor `TEST_RUNNER_FOO=1` reached `ProcessInfo` in the test bundle — tried with
both `test` and `test-without-building`. This is the same limitation the fixture-seeding tool
worked around with a marker file.

Consequence: **`testLiveHorimiyaCompletionPushesProgress` cannot be run from the CLI at all.**
Its `MAL_LIVE_WRITE=1` gate can only be set from an Xcode scheme. Its live leg was verified by
hand on 2026-08-24, *not* by running that test. Failing closed is right for a gate that writes
to a real account, but the comment implies a CLI usage that does not work — either fix the
comment or move the gate to a marker file.

Relatedly: the plan's claim that the foreground check "advanced the persisted stand-in item's
retry count from 1 to 2" is asserted **out of process**, after the run. It could not be
confirmed retroactively, because `testSignOutClearsTheAccountAndItsQueue` runs last
alphabetically and clears the outbox. Re-run `testForegroundingRetriesQueuedWork` alone and
read the outbox immediately if that number needs to stand on its own.

## Why the new test seams exist

Three DEBUG-only launch arguments now shape these checks. All are scoped so they cannot reach a
real account:

- `-uitest-mal-offline` — swaps `MALOfflineTransport` in **for the authenticated client only**;
  `MALTokenClient` keeps the real transport, so a simulated outage cannot push a real account
  toward reauthorization.
- `-uitest-mal-state signed-in` — seeds the stand-in profile (`UITestReader`, id `1_000_001`)
  on ephemeral stores, with the credential string `uitest-access`, which cannot authenticate.
- `-uitest-mal-reset-outbox` — clears the queue **for the stand-in user id only**.

Two independent things therefore keep these checks off a real MyAnimeList list: the credential
cannot authenticate, and with the offline transport no request leaves the process at all.

`testForegroundingRetriesQueuedWork` is weaker than its name: it proves the retry **fires**,
not that it **delivers** — the stand-in credential cannot deliver by construction. Delivery
through that same drain is what the live Horimiya run proved.

## Two production changes worth keeping regardless of the tests

- `ReaderView` — the reader's close button had **no accessibility label at all**. The reader
  hides both the navigation bar and the tab bar, so that button is the only way out; unlabelled,
  it was unreachable to VoiceOver. It is now `Close reader` / `readerCloseButton`.
- `ReaderView` — the page indicator is now `readerPageIndicator`. Matching it by its `" · "`
  text was ambiguous: the end-of-chapter marker reads `END · N PAGES`.

## Gotchas

**Do not tap library cards by normalized coordinate.** The grid re-lays out as covers stream
in, so a coordinate computed from the matched frame lands on whichever cell has moved into that
spot. A *passing* run opened **Made in Abyss** while the test believed it had opened Chainsaw
Man, and asserted nothing that could notice. The driver now taps the element and asserts the
title it landed on.

**The reader restores the last-read position**, so an already-read chapter opens *on* its final
page and a forward probe advances into the next chapter. The driver probes backwards, walks to
page 1, then reads forward.

**The app data container keeps changing** — four different ids across this session
(`67859B35` → `302874AE` → `21D28C16` → …). Re-resolve `get_app_container` every single time;
never cache the path across steps.

## Who owns what

**Codex is mid-flight on a product/design lane.** As of this writing it has left uncommitted on
`main`: `PRODUCT.md`, `.impeccable/`, `docs/adr/0021-background-library-refresh-and-new-chapter-notifications.md`,
a 41-line `docs/glossary.md` addition, and two handoffs of its own
(`…-impeccable-sequence-next-handoff.md`, `…-mal-oauth-progress-complete-handoff.md`).
**Leave those alone** — they are Codex's working set, and the user has said Codex continues.

**ADR-0021 was reviewed by the user on 2026-08-24** and stands as `Accepted`. Treat it as a
settled decision, not an open question.

Still worth noting: that lane's work — the ADR, `PRODUCT.md`, `DESIGN.md`, the glossary
addition and the view-file pass — **is all uncommitted on `main`**, which is how the last two
sessions started too.

**The lanes now collide — check this before starting anything.** Within minutes of the above
being written, Codex began the `$impeccable adapt` pass and has `Views/ReaderView.swift`,
`Views/BookmarksView.swift`, `Views/MangaDetailView.swift`, `Views/CategoryGridView.swift`,
`Components/MangaCoverCard.swift`, `Components/PagedMangaGrid.swift`,
`Components/SourceBranding.swift` and `Components/Theme.swift` modified **uncommitted on
`main`**, plus a new `DESIGN.md`.

Claude's items 1–2 touch `Manga-ReaderUITests/`, `Views/ReaderView.swift` and
`Services/LibraryStore.swift` — two of which Codex is editing right now.

Two consequences:

- **Do not edit those view files in this lane** until Codex's pass is committed. Start with
  item 2 (`LibraryStore.swift`) or item 3 (test-gate wiring), which Codex is not touching.
- **The UI-test identifiers are load-bearing and easy to lose in an accessibility sweep.**
  `readerPageIndicator`, `readerCloseButton` and `libraryCoverCard` are the only stable handles
  the five Task 12 checks have. Both were still present at the time of writing (verified by
  grep), but re-run the five checks after Codex's pass lands — a redesign that renames or drops
  an identifier will take all five down at once, and **CI will not catch it**, because the UI
  target does not run there.
