# Handoff — Phase 2 is specified; Phase 3 builds the runtime against it

Date: 2026-09-03
Repository: `/Users/eliasmagdaleno/Manga-Reader`
Branch: `docs/handoff-2026-09-03`, off `main` at `7448a0e`.

**This is the live handoff, and it is the whole of what is outstanding.** Writing a new one means
`git mv`-ing this into `archive/` first and carrying forward whatever below is still true
(`CLAUDE.md` → "Handoffs").

## The roadmap

Six phases, ~8–9 weeks. The reasoning and the Paperback catalog research behind it are in
`archive/2026-08-31-launch-roadmap-handoff.md`. **Read it once** rather than re-deriving it.

1. **Finish what is nearly done** — *two device tasks remain; no code is owed.*
2. **Host API design** — ✅ **done** (PR #130). The contract is written.
3. **JavaScriptCore runtime + WeebCentral port** (~2w) — **this is the next thing to build.**
4. **Repo format + installer** (~1–1.5w).
5. **Theme engines** (~1w for Madara, then days each) — Madara alone is 29 sites.
6. **Launch prep** (~1w).

The catalog finding that shapes everything from here: Paperback's ~68 sources are **55
generic-theme sites plus 23 bespoke ones**, so the runtime must serve an extension that takes
*configuration*, not one extension per site. Phase 2 took that as its central constraint.

## What this session shipped

Two supervised orchestration workers, both delivered.

| PR | What |
|---|---|
| #130 | The Phase 2 Host API design + ADR-0003 Amendment 2 — **merged** |
| #131 | `SourceRegistry.shared` retired from the view layer — open, auto-merge armed |

### Phase 2 is specified — read it before writing any runtime code

`docs/superpowers/specs/2026-09-02-host-api-design.md` (666 lines), with the architectural
decisions in **ADR-0003 Amendment 2**. Between them they answer all 18 questions the surface
inventory left open. The split is deliberate and worth preserving: **the ADR owns the decisions and
their reasoning; the spec owns wire shapes, validation rules, and operation semantics.**

The shape it settles, in one paragraph: an installed bundle carries one executable Extension and
one or more *Source declarations*, each selecting an exported engine and supplying immutable,
deep-frozen JSON configuration. Many declarations may select the same engine — that is the
generic-theme shape, a Madara engine written once while base URL, selectors, path templates,
language policy, and presentation strings vary per configuration. The runtime invokes
`invoke(operation, request, context)`, where `context` carries `source`, the host capabilities
(`http`, `browser`, `storage`, `log`), and a cancellation `signal`.

**Section 15 is the part Phase 3 is measured against.** It lists twelve acceptance criteria a
JavaScriptCore implementation must demonstrate by test — among them that one engine serves three
differently configured Sources without duplication, that manifest validation runs no Extension
code, that Source-id stamping cannot be overridden by Extension output, that two configured Sources
cannot read each other's storage or cookies, and that **the compiled `WeebCentralSource` can be
replaced by a configuration-backed Extension with equivalent behavior**. Treat that list as Phase
3's definition of done.

### The four open evidence gates — do not paper over them

Section 16 leaves four implementation choices open *on purpose*, because the available evidence
could not settle them honestly. Each must be closed before its dependent slice is called complete:

1. **Exact limits** — request, response, CPU, wall-clock, storage, log, and concurrency budgets.
   Needs the profiling corpus named in Section 5.
2. **The WebKit isolation mechanism.** The spec cannot yet name the iOS 17.5 mechanism that gives
   *both* persistent Cloudflare clearance *and* strong per-Source isolation. Needs a prototype
   (Section 9). This one is a genuine risk to Phase 3 — today's `WebViewService` deliberately uses
   one shared persistent store precisely so `cf_clearance` survives, and per-Source isolation
   pulls against that.
3. **Stable repository identity** across URL moves, forks, and signing-key rotation — belongs to
   Phase 4's repository-format and signing design.
4. **Who may attest adult classification**, and how review is maintained — needs the distribution
   threat model.

None of them changes the v1 semantic boundary, which is why the runtime can start now.

### The registry is now injected, not reached for

PR #131 removed every `SourceRegistry.shared` *read* outside `AppComposition`. This closes the bug
the last three handoffs carried as a gotcha: the detail page resolved sources through the singleton
while the app was built with an injected registry, so lookups missed and the page tried to load
chapters from a source that does not serve that manga.

- Views take the registry from the environment. `HomeView` and `SearchView` needed a thin
  environment-reading wrapper, because a `@StateObject` built in `init` cannot see the environment.
- `MangaDetailViewModel` gained `adopt(registry:)`, called on appear — the pattern
  `MangaDetailView` already used — and `retarget` lost its `= .shared` default parameter.
- `ReaderViewModel` now requires its source from callers that read the registry from the
  environment.
- **Two call sites turned up beyond the eight in the brief:** `retarget`'s default parameter and
  `ReaderViewModel`'s. If you go looking for singleton reads, grep rather than trusting a list.
- `Manga-ReaderTests/RegistryInjectionTests.swift` (9 tests) uses source ids the app does not
  compile in, so an accidental singleton read cannot pass by coincidence.
- **Deliberately left:** `AppComposition`'s own `registry ?? .shared` production default, and two
  `#Preview` blocks passing `.environmentObject(SourceRegistry.shared)`. Both are explained in the
  PR body. Everything else is a doc comment.

Suite went **773 → 782 total, 780 passed, 2 skipped, 0 failed**. `CLAUDE.md`'s registry bullet now
records the rule, so it does not have to live on in a handoff.

This mattered now rather than later because Phases 3–5 make sources *installable at runtime*, which
is exactly the condition under which a stale singleton diverges from the graph's registry.

## What is owed

### 1. Live-verify MAL progress push — the user's to run

Built, wired, tested (`MALProgressCoordinator`, `MALProgressOutbox`, the Settings toggle and queue
status). What no unit test can show: **sign in on a device, read a chapter to the end, and confirm
the number moves on myanimelist.net.** `scripts/mal_live_write.py` pokes the API directly if the
in-app path needs isolating.

### 2. The manual VoiceOver pass — #90, the user's to run

Open, `ready-for-human`, **no row has a verdict yet**, and no results file in
`docs/accessibility/` — which is how you can tell at a glance it has not started.

Run `./scripts/voiceover-pass.sh` from the repo root. It parses the checklist at runtime, takes
pass/fail/skip per row, writes `docs/accessibility/voiceover-results-<date>.md`, and resumes where
it stopped. It needs a **real iPhone** — simulator VoiceOver differs on the rotor and on focus
restoration, which is most of what these rows test.

Rows most needing eyes: **4.3**, **6.5**, **7.2**, **7.5**, **7.6**.

**Section 8** (11 rows) covers the source picker. Two of its rows were investigated before the pass
and are expected to *pass* rather than fail — 8.8 was a real defect, now fixed; 8.5 was not a defect
at all. **Neither is closed:** a trait being present is not VoiceOver speaking it, and that
distinction is the whole reason this is a device pass. The rest of section 8 — the stamp's composed
label, the pin being audible, the two Settings lists distinguishable by rotor — has never been heard.

Close #90 when every row has a verdict, **not** when every defect is fixed.

### 3. PR #131 has not landed yet

Open with squash auto-merge armed. SwiftLint passed; `Build & unit tests` was still running when
this was written. It should land on its own. **Confirm it did** before building on `main`, since
Phase 3 will touch the same source-resolution paths.

### 4. Nobody has read PR #130's diff

It auto-merged overnight, on CI plus its own author's verification. The claims in this handoff about
what it says come from reading the merged document, not from reviewing the change as it landed.
Given that it is the forever contract for Phases 3–5, **a careful read before building against it is
cheap insurance** — the same read found two real defects in #127.

### 5. Naming debt, small and deliberate

`-uitest-updates-state` seeds a fixture that has nothing to do with updates (`two-listings`). One
seeding path with isolated storage was judged worth more than a tidier spelling; rename it if a
third unrelated state appears.

## Launch blockers that are not features

- **No app icon.** `AppIcon.appiconset/` holds only `Contents.json`. Being outsourced — **order it
  early so it is not the long pole.** Unchanged across four handoffs now, which means it still has
  not been ordered. This is the one blocker that cannot be compressed by working harder later.
- **The MAL privacy-label recheck.** `PrivacyInfo.xcprivacy` shipped (#128) with one boundary
  deliberately unresolved: optional MAL sync sends completed-reading progress to the reader's own
  authenticated MAL account. #128 treats that as user-authorized account functionality rather than
  collection by this app — the developer receives none of it — but says outright that Apple's broad
  definition of collection focuses on retained off-device transmission and that this should be
  rechecked. It does not affect the required-reason mapping. **Do not let it get lost when the App
  Store privacy labels are filled in.**
- **Adult-source gating** — settled by ADR-0022. Not a blocker, just a thing not to undo.
- No listing screenshots, privacy-policy URL, App Store description, or TestFlight run.

## On dispatching agents — what this session learned

Both workers ran through **orchestration** rather than as handoffs, and being told when they
finished was worth it: one of them died mid-task and would otherwise have looked idle forever.

```sh
orca orchestration run-create --objective "<objective>" --json
orca orchestration task-create --spec "<full brief>" --json
orca orchestration worker-start --task <id> --worktree <sel> --agent <codex|claude> \
  --model <id> --effort high --json
orca orchestration check --wait --types worker_done,escalation,question --timeout-ms 900000 --json
```

Points that cost real time here:

- **Worktree and repo selectors need a prefix.** `--repo <uuid>` and
  `--worktree <repo-id>::<path>` both fail with `selector_not_found`; they want `id:<uuid>` and
  `id:<repo-id>::<path>`. The error names neither the flag nor the fix.
- **After the first `worker-start`, later ones fail `consumer_fenced`** until you pass
  `--from <coordinator terminal handle>` explicitly. `run-use` does not clear it, and creating a
  fresh Run does not either.
- **If the Orca runtime restarts, every orchestration command needs `--terminal <coordinator
  handle>`** or it fails `no_active_terminal`. Record your coordinator handle at `run-create` time;
  `run-show` still reports it afterwards.
- **A `check --wait` can end in `runtime_unavailable` rather than a timeout.** That is the app
  restarting under you, not a worker failure — the error carries an exact `--retry-request` command.
  Check PR state before assuming anything was lost.
- **A worker can die mid-turn and still look `live`.** One hit `API Error: ENOTFOUND`, stopped, and
  reported `status: live` / `dispatched` with 91 insertions sitting uncommitted. `worker-read` shows
  the transcript, `terminal read` shows the screen, and `git -C <worktree> diff --stat` shows
  whether it actually did anything. It resumed fine from a `terminal send` nudge and finished the
  whole task.
- **Start every independent worker before the first wait**, or the work serializes.
- **Set `--model`/`--effort` at start time.** Changing effort mid-flight means discarding work.
- **A `worker_done` is not a merge.** Verify the claims: grepping the branch for what #131 said it
  removed took seconds and is the only reason this handoff can state it as fact.
- The repo's configured setup hook is `pnpm install`, which has nothing to do in a Swift project
  with no `package.json`. `--setup skip` is correct here.

## Gotchas

Re-verify any that becomes load-bearing rather than trusting this list.

- **A passing test is not evidence until you have seen it fail.** Row 8.5 was "fixed" with an
  explicit `.accessibilityAddTraits`, and the new test passed — *and passed again with the modifier
  stashed*, because SwiftUI's `Menu` already supplies the trait. #131 followed the rule properly:
  mutating all three resolution paths back to the singleton failed 6 of 9 new tests, including the
  shipped bug's exact signature. Stash the fix and re-run before believing a green assertion.
- **File:line citations rot within one session.** #123 invalidated a citation written hours earlier
  in the same session. Both Phase 2 documents carry a verified-against commit for this reason, and
  cite living owned documents by *term or section*, never by line. Keep doing that.
- **Changing an accessibility label silently breaks XCUITests.** They match the *label*, not the
  drawn text, and CI runs neither UI suite. Four assertions match headings by drawn text
  (`app.staticTexts["MyAnimeList"]`, `["More Like This"]`, `["Keep your library current"]`,
  `["Updates"]`). Grep the UI tests before touching any label.
- **A bare accessibility query can match the wrong list.** Settings has two lists of source names;
  rows are namespaced `browseSource.` and `preferredSource.` for exactly this reason.
- **CI is a major version behind local** — `macos-15` → Xcode 16.4 / Swift 6.0 vs local 26.x / 6.2.
  Green locally is not evidence for CI on new syntax. Treat isolated conformances,
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

- **Bounds-check citations mechanically before trusting a document.** Regex every `path:line` out of
  the Markdown, assert the file exists and the range is within its line count, then content-check
  the load-bearing claims by hand. On #127 that was 215 citations verified in seconds, which is what
  made a real review of a 359-line evidence document affordable.
- **You can look at a UI test's screenshots.** Run with `-resultBundlePath <path>`, then
  `xcrun xcresulttool export attachments --path <bundle> --output-path <dir>`; `manifest.json` maps
  each attachment's `suggestedHumanReadableName` to its exported file. This is the missing half of
  the `ui-verification-technique` memory.
- **Test totals come from the result bundle, not the log tail.**
  `xcrun xcresulttool get test-results summary --path <bundle>` gives pass/fail/skip counts; the
  streamed log prints per-suite lines that are easy to mistake for the total.

## Repository state

- `main` at `7448a0e` (#130 merged). This branch carries only the handoff.
- `gh issue list`: **#90 only**. `gh pr list`: **#131** open with squash auto-merge armed, waiting
  on `Build & unit tests`.
- Unit suite **782 total, 780 passed, 2 skipped, 0 failed** (from #131's run, not yet on `main`).
  `main` itself is at 773/771/2/0. SwiftLint clean.
- Three idle Orca worktrees remain under `~/orca/workspaces/Manga-Reader/` —
  `host-api-inventory`, `privacy-manifest`, and `registry-injection`. The first two are fully
  merged; the third holds #131 until it lands. `orca worktree rm` them when convenient.
- `docs/superpowers/handoff/` holds this file and `archive/` (73 archived handoffs plus its
  README). Two `.md` files at this level means someone skipped the rule.
