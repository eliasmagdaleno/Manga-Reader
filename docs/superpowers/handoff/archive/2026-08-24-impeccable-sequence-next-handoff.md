# Handoff — Run the whole-app Impeccable sequence before notification implementation

Session of 2026-08-24. The product/design audit and the background-update grilling are complete.
There is **no active implementation task**. Run the Impeccable sequence below before planning or
building ADR-0021.

## Repository state

- Branch: `main`
- HEAD: `13b8846` — `Verify MAL progress lifecycle on device (#85)`
- Existing user-owned untracked file:
  `docs/superpowers/handoff/archive/2026-08-24-mal-oauth-progress-complete-handoff.md`. Preserve it.
- This session created or changed:
  - `PRODUCT.md`
  - `.impeccable/config.json`
  - `.impeccable/critique/2026-08-25T00-46-11Z__manga-reader.md`
  - `docs/glossary.md`
  - `docs/adr/0021-background-library-refresh-and-new-chapter-notifications.md`
  - this handoff
- `git diff --check` passed after the product, glossary, and ADR edits.
- No app source or project file was changed.

## Start here

Run these as separate bounded Impeccable sessions, in order. Finish and verify each command before
starting the next; preserve app behavior and the incumbent Ink & Seal identity unless the command's
confirmed brief explicitly changes it.

1. **`$impeccable document`** — capture the existing Ink & Seal visual system in `DESIGN.md`.
   The incumbent system is coherent and is the visual authority; do not treat the missing file as a
   greenfield redesign invitation.
2. **`$impeccable adapt all of the app`** — make the existing screens release-safe across Dynamic
   Type, VoiceOver primary tasks, Reduce Motion, light/dark contrast, 44-point targets, compact
   widths, and iPad. This is the public-release accessibility baseline confirmed by the user.
3. **`$impeccable shape Home and Library updates`** — plan the deliberate Home blend and the
   first-class personal Updates experience. This shapes the UI/data contract only; ADR-0021's
   background scheduler and notification pipeline remain a later implementation project.
4. **`$impeccable onboard hidden reading interactions`** — expose or teach Library refresh,
   chapter secondary actions, and tap-to-reveal reader chrome while retaining gestures as shortcuts.
5. **`$impeccable clarify source scope and update badges`** — distinguish Home's global browse
   source from Search's local source, and make numeric Library badges unmistakably mean unread
   chapters.
6. **`$impeccable harden empty, loading, stale, and error states`** — add direct recovery/next-step
   actions, accessibility announcements, focus restoration, and honest freshness language.
7. **`$impeccable polish all changed surfaces`** — one bounded visual and interaction finishing
   pass after the structural commands are complete.
8. **`$impeccable audit all of the app`** and **`$impeccable critique all of the app`** — re-score
   the finished app and compare the critique trend against the current 30/40 baseline.

## Confirmed product direction

- Home is a deliberate blend: actionable personal updates first when present, then personalized
  recommendations, then source-wide discovery.
- The first public release requires readable contrast, Dynamic Type, 44-point controls,
  VoiceOver-operable primary tasks, and Reduce Motion support. Custom rotors, a dedicated Assistive
  Access layout, and comprehensive keyboard optimization may follow later.
- Adult sources remain opt-in.
- Analytics are intended to be on by default with an easy Settings opt-out, but provider, event
  schema, retention, disclosure, regional compliance, deletion/export, and model-training use are
  still open. Do not invent or implement analytics during this sequence.
- Impeccable's recorded default is comp-first (`.impeccable/config.json`).

The durable source is `PRODUCT.md`; update it only when the user changes product truth.

## Current critique and audit

The archived critique is
`.impeccable/critique/2026-08-25T00-46-11Z__manga-reader.md`.

- Design critique: **30/40**. Ink & Seal is specific and coherent; the main UX failure is that the
  product promise “keep me current” is buried behind generic feeds, small Library badges, and a
  hidden pull-to-refresh gesture.
- Native audit: **11/20**. The app reads as genuinely native, but accessibility and adaptivity need
  significant work before public release.
- Deterministic detector: zero findings, but it is markup-oriented and provides no meaningful
  assurance for SwiftUI.
