# Handoff — Phase 1 owes only two device tasks; the Phase 2 spec is now unblocked

Date: 2026-09-01 (night)
Repository: `/Users/eliasmagdaleno/Manga-Reader`
Branch: `docs/handoff-2026-09-01-night`, off `main` at `b6ec56e`.

**This is the live handoff, and it is the whole of what is outstanding.** Writing a new one means
`git mv`-ing this into `archive/` first and carrying forward whatever below is still true
(`CLAUDE.md` → "Handoffs").

## The roadmap, unchanged

Six phases, ~8–9 weeks. The reasoning, and the Paperback catalog research behind it, is in
`archive/2026-08-31-launch-roadmap-handoff.md`. **Read it once** rather than re-deriving it.

1. **Finish what is nearly done** — source picker ✅, MAL live-verify, VoiceOver pass. *Two device
   tasks remain; no code is owed.*
2. **Host API design** (~1–1.5w) — spec + ADR amending 0003. The forever contract. **Its input
   inventory now exists (PR #127); this is the next thing to work on.**
3. **JavaScriptCore runtime + WeebCentral port** (~2w).
4. **Repo format + installer** (~1–1.5w).
5. **Theme engines** (~1w for Madara, then days each) — Madara alone is 29 sites.
6. **Launch prep** (~1w).

The catalog finding that shapes Phase 2: Paperback's ~68 sources are **55 generic-theme sites
plus 23 bespoke ones**, so the host API must serve an extension that takes *configuration*, not
one extension per site.

## What this session shipped

Two Codex agents, dispatched by the previous session and unsupervised, both delivered.

| PR | What |
|---|---|
| #128 | `PrivacyInfo.xcprivacy`, with the required-reason audit behind it — **merged** |
| #127 | The host API surface inventory, plus two citation-rot fixes found in review |

### Phase 2's input now exists — read it before designing anything

`docs/superpowers/specs/2026-09-01-host-api-surface-inventory.md`. It is **evidence, not a
design** — deliberately. It records:

- every capability `WeebCentralSource` actually consumes, with wire shapes, mapping, and failure
  behavior per operation;
- `MangaSource` as an extension-facing contract, including where it already violates its own
  "bridge-friendly" comment;
- what `WebViewService`/`SourceContext` actually expose;
- capabilities that live *outside* the browse/read methods and are easy to miss when deriving a
  contract from entry points alone;
- **18 open questions**, each stated as a question.

Those 18 questions are the Phase 2 agenda. The spec + ADR-0003 amendment is the work of answering
them. **ADR-0003 Amendment 1 already settled that MangaDex is present**, so assume it.

The document is stamped `**Verified against:** 4f6e140` because it carries 212 line citations into
files `CLAUDE.md` calls volatile — 68 into `WeebCentralSource.swift` alone. If a citation
mismatches, that stamp is how you tell doc rot from code drift.

### The privacy manifest, and the one question it left open

`CA92.1` for UserDefaults (not `1C8F.1`: no App Group entitlement, and the single
`UserDefaults(suiteName:)` call is DEBUG-only UI-test fixture isolation in
`UpdatesUITestState.freshStorage`). `C617.1` for file timestamps, from `ImageDiskCache` reading
`.contentModificationDateKey`/`.fileSizeKey` to trim the cache. Tracking false; tracking domains
and collected data types empty.

**One boundary is deliberately unresolved and is owed at privacy-label review:** optional MAL sync
sends completed-reading progress to the reader's own authenticated MAL account. PR #128 treats that
as user-authorized account functionality rather than collection by this app — the developer
receives none of it — but says outright that Apple's broad definition of collection focuses on
retained off-device transmission and that this should be rechecked. It does not affect the
required-reason mapping. **Do not let that recheck get lost when the App Store privacy labels are
filled in.**

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

**Section 8** (11 rows) covers the source picker. Two of its rows were investigated before the pass
and are expected to *pass* rather than fail — 8.8 was a real defect, now fixed; 8.5 was not a defect
at all. **Neither is closed:** a trait being present is not VoiceOver speaking it, and that
distinction is the whole reason this is a device pass. The rest of section 8 — the stamp's composed
label, the pin being audible, the two Settings lists distinguishable by rotor — has never been heard.

Close #90 when every row has a verdict, **not** when every defect is fixed.

### 3. Naming debt, small and deliberate

`-uitest-updates-state` seeds a fixture that has nothing to do with updates (`two-listings`).
One seeding path with isolated storage was judged worth more than a tidier spelling; rename it if
a third unrelated state appears.

## Launch blockers that are not features

- **No app icon.** `AppIcon.appiconset/` holds only `Contents.json`. Being outsourced — **order it
  early so it is not the long pole.** Unchanged across three handoffs now, which means it still has
  not been ordered. This is the one blocker that cannot be compressed by working harder later.
- **`PrivacyInfo.xcprivacy`** — done (#128), verified present in the built `.app`.
- **Adult-source gating** — settled by ADR-0022. Not a blocker, just a thing not to undo.
- No listing screenshots, privacy-policy URL, App Store description, or TestFlight run.

## On dispatching agents — what this session learned

Both agents were **handoffs** (`orca worktree create --agent codex --prompt …`), which transfers
ownership and stops watching. One of them parked on "Does that design have your approval?" and
**nothing surfaced it**: it was invisible to `git` (nothing committed), and `orca worktree ps`
reported it as `done`. It was caught only because someone happened to look at the Orca window.

If you want to be told when a worker finishes, escalates, or asks, dispatch through **orchestration**
instead and block on the inbox:

```sh
orca orchestration run-create --objective "<objective>" --json
orca orchestration task-create --spec "<full brief>" --json
orca orchestration worker-start --task <id> --worktree new-top-level --name <name> \
  --agent codex --model <id> --effort high --setup run --json
orca orchestration check --wait --types worker_done,escalation,question --timeout-ms 900000 --json
```

Points that cost something here:

- **Start every independent worker before the first wait**, or the work serializes.
- **Set `--model`/`--effort` at start time.** One agent ran `gpt-5.6-sol` at `low` on a task whose
  stated failure mode was "a wrong-but-plausible reason code". It happened to do well, but changing
  effort mid-flight means discarding the work already done.
- **A `check --wait` timeout is a checkpoint, not a failure.** Coding tasks run 15–60 minutes.
- **A `worker_done` is not a merge.** Both PRs needed review; #127 needed two fixes.
- Use a plain handoff when nobody is waiting. Orchestration's task rows and lifecycle preamble are
  overhead if you genuinely intend to read the PR later and nothing else.

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
  discarded. Stash the fix and re-run before believing a green assertion.
- **File:line citations rot within one session.** #123 invalidated a citation written hours earlier
  in the same session. This is also why the inventory spec carries a verified-against commit, and
  why its glossary references name terms rather than line numbers: **never cite a living owned
  document by line.**
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

- **Bounds-check citations mechanically before trusting a document.** Regex every `path:line`
  out of the Markdown, assert the file exists and the range is within its line count, then
  content-check the load-bearing claims by hand. On #127 that was 215 citations verified in
  seconds, which is what made a real review of a 359-line evidence document affordable.
- **You can look at a UI test's screenshots.** Run with `-resultBundlePath <path>`, then
  `xcrun xcresulttool export attachments --path <bundle> --output-path <dir>`; `manifest.json`
  maps each attachment's `suggestedHumanReadableName` to its exported file. This is the missing
  half of the `ui-verification-technique` memory.
- **Test totals come from the result bundle, not the log tail.**
  `xcrun xcresulttool get test-results summary --path <bundle>` gives pass/fail/skip counts; the
  streamed log prints per-suite lines that are easy to mistake for the total.

## Repository state

- `main` at `b6ec56e` (#128 merged). This branch carries only the handoff.
- `gh issue list`: **#90 only**. `gh pr list`: **#127** open with squash auto-merge armed, waiting
  on `Build & unit tests`; it should land on its own.
- Unit suite **773 total, 771 passed, 2 skipped, 0 failed** (from #128's run). SwiftLint clean.
- Two idle Orca worktrees remain — `host-api-inventory` and `privacy-manifest`, both under
  `~/orca/workspaces/Manga-Reader/`. Their work is merged or in flight; `orca worktree rm` them
  when convenient.
- `docs/superpowers/handoff/` holds this file and `archive/` (72 archived handoffs plus its
  README). Two `.md` files at this level means someone skipped the rule.
