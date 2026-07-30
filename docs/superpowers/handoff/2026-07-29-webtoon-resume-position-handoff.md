# Session Handoff — 2026-07-29: webtoon resume position (ADR-0014, not yet written)

**Audience:** the next session, starting fresh on `webtoon-resume-position`.

**Nothing is implemented yet.** All four design decisions were argued out in a grilling session and
are recorded below with the alternative each one beat. The next step is to write **ADR-0014** from
this, then implement. The reader work that precedes this is done and merged.

## State

| | |
|---|---|
| `main` | `bd0d678` — PR #30 merged (`--squash --delete-branch`), ADR-0012 + ADR-0013 |
| Working branch | `webtoon-resume-position`, cut from `main`, contains only this handoff |
| ADRs | next free number is **0014** |
| Tests | 317 green on `main` |

## What prompted this

Hand-checking ADR-0013 turned up that webtoon resume never restored position at all — the vertical
reader was mounted too late for its `onChange` observer to see the load complete. That bug is fixed
and merged (`task(id:)` instead of `onChange`). Resume now lands **close to** where the reader
stopped, but not exactly, and the remaining error is a **model** limitation, not a scroll bug:

`ReadingEntry.page` is a *page index* and a webtoon "page" is a long strip, so a chapter of 8 strips
offers exactly 8 resume points. You land at the top of the strip you were partway down.

The instinct to "add more resume points" is right, but only on the restore side — see the fourth
decision. As a *storage* model it would bake the resolution into every saved entry.

## The decision that constrains everything else

**`entry.page` is not just a resume pointer — it is the completion signal for three other
subsystems, one of which is the recommender.** Verified 2026-07-29:

- `ReadingResume.swift:68-71` — `finished = entry.pageCount > 0 && entry.page >= entry.pageCount - 1`,
  which picks `.cont` vs `.reread` for Continue Reading.
- `TasteProfile.swift:99` — the same computation, feeding taste signals.
- `ChapterRow.swift:23` — `inProgress = pageCount > 0 && page < pageCount - 1`, the in-progress badge.

That is why `HistoryStore.record` does `first.page = max(first.page, page)`
(`HistoryStore.swift:67`) — the monotonicity is **load-bearing, not incidental**. Repurposing `page`
as a last-position pointer would let a backwards scroll un-finish a finished chapter, flip Continue
Reading, resurrect a badge, and alter a recommender input. Do not do it.

## Decisions (write these up as ADR-0014)

### 1. `ReadingEntry` gains `fraction`; `page` stays an `Int`

`var fraction: Double = 0`, meaning "how far down `page` the reader had scrolled". Migration is free:
the default fills in for every existing entry and reads as today's behaviour.

**Beat:** making `page` a `Double` (`5.6` = 60% down strip 5). One field, migration equally free,
`max()` keeps working. Rejected because `page` is shared with the two *paged* modes, where it is a
`TabView` selection and a fraction is meaningless — widening it would make the field lie for two of
three reading modes to serve the third, and turn every progress comparison into floating point.

**Accepted cost:** two fields that must stay consistent. A `fraction` is only meaningful against the
`page` it was captured on, so anything writing one must write both; a stale pairing resumes at a
plausible-looking wrong place. The `Double` option is immune to this by construction.

### 2. The fraction attaches to `page`, and both stay monotonic

`record` takes `(page, fraction)` and applies a **lexicographic max**: same page, keep the larger
fraction; higher page, take the new pair. Every completion consumer above is untouched.

**Beat:** adding `resumePage` / `resumeFraction` as a true last-position pointer alongside the
completion fields. Always exact, including the backwards-scroll case. Rejected for putting a second
notion of position into a persisted type — two fields that look like the same thing, plus a rule
about which one every future reader of `ReadingEntry` should consult, which is exactly the ambiguity
that gets resolved wrongly in six months.

**Accepted cost:** scroll back to re-read, then exit, and you resume at your furthest point rather
than where you were. **This is already true today in both reading modes**, so it is a case left
unfixed rather than a regression. Revisit if it actually bothers anyone.

### 3. Persist on scroll-idle debounce, plus disappear and scene-phase background

The live position lives in the view model; `HistoryStore` is written on a ~1s debounce of scroll idle,
and unconditionally on disappear and on backgrounding.

**Why it matters:** `HistoryStore.save()` re-encodes the **entire** entries array — capped at 500
(`HistoryStore.swift:45`) — *and* the read-marks array, to JSON, on every single `record` call
(`:167-174`). Today `record` fires on page-appear, a few dozen times per chapter. Tracking a fraction
continuously would make that a full re-encode per scroll frame.

**Beat:** persisting only on disappear/background — zero write amplification and no debounce to own,
but it loses position on a force-quit or crash. Reading a long webtoon is the longest single-screen
session in the app and there is no other autosave anywhere, so that is the one failure mode users
notice. Also beat: recording when the top-most strip changes, which has today's write frequency but
stores only strip-boundary fractions — i.e. back to landing at the top of a strip.

**Follow-on, not urgent:** `save()` should stop being an all-or-nothing re-encode. The debounce makes
it survivable.

### 4. Capture with a `GeometryReader` per row; restore with a sub-page anchor grid

**Capture:** one `GeometryReader` per *realized* row, reporting the strip's frame in a named
coordinate space; derive which strip covers the viewport top and how far into it. Only a handful of
rows are realized in a `LazyVStack` at once. iOS 17's `.scrollPosition(id:)` gives the top visible
strip more cleanly but no fraction, so it does not remove the need.

