# Handoff — Phase 3 Wave 1 is done; Wave 2 is next

Date: 2026-09-03 (evening), revised 2026-09-04 when Wave 1 closed and Wave 2 was dispatched
Repository: `/Users/eliasmagdaleno/Manga-Reader` (directory unchanged; GitHub is
`eliasmagdaleno/MangaCarta`)
Branch: `docs/handoff-wave-1-closed`, off `main` at `3f281c1`.

**This is the live handoff, and it is the whole of what is outstanding.** Writing a new one means
`git mv`-ing this into `archive/` first and carrying forward whatever below is still true
(`CLAUDE.md` → "Handoffs").

## The roadmap

Six phases, ~8–9 weeks. The reasoning and the Paperback catalog research are in
`archive/2026-08-31-launch-roadmap-handoff.md`. **Read it once** rather than re-deriving it.

1. **Finish what is nearly done** — *two device tasks remain; no code is owed.*
2. **Host API design** — ✅ done (#130).
3. **JavaScriptCore runtime + WeebCentral port** (~2w) — **Wave 1 done; Wave 2 is next.**
4. **Repo format + installer** (~1–1.5w).
5. **Theme engines** (~1w for Madara, then days each) — Madara alone is 29 sites.
6. **Launch prep** (~1w).

## Wave 1 shipped — six of twelve acceptance criteria are closed

The plan is `docs/superpowers/plans/2026-09-03-phase-3-jsc-runtime.md`: seven slices, the dependency
graph, wave order, per-slice model/provider guidance, and worker briefs. **Spec Section 15's twelve
acceptance criteria are the definition of done**, and each is owned by exactly one slice.

| Slice | Criteria | PR | State |
|---|---|---|---|
| S2 — domain wire schemas + adapters | 3, 4 | #137 | merged `2d1cacc` |
| S1 — manifest & declaration validation | 2, 9 | #139 | merged `dfcecbf` |
| S3 — WebKit isolation spike | 6 (cookies), 8 | #140 | merged `3f281c1` |

**Criteria still unowned by merged code: 1, 5, 7, 10, 11, 12** — Waves 2 and 3.

### Evidence gate 2 is closed, and the answer was the good one

S3's deliverable was a decision, not a feature, and it landed as **ADR-0003 Amendment 3**:
`WKWebsiteDataStore(forIdentifier:)` on iOS 17.5 gives **both** per-Source isolation and
persistence across relaunch. The spec's fallback — nonpersistent stores, clearance lost every
launch — **is not taken**, so readers do not re-solve Cloudflare challenges on every cold start.

**Three** host rules came out of the prototype and **S5 must carry all three**. They are three
faces of one behaviour: an identified store materialises lazily, so nearly everything about it is
true only *eventually*.

- **A store no `WKWebView` was ever constructed against never becomes durable.** Writing through
  `WKHTTPCookieStore` and holding the store alive was not enough.
- **A freshly opened store's cookie jar loads asynchronously.** The first `getAllCookies` returns
  an **empty jar with no error**. Never gate behavior on an immediate jar read — drive the browser
  and let WebKit apply cookies. Losing that race looks exactly like *"Cloudflare keeps
  re-challenging me"*, and it already produced one wrong preliminary conclusion inside the spike.
- **A constructed store is not yet on disk; `fetchAllDataStoreIdentifiers` will not list it.**
  The object is created eagerly and its directory lazily, on *first use*. So **an installer or
  data-removal screen that enumerates stores at launch reads a listing that has not caught up, and
  would show a reader nothing.** Await one operation on a store before expecting it to appear.

The store identifier is a **name-based (v5) UUID over a fixed namespace and the qualified Source
id**. The namespace constant is permanent — changing it orphans every reader's clearance.

`WebViewService` is deliberately **unchanged**: it keeps its shared store for the compiled
`WeebCentralSource` until that Source is ported (criterion 12), so the app holds both mechanisms
until then.

## What is owed

### 1. Wave 2 is dispatched and running — supervise it

**Wave 1 is complete.** #137, #139 and #140 are all merged; `main` is at `3f281c1` and the unit
bundle is green at 889 tests.

**Wave 2 was dispatched 2026-09-04 as Run `run_f1c064acb57c`**, coordinator handle
`term_15c0eb64-b03c-4606-add4-e337286e7ea7`. **Record that handle** — after a runtime restart every
orchestration command needs it. Both worktrees are off `main` at `3f281c1` with `Secrets.xcconfig`
copied in, and both workers were confirmed *actually running* by their terminal preview, not merely
by `state: ready`:

| Slice | Criteria | Worktree | Agent | Dispatch |
|---|---|---|---|---|
| S4 — JSC runtime core + bridge | 7 | `phase3-s4-jsc-runtime` | Claude Opus high | `ctx_229a97888248` |
| S5 — host capabilities | 5, 6 (storage), 11 | `phase3-s5-host-capabilities` | Codex `gpt-5.6-sol` high | `ctx_296bc5d9671d` |

**What is owed here is supervision, not dispatch.** Concretely, and in this order when a slice
reports done:

1. `git -C <worktree> status` and the terminal preview — **the dispatch status lies**, and both
   Wave 1 stalls looked `live`.
2. Rebase onto `main` and expect a `project.pbxproj` conflict if the peer landed first; the
   resolution is **keep-both**.
3. Re-run the **full** `MangaCartaTests` bundle after that rebase and read the totals from the
   result bundle. A worker's own green run does not survive the next merge — that is exactly how
   #140 got through.
4. Only then merge, and check the PR body names a test per acceptance criterion it claims.

Their briefs are in the plan (`docs/superpowers/plans/2026-09-03-phase-3-jsc-runtime.md`), written
against what Wave 1 actually landed. **PRs #142 and #143 may still have been in flight** when this
was written — #142 is this correction, #143 is the Wave 2 briefs.

#140 took two extra rounds after it was first reported done, and both are worth carrying:

- It conflicted with #139 in `project.pbxproj`, because two slices adding test files touch the same
  group children and Sources phase. Resolution is **keep-both** — every hunk is a pure addition.
- After that rebase, one of its own tests failed **in the full bundle while passing in isolation**.
  Not flakiness: constructing an identified store creates its directory lazily, so the on-disk
  listing had not caught up under bundle load. The fix awaits one operation on the store and
  asserts through a **bounded wait that names the eventual consistency** rather than hiding it; the
  test still fails when pointed at a store that never registers. That is where the third host rule
  above came from.

The deeper point, which will recur in every wave: **a worker's green run is not evidence that its
tests survive the next merge.** #140's suite was the only new suite in the bundle when its worker
ran it. Re-run after every rebase, from the result bundle.

### 2. What the two Wave 2 slices are building

Both are running (item 1). This is what they were told, and what to check their PRs against.

- **S4 — JSC runtime core + invocation bridge** (criterion 7). **Opus high earns its place here.**
  S2 left it a hard requirement: Foundation conversion **erases `undefined` and Symbol properties
  and collapses functions and typed arrays into indistinguishable objects**, so the bridge must
  reject on raw `JSValue` kinds *before* conversion. The Foundation-level validator catches the
  native analogues, but that is not a substitute.
- **S5 — host capabilities: http, storage, log** (criteria 5, 6 storage, 11). Build
  `host.browser.extract` on a **per-Source** store per Amendment 3, carrying all three rules above —
  **not** on `WebViewService`'s shared store.

**Run one on Claude and one on Codex.** This is not a preference; see "Dispatch mechanics".

### 3. Amend the spec for contract gaps 1–4

Five gaps were found reading #130 before Wave 1. **Gap 5 is resolved** — S3's amendment gives
`interaction` two cases, `allowForeground` and `never`, and makes the effective policy the
**intersection** of the author's request and the host's invocation context, because an engine
cannot know whether the app is foregrounded and must not be able to talk its way into a sheet
during a background refresh.

The other four are **still open in the spec**, each implemented under a documented reading that the
PR bodies record. An implementation slice does not edit the design doc, so someone must:

1. **§1.2's canonical declaration example omits `hostAPI`**, which §7 calls required — and unknown
   keys outside `configuration` fail installation, so the example is not a valid declaration.
2. **`hostAPI` version strings have no grammar.** Patch components, comparison, and invalid-string
   handling are undefined. S1 chose a strict rule; the spec should say it.
3. **The `warnings` channel exists only on `Page<T>`.** `chapters`, `pages` and `detail` have no
   slot for the warnings §2.3 and §2.4 tell them to emit, which makes **criterion 3 untestable for
   three of the five types**. S2 carried warnings uniformly anyway. **This is the consequential
   one.**
4. **The cover-URL rule can let one bad card reject a whole feed.** §10 splits *malformed* covers
   (drop the field) from *policy-invalid* ones (reject the operation) without drawing the line, so
   a single `http://` cover erases an otherwise usable feed and defeats §2.1's partial-success
   rule. S2 implemented the literal reading. **Worth reconsidering, not just documenting.**

### 4. The UI test suites are failing on `main` — issue #134

15 tests across both UI bundles. **Not the rename's doing** — reproduced from a clean `main`
worktree at `dfc6164` with the byte-identical assertion. The more important half is *why nobody
noticed*: **CI runs neither UI suite.** Not yet diagnosed. Ruled out: the app launches, MangaDex
returns 200, the container is intact, the fixture path is computed app-side. Several failing tests
are live-network or MAL-dependent and MAL has never been signed in on this simulator — plausible,
**not confirmed**.

Worth deciding, not just fixing: whether live-network UI tests belong in CI at all. A suite that
cannot run in CI and is not run locally either is not coverage, only the appearance of it.

### 5. Live-verify MAL progress push — the user's to run

Built, wired, tested (`MALProgressCoordinator`, `MALProgressOutbox`, the Settings toggle and queue
status). What no unit test can show: **sign in on a device, read a chapter to the end, and confirm
the number moves on myanimelist.net.** `scripts/mal_live_write.py` pokes the API directly if the
in-app path needs isolating. This may also bear on #134.

### 6. The manual VoiceOver pass — #90, the user's to run

Open, `ready-for-human`, **no row has a verdict yet**, and no results file in
`docs/accessibility/` — which is how you can tell at a glance it has not started.

`./scripts/voiceover-pass.sh` from the repo root parses the checklist at runtime, takes
pass/fail/skip per row, writes `docs/accessibility/voiceover-results-<date>.md`, and resumes where
it stopped. It needs a **real iPhone** — simulator VoiceOver differs on the rotor and on focus
restoration, which is most of what these rows test.

Rows most needing eyes: **4.3**, **6.5**, **7.2**, **7.5**, **7.6**.

**Section 8** (11 rows) covers the source picker. Two of its rows were investigated before the pass
and are expected to *pass* — 8.8 was a real defect, now fixed; 8.5 was not a defect at all.
**Neither is closed:** a trait being present is not VoiceOver speaking it, and that distinction is
the whole reason this is a device pass.

Close #90 when every row has a verdict, **not** when every defect is fixed.

Items 5 and 6 both want a device in hand; doing them in one sitting is worth more than doing them
well apart.

### 7. Naming debt, small and deliberate

`-uitest-updates-state` seeds a fixture that has nothing to do with updates (`two-listings`). One
seeding path with isolated storage was judged worth more than a tidier spelling; rename it if a
third unrelated state appears.

## Launch blockers that are not features

- **No app icon.** `AppIcon.appiconset/` holds only `Contents.json`. Being outsourced — **order it
  early so it is not the long pole.** Unchanged across six handoffs now. This is the one blocker
  that cannot be compressed by working harder later. It needs the *MangaCarta* name on it.
- **The MAL privacy-label recheck.** `PrivacyInfo.xcprivacy` shipped (#128) with one boundary
  deliberately unresolved: optional MAL sync sends completed-reading progress to the reader's own
  authenticated account. #128 treats that as user-authorized account functionality rather than
  collection by this app — the developer receives none of it — but says outright it should be
  rechecked against Apple's broader definition. It does not affect the required-reason mapping.
  **Do not let it get lost when the App Store privacy labels are filled in.**
- **Adult-source gating** — settled by ADR-0022. Not a blocker, just a thing not to undo.
- No listing screenshots, privacy-policy URL, App Store description, or TestFlight run.
- The App Store listing name is MangaCarta; **nobody has checked it against existing App Store apps
  or trademarks.** Worth five minutes before the listing is written.

## Dispatch mechanics

```sh
orca orchestration run-create --from <coordinator handle> --objective "<objective>" --json
orca orchestration task-create --from <coordinator handle> --spec "<full brief>" --json
orca orchestration worker-start --from <coordinator handle> --task <id> \
  --worktree id:<repo-id>::<path> --agent <codex|claude> --model <id> --effort high --json
orca orchestration check --terminal <coordinator handle> --types worker_done,escalation,question --json
```

Each of these cost real time when it was learned.

- Selectors need an `id:` prefix — `--repo id:<uuid>`, `--worktree id:<repo-id>::<path>`. The error
  names neither the flag nor the fix.
- **`--from <coordinator handle>` is needed from the very first command.** Outside a live Orca
  terminal, `run-create` itself fails `no_active_sender_terminal`; later `worker-start`s fail
  `consumer_fenced`. Get the handle from `orca terminal list --json` — any terminal whose
  `worktreePath` is the main repo will do.
- **Flag spellings differ per subcommand.** `worker-stop`/`worker-read`/`worker-abandon` take
  `--dispatch` and **reject** `--from`; `task-update` takes `--id`, not `--task`; `check` takes
  `--terminal`, not `--from`.
- **Split every parallel wave across providers.** Wave 1 put S1 and S3 on Claude and S2 on Codex.
  Claude's session limit hit mid-implementation and **both** Claude workers stopped with
  uncommitted work **while still reporting `liveness: live`**; the Codex worker was untouched and
  finished. One provider per wave is one failure domain and the failure is silent — nothing resumed
  until a human looked, hours later. After any wave goes quiet, check `git -C <worktree> status`
  and the terminal preview; **the dispatch status lies.**
- **Default `--model` to something cheap; make Opus high earn its place.** `claude-sonnet-5` or
  `gpt-5.6-sol` is the default. **Fable is not available on this account** — a worker dispatched on
  `claude-fable-5-1` parks at an unconfirmed launch prompt instead of failing, so it looks
  dispatched and is not. Per-slice choices are in the plan's model-and-provider section.
- **A launched worker may sit at a confirmation prompt without ever starting**, reporting `ready`
  and `live` with only the seed message in its transcript. That is the cheap moment to swap a
  model — but only if you look.
- **`--setup skip` is rejected when the worktree already exists** (`invalid_argument: Creation and
  setup options apply only to new-child or new-top-level worktrees`). It applies only to worktrees
  `worker-start` creates itself.
- **Changing a worker's model means abandon, not stop.** `worker-stop` cannot settle a
  `user_owned` terminal — it returns `state: stop_unknown` and closes nothing — and the task then
  refuses `ready`. The sequence that works is `worker-abandon --dispatch <id>` →
  `task-update --from <coordinator> --id <task> --status ready` → a fresh `worker-start`.
- If the Orca runtime restarts, every command needs `--terminal <coordinator handle>` or it fails
  `no_active_terminal`. Record that handle at `run-create`; `run-show` reports it afterwards.
- `check --wait` ending in `runtime_unavailable` is the app restarting, not a worker failure — the
  error carries an exact `--retry-request`. Check PR state before assuming loss.
- **Start every independent worker before the first wait**, or the work serializes.
- Set `--model`/`--effort` at start time; changing effort mid-flight discards work.
- **A `worker_done` is not a merge**, and it is not a green suite either. #140 reported done and
  its test then failed in the full bundle. Verify by rebasing onto `main` and re-running.
- **A worker's green run can go red when the next slice merges**, because its suite was the only
  new one in the bundle when it ran. Re-run after every rebase.

## Gotchas

Re-verify any that becomes load-bearing rather than trusting this list.

- **A passing test is not evidence until you have seen it fail.** Row 8.5 was "fixed" with an
  explicit `.accessibilityAddTraits`, and the new test passed — *and passed again with the modifier
  stashed*, because SwiftUI's `Menu` already supplies the trait.
- **Squash merges make the commit graph lie about what is merged.** Every merged branch shows
  1–2 commits "not on main" and a huge `git diff origin/main HEAD`; the PR state is the only
  reliable check. This matters when cleaning up branches — `git branch -d` refuses them all.
- **File:line citations rot within one session.** Cite living documents by *term or section*.
- **Changing an accessibility label silently breaks XCUITests.** They match the *label*, not the
  drawn text — and per #134 CI runs neither UI suite, so nothing will tell you.
- **A bare accessibility query can match the wrong list.** Settings has two lists of source names;
  rows are namespaced `browseSource.` and `preferredSource.` for exactly this reason.
- **CI is a major version behind local** — `macos-15` → Xcode 16.4 / Swift 6.0 vs local 26.x / 6.2.
  Treat isolated conformances, `nonisolated(nonsending)`, `@concurrent` and `Task.immediate` as
  unavailable. **This will bite S4 hardest**, since a JSC bridge is where a Swift 6.2 concurrency
  feature is most tempting.
- **CI's SwiftLint is not this machine's either.** A five-member tuple failed CI on `large_tuple`
  while local SwiftLint 0.65.0 passed the same file, exit 0.
- **`AppComposition.init` sits right at SwiftLint's body-length limit.** Extract rather than inline.
- **A wedged simulator looks exactly like a failing suite.** `** TEST FAILED **` with no failing
  test named is `Application failed preflight checks` / `Busy`. `xcrun simctl boot "iPhone 17 Pro"`
  and re-run. **Do not erase the device** — it holds the seeded fixture, and erasing has already
  destroyed `works.json` once.
- **`project.pbxproj` churns under you** whenever Xcode has the project open. Check
  `git diff --stat` immediately before `git add`. **Two slices adding test files will conflict
  there** — #139 and #140 did; the resolution is keep-both, since both sides are pure additions to
  the group children and the Sources build phase.
- **`Secrets.xcconfig` is gitignored**, so a fresh worktree fails to build with "Unable to open base
  configuration reference file" until you copy it in. This is not a broken branch.
- **`TEST_RUNNER_`-prefixed shell variables reach the hosted unit bundle**, not just UI tests —
  simpler than the marker-file workaround `seed-simulator.sh` uses.
- **Recorded so nobody retries them** (from the S3 spike): a `WKURLSchemeHandler` response reaches
  the navigation-response delegate downgraded to a bare `NSURLResponse` with **every header
  stripped**, and `loadSimulatedRequest` does not run the response-policy step at all. Only a real
  network load carries response headers to the delegate.
- **Branch protection does not stop this account** — `enforce_admins: false`. A direct push to
  `main` lands and waives both required checks. Ask first.
- **Do not stack PRs** — a child closes unrecoverably when its base is deleted.
- **A full CI run takes ~12 minutes.** `gh pr merge --auto` beats waiting.
- **Target the iPhone 17 Pro simulator** on every `xcodebuild` — it holds the seeded fixture.
- **Test totals come from the result bundle, not the log tail.**
  `xcrun xcresulttool get test-results summary --path <bundle>`.

## Repository state

- `main` at `3f281c1` (#140 merged). PRs #136–#141 are all merged; **Wave 1 is complete**.
- `gh issue list`: **#90** (VoiceOver, ready-for-human) and **#134** (UI suites failing).
- Unit suite `MangaCartaTests`: **889 tests, 884 passed, 0 failed, 5 skipped on `main`.** Both UI bundles: **failing,
  pre-existing (#134)**. SwiftLint clean.
- Orca worktrees under `~/orca/workspaces/Manga-Reader/`: `phase3-s4-jsc-runtime` and
  `phase3-s5-host-capabilities` are **live Wave 2 work**; `phase3-s1-manifest` and
  `phase3-s3-webkit-spike` are **fully merged and removable**. Four others were removed on
  2026-09-03 along with sixteen stale local branches.
- `docs/superpowers/handoff/` holds this file and `archive/` (75 archived handoffs plus its
  README). Two `.md` files at this level means someone skipped the rule.
