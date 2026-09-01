# Handoff — the source picker is shipped; Phase 1 is two human tasks from done

Date: 2026-09-01 (early)
Repository: `/Users/eliasmagdaleno/Manga-Reader`
Branch: `docs/handoff-picker-shipped`, off `main` at `1956324`.

**This is the live handoff, and it is the whole of what is outstanding.** Writing a new one
means `git mv`-ing this into `archive/` first and carrying forward whatever below is still true
(`CLAUDE.md` → "Handoffs").

## The roadmap

Six phases, ~8–9 weeks of focused work, sequenced by dependency. The reasoning — especially the
Paperback catalog research — is in `archive/2026-08-31-launch-roadmap-handoff.md`. **Read it
once** rather than re-deriving it.

1. **Finish what is nearly done** — source picker ✅, MAL live-verify, VoiceOver pass. *Two human
   tasks remain; no code is owed.*
2. **Host API design** (~1–1.5w) — spec + ADR amending 0003. The forever contract.
3. **JavaScriptCore runtime + WeebCentral port** (~2w).
4. **Repo format + installer** (~1–1.5w).
5. **Theme engines** (~1w for Madara, then days each) — Madara alone is 29 sites.
6. **Launch prep** (~1w).

The one-line catalog finding, because it shapes Phase 2: Paperback's ~68 sources are **55
generic-theme sites plus 23 bespoke ones**, so the host API must be designed for an extension
that takes *configuration*, not one-extension-per-site.

## What shipped

`main` carries five merged PRs from this work:

| PR | What |
|---|---|
| #115 | The launch roadmap |
| #116 | Fulfillment logic — router, count cache, coordinator, preference store, presentation |
| #117 | Handoff superseding the roadmap |
| #118 | The picker on screen, plus the Settings primary-source preference |
| #119 | A two-listing UI-test fixture, and the registry bug it caught |

**642 unit tests, 4 source-picker UI tests, 5 update UI tests, 0 failures.** SwiftLint clean.
ADR-0004 gained **Amendment 1**.

### The feature, as built

Paperback's two-scope model, which is what the user asked for by name:

- **A primary source** (Settings) settles ties in place of MangaDex. It settles *ties only* —
  preferring a source's scans is not a claim it has chapters it lacks.
- **A per-Work pin** (the detail page) beats the ranking outright and persists. Chosen over
  transient overriding because the transient version's failure mode — the app switching you back
  tomorrow because a count moved — is indistinguishable from a bug.

Switching genuinely re-fetches: `MangaDetailViewModel.retarget(to:using:)` moves fulfillment
while the displayed `Manga` stays put, because ADR-0001 makes the Work the identity and a Listing
only one source's copy.

### Decisions embedded in the code, so nobody relitigates them by accident

- **`nil` count means unknown, never zero.** Three evidence tiers: counted non-empty, uncounted,
  counted-empty. An uncounted Listing beats one counted at zero, loses to one counted at all.
- **A known reference total caps the count rather than dividing by it.** 205 entries for a
  201-chapter series is padding, not completeness.
- **Unnumbered entries ("Oneshot", "Extra") are not counted** — readable but not comparable.
- **A source that throws stays uncounted, never zero.** Recording zero would bury a source for a
  full TTL on the strength of an outage.
- **A pin whose source is unregistered falls back to the ranking but is not deleted.**
- **Only a pin redirects on open, never the ranking** — you tapped a specific card.
- **"No preference" is a real selected row.** Without it there is no telling the default from a
  deliberate choice, and no way back.

## What is owed

### 1. Live-verify MAL progress push — the user's to run

The subsystem is built, wired and tested (`MALProgressCoordinator`, `MALProgressOutbox`, the
Settings toggle and queue status). What no unit test can show: **sign in on a device, read a
chapter to the end, and confirm the number moves on myanimelist.net.**
`scripts/mal_live_write.py` pokes the API directly if the in-app path needs isolating.

### 2. The manual VoiceOver pass — #90, the user's to run

Open, `ready-for-human`, **no row has a verdict yet**, and no results file in
`docs/accessibility/`, which is how you can tell at a glance it has not started.

Run `./scripts/voiceover-pass.sh` from the repo root. It parses the checklist at runtime, takes
pass/fail/skip per row, writes `docs/accessibility/voiceover-results-<date>.md`, and resumes
where it stopped. It needs a **real iPhone** — simulator VoiceOver differs on the rotor and on
focus restoration, which is most of what these rows test.

Rows most needing eyes: **4.3**, **6.5**, **7.2**, **7.5**, **7.6**. Close #90 when every row has
a verdict, **not** when every defect is fixed.

**New rows are now warranted** for the picker, which did not exist when the checklist was
written: the stamp reports itself as a button with a composed label and a hint, its menu rows
carry a checkmark rather than colour alone, and Settings' two source lists are distinguished by
heading. None of that has been heard through VoiceOver.

### 3. The duplication shape of doc rot — untouched, agent work

#113 fixed only *snapshots*. The same-fact-in-two-places shape is three of five known instances
and is still unaddressed. Audit `CLAUDE.md`, `DESIGN.md`, `PRODUCT.md`, `README.md`,
`docs/glossary.md`, `docs/agents/*.md` and the memory files; every factual claim about the code
should be grep-verifiable *now*. **ADRs are the exception** — amend, never correct.

Known instances waiting, and this session added to the pile:

