# Handoff — the docs are true again; two Codex agents are running; Phase 1 is still two device tasks

Date: 2026-09-01 (evening)
Repository: `/Users/eliasmagdaleno/Manga-Reader`
Branch: `docs/handoff-2026-09-01-evening`, off `main` at `4f6e140`.

**This is the live handoff, and it is the whole of what is outstanding.** Writing a new one means
`git mv`-ing this into `archive/` first and carrying forward whatever below is still true
(`CLAUDE.md` → "Handoffs").

## The roadmap, unchanged

Six phases, ~8–9 weeks. The reasoning, and the Paperback catalog research behind it, is in
`archive/2026-08-31-launch-roadmap-handoff.md`. **Read it once** rather than re-deriving it.

1. **Finish what is nearly done** — source picker ✅, MAL live-verify, VoiceOver pass. *Two device
   tasks remain; no code is owed.*
2. **Host API design** (~1–1.5w) — spec + ADR amending 0003. The forever contract. **A Codex
   agent is producing the input inventory for this right now — see "Work in flight".**
3. **JavaScriptCore runtime + WeebCentral port** (~2w).
4. **Repo format + installer** (~1–1.5w).
5. **Theme engines** (~1w for Madara, then days each) — Madara alone is 29 sites.
6. **Launch prep** (~1w).

The catalog finding that shapes Phase 2: Paperback's ~68 sources are **55 generic-theme sites
plus 23 bespoke ones**, so the host API must serve an extension that takes *configuration*, not
one extension per site.

## What this session shipped

| PR | What |
|---|---|
| #121 | The document-ownership rule, the audit under it, and VoiceOver section 8 |
| #122 | ADR-0022 (no adult source in the release) and ADR-0003 Amendment 1 |
| #123 | The browse-source rows say which source is active |
| #124 | The picker menu's checkmark proven not to be decoration |
| #125 | 8.8's suspected note struck; a stale citation corrected (**open at time of writing**) |

Unit suite **773 pass / 0 fail / 2 skipped**; `SourcePreferenceUITests` **6 of 6**. SwiftLint clean.

### The document-ownership rule — read this before writing any document

`CLAUDE.md` → "Document ownership". **Every fact has exactly one owning document; non-owners
link, they never restate.** ADRs own decisions (amend, never correct), the glossary owns terms,
`CLAUDE.md` owns conventions and current state, `PRODUCT.md` owns intent, `DESIGN.md` owns the
visual system, `README.md` owns a stranger's first sixty seconds, and this directory owns what is
outstanding.

The failure it prevents is not staleness but **the same fact stated twice**, which was three of
the five known instances of rot here. So the fix for a stale claim is usually **deletion plus a
link**, not a correction. Two consequences are already load-bearing: `README.md` carries no
roadmap and no architecture breakdown, and **a decision recorded only in a handoff is not
recorded** — which is why ADR-0003 Amendment 1 exists.

The rule is a convention, not a script, deliberately. A checked-in verifier was considered and
rejected as the wrong layer: it would keep both copies of a duplicated fact true rather than
removing the duplicate.

### Decisions now written down

- **ADR-0022 — the release ships no adult source.** Enforced by *not merging*; the `nhentai`
  branch stays local-only. No build-configuration mechanism: it would defend against a merge that
  is itself the decision. The gating machinery (`isNSFW`, `visibleSources(includeAdult:)`,
  `enforceAdultGating(includeAdult:)`) stays and keeps its tests, so this reverses by registering
  a source. Settings now **hides** the "Show adult sources" toggle while nothing declares
  `isNSFW`; the stored preference is untouched, so it returns with its old value.
- **ADR-0003 Amendment 1 — MangaDex stays built in**, against "ship zero built-in aggregator
  sources", because ADR-0016 makes it the resolution bridge that For You, More Like This and MAL
  progress all depend on. Extensions are additive. **Phase 2's host API amendment should assume
  MangaDex is present.**

