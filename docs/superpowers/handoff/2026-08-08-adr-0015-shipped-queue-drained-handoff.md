# Session Handoff — 2026-08-08: ADR-0015 shipped, ADR queue drained

**Audience:** the next session. Supersedes `2026-08-07-adr-0015-amendments-decided-handoff.md`
entirely — its "Next" list is done and its four amendments are now in the ADR text.

**Work in flight: none.** `main` is clean and every ADR 0001–0015 is Accepted *and* implemented.
This is the first handoff in a while that hands off no partial work, which is why the "What to pick
up" section below matters more than usual.

## State

| | |
|---|---|
| `main` | **`ef55323`**, clean, in sync with origin |
| Branches | `foryou-rail-state` merged (PR #34, squashed to `fb7e84b`) and deleted both ends |
| Tests | **433 pass / 1 skipped / 0 failures**, verified locally and in CI |
| ADR-0015 | Implemented, device-checked, merged. Six amendments folded in |

## What this session did

Picked the work up off a machine migration. The last two days of work existed only on the old Mac —
`foryou-rail-state` had never been pushed — so nothing on this machine knew ADR-0015 existed. The
branch came over, then ADR-0015 went from ADR-only to merged:

1. **Amended the ADR** with the four decisions the 2026-08-07 grilling overturned.
2. **Engine** (`10df717`) — published `RailState`, `TagBlocked = (Work) -> Bool`,
   `profileAndExclusions()` returns the refusal reason via a private `ProfileOutcome`, ceiling test
   in `refusalReason(signals:profile:)`. Seven new tests.
3. **View** (`510e445`) — one `else if` in `HomeView`; `ForYouUnavailableNotice` in
   `Views/Components/` (synchronized group, no `project.pbxproj` edit needed).
4. **Composition root** (`3a3927d`) — `UpgradeAttemptMemory` hoisted and shared with the queue.
5. **Neutral fill** (`72366a0`) — see amendment 6 below.

Then repo hygiene (`ef55323`): `.DS_Store` and `**/xcuserdata/` ignored, and the `pbxproj` caveat in
`CLAUDE.md` corrected.

## Two more amendments, found by building rather than reasoning

The 2026-08-07 session found four decisions written from recall. Implementing them produced **two
more of exactly the same kind**, which is worth internalizing rather than just reading:

- **Amendment 5** — the ADR required `railState` to be assigned on `load()`'s `loadedOnce`
  short-circuit. There is nothing correct to assign there: that path returns *because* a previous
  `rebuild()` already decided the state, so writing to it could only overwrite a decided state with
  `.building`. `load()` is untouched.
- **Amendment 6** — the ADR rejected an `errorMessage` string on the ground that this state is not
  an error, but that argument was about *words*. The first implementation dropped `InkNotice`'s
  exclamation icon and kept its `Ink.sealSoft` fill; on screen it still read as an error banner.
  Now `Ink.surfaceAlt` + hairline. **This one was invisible to every test that could have been
  written — it needed a screenshot.**

All six are recorded in the ADR with what was wrong and why, in an "Amendments (2026-08-07)"
section. That record is the part a later reader cannot reconstruct from the corrected text.

## Device check — the technique, so it doesn't need re-deriving

`noTaggableSignal` was verified on the iPhone 17 simulator without adding any debug code to the app.
Two-phase, because `WorkID` is a random UUID and the attempt records cannot be precomputed:

1. Write history entries into the app's `UserDefaults` —
   `xcrun simctl spawn "iPhone 17" defaults write Elias-Magdaleno.Manga-Reader history.entries -data <hex>`,
   where the payload is a plain `JSONEncoder` array of `ReadingEntry` (dates are seconds since
   2001-01-01). Use a scraping source id and opaque numeric manga ids so the Works are untaggable.
2. Launch. The engine mints Works from history on the first rail build, producing
   `Library/Application Support/works.json` in the data container
   (`xcrun simctl get_app_container "iPhone 17" <bundleid> data`).
3. Read the minted `WorkID`s out of that file and write a sibling `upgrade-attempts.json`:
   `{"entries":[{"workId":{"raw":"…"},"checkedAt":<secs>,"outcome":{"unmatched":{"knownTitlesCount":N}}}]}`
   with `N` = that Work's `knownTitles.count`.
4. Relaunch and screenshot. Deleting the attempts file returns the slot to silence, which is what
   makes the before/after a real comparison rather than a layout accident.

Confirmed in light and dark. Scripts were scratchpad-only and are gone; the recipe above is the
durable part.

## What to pick up — recommendation

**ADR-0005, manual link override.** Accepted 2026-07-24 and never built: `WorkStore.merge(_:into:)`
(`:243`) exists as the primitive and comments already anticipate "a manual link arrives after both
Works already exist", but nothing user-facing calls it. Three things point at it:

- It is **ADR-0015's first revisit trigger**, written three days ago: surfacing it from the new
  notice turns `noTaggableSignal` from a dead end into an actionable state, and the notice's final
  clause is what gets rewritten when it lands.
- ADR-0015 **deferred** it explicitly ("the richer fix, not taken here"), it did not reject it.
- It is the oldest accepted-but-unbuilt decision in the repo.

**Grill ADR-0005 against the current call sites before planning from it.** Its text predates a great
deal of code, and this ADR's six amendments are six instances of what happens when that step is
skipped.

## Also open, in rough priority order

- **Deferred cleanup, explicitly owed:** retire `MyAnimeListDebugView` and its 3 live UI tests — the
  real More Like This rail has been proven since 2026-07-22.
- **No automated coverage of the `HomeView` rail branch or the root wiring.** Both rest on the
  manual device check above. `ForYouUnavailableNotice` carries the accessibility identifier
  `forYouUnavailableNotice` so a UI test can drive it.
- **Tracked minors from the blend work:** `malId` on `LibraryItem` so saved seeds skip the title
  search; More Like This reverse-resolution beyond MangaDex-only.
- **ADR-0015's mixed-library hazard** — three taggable Works beside twenty untaggable ones opens the
  gate and builds a rail from an eighth of the reader's taste. By the ADR's own terms this is not
  due until it is *reported* as bad recommendations rather than absent ones.
- **Not scheduled, and named as such:** cross-device sync, per-chapter read/unread marks, anything
  past manual refresh.

**Standing constraint:** the extension/repo system and comix.to are shelved, deliberately, since
2026-07-21. Do not resurrect without checking in first.

## Gotchas

The prior handoff's list still applies. Three updates from this session:

- **`project.pbxproj` churns during plain `xcodebuild build`/`test` runs**, not only after `xcp`.
  It happened twice here with Xcode open and `xcp` never invoked — synchronized-group entries
  collapsing to one line, plus a `name =` key dropped. Xcode was running both times, so this does
  *not* establish `xcodebuild` as the cause; `CLAUDE.md` now says exactly that rather than swapping
  one unverified claim for another. Check `git diff --stat` before every `git add`.
- **The simulator wedges on repeated `xcodebuild test` runs** — "Simulator device failed to launch …
  Busy (Application failed preflight checks)". It is not a code failure and not the flaky-UI-test
  pattern. `xcrun simctl shutdown all && xcrun simctl erase "iPhone 17"` clears it every time. This
  cost three false red runs before being recognized.
- **`gh pr checks` parses badly with `awk '{print $2}'`** — "Build & unit tests" contains a space,
  so field 2 is `&`. Use `awk -F'\t'`.

## Machine-migration leftovers

- **The Remember plugin's history did not come over.** `.remember/` here starts 2026-08-07 23:43
  (this machine's own setup) with an empty `archive.md` and no rotated archives. On the old Mac it
  is at `/Users/eliasmagdaleno/xcode/Manga-Reader/.remember/` — note the old path differs from this
  machine's `/Users/eliasmagdaleno/Manga-Reader`. It is gitignored, so cloning will never bring it.
- **The auto-memory came over intact** (15 files + index), re-keyed to the new project path.
- `NEW-MAC-SETUP.md` and `manga-reader-briefing.md` in `~/Downloads` are both stale as of this
  session; the briefing has been deleted, the setup doc has not been updated.
