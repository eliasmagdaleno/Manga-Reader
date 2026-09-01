# Handoff — Phase 1's logic is built; the view is not

Date: 2026-08-31 (late)
Repository: `/Users/eliasmagdaleno/Manga-Reader`
Branches: `feature/fulfillment-routing` (PR #116, open) and `docs/handoff-source-picker` (this).

**This is the live handoff, and it is the whole of what is outstanding.** Writing a new one means
`git mv`-ing this into `archive/` first and carrying forward whatever below is still true
(`CLAUDE.md` → "Handoffs"). It supersedes the launch-roadmap handoff, whose roadmap is restated
here in short and whose two owed threads carry forward unchanged.

## The roadmap, unchanged

Six phases, ~8–9 weeks of focused work, sequenced by dependency. Phase 1 is in progress; 2–6 are
untouched. The full reasoning is in the archived launch-roadmap handoff — **read it once** rather
than re-deriving it, particularly the catalog research.

1. **Finish what is nearly done** — source picker, MAL live-verify, VoiceOver pass. *In progress.*
2. **Host API design** (~1–1.5w) — spec + ADR amending 0003. The forever contract.
3. **JavaScriptCore runtime + WeebCentral port** (~2w).
4. **Repo format + installer** (~1–1.5w).
5. **Theme engines** (~1w for Madara, then days each) — Madara alone is 29 sites.
6. **Launch prep** (~1w).

The one-line version of the catalog finding, because it shapes Phase 2: Paperback's ~68 sources
are **55 generic-theme sites plus 23 bespoke ones**, so the host API must be designed for an
extension that takes *configuration*, not one-extension-per-site.

## What shipped this session

**PR #115, merged** (`57b2ec5`) — the launch roadmap.

**PR #116, open** — the source picker's entire logic layer, TDD'd, six commits:

| Type | Role |
|---|---|
| `FulfillmentRouter.rank` | ADR-0004's policy — evidence tiers, preference tiebreak, reference-total cap |
| `FulfillmentRouter.distinctChapterCount` | distinct chapters via the existing `ChapterOrdinal` |
| `ListingCountCache` | `Caches/`, 24h TTL, stale reads as unknown |
| `FulfillmentCoordinator` | cache-only synchronous pick, concurrent background reconcile |
| `SourcePreferenceStore` | primary source + per-Work pins |
| `SourcePickerPresentation` | the rows the view will render |

**638 tests, 0 failures**, 2 skipped (603 at session start). ADR-0004 gained **Amendment 1**.

### Decisions embedded in that code, so nobody relitigates them by accident

- **`nil` count means unknown, never zero** (ADR-0007). Three evidence tiers: counted non-empty,
  uncounted, counted-empty. An uncounted Listing beats one counted at zero and loses to one
  counted at all — the optimistic-render trade.
- **A known reference total caps the count rather than dividing by it.** 205 entries for a
  201-chapter series is padding, not completeness. Capping makes complete Listings tie, handing
  the choice to the quality preference.
- **Unnumbered entries ("Oneshot", "Extra") are not counted.** Readable but not *comparable*
  across sources.
- **A source that throws stays uncounted, never recorded as zero.** A timeout, a Cloudflare
  challenge and a redesign look identical; recording zero would bury a source for a full TTL on
  the strength of an outage.
- **A pin whose source is unregistered falls back to the ranking but is not deleted.** The source
  may come back.
- **The task group mirrors `LibraryStore.refresh`'s shape deliberately.** An earlier version used
  `compactMap`/`reduce` over the group — fine on local Swift 6.2, exactly the kind of thing CI's
  6.0 rejects.

## What is owed

### 1. Finish the picker — the view and the wiring. This is next.

Everything below the view is done and tested. What remains:

- **`MangaDetailView`** — `SourceStamp` (around line 151) becomes a picker when
  `SourcePickerPresentation.offersAChoice`, and stays exactly as it is when it does not. Render
  `presentation.rows`; each row carries `name`, `detail`, `isCurrent` and an
  `accessibilityLabel` already written for it. Selecting a row calls
  `SourcePreferenceStore.choose(_:for:)`; selecting the already-current row should
  `clearChoice(for:)`.
- **`AppComposition`** — construct `ListingCountCache`, `SourcePreferenceStore` and
  `FulfillmentCoordinator` and inject them the way the other services are.
- **Call `reconcile(_:)` when the detail page appears**, not before. Eager reconciling of the
  library is the strategy ADR-0004 rejects.
- **A Settings row for the primary source.** `SourcePreferenceStore.primarySourceId` is `nil`
  until chosen and the router falls back to MangaDex, so the UI needs a "no preference" state —
  do not default the picker to MangaDex, or choosing it becomes indistinguishable from not
  choosing.
- **A UI test.** No tap tool here, so this is the only way the wiring gets verified; see the
  `ui-verification-technique` memory. Note **no existing UI test touches the source stamp** —
  checked this session — so its label is currently free to change.

**Deliberately not built:** switching source does not yet re-fetch the chapter list. `chosenListing(for:)`
answers *which* Listing to open; making `MangaDetailView`/`ChapterListView` actually load from it
is part of this task and is the fiddliest half. Budget for it.

### 2. The manual VoiceOver pass — #90, and it is the user's to run

Unchanged. Open, `ready-for-human`, **no row has a verdict yet**, no results file in
`docs/accessibility/`. Run `./scripts/voiceover-pass.sh` from the repo root; it parses the
checklist at runtime, takes pass/fail/skip per row, writes
`docs/accessibility/voiceover-results-<date>.md`, and resumes where it stopped. Needs a **real
iPhone** — simulator VoiceOver differs on the rotor and focus restoration, which is most of what
these rows test.

Rows most needing eyes: **4.3**, **6.5**, **7.2**, **7.5**, **7.6**. Close #90 when every row has
a verdict, **not** when every defect is fixed.

### 3. Live-verify MAL progress push

The subsystem is built, wired and tested (`MALProgressCoordinator`, `MALProgressOutbox`, Settings
toggle and queue status). What no unit test can show: read a chapter to the end on a device with
a real account signed in, and confirm the number moves on myanimelist.net.
`scripts/mal_live_write.py` pokes the API directly if the in-app path needs isolating.

### 4. The duplication shape of doc rot — untouched, agent work

#113 fixed only *snapshots*. The same-fact-in-two-places shape is three of five known instances.
Audit `CLAUDE.md`, `DESIGN.md`, `PRODUCT.md`, `README.md`, `docs/glossary.md`, `docs/agents/*.md`
and the memory files; every factual claim about the code should be grep-verifiable *now*.
**ADRs are the exception** — amend, never correct.

Known instances waiting: `PRODUCT.md` still says "Content refresh is currently user-initiated"
(ADR-0021 shipped); `PRODUCT.md` also says search happens "within a selected source", which is
still true but will go false the moment cross-source search lands. Worth deciding whether the fix
is a one-time audit or something structural — a one-time audit produces instance seven eventually.

## Launch blockers that are not features

- **No app icon.** `AppIcon.appiconset/` holds only `Contents.json`. Being outsourced; order early.
- **No `PrivacyInfo.xcprivacy`.** Required at submission; `UserDefaults` and file-timestamp APIs
  need declared reason codes.
- **Adult-source gating is the largest review risk.** The source lives only on the local-only
  `nhentai` branch, so dropping it from the release build is close to free today.
- No listing screenshots, privacy-policy URL, App Store description, or TestFlight run.

## Decision recorded, not yet an ADR

**Keep MangaDex built-in**, against ADR-0003's "ship zero built-in aggregator sources", because
ADR-0016 makes it the resolution bridge that For You, More Like This and MAL progress sync all
depend on. Extensions are **additive**. Phase 2 should write this as an amendment to ADR-0003.

## Gotchas

Carried forward; re-verify any that becomes load-bearing rather than trusting this list.

- **Changing an accessibility label silently breaks XCUITests.** They match the *label*, not drawn
  text, and CI runs neither affected suite. Four assertions match headings by drawn text
  (`app.staticTexts["MyAnimeList"]`, `["More Like This"]`, `["Keep your library current"]`,
  `["Updates"]`). Grep the UI tests before touching any label.
- **CI is a major version behind local** — `macos-15` → Xcode 16.4 / Swift 6.0 vs local 26.x /
  6.2. Green locally is not evidence for CI on new syntax or newer concurrency inference.
- **`project.pbxproj` churns under you** whenever Xcode has the project open. Every `xcp add-file`
  this session produced ~46 lines of unrelated churn; `git checkout` the file and re-run `xcp`,
  which gave a clean 4-line insert each time. Check `git diff --stat` immediately before `git add`.
- **Branch protection does not stop this account** — `enforce_admins: false`. A direct push to
  `main` lands and waives both required checks. Ask first.
- **Do not stack PRs** — a child closes unrecoverably when its base is deleted. A code commit
  landed on the docs branch this session and was moved to its own branch off `main` before pushing.
- **A full CI run takes ~12 minutes.** `gh pr merge --auto` beats waiting.
- **Target the iPhone 17 Pro simulator** on every `xcodebuild` — it holds the seeded fixture.

## Repository state

- `main` at `57b2ec5`. `feature/fulfillment-routing` is six commits ahead of `bf3ac42`
  (PR #116, CI pending at the time of writing). This branch carries only the handoff.
- `gh issue list`: **#90 only**.
- Unit suite: **638 pass, 0 failures**, 2 skipped.
- `docs/superpowers/handoff/` holds this file and `archive/` (69 archived handoffs plus its
  README). Two `.md` files here
  means someone skipped the rule.