## Work in flight — two Codex agents, unsupervised

Handed off 2026-09-01 via Orca. Both are **independent worktrees off `main`**, both were told to
open PRs and never to push to `main`. Nothing is monitoring them; **check for their PRs before
starting either task yourself.**

- **`privacy-manifest`** — add `PrivacyInfo.xcprivacy`. Briefed to verify the required-reason API
  list rather than trust it, to justify each reason code in the PR, and to confirm the manifest
  is **in the built `.app`**, not merely in the repo — a manifest that failed to copy looks
  identical to success in `git diff`.
- **`host-api-inventory`** — produce
  `docs/superpowers/specs/2026-09-01-host-api-surface-inventory.md`: every capability
  `WeebCentralSource` actually consumes, `MangaSource` as an extension-facing contract, what
  `WebViewService`/`SourceContext` expose, capabilities used *outside* the protocol, and open
  questions stated as questions. **Explicitly told not to design the API** — the forever contract
  is not a cold agent's to guess at.

If either produced nothing, the task is unstarted, not half-done; both were scoped to be
restartable from their brief.

## What is owed

### 1. Live-verify MAL progress push — the user's to run

Built, wired, tested (`MALProgressCoordinator`, `MALProgressOutbox`, the Settings toggle and
queue status). What no unit test can show: **sign in on a device, read a chapter to the end, and
confirm the number moves on myanimelist.net.** `scripts/mal_live_write.py` pokes the API directly
if the in-app path needs isolating.

### 2. The manual VoiceOver pass — #90, the user's to run

Open, `ready-for-human`, **no row has a verdict yet**, and no results file in
`docs/accessibility/` — which is how you can tell at a glance it has not started.

Run `./scripts/voiceover-pass.sh` from the repo root. It parses the checklist at runtime, takes
pass/fail/skip per row, writes `docs/accessibility/voiceover-results-<date>.md`, and resumes
where it stopped. It needs a **real iPhone** — simulator VoiceOver differs on the rotor and on
focus restoration, which is most of what these rows test.

Rows most needing eyes: **4.3**, **6.5**, **7.2**, **7.5**, **7.6**.

**Section 8 now exists** (11 rows) for the source picker. Two of its rows were investigated
before the pass and are expected to *pass* rather than fail — 8.8 was a real defect, now fixed;
8.5 was not a defect at all. **Neither is closed:** a trait being present is not VoiceOver
speaking it, and that distinction is the whole reason this is a device pass. The rest of section
8 — the stamp's composed label, the pin being audible, the two Settings lists distinguishable by
rotor — has never been heard.

Close #90 when every row has a verdict, **not** when every defect is fixed.

### 3. Naming debt, small and deliberate

`-uitest-updates-state` seeds a fixture that has nothing to do with updates (`two-listings`).
One seeding path with isolated storage was judged worth more than a tidier spelling; rename it if
a third unrelated state appears.

## Launch blockers that are not features

- **No app icon.** `AppIcon.appiconset/` holds only `Contents.json`. Being outsourced — **order it
  early so it is not the long pole.** Unchanged from the last handoff, which means it has not been
  ordered.
- **`PrivacyInfo.xcprivacy`** — assigned to a Codex agent this session (above). Check for its PR.
- **Adult-source gating** — settled by ADR-0022. No longer a blocker, just a thing not to undo.
- No listing screenshots, privacy-policy URL, App Store description, or TestFlight run.

## Gotchas

Re-verify any that becomes load-bearing rather than trusting this list.

- **`SourceRegistry.shared` is not always the graph's registry.** This shipped as a real bug:
  the detail page resolved sources through the singleton while the app was built with an injected
  registry, so lookups missed, display names fell back to raw ids, and the page tried to load
  chapters from a source not serving that manga. `AppComposition.registry` exposes the real one
  and it is in the environment — **use it, not the singleton, in views.** A view model built in
  `init` cannot see the environment, which is why `MangaDetailView` re-resolves its Listing on
  appear. This gets worse in Phases 3–5, where sources become installable.
