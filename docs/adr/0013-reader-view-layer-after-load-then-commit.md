# ADR-0013 — The reader's view layer after load-then-commit

- **Status:** Accepted (2026-07-29)
- **Amends:** ADR-0012 (its "the landing-page calculation straddles the split" cost — this is the
  second pass it asked for, and it lands the seam in the view model's favour)
- **Related:** ADR-0008 (transient vs permanent, in the upgrade queue), ADR-0003 (bridged sources
  cannot conform to `ClassifiedFailure`)

## Context

ADR-0012's model layer shipped in `33c29be`: `ReaderPresentation`, `isTransientFailure`, and a
`ReaderViewModel` whose `advance` is load-then-commit. `ReaderView` was deliberately left untouched
in that commit and still holds the original bug. This ADR is the wiring, and it exists because
**load-then-commit removed four protections that were holding by accident.**

None of the four was ever written down as a protection. Each was a side effect of `loadNextChapter`
setting `pages = []` before awaiting (`ReaderView.swift:150`, `:161`), which tore the pager down and
put the whole screen into `.loading` for the duration of every chapter fetch:

1. **The pager index could not be stranded**, because the pager did not exist while a chapter
   loaded. Retaining `pages` leaves `currentPage` sitting on the sentinel index that requested the
   advance.
2. **Re-entry was impossible**, because there was nothing left to swipe. Retaining the pager lets a
   second `Task` (`ReaderView.swift:240`, `:242`) enter an `advance` that has no guard.
3. **A loading indicator appeared for free**, because `pages.isEmpty` drove `presentation` to
   `.loading`. Retaining pages means `pageCount > 0`, so the body stays `.content`
   (`ReaderPresentation.swift:117-122`) and the trigger index renders `Color.clear`.
4. **The progress counters were reset by whoever changed the chapter**, and that was the view
   (`ReaderView.swift:153-154`, `:164-165`). The view no longer changes chapters.

The pattern is the same one ADR-0012 was written about: a property that holds because of an
unrelated implementation detail, with nothing forcing it. Four of the eight decisions below only
replace something the commit-ordering change silently took away.

**Facts verified live 2026-07-29 (do not re-derive):**

- **The full unit suite is green at 303 tests, 0 failures** on `reader-failure-states` at `33c29be`
  (274 pre-existing + 29 from ADR-0012). The retroactive `ClassifiedFailure` conformances on
  `MangaDexError` and `SourceError` broke nothing.
- **`pageOrder`'s `else` branch (`ReaderView.swift:228`) is reachable only by the two advance-trigger
  indices.** `pageOrder` emits `-prevExtra ..< pages.count + nextExtra` where each extra is 0 or 2
  (`:247-253`), so `-1` and `pages.count` are the interstitials and `-2` and `pages.count + 1` — the
  two indices `onChange` treats as triggers (`:239-243`) — are the only fall-through. When an
  adjacent chapter is nil its extra is 0 and those indices do not exist. `Color.clear` is not a
  bounds-safety fallback; it *is* the trigger page.
- **`HistoryStore.record` takes `max(first.page, page)`** for the same manga + chapter
  (`HistoryStore.swift:67`). An over-eager progress reset therefore cannot regress recorded history;
  the failure mode is one-sided — silently *not* recording.
- **Exactly one error case produces developer-facing copy.** `MangaDexError.httpStatus` returns
  `"Request failed with HTTP status \(code)."` (`MangaDexAPI.swift:349`). Every `SourceError` case is
  already a plain English sentence (`MangaSource.swift:83-94`), and so is `ReaderError.noPages`.
- **`errorMessage == nil` after a completed load is a reliable "it committed" test.** `advance`
  clears it on entry and assigns it only in the `catch` (`ReaderViewModel.swift:117`, `:131`).
- **`PageRetry` is a `Button` on purpose** — "so its tap wins over the reader's chrome-toggle tap
  gesture" (`ReaderView.swift:466-467`). Any new tappable overlay in the reader inherits that
  requirement.

## Decisions

### The pager target is where the pager belongs, not where a load landed

`landingPage` is renamed **`pagerTarget`** and widened: it is written on both paths of `advance`, so
after a *failed* advance it holds the position the pager should retreat to. The retreat is derived
from the `Landing` that was requested — `.first` was a forward advance, so the target is the last
real page of the retained chapter; `.last` was backward, so `0`; `.exact` was an initial load or a
retry, so unchanged.

The paged reader must move, because failure leaves `currentPage` on `pages.count + 1`, which renders
the blank trigger page. Leaving the user there technically preserves the chapter they were reading
and shows them a blank screen anyway, which forfeits most of what load-then-commit bought.

Keeping the name and documenting the widened meaning was rejected. It is cheaper — `landingPage` is
asserted by name in three of the thirteen view-model tests (`ReaderViewModelTests.swift:178`, `:190`,
`:237`) — and it reintroduces the exact defect ADR-0012 was
written about at the scale of one identifier: a property whose name asserts success while its value
also encodes failure. Snapping back to the interstitial instead of the last page was also rejected;
it is more legible about *what* failed and parks the user on a card advertising a chapter that does
not load.

**Accepted cost: the view model now holds an opinion about pager positioning.** ADR-0012 flagged this
seam as possibly needing a second pass and this is it, decided in the model's favour. The view keeps
`currentPage` because the pager mutates it on every swipe and the sentinel-index scheme is pure pager
mechanics; the model only says where it *should* be after a load.

### One counter, two markers: issued and completed

`advance` keeps a private monotonic `requestGeneration`, incremented when a request is **issued**,
and publishes `lastCompletedRequest`, set when a request **completes** and is still the newest. The
view's repositioning keys off `lastCompletedRequest`.

It cannot key off `pagerTarget`'s *value*. `loadNext` requests `.first`, which computes to `0`
(`ReaderViewModel.swift:144-151`), so advancing from a chapter opened at page 0 gives `0 → 0`,
`onChange` never fires, `currentPage` stays on the stale sentinel — and that index re-fires
`loadNext` against the new chapter. The common case is the broken one, and this is the same
value-versus-event mistake the vertical reader has been shipping (see below). Position needs an
event.

Two independent hand-bumped integers — one for the reposition, one for arbitration — was rejected.
Deriving both markers from one counter means they cannot disagree: `lastCompletedRequest` is always a
value `requestGeneration` actually issued, "has the newest request finished" is a comparison, and a
future cancellation story already has the state it needs.

**Accepted cost: the view reads a property named for *requests* to decide something about *pager
position*.** The indirection is real and needs a comment at the call site saying a completed request
is the only thing that moves the pager.

### The latest request wins; superseded ones commit nothing and report nothing

`advance` captures its generation and, after the await, returns without acting if a newer request has
been issued. The guard covers the commit, the `catch`, **and** `isLoading`.

All three matter. A superseded request that *fails* must not raise a banner about a chapter the user
has already navigated away from, and `defer { isLoading = false }` (`ReaderViewModel.swift:118`) as
written lets whichever request finishes first clear the flag under one still running.

`guard !isLoading else { return }` was rejected: it is one line and it drops the wrong request.
During a slow forward load the user changes their mind and swipes back, nothing happens, and then the
forward chapter commits and takes them there anyway. Cancelling the in-flight task was rejected as
worse *here*: it means the view model owning a `Task` handle, and a cancelled `advance` throws
`CancellationError` into that same `catch`, so it would surface a banner reading "Couldn't load the
next chapter. cancelled" unless special-cased. Generation-checking is correct under any interleaving
without introducing task ownership, and cancellation later becomes an optimisation on top of a rule
that is already right.

**Accepted cost: the superseded fetch still runs to completion** and still costs a round trip and a
`prefetch` call on a full chapter of image URLs (`ReaderViewModel.swift:129`). We only decline to act
on its result.

### Post-load bookkeeping is one ordered handler, not three racing observers

The view does all of its post-load work in a single `onChange(of: vm.lastCompletedRequest)`, in a
fixed order: reset the progress counters if `vm.currentChapter.id != progressChapterID`, then
`currentPage = vm.pagerTarget`, then `advanceProgress(to:)`.

The counters need resetting at all because `furthestPage` and `hasRecordedProgress` were reset by the
view's own `loadNextChapter` (`ReaderView.swift:153-154`) and that method is going away. Without it,
`advanceProgress`'s guard `index > furthestPage || !hasRecordedProgress` (`:197`) means a reader who
left chapter N at page 40 records *nothing* for pages 0–40 of chapter N+1 — and nothing at all for
any chapter shorter than 40 pages.

The reset can key on chapter identity because load-then-commit makes `currentChapter` change **only**
on a successful commit. That signal did not exist before and is a direct dividend of the commit
ordering.

Three separate `onChange` modifiers — one to reset, one to position, one for `currentPage`
(`:236-244`) — was rejected. If the position lands and `advanceProgress(to: 0)` runs before the reset,
the guard eats it and page 0 of the new chapter goes unrecorded until the user swipes. SwiftUI fires
`onChange` in attachment order in practice, and that is not a documented guarantee worth resting a
data-correctness path on.

**Accepted cost: a correctness-critical three-step sequence now lives in view code and is not
unit-testable.** Moving `furthestPage`/`hasRecordedProgress` into the view model would make it
impossible to get out of step, and was rejected for widening the seam further to hold state whose
only consumer is a view-side guard. This is the weakest of the eight decisions and the first one to
revisit if progress recording misbehaves.

### The vertical reader restores on commit only, and never snaps back

The webtoon reader's scroll restore keys off `lastCompletedRequest` with an `errorMessage == nil`
guard, inside the `ScrollViewReader` (the proxy is not reachable from the body-level handler), and
scrolls to `vm.pagerTarget`.

It replaces `.onChange(of: pages.count) { proxy.scrollTo(min(initialPage, count - 1)) }`
(`ReaderView.swift:282-285`), which has **two live bugs today**, independent of this branch: it
no-ops when consecutive chapters have equal page counts, leaving the reader scrolled partway into the
new chapter, and it reads `initialPage`, the immutable init parameter, so a session resumed at page
15 tries to restore page 15 of every subsequent chapter. One handler now covers the initial open, a
retry, and a chapter change.

**Vertical does not snap back on failure, and paged does.** The asymmetry is deliberate: the paged
reader has a discrete selection that failure strands on an index rendering nothing, so it must move;
the vertical reader has a continuous offset that failure leaves at the bottom of a chapter still
fully rendered, which is a legitimate place to be. Scrolling them to the last page's top would be a
yank with no problem to solve.

**Accepted cost: retry-by-gesture is worse in vertical mode.** The advance trigger is
`Color.clear.frame(height: 50).onAppear` (`ReaderView.swift:269-272`), and `onAppear` will not re-fire
without scrolling away and back, so after a failure the banner is the user's only signal and scrolling
up and back down is the only retry.

### Banner dismissal is view state; the model is never mutated to hide UI

The view holds `acknowledgedRequest` and renders `presentation.banner` only when it differs from
`lastCompletedRequest`. Tapping the banner acknowledges it; a ~5s timer keyed on the same value
auto-dismisses. A new failure bumps `lastCompletedRequest`, so the next banner shows even when the
message is identical — which every value-comparison approach gets wrong.

Adding `dismissBanner()` to the view model was rejected on the stronger of two arguments. The weaker
one is that dismissal is UI state and ADR-0012 drew the seam there. The load-bearing one is that
`errorMessage` is not the banner's text: `ReaderPresentation` derives the entire body from it
(`ReaderPresentation.swift:112-123`), and clearing it makes the model forget a failure happened while
leaving `failureIsTransient` behind as a stale flag describing a failure it no longer admits to.
Mutating the record to hide a strip of UI is the wrong direction.

Leaving the banner undismissable — it clears on the next load attempt (`ReaderViewModel.swift:117`) —
was rejected: a strip you cannot get rid of, reporting a failure you did not cause, is poor manners,
and it can persist for as long as the user keeps reading that chapter.

**Accepted cost: `presentation.banner` becomes advisory rather than authoritative.** The view can
suppress it, so `banner != nil` no longer means "a banner is on screen", and a `ReaderPresentation`
test cannot tell you what the user sees. The banner must also be a `Button`, per `PageRetry`'s
recorded reason (`ReaderView.swift:466-467`).

### The failure message names the direction, and one error type gets human copy

Two changes to what the user reads.

**The direction is composed in `advance`'s `catch`, keyed off the requested `Landing`:** `.first` →
"Couldn't load the next chapter. `<reason>`", `.last` → previous, `.exact` → `<reason>` unprefixed,
since that renders full-screen where the subject is unambiguous. Bare
`error.localizedDescription` (`ReaderViewModel.swift:131`) is fine full-screen and useless in a
banner — the user swipes forward, is snapped back, and reads a sentence with no subject. Publishing
the failed target chapter so the banner could name it was rejected: it costs a `@Published` that
exists only to caption a string, it reads badly against `ReaderError.noPages` (whose message is
already a full sentence about a chapter), and direction is the information the user actually lacks.
They know which chapter they swiped toward; they do not know that the swipe is why they are back
where they started.

**`MangaDexError.httpStatus` is rewritten for humans by a pure `readerFailureMessage(_:)`** placed
beside `isTransientFailure` in `ReaderPresentation.swift`, returning "This chapter isn't available to
read from this source. (HTTP 404)" and passing every other error through untouched. It goes there
because it is the same concern — the reader's opinion about what an error means — and stays a pure
function of an `Error`, so the tests that walk the classification cover the copy too. **The code stays
in the sentence** because ADR-0012's first hazard means we cannot claim the chapter does not exist,
only that it is not available here; when this is hit in the field the code is what distinguishes the
two.

Editing `MangaDexError.errorDescription` itself was rejected for this branch: those strings surface on
Home, Detail, Search and More Like This, and rewording a shared error type changes user-visible copy
on four screens with no tests asserting any of it. That is the right eventual fix and the wrong change
here.

**Accepted cost: two places now decide reader copy** — the model composes direction, a free function
rewrites one case — and a reader looking for "where does this sentence come from" has to find both.

### The advance trigger index is the loading page

The `else` branch of `pagedReader` renders `InterstitialPage` for the adjacent chapter plus a spinner
gated on `vm.isLoading`, instead of `Color.clear` (`ReaderView.swift:228`).

This is the protection ADR-0012 removed without noticing: the spinner and "Fetching pages"
(`:348-358`) used to appear during every chapter advance purely because `pages` was cleared first.
With pages retained the body stays `.content` for the whole fetch and the user sits on a blank screen
for however long `/at-home/server` takes. The fix is cheap because that branch is exactly the two
trigger indices and nothing else (see Context), so it is not a bounds fallback being repurposed — the
page whose only job is to request the next chapter becomes the page that reports on it. The user swipes
off "NEXT CHAPTER · Chapter 44" onto the same card with a spinner under it.

Letting `presentation` report `.loading` during an advance was rejected: that is the current
behaviour and it is precisely what ADR-0012's body condition rejected, since tearing down readable
content for a load that may fail is what load-then-commit exists to prevent. Taking it back for the
loading case would half-undo the decision. A progress indicator in the chrome instead was rejected
because chrome is hidden while reading.

**Accepted cost: `InterstitialPage` grows a third state** (`ReaderView.swift:488-520`), and two
consecutive pager pages show the same chapter card — continuity or duplication depending on how you
read it.

## Hazards

- **The folded post-load handler is untestable.** Reset-then-position-then-record is view code, and
  the bug it prevents (silently not recording progress after a chapter change) is invisible until
  someone inspects history. Nothing will catch a regression here.
- **`presentation.banner` no longer describes the screen.** The acknowledgement token means a
  `ReaderPresentation` test asserting `banner != nil` proves only that the model wants to show one.
- **`requestGeneration` and `lastCompletedRequest` are one concept in two properties.** A future edit
  that bumps the published marker without checking the generation, or vice versa, reintroduces the
  interleaving bug silently — both guards are `guard mine == generation` and neither fails loudly.
- **Nothing here addresses `.task` cancellation** (carried from ADR-0012). Latest-wins makes the
  *commit* correct; the work still runs.
- **The 404 hazard is unchanged.** An externally hosted MangaDex chapter and a missing one still
  produce the same message, now a more polished one (`MangaDexAPI.swift:125-131`, `:156-167`).

## Revisit triggers

- If progress recording misbehaves after a chapter change, move `furthestPage` and
  `hasRecordedProgress` into `ReaderViewModel` next to `currentChapter` so they reset in the same
  assignment that commits. That is the rejected alternative above and the one to reach for first.
- If task cancellation lands, it supersedes latest-wins arbitration rather than sitting beside it —
  and the `catch` must learn to ignore `CancellationError` before it does, or every cancelled advance
  raises a banner.
- If a third caller needs to know a load completed, promote `lastCompletedRequest` from "the thing
  that moves the pager" to a named domain event; three consumers of a bare `Int` is one too many.
- If `MangaDexError`'s copy is ever fixed at source, delete `readerFailureMessage`'s `httpStatus`
  case rather than leaving two layers rewriting the same string.
