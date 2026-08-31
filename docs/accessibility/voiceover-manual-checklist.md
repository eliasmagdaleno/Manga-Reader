# Manual VoiceOver checklist — issue #90

A human-driven pass over the flows automated evidence cannot close: traversal order,
announcements, and focus behaviour. Derived from the shipping views, so every expectation
below names a real element and, where it matters, the line that produces it.

- **Device:** a real iPhone if possible (VoiceOver in the simulator differs on rotor and
  focus restoration). Simulator fallback: iPhone 17 Pro, the seeded-fixture device.
- **Turn on:** Settings → Accessibility → VoiceOver, and bind the Accessibility Shortcut
  (triple-click side button) so you can drop out of VoiceOver fast.
- **Gestures used below:** swipe right = next element, swipe left = previous,
  double-tap = activate, two-finger swipe up = read from top, rotor (two-finger twist) →
  **Actions** then swipe up/down = custom actions, then double-tap to run.

**To run it:** `./scripts/voiceover-pass.sh` from the repo root walks these rows one at
a time, so you can read your phone instead of scrolling this table. It parses the rows
below at runtime — this file stays the source of truth — records verdicts in
`docs/accessibility/voiceover-results-<date>.md`, and resumes where you stopped, since a
55-row pass is long enough that quitting halfway is a normal way to use it. Editing this
table by hand works too.

Record for each row: **pass / fail / note**. A "suspected" row is a place the code already
looks wrong — confirm the symptom before filing, and file it as its own issue.

## Ground rules for judging

- Every control announces a **label**, a **trait** ("button", "link"), and where it has one a
  **value** ("selected", the reading mode).
- State never depends on colour alone (DESIGN.md, "Focus / State"). If a row is dimmed to mean
  *read*, VoiceOver has to say so.
- Nothing focusable is invisible; nothing visible is unreachable.
- After a sheet or a full-screen view closes, focus lands on **the thing that opened it** — not
  the top of the screen, and never on a dismissed layer.

---

## 1. Library (Bookmarks tab)

| # | Step | Expected |
|---|---|---|
| 1.1 | Two-finger swipe up from the top | Reads "Library" heading, then the collection chips, then the grid — no element skipped, no repeat |
| 1.2 | Reach a collection chip ("All", "Updates", a collection) | Announces its title and count, trait **button**, value **"Selected"** / **"Not selected"** (`BookmarksView.swift:238`) |
| 1.3 | Double-tap a chip | Filter changes; focus stays on the chip; new value announced |
| 1.4 | Reach a cover card | One element, not four — reads "*title*, N unread chapters, *stamp*" (`MangaCoverCard.swift:78`) |
| 1.5 | Reach the toolbar refresh button | "Refresh Library, button", hint "Checks saved titles for new chapters" (`BookmarksView.swift:131`) |
| 1.6 | Double-tap refresh | Hears **"Library updated"** announced when it completes (`BookmarksView.swift:163`) — and the visual banner is not the only signal |
| 1.7 | During the refresh | Button reports disabled; focus is not yanked to the banner mid-read |
| 1.8 | Reach "Manage Collections" | Announces the label, not "slider horizontal 3" (`BookmarksView.swift:139`) |
| 1.9 | **Focus restoration:** open Manage Collections, close the sheet | Focus returns to the **Manage Collections button** |
| 1.10 | Pull-to-refresh, if the gesture exists on this screen | There is a VoiceOver-operable route to the same action (the toolbar button counts — DESIGN.md forbids gesture-only tasks) |

**Suspected:** the "Updates" chip's count and the unread badge are two different numbers with
similar phrasing — check they don't read as contradictory.

## 2. Updates header (wherever `UpdatesHeader` appears)

| # | Step | Expected |
|---|---|---|
| 2.1 | Reach the refresh button, idle | "Refresh updates. *status text*" — status includes unread count and last-checked (`UpdatesHeader.swift:42`) |
| 2.2 | While refreshing | "Refreshing updates", and the button reports disabled |
| 2.3 | Reach a `WorkUpdateRow` | One element: "*title*, *chapter text*" — the cover and chevron are hidden (`WorkUpdateRow.swift:48`) |

## 3. Browse → detail

| # | Step | Expected |
|---|---|---|
| 3.1 | From a rail or grid, double-tap a cover | Detail view opens; focus lands at the top of the new screen, and the back button is reachable |
| 3.2 | Traverse the header | Title, then metadata, then the library button — the source badge reads "Source: *name*" once, not per glyph (`SourceBranding.swift:125`) |
| 3.3 | Library button | "Add to Library" or "Manage Library Collections", matching current state (`MangaDetailView.swift:334`) |
| 3.4 | Double-tap it while out of library | State flips **and** the label re-announces on next focus |
| 3.5 | Tag chips | Each reads "Browse *tag*, button" (`MangaDetailView.swift:352`) |
| 3.6 | Synopsis | Readable as continuous text; any "more" affordance is a real button |
| 3.7 | "Open on *source*" | Labelled, not a bare glyph (`MangaDetailView.swift:99`) |
| 3.8 | Chapter preview rows | See §4 — same rows, same expectations |
| 3.9 | "Show all N chapters" | Reads the full sentence, trait button/link (`MangaDetailView.swift:513`) |
| 3.10 | More Like This rail | Announces as a group with a heading; cards read like 1.4 |

## 4. Chapter rows — read / unread actions

