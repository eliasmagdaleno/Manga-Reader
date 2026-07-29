# Session Handoff — 2026-07-29: reader 404 trap, model layer done, view rewire left

**Audience:** the next session finishing ADR-0012.

Companion to `2026-07-29-anilist-pool-handoff.md`, which is **still current for the recommender**
and untouched by this work. Its blocker stands: ADR-0011 needs 3 AniList-resolved Works and the
live store has 1, so seeding the library with two or three mainstream series is still a
prerequisite before any pool code. Nothing below changes that.

## What prompted this

User report: opening a chapter that 404s traps you in the reader. The only control is Retry, which
can never succeed, and force-quitting the app is the only way out. Reproduced and root-caused —
three reasonable decisions lined up so the exit was reachable only through the view that failure
prevents from rendering. Full trace in ADR-0012's Context.

## State

| | |
|---|---|
| `main` | `163d650` — PR #29 merged this session (`--squash --delete-branch`) |
| Working branch | `reader-failure-states`, cut from `main`, **not yet committed** |
| ADRs | 0012 accepted and written; **next free number is 0013** |
| New tests | 29 added, all green (16 presentation + 13 view model) |
| Full suite | **NOT yet run** since these landed — do this first |

## Done

- **ADR-0012** — `docs/adr/0012-reader-failure-states-and-chapter-advance-commit.md`. Six decisions,
  all line citations verified against the code. Read it before touching anything; it is the spec.
- **`Manga-Reader/Models/ReaderPresentation.swift`** — the state→screen decision as a pure value,
  plus `isTransientFailure` / the `ClassifiedFailure` protocol with conformances on `MangaDexError`
  and `SourceError`.
- **`Manga-Reader/Models/ReaderViewModel.swift`** — `@MainActor`, injected `MangaSource`, injected
  prefetch. `advance(to:landing:)` is load-then-commit. Also owns `ReaderError.noPages`.
- **`Manga-ReaderTests/ReaderPresentationTests.swift`** (16) and
  **`ReaderViewModelTests.swift`** (13). Both added to the project with `xcp` — `Manga-ReaderTests`
  is not a synchronized group. `Models/` is, so the two source files needed no project edit.

Both test files were **confirmed red before the implementation**, and deliberately so:

- The presentation stub returned `.content` / `chromeForced: false` always → 8 of 15 failed,
  including the exhaustive invariant on all 8 input combinations.
- The view model was first written with the **shipped** mutate-first `advance` → exactly the three
  load-then-commit tests failed and everything else passed. That is the proof the new tests catch
  the original bug rather than merely describing the new code.

## Left to do

### 1. Run the full suite

It has not been run since these files landed. Expect 274 + 29 = **303**. Anything else means one of
the new files broke something — most likely the `ClassifiedFailure` conformances, which are
retroactive extensions on two widely-used error enums.

### 2. Rewire `ReaderView` (the remaining work, and the biggest edit)

`ReaderView.swift` is still entirely unmodified — it holds its own `@State` and calls
`SourceRegistry.shared` directly at `:128` and `:380`. It must become a consumer of
`ReaderViewModel`:

- Replace `pages` / `errorMessage` / `isLoading` / `currentChapter` / `loadedChapters` `@State` with
  a `@StateObject ReaderViewModel`. **Keep `showChrome`, `currentPage`, `mode` (`@AppStorage`) and
  the `history` progress recording in the view** — ADR-0012 puts UI state and progress there
  deliberately.
- Drive the body off `vm.presentation.body` rather than the current `if let errorMessage` chain at
  `:104-110`.
- Gate both overlays (`:113`, `:116`) and `.statusBarHidden` (`:120`) on
  `showChrome || vm.presentation.chromeForced`.
- `errorState` (`:169`) must render Retry **only** when `canRetry`, and always offer a way out.
- Add the banner for `vm.presentation.banner` — this is new UI. `InkNotice` is a block element, not
  an overlay, so it needs an overlay treatment rather than a reuse.
