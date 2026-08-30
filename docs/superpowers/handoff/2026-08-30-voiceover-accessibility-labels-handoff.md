# Handoff — VoiceOver checklist written; every code-side label defect fixed

Date: 2026-08-30
Repository: `/Users/eliasmagdaleno/Manga-Reader`
Branch: `main`

## State

Issue **#90** (manual VoiceOver traversal) is still **open, and should be** — see "What is
actually owed" below. What shipped is everything a code change *can* do for it: the script for
the manual pass, plus fixes for all six accessibility-label defects that writing the script
surfaced.

| PR | What | Status |
|---|---|---|
| **#102** | `docs/accessibility/voiceover-manual-checklist.md` — the manual pass, ~50 numbered rows | merged `846b3a6` |
| **#103** | `ChapterRowPresentation` — chapter rows | merged `1b31432` |
| **#104** | `ReaderAccessibility` — reader pages, indicators, chapter-list toolbar | merged `31d12c6` |
| **#105** | History row + `WorkUpdateSummary.accessibilityLabel` | auto-merge armed on green |

If **#105** is not on `main` when you pick this up, check it: `gh pr view 105`. Nothing else
is in flight.

## What was wrong, in one sentence

This app was built to be read with the eyes, and its visual identity is the reason: Ink & Seal
puts state in *dim colour* and identity in *tracked uppercase and middle dots*. Neither is
perceivable to VoiceOver. Every defect found was one of those two shapes:

- **State by colour alone** — `ChapterRow` dimmed to mean "read" and said nothing;
  `WorkUpdateRow`'s "NEW" badge and `isMuted` were drawn and not spoken.
- **Typography where a word belongs** — `"CH·12"`, `"4 · 20"`, `"END · 20 PAGES"`,
  `"CH·5 · page 3/20"`, `SELECT` / `CANCEL` / `NEWEST`. A middle dot is not a word.
- Plus the pure absence: reader pages (`ZoomablePage`, `WebtoonPage`) were bare unlabelled
  images, so the pager may have had nothing for VoiceOver to land on at all.

DESIGN.md line 155 already forbade the first shape. The rule existed; nothing enforced it.

## The pattern all three fixes follow, and why

Each fix puts the spoken string in a **pure value beside the view, not in the view** —
`ChapterRowPresentation`, `ReaderAccessibility`, `WorkUpdateSummary.accessibilityLabel`,
`ReadingEntry.accessibilityLabel(relativeTime:)`. This matches the repo's existing
`*Presentation` types (`ReaderPresentation`, `LibraryUpdatesPresentation`) and it is what makes
a spoken sentence testable without standing up a SwiftUI view.

Where the eye and the ear describe the same state, **one value computes both**, so they cannot
drift: `ChapterRowPresentation` returns `isDimmed` and `accessibilityLabel` from the same two
booleans, and `WorkUpdateRow`'s visible subtitle now reads from the same `unreadChapterText`
its label uses. The tests that matter are the ones that walk the whole input space —
`testStateIsAlwaysSpoken`, `testDimmedRowsAreExactlyTheOnesThatSayRead`,
`testEveryPageSaysWhichPageOfHowMany`, `testNoSpokenStringContainsTheMiddleDot` — so a state
added later cannot reintroduce a silently colour-only row.

## The gotcha worth carrying

**Changing an accessibility label silently breaks XCUITests, and CI will not tell you.**
`app.buttons["NEWEST"]` matches the *label*, not the drawn text, and
`indicatorCurrent`/`indicatorTotal` in `Manga_ReaderUITests.swift` were parsing the middle dot
out of `indicator.label`. Both broke on #104 and had to be rewritten. CI runs build + unit
tests only, and those two live in the live-network suites CI does not run — so nothing would
have caught it.

**Before changing any accessibility label, grep the UI tests for the old string.** The
assertion should depend on the *spoken* form, which is the contract; the visual string is free
to change again.

## What is actually owed

**#90 is a human gate and none of this closes it.** Every change above makes the app *say* the
right thing. Only a person driving VoiceOver on-device can confirm traversal order, focus
restoration, and that the reader pages are actually reachable — which is precisely what the
automated evidence from PR #89 could not establish either.

Work the checklist at `docs/accessibility/voiceover-manual-checklist.md`, record a verdict per
row, and close #90 when every row has one — **not** when every defect is fixed. Rows 4.3 (are
the custom read actions still reachable now that the row is one element?) and 6.5 (are the
pages reachable at all?) are the ones this session's changes most need confirmed, since both
were reasoned from the code rather than observed.

Two rows were fixed but never seen: the checklist's *suspected* markers on chapter rows,
reader pages, indicators and toolbar labels were written from reading the code. If the manual
pass finds one of them was never actually broken, say so in the row rather than assuming the
fix was needed.

## Suggested next work

The backlog is `gh issue list`, which after this holds only #90. Nothing else is owed. If you
want adjacent work, the checklist's §7 cross-cutting rows (rotor headings, live-loading rails,
AX text sizes) are unexamined and would likely produce real issues.