Applies to both the detail preview (`MangaDetailView.swift:480-490`) and the full
`ChapterListView` (`ChapterListView.swift:64-69`).

| # | Step | Expected |
|---|---|---|
| 4.1 | Focus a chapter row | **One** element reading chapter number, title, and date |
| 4.2 | Same row, read state | The announcement says read / unread — or in-progress with the page number |
| 4.3 | Rotor → Actions on the row | Offers "Mark as read" / "Mark as unread" (matching current state) and "Mark this and all below as read" |
| 4.4 | Run the toggle action | State changes; VoiceOver confirms, or the row re-announces changed on next focus |
| 4.5 | Run "mark this and all below" | Every row below changes; focus does not jump to the top of the list |
| 4.6 | Double-tap the row itself | Opens the reader at the saved position, not page 1 |

**Suspected (4.1 / 4.2):** `ChapterRow` has no `accessibilityElement(children: .combine)` and
no label — its three `Text`s are likely three separate focus stops, and read state is carried
**only** by the dim `Ink.tertiary` colour. Both are plain violations of the ground rules above
if confirmed. Check whether the custom actions in 4.3 are still reachable when focus is on a
child rather than the row.

## 5. Batch selection (ChapterListView)

| # | Step | Expected |
|---|---|---|
| 5.1 | The top hint banner | Reads as static text once, near the top of traversal (`ChapterListView.swift:79`) |
| 5.2 | "SELECT" in the toolbar | Announced as "Select", not spelled out letter by letter |
| 5.3 | Enter selection mode | Announcement or focus change makes the mode switch perceivable — not silent |
| 5.4 | Focus a row in selection mode | Announces selected / not selected |
| 5.5 | Bottom bar | "Select All" / "Deselect All", "Mark Unread", "Mark Read" all reachable; disabled state announced when nothing is selected |
| 5.6 | Mark Read with a selection | Change applies; focus stays in the bottom bar |
| 5.7 | "CANCEL" | Exits; focus returns somewhere sensible in the list |
| 5.8 | The sort button | Reads "Newest" / "Oldest" as a word plus its trait, not "arrow up arrow down" |

**Suspected (5.2 / 5.8):** these are uppercase `Text` labels with letter tracking inside plain
buttons — likely to read as initialisms.

## 6. Reader

Chrome starts visible (`showChrome = true`) and toggles on a single tap.

| # | Step | Expected |
|---|---|---|
| 6.1 | Reader opens | Focus lands inside the reader, and "Close reader" is reachable within a few swipes (`ReaderView.swift:607`) |
| 6.2 | Reading-mode button | "Reading mode", value = current mode (`ReaderView.swift:634`) |
| 6.3 | Change mode via the menu | Picker items are reachable and labelled; the new mode is announced |
| 6.4 | Page indicator | Conveys "page N of M" — **not** "3 · 12" read as a middle dot (`ReaderView.swift:664`) |
| 6.5 | Swipe through pages, paged mode | Each page is a reachable element that announces *something* ("page N", ideally) — not silence, and not "image" |
| 6.6 | Right-to-left mode | Swipe direction and announced page numbers agree; a VoiceOver swipe-right doesn't silently move backwards through the story |
| 6.7 | Chapter interstitial page | Reads the chapter it is about to load; loading state is announced |
| 6.8 | Error banner | Announced when it appears, and its dismiss target is reachable before the 5s auto-dismiss (`ReaderView.swift:286`) |
| 6.9 | Vertical (webtoon) mode | The strip scrolls with three-finger swipes; pages announce; the anchor overlay is not focusable |
| 6.10 | End-of-chapter mark | Reads "End, N pages" — not "END · 12 PAGES" spelled out |
| 6.11 | Chrome hidden (single tap) | The close button is either still reachable or restorable without sight — the reader hides both system bars, so this is the only exit |
| 6.12 | **Focus restoration:** close the reader | Focus returns to the chapter row that opened it |

**Suspected (6.5):** `ZoomablePage` wraps `CachedAsyncImage` with no label or identifier
(`ReaderView.swift:705-730`), so pages may be unlabelled or entirely unreachable — which would
make the pager unnavigable by VoiceOver even though the chrome is fine.
**Suspected (6.4 / 6.10):** both strings are typographic (`·`, tracking) with no
`accessibilityLabel`.

## 7. Cross-cutting

| # | Step | Expected |
|---|---|---|
| 7.1 | Tab bar | Each tab announces name, trait, and selected state |
| 7.2 | Rotor → Headings | Section headings exist on Home, Library, and detail; you can jump between them |
| 7.3 | Any live-loading rail | Loading and empty states announce; you never focus a spinner with no label |
| 7.4 | Notices (`ForYouBasisNotice`, `UnmatchedTitleNotice`, `ForYouUnavailableNotice`) | Read as text with any action inside them reachable |
| 7.5 | Whole pass, screen rotation | Traversal order survives rotation |
| 7.6 | Whole pass at AX text sizes | Nothing is clipped out of the accessibility tree when the layout goes vertical |

---

## Filing what you find

One issue per defect, labelled `needs-triage`, milestone **Accessibility & UI polish**,
each naming the checklist row (e.g. "VoiceOver 4.1") and the file:line. The four *suspected*
clusters above (chapter rows, uppercase toolbar labels, reader pages, typographic indicators)
are each a plausible single fix — group them that way rather than one issue per row.

Close #90 when every row has a verdict, not when every defect is fixed.
