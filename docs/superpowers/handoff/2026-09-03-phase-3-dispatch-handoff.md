# Handoff — the app is MangaCarta; Phase 3 is planned and ready to dispatch

Date: 2026-09-03 (afternoon)
Repository: `/Users/eliasmagdaleno/Manga-Reader` (directory unchanged; GitHub is now
`eliasmagdaleno/MangaCarta`)
Branch: `docs/handoff-2026-09-03-phase-3`, off `main` at `9394faa`.

**This is the live handoff, and it is the whole of what is outstanding.** Writing a new one means
`git mv`-ing this into `archive/` first and carrying forward whatever below is still true
(`CLAUDE.md` → "Handoffs").

## The roadmap

Six phases, ~8–9 weeks. The reasoning and the Paperback catalog research are in
`archive/2026-08-31-launch-roadmap-handoff.md`. **Read it once** rather than re-deriving it.

1. **Finish what is nearly done** — *two device tasks remain; no code is owed.*
2. **Host API design** — ✅ done (#130).
3. **JavaScriptCore runtime + WeebCentral port** (~2w) — **planned, briefs written, ready to
   dispatch. This is the next thing to build.**
4. **Repo format + installer** (~1–1.5w).
5. **Theme engines** (~1w for Madara, then days each) — Madara alone is 29 sites.
6. **Launch prep** (~1w).

## What this session shipped

**The app is named MangaCarta** (#133, merged). Product, target, scheme, Swift module
(`Manga_Reader` → `MangaCarta`), on-disk directories, app struct, MangaDex User-Agent token, and
the GitHub repository. Recorded as **ADR-0023**.

The timing was the substantive part: Phases 3–5 mint this project's first durable *external*
artifacts — a JS Host API third-party authors write against, a bundle format, a repository manifest
schema. Those acquire a name at birth. Renaming now cost one PR; after Phase 4 it would have cost a
migration imposed on people outside this repository.

**The bundle identifier `Elias-Magdaleno.Manga-Reader` is deliberately frozen**, along with the
`…libraryRefresh` BGTask id (in *both* `UpdateScheduler` and `Info.plist` — they must stay in
lockstep or `BGTaskScheduler.register` throws at launch), the `mangareader://oauth/mal` URL scheme
(registered server-side with MyAnimeList), and `MALCredentialStore`'s Keychain service. ADR-0023
holds the reasoning. **Do not "finish" the rename by changing these** — the bundle id is the key to
the app's data container, and the store filenames beneath it carry no app name of their own, so
changing it would not rename the library, it would orphan it. Verified after the rename:
`works.json` dated 24 Aug is still in the simulator container.

Also re-enabled SwiftLint's `type_name`, which had been disabled with a comment that the rename
made false. It passes on CI as well as locally.

## Phase 3 is planned — the briefs are written

`docs/superpowers/plans/2026-09-03-phase-3-jsc-runtime.md` holds the whole thing: seven slices, the
dependency graph, wave order, suggested agent per slice, and **three ready-to-paste worker briefs
for Wave 1** plus a shared preamble carrying the working rules.

The cut follows the spec's own layering. **S1 (manifest validation), S2 (domain wire schemas) and
S3 (the WebKit isolation spike) are independent of each other and of the runtime core** — S1 and S2
are pure functions over JSON with no JavaScriptCore dependency at all. That is what makes Wave 1
genuinely three-wide rather than nominally parallel.

Every one of Section 15's twelve acceptance criteria is owned by exactly one slice, so "is Phase 3
done" is answerable by checking off a list rather than by judgement.

**S3 is the slice to watch.** It closes evidence gate 2, and it is a research task whose deliverable
is a decision: does iOS 17.5 offer a WebKit mechanism giving *both* persistent Cloudflare clearance
*and* per-Source isolation? Today's `WebViewService` deliberately uses one shared persistent store
precisely so `cf_clearance` survives, so the two requirements pull against each other. The spec
already names the fallback — separate nonpersistent stores plus explicit loss of cross-launch
clearance, **never** a shared global store. **Both outcomes are acceptable; silence is not.** Its
output is an ADR-0003 amendment, because a decision that lives only in a handoff is not recorded.
It runs in Wave 1 rather than when S5 needs it, because a bad answer changes what Wave 2 builds.

## What is owed

### 1. Dispatch Wave 1 — the immediate next action

`main` is clean and the rename has landed, so Phase 3 branches can be cut. Nothing blocks S1, S2 or
S3. Dispatch mechanics and their hard-won gotchas are near the bottom of this document.

### 2. The UI test suites are failing on `main` — issue #134, new this session

15 tests across both UI bundles, e.g. `XCTAssertTrue failed - the detail page should list a
chapter`. **This is not the rename's doing** — the same tests were run from a clean `main` worktree
at `dfc6164` and failed with the byte-identical assertion.

The more important half is *why nobody noticed*: **CI runs neither UI suite**, so they can rot
indefinitely without turning anything red. Not yet diagnosed. Ruled out so far: the app launches,
MangaDex returns 200, the container is intact, and the UI-test fixture path is computed entirely
app-side. Several failing tests are live-network or MAL-dependent and MAL has never been signed in
on this simulator, which is a plausible first hypothesis but is **not confirmed**.

Worth deciding, not just fixing: whether live-network UI tests belong in CI at all. A suite that
cannot run in CI and is not run locally either is not providing coverage, only the appearance of it.

### 3. Live-verify MAL progress push — the user's to run

Built, wired, tested (`MALProgressCoordinator`, `MALProgressOutbox`, the Settings toggle and queue
status). What no unit test can show: **sign in on a device, read a chapter to the end, and confirm
the number moves on myanimelist.net.** `scripts/mal_live_write.py` pokes the API directly if the
in-app path needs isolating. This may also bear on #134.

### 4. The manual VoiceOver pass — #90, the user's to run

Open, `ready-for-human`, **no row has a verdict yet**, and no results file in
`docs/accessibility/` — which is how you can tell at a glance it has not started.

`./scripts/voiceover-pass.sh` from the repo root parses the checklist at runtime, takes
pass/fail/skip per row, writes `docs/accessibility/voiceover-results-<date>.md`, and resumes where
it stopped. It needs a **real iPhone** — simulator VoiceOver differs on the rotor and on focus
restoration, which is most of what these rows test.

Rows most needing eyes: **4.3**, **6.5**, **7.2**, **7.5**, **7.6**.

**Section 8** (11 rows) covers the source picker. Two of its rows were investigated before the pass
and are expected to *pass* rather than fail — 8.8 was a real defect, now fixed; 8.5 was not a defect
at all. **Neither is closed:** a trait being present is not VoiceOver speaking it, and that
distinction is the whole reason this is a device pass.

Close #90 when every row has a verdict, **not** when every defect is fixed.

Items 3 and 4 both want a device in hand; doing them in one sitting is worth more than doing them
well apart.

### 5. Nobody has read PR #130's diff

Still true, carried forward. It auto-merged overnight on CI plus its own author's verification.
Given it is the forever contract for Phases 3–5, **a careful read before building against it is
cheap insurance** — the same kind of read found two real defects in #127. Ideally before S1 and S2
land code against it.

### 6. Naming debt, small and deliberate

`-uitest-updates-state` seeds a fixture that has nothing to do with updates (`two-listings`). One
seeding path with isolated storage was judged worth more than a tidier spelling; rename it if a
third unrelated state appears.

## Launch blockers that are not features

- **No app icon.** `AppIcon.appiconset/` holds only `Contents.json`. Being outsourced — **order it
  early so it is not the long pole.** Unchanged across five handoffs now. This is the one blocker
  that cannot be compressed by working harder later. It now needs the *MangaCarta* name on it,
  which is a reason to have waited and no reason to wait longer.
- **The MAL privacy-label recheck.** `PrivacyInfo.xcprivacy` shipped (#128) with one boundary
  deliberately unresolved: optional MAL sync sends completed-reading progress to the reader's own
  authenticated account. #128 treats that as user-authorized account functionality rather than
  collection by this app — the developer receives none of it — but says outright it should be
  rechecked against Apple's broader definition. It does not affect the required-reason mapping.
  **Do not let it get lost when the App Store privacy labels are filled in.**
- **Adult-source gating** — settled by ADR-0022. Not a blocker, just a thing not to undo.
- No listing screenshots, privacy-policy URL, App Store description, or TestFlight run.
- The App Store listing name is now MangaCarta; **nobody has checked it against existing App Store
  apps or trademarks.** Worth five minutes before the listing is written.

## Dispatch mechanics

```sh
orca orchestration run-create --objective "<objective>" --json     # record the coordinator handle
orca orchestration task-create --spec "<full brief>" --json
orca orchestration worker-start --task <id> --worktree id:<repo-id>::<path> \
  --agent <codex|claude> --model <id> --effort high --setup skip --json
orca orchestration check --wait --types worker_done,escalation,question --timeout-ms 900000 --json
```

Each of these cost real time when it was learned:

- Selectors need an `id:` prefix — `--repo id:<uuid>`, `--worktree id:<repo-id>::<path>`. The error
  names neither the flag nor the fix.
- After the first `worker-start`, later ones fail `consumer_fenced` until you pass
  `--from <coordinator handle>`. Neither `run-use` nor a fresh Run clears it.
- If the Orca runtime restarts, every command needs `--terminal <coordinator handle>` or it fails
  `no_active_terminal`. Record that handle at `run-create`; `run-show` reports it afterwards.
- `check --wait` ending in `runtime_unavailable` is the app restarting, not a worker failure — the
  error carries an exact `--retry-request`. Check PR state before assuming loss.
- **A worker can die mid-turn and still report `live`.** One hit `API Error: ENOTFOUND`, stopped,
  and reported `status: live` with 91 insertions uncommitted. `worker-read` shows the transcript,
  `git -C <worktree> diff --stat` shows whether it did anything; a `terminal send` nudge resumed it.
- **Start every independent worker before the first wait**, or the work serializes.
- Set `--model`/`--effort` at start time; changing effort mid-flight discards work.
- **A `worker_done` is not a merge.** Verify the claim by grepping the branch.
- `--setup skip` is correct — the configured hook is `pnpm install`, meaningless in a Swift repo.

## Gotchas

Re-verify any that becomes load-bearing rather than trusting this list.

- **A passing test is not evidence until you have seen it fail.** Row 8.5 was "fixed" with an
  explicit `.accessibilityAddTraits`, and the new test passed — *and passed again with the modifier
  stashed*, because SwiftUI's `Menu` already supplies the trait. Stash the fix and re-run before
  believing a green assertion.
- **File:line citations rot within one session.** #123 invalidated one written hours earlier the
  same day. Cite living documents by *term or section*, never by line.
- **Changing an accessibility label silently breaks XCUITests.** They match the *label*, not the
  drawn text — and per #134 CI runs neither UI suite, so nothing will tell you. Grep the UI tests
  before touching any label.
- **A bare accessibility query can match the wrong list.** Settings has two lists of source names;
  rows are namespaced `browseSource.` and `preferredSource.` for exactly this reason.
- **CI is a major version behind local** — `macos-15` → Xcode 16.4 / Swift 6.0 vs local 26.x / 6.2.
  Green locally is not evidence for CI on new syntax. Treat isolated conformances,
  `nonisolated(nonsending)`, `@concurrent` and `Task.immediate` as unavailable. **This will bite S4
  hardest**, since a JSC bridge is exactly where a Swift 6.2 concurrency feature is tempting.
- **CI's SwiftLint is not this machine's either.** A five-member tuple failed CI on `large_tuple`
  while local SwiftLint 0.65.0 passed the same file, exit 0.
- **`AppComposition.init` sits right at SwiftLint's body-length limit.** Adding two lines trips
  `function_body_length`. Extract rather than inline.
- **A wedged simulator looks exactly like a failing suite.** `** TEST FAILED **` with no failing
  test named is `Application failed preflight checks` / `Busy`. `xcrun simctl boot "iPhone 17 Pro"`
  and re-run. **Do not erase the device** — it holds the seeded fixture, and erasing has already
  destroyed `works.json` once (`sim-data-is-a-fixture` memory).
- **`project.pbxproj` churns under you** whenever Xcode has the project open. Check
  `git diff --stat` immediately before `git add`, not right after `xcp`. **A large rename needs
  Xcode quit outright** — that is how #133 kept a clean 66/66 symmetric diff.
- **`Secrets.xcconfig` is gitignored**, so a fresh worktree fails to build with "Unable to open base
  configuration reference file" until you copy it in. This is not a broken branch.
- **Branch protection does not stop this account** — `enforce_admins: false`. A direct push to
  `main` lands and waives both required checks. Ask first.
- **Do not stack PRs** — a child closes unrecoverably when its base is deleted.
- **A full CI run takes ~12 minutes.** `gh pr merge --auto` beats waiting.
- **Target the iPhone 17 Pro simulator** on every `xcodebuild` — it holds the seeded fixture.
- **Test totals come from the result bundle, not the log tail.**
  `xcrun xcresulttool get test-results summary --path <bundle>`. To see which tests failed, walk
  `get test-results tests` — the bundle nests Test Plan → bundle → suite → case, and the bundle-level
  `result` is how you tell a unit-suite failure from a UI-suite one at a glance.

## Repository state

- `main` at `9394faa` (#133 merged). This branch carries the handoff and the Phase 3 plan.
- `gh issue list`: **#90** (VoiceOver, ready-for-human) and **#134** (UI suites failing, new).
- Unit suite `MangaCartaTests`: **passing**. Both UI bundles: **failing, pre-existing (#134)**.
  SwiftLint clean, `type_name` now enabled.
- Three idle Orca worktrees remain under `~/orca/workspaces/Manga-Reader/` —
  `host-api-inventory`, `privacy-manifest`, `registry-injection`. All three are fully merged;
  `orca worktree rm` them when convenient.
- `docs/superpowers/handoff/` holds this file and `archive/` (74 archived handoffs plus its
  README). Two `.md` files at this level means someone skipped the rule.