- `PRODUCT.md`: "Content refresh is currently user-initiated" — ADR-0021 shipped.
- `PRODUCT.md`: readers "search within a selected source" — still true, goes false the moment
  cross-source search lands.
- `PRODUCT.md` and `DESIGN.md` say nothing about fulfillment or the source picker, which is now
  a shipped, user-visible surface with its own preference in Settings.
- `CLAUDE.md`'s "Current state" does not mention fulfillment either.

Worth deciding before starting whether the fix is a one-time audit or something structural — a
one-time audit produces instance seven eventually.

### 4. Naming debt, small and deliberate

`-uitest-updates-state` now seeds a fixture that has nothing to do with updates
(`two-listings`). The flag's name predates the second use. One seeding path with isolated
storage was judged worth more than a tidier spelling; rename it if a third unrelated state
appears.

## Launch blockers that are not features

- **No app icon.** `AppIcon.appiconset/` holds only `Contents.json`. Being outsourced — order it
  early so it is not the long pole.
- **No `PrivacyInfo.xcprivacy`.** Required at submission; `UserDefaults` and file-timestamp APIs
  both need declared reason codes.
- **Adult-source gating is the largest review risk.** The source lives only on the local-only
  `nhentai` branch, so dropping it from the release build is close to free today and gets more
  expensive later.
- No listing screenshots, privacy-policy URL, App Store description, or TestFlight run.

## Decision recorded, not yet an ADR

**Keep MangaDex built-in**, against ADR-0003's "ship zero built-in aggregator sources", because
ADR-0016 makes it the resolution bridge that For You, More Like This and MAL progress sync all
depend on. Extensions are **additive**. Phase 2 should write this as an amendment to ADR-0003.

## Gotchas

Re-verify any that becomes load-bearing rather than trusting this list.

- **`SourceRegistry.shared` is not always the graph's registry.** This shipped as a real bug and
  was caught only by the new fixture: the detail page resolved sources through the singleton
  while the app had been built with an injected registry, so lookups missed, display names fell
  back to raw ids, and the page tried to load chapters from a source that was not serving that
  manga. `AppComposition.registry` now exposes the real one and it is in the environment —
  **use it, not the singleton, in views.** A view model built in `init` still cannot see the
  environment, which is why `MangaDetailView` re-resolves its Listing on appear. This class of
  bug gets worse in Phases 3–5, where sources become installable.
- **Changing an accessibility label silently breaks XCUITests.** They match the *label*, not the
  drawn text, and CI runs neither UI suite. Four assertions match headings by drawn text
  (`app.staticTexts["MyAnimeList"]`, `["More Like This"]`, `["Keep your library current"]`,
  `["Updates"]`). Grep the UI tests before touching any label.
- **A bare accessibility query can match the wrong list.** `app.buttons["MangaDex"]` matched the
  browse-source row rather than the preferred-source row; the preference rows now carry
  `preferredSource.`-namespaced identifiers. Two lists of the same names need namespaced ids.
- **CI is a major version behind local** — `macos-15` → Xcode 16.4 / Swift 6.0 vs local 26.x /
  6.2. Green locally is not evidence for CI on new syntax or newer concurrency inference.
- **CI's SwiftLint is not this machine's either.** A five-member tuple failed CI on `large_tuple`
  while local SwiftLint **0.65.0** passed the same file, same config, exit 0. A clean local lint
  is not evidence for the CI lint job.
- **`AppComposition.init` sits right at SwiftLint's body-length limit.** Adding two lines to it
  trips `function_body_length`. Extract rather than inline.
- **A wedged simulator looks exactly like a failing suite.** Three consecutive full-suite runs
  reported `** TEST FAILED **` with no failing test; the real error was
  `Application failed preflight checks` / `Busy`. `xcrun simctl boot "iPhone 17 Pro"` and re-run.
  **Do not erase the device** — it holds the seeded fixture, and erasing has already destroyed
  `works.json` once (`sim-data-is-a-fixture` memory).
- **`project.pbxproj` churns under you** whenever Xcode has the project open. Every `xcp add-file`
  this session produced ~46 lines of unrelated churn; `git checkout` the file and re-run `xcp`,
  which gave a clean 4-line insert each time. Check `git diff --stat` immediately before
  `git add`.
- **Branch protection does not stop this account** — `enforce_admins: false`. A direct push to
  `main` lands and waives both required checks. Ask first.
- **Do not stack PRs** — a child closes unrecoverably when its base is deleted.
- **A full CI run takes ~12 minutes.** `gh pr merge --auto` beats waiting.
- **Target the iPhone 17 Pro simulator** on every `xcodebuild` — it holds the seeded fixture.

## Technique worth reusing

**You can actually look at a UI test's screenshots.** Run with `-resultBundlePath <path>`, then
`xcrun xcresulttool export attachments --path <bundle> --output-path <dir>`; `manifest.json` maps
each attachment's `suggestedHumanReadableName` to its exported file. This is how the two design
defects in this session were found — an unlabelled browse-source list, and the raw-id menu — and
neither was visible from a passing assertion. It is the missing half of the
`ui-verification-technique` memory.

## Repository state

- `main` at `1956324`, working tree clean. This branch carries only the handoff.
- `gh issue list`: **#90 only**. `gh pr list`: empty.
- Unit suite: **642 pass, 0 failures**, 2 skipped. UI suites: 4 + 5 pass.
- `docs/superpowers/handoff/` holds this file and `archive/` (70 archived handoffs plus its
  README). Two `.md` files here means someone skipped the rule.