- `advanceProgress` (`:195`) keeps calling `history.record`, but reads `vm.currentChapter`.
- The pager must honour `vm.landingPage` instead of computing its own start from `startPageRequest`.

**Gotcha:** `pageOrder` (`:247`) is what turns an empty page list into an empty `TabView`. With the
presentation type driving the body, `.content` is only reached when `pageCount > 0`, so that path
becomes unreachable — but do not delete `pageOrder`'s bounds handling, since the interstitial
indices still depend on it.

### 3. Hand-check on the iPhone 17 simulator

ADR-0012 explicitly does **not** cover this with a UI test, and the reason is recorded: the UI tests
hit live MangaDex, are not in CI, and one red is no signal. What the unit tests cannot prove is that
`dismiss()` actually escapes a `NavigationLink` push with the navigation bar hidden
(`ReaderView.swift:121`). Verify by hand:

1. Open a chapter that 404s → error text, **no** Retry, a working ✕.
2. Open a healthy chapter, read, swipe into a dead next chapter → the chapter you were on survives,
   error appears as a banner.
3. Normal open still works and the top bar auto-hides once pages arrive.

Item 1 is the actual reported bug. Do not claim the fix works without it.

### 4. Commit, PR

Branch from `main` was already done. **Do not stack** — see the standing gotcha.

## Decisions worth not re-litigating

All argued out in a grilling session and recorded in ADR-0012 with the rejected alternatives:

- Chrome visibility is **derived** (`showChrome || pages.isEmpty`), never assigned in a `catch`.
  Assigning works today and creates permanent bookkeeping.
- **Unknown errors are transient.** Matches `permanentStatus`'s `default: return nil`. Wrongly
  offering Retry costs a tap; wrongly withholding it strands a user.
- **408 is transient here but not in `MetadataUpgradeQueue.permanentStatus`** (which excludes only
  429). Deliberate divergence, recorded as a revisit trigger — the queue should probably adopt it.
- Zero pages is decided in the model, **not thrown by the sources**, purely because
  `ReaderView.swift:380` is the only consumer. Revisit if a second one appears.

## Facts verified live 2026-07-29 (do not re-derive)

- `GET /at-home/server/{id}` returns **404 `not_found_http_exception`** for a missing chapter.
  Probed with a nil UUID and a malformed id; both 404.
- Both sources can return `[]` with no throw — `MangaDexAPI.swift:591`, `WeebCentralSource.swift:87`.
- `ReaderView.swift:380` is the only production consumer of `pageURLs`; all 14 mocks stub `[]`.
- `permanentStatus(of:)` is `MetadataUpgradeQueue.swift:259-267`: `400..<500` except `429`, and
  `nil` for unrecognised error types.

## Known hazard this fix does NOT address

MangaDex returns 404 from `/at-home/server` for **externally hosted** chapters as well as missing
ones, and `Chapter` decodes neither `externalUrl` nor a page count (`MangaDexAPI.swift:125-131`,
`:156-167`). So "read this on the publisher's site" and "this is gone" are indistinguishable and
now produce the same permanent-failure message. Recorded as an ADR-0012 hazard and revisit trigger.
Fixing it is a chapter-list change, not a reader change.

## Gotchas (carried forward, all still true)

- **SourceKit is unreliable here** and was noisy all session — "No such module 'XCTest'", "Cannot
  find type 'Chapter' in scope" on files that compile and test clean. Judge only by `xcodebuild`.
- **The `agy` post-commit hook runs its own `xcodebuild`** and holds the DerivedData lock for 2+
  minutes; a concurrent build dies with "database is locked". Gate on
  `until ! pgrep -f "agy --model" >/dev/null; do sleep 15; done`.
- **Do not stack PRs.** Merging a base with `--delete-branch` closes the child unrecoverably.
- **`xcp` writes reformat the three synchronized-group entries**, and Xcode silently reformats them
  back on its own schedule. Check `git diff --stat` immediately before `git add`, not after `xcp`.