**Restore:** overlay each `WebtoonPage` with a `VStack` of N `Color.clear` views carrying ids:

```swift
.overlay {
    VStack(spacing: 0) {
        ForEach(0..<slotCount, id: \.self) { slot in
            Color.clear.id(StripAnchor(page: index, slot: slot))
        }
    }
}
```

The overlay inherits the strip's measured height and `Color` is infinitely flexible, so the `VStack`
divides it into N equal slices **with no height arithmetic**. Restore is then
`scrollTo(StripAnchor(page: 5, slot: Int(0.62 * N)), anchor: .top)` — exact to 1/N of a strip, N a
tunable constant (at N = 50 a 3000pt strip resolves to ~60pt).

**Beat:** compensated anchor arithmetic — `anchor: UnitPoint(x: 0, y: f')` with
`f' = f·pageH / (pageH − viewportH)`, derived from the fact that `scrollTo` aligns the *same* unit
point on item and container. No extra views, and `pageH` is already available from the capture
`GeometryReader`. Rejected because the denominator goes to zero for any strip shorter than the
viewport, and `f'` exceeds 1 whenever `f > (pageH − viewportH)/pageH` — at pageH 2000, viewportH 800,
f 0.9 it is 1.5, and what `scrollTo` does with an out-of-range unit point is unspecified. Clamping
silently reintroduces "closer but not exact", which is the bug being fixed.

**Accepted cost:** capture and restore deliberately use *different* mechanisms — measuring is cheap
and wants precision, addressing wants stable identity — so the two halves are not symmetrical and a
reader has to understand both. Restore precision is quantized at 1/N, but N is a rendering constant,
not persisted, so it can be turned up later without touching saved data.

**Escape hatch if precision still misses:** go `UIScrollView` via `UIViewRepresentable`, where
`contentOffset` is exact. There is precedent — `Components/ZoomableContainer.swift` is UIScrollView-
backed because SwiftUI's zoom physics were wrong, which is the same shape of problem. Not recommended
now: a `LazyVStack` does not stay lazy inside a `UIScrollView`, so it means owning the lazy loading
too.

## Suggested order of work

1. Write **ADR-0014** from the four decisions above, house format, `Related: ADR-0013`. The
   `entry.page`-is-a-completion-signal finding belongs in its Context as a verified fact.
2. `ReadingEntry.fraction` + the lexicographic max in `HistoryStore.record`, TDD — this part is pure
   model and fully testable. Assert that a backwards scroll cannot reduce stored progress, and that
   `finished` for all three consumers is unchanged by any fraction value.
3. Capture in `verticalReader`, with the debounce. Persisting is view-adjacent, so keep the *decision*
   about what to write in a testable place and the plumbing thin.
4. Restore via the anchor grid, replacing the `scrollTo(vm.pagerTarget, anchor: .top)` that ADR-0013
   put in the `task(id:)`.
5. Hand-check: resume mid-strip, resume after a rotation, and confirm the paged modes are untouched.

## Carried-forward hazards worth knowing

- **The 50ms sleep in the webtoon restore.** ADR-0013 accepted a fixed wait before `scrollTo` because
  `task` starts before layout and a `LazyVStack` has no realized rows to aim at. It is guarded on
  `pagerTarget > 0`. The anchor grid does not remove the need for it.
- **Switching reading mode mid-chapter does not carry position** — entering webtoon scrolls to the
  page the chapter was *entered* at, not the one being read. Pre-existing; may be worth folding in.
- **A stub `MangaSource` mutated by both the test and the code under test must be `@MainActor`.**
  `MangaSource`'s methods are nonisolated, so `await source.pageURLs(...)` from a `@MainActor` view
  model runs off the main actor. `ReaderViewModelTests`' gated stub corrupted its own dictionaries and
  crashed with `-[__NSCFNumber objectForKey:]: unrecognized selector` — *after passing twice*.
- **SourceKit is unreliable here** — "No such module 'XCTest'", "Cannot find type 'Chapter' in scope"
  on files that compile and test clean. Judge only by `xcodebuild`.
- **The `agy` post-commit hook runs its own `xcodebuild`** and holds the DerivedData lock for 2+
  minutes; a concurrent build dies with "database is locked". Gate on
  `until ! pgrep -f "agy --model" >/dev/null; do sleep 15; done`.
- **Do not stack PRs.** Merging a base with `--delete-branch` closes the child unrecoverably.

## Also still open on the reader (separate, smaller)

- **Externally hosted chapters are reported to the user as broken.** They answer `/at-home/server`
  with 200 and an empty file list, so they fail through the zero-pages path and read "This chapter has
  no pages to read." Nothing is wrong — the chapter is published on the publisher's site. Cheap to
  fix: they report `pages: 0` in the `/chapter` feed and `ChapterAttributes`
  (`MangaDexAPI.swift:125-131`) does not decode `pages` yet, so one field would let the chapter list
  mark or route the row before anyone opens it. **The most worthwhile reader follow-up.**
- **The 5xx wording.** `readerFailureMessage` rewrites every `MangaDexError.httpStatus` to "This
  chapter isn't available to read from this source. (HTTP 503)", so a transient 503 gets that sentence
  next to a Retry button. One branch keyed on the classification already computed fixes it.