- **A passing test is not evidence until you have seen it fail.** Row 8.5 was "fixed" with an
  explicit `.accessibilityAddTraits`, and the new test passed — *and passed again with the
  modifier stashed*, because SwiftUI's `Menu` already supplies the trait. The change was
  discarded. Stash the fix and re-run before believing a green assertion, especially in
  XCUITest where the framework supplies more behaviour than you wrote.
- **File:line citations rot within one session.** #123 added lines to `SettingsView.swift` and
  invalidated a citation written hours earlier in the same session (#125 fixed it). Re-grep
  citations when you touch the file they point into.
- **Changing an accessibility label silently breaks XCUITests.** They match the *label*, not the
  drawn text, and CI runs neither UI suite. Four assertions match headings by drawn text
  (`app.staticTexts["MyAnimeList"]`, `["More Like This"]`, `["Keep your library current"]`,
  `["Updates"]`). Grep the UI tests before touching any label.
- **A bare accessibility query can match the wrong list.** Settings has two lists of source names;
  rows are namespaced `browseSource.` and `preferredSource.` for exactly this reason.
- **CI is a major version behind local** — `macos-15` → Xcode 16.4 / Swift 6.0 vs local 26.x /
  6.2. Green locally is not evidence for CI on new syntax. Treat isolated conformances,
  `nonisolated(nonsending)`, `@concurrent` and `Task.immediate` as unavailable.
- **CI's SwiftLint is not this machine's either.** A five-member tuple failed CI on `large_tuple`
  while local SwiftLint 0.65.0 passed the same file, same config, exit 0.
- **`AppComposition.init` sits right at SwiftLint's body-length limit.** Adding two lines trips
  `function_body_length`. Extract rather than inline.
- **A wedged simulator looks exactly like a failing suite.** `** TEST FAILED **` with no failing
  test named is `Application failed preflight checks` / `Busy`. `xcrun simctl boot "iPhone 17 Pro"`
  and re-run. **Do not erase the device** — it holds the seeded fixture, and erasing has already
  destroyed `works.json` once (`sim-data-is-a-fixture` memory).
- **`project.pbxproj` churns under you** whenever Xcode has the project open. Check
  `git diff --stat` immediately before `git add`, not right after `xcp`.
- **Branch protection does not stop this account** — `enforce_admins: false`. A direct push to
  `main` lands and waives both required checks. Ask first.
- **Do not stack PRs** — a child closes unrecoverably when its base is deleted.
- **A full CI run takes ~12 minutes.** `gh pr merge --auto` beats waiting.
- **Target the iPhone 17 Pro simulator** on every `xcodebuild` — it holds the seeded fixture.

## Technique worth reusing

- **You can look at a UI test's screenshots.** Run with `-resultBundlePath <path>`, then
  `xcrun xcresulttool export attachments --path <bundle> --output-path <dir>`; `manifest.json`
  maps each attachment's `suggestedHumanReadableName` to its exported file. This is the missing
  half of the `ui-verification-technique` memory.
- **Test totals come from the result bundle, not the log tail.**
  `xcrun xcresulttool get test-results summary --path <bundle>` gives pass/fail/skip counts; the
  streamed log prints per-suite lines that are easy to mistake for the total.

## Repository state

- `main` at `4f6e140`, working tree clean. This branch carries only the handoff.
- `gh issue list`: **#90 only**. `gh pr list`: **#125** open (docs, auto-merge queued), plus
  whatever the two Codex agents have opened since.
- Unit suite **773 pass / 0 fail / 2 skipped**. `SourcePreferenceUITests` 6 of 6; updates UI suite
  5 of 5.
- `docs/superpowers/handoff/` holds this file and `archive/` (71 archived handoffs plus its
  README). Two `.md` files at this level means someone skipped the rule.