- Visual evidence: existing light/dark screenshots plus the installed app on the iPhone 17 Pro
  simulator. The iPad findings are source-based and still require simulator/device confirmation.

### Release-blocking audit findings

1. Fixed 10–13 pt branded typography bypasses Dynamic Type
   (`Manga-Reader/Views/Components/Theme.swift:65-74`).
2. Color contrast failures include light tertiary/background ≈ 2.43:1, light seal/background ≈
   3.8:1, and dark tertiary/background ≈ 3.45:1
   (`Manga-Reader/Views/Components/Theme.swift:39-60`).
3. Reduce Motion, Increased Contrast, Reduce Transparency, Bold Text, and Differentiate Without
   Color are not handled systematically.
4. Reader chrome controls render at 40×40 pt, below Apple's 44-point target
   (`Manga-Reader/Views/ReaderView.swift:634-642`).
5. The target supports iPad, but Library columns, cover sizes, Settings composition, and reader
   sizing remain phone-shaped. `ReaderView` reads `UIScreen.main.bounds`
   (`Manga-Reader/Views/ReaderView.swift:525`).

### UX findings to preserve through the sequence

- Keep the strong detail-to-reader state logic: Start, Continue, next chapter, and reread.
- Keep system navigation, controls, and native zoom/pan physics.
- Keep the careful destructive-history and MyAnimeList account copy.
- Give recoverable Home/detail errors an adjacent action.
- Give empty Library and collection states direct routes to Browse/Search or collection management.
- Make pull-to-refresh, long-press chapter actions, and reader-chrome reveal discoverable without
  removing their shortcut value.
- Do not let adapting for accessibility flatten Ink & Seal into generic system styling. Preserve
  its product-specific layer while system components own interaction and semantics.

## Notification work is decided, not started

`docs/adr/0021-background-library-refresh-and-new-chapter-notifications.md` is accepted and is the
implementation authority after the Impeccable sequence. `docs/glossary.md` now defines Library
refresh, Background Library refresh, new-chapter event, notification baseline, newly discovered,
and new-chapter notification.

The ADR pins:

- device-only, best-effort `BGAppRefreshTask` plus local notifications first;
- no exact twice-daily or delivery-time promise;
- refresh on app activation and manual refresh as healing paths;
- Work-level event identity with Listing-specific source checks;
- a silent first-refresh baseline;
- one notification per Work per refresh and iOS grouping across Works;
- chapter-list deep links rather than skipping to the newest chapter;
- generic adult-title notification copy unless separately enabled;
- independent notification authorization and in-app Updates;
- persisted, cancellable, prioritized round-robin scheduling for large libraries;
- removal clears notification state, while mute preserves it;
- newly discovered presentation state remains separate from read/unread state.

Do not implement that pipeline during the Impeccable refinement sequence. The shaped Home/Library
surface may define the view-facing state it will eventually consume, but source polling,
BackgroundTasks registration, notification authorization, scheduling, and persistence belong to a
separate test-first plan afterward.

## Important code fact for later

The existing manual refresh is wrong for a multi-source Library: `LibraryStore.refresh()` captures
`SourceRegistry.shared.active` once and uses it for every saved id
(`Manga-Reader/Services/LibraryStore.swift:270-289`), even though `LibraryItem` persists `sourceId`
(`:12-18`). The ADR replaces this with Work-level refresh over each Work's Listing keys. Do not
paper over the bug by merely switching from the active Source to `LibraryItem.sourceId`; that would
still miss linked Listings and duplicate Work-level events.

## Completion gate

The Impeccable sequence is complete only when:

- `DESIGN.md` records the incumbent visual authority;
- every command above has either completed or has an explicit user-approved deferral;
- the final native audit includes iPhone and iPad, light and dark appearances, and a large Dynamic
  Type pass;
- primary tasks have VoiceOver evidence rather than source inspection alone;
- the final critique snapshot is persisted and its trend is reported;
- app behavior remains verified with the repository's required iPhone 17 Pro destination and
  `-parallel-testing-enabled NO` for every test invocation;
- the working tree is reviewed immediately before staging so unrelated `project.pbxproj` churn and
  the pre-existing handoff file remain untouched.

After this gate, create a separate test-first plan for ADR-0021. Do not treat this handoff as that
implementation plan.
