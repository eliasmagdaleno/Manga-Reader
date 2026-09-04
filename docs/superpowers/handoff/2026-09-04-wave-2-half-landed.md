# Handoff — Wave 2 is half landed; S5 is parked on a usage limit

Date: 2026-09-04 (late afternoon)
Repository: `/Users/eliasmagdaleno/Manga-Reader` (directory unchanged; GitHub is
`eliasmagdaleno/MangaCarta`)
Branch: `docs/handoff-2026-09-04`, off `main` at `90f15e5`.

**This is the live handoff, and it is the whole of what is outstanding.** Writing a new one means
`git mv`-ing this into `archive/` first and carrying forward whatever below is still true
(`CLAUDE.md` → "Handoffs").

## The roadmap

Six phases, ~8–9 weeks. The reasoning and the Paperback catalog research are in
`archive/2026-08-31-launch-roadmap-handoff.md`. **Read it once** rather than re-deriving it.

1. **Finish what is nearly done** — *two device tasks remain; no code is owed.*
2. **Host API design** — ✅ done (#130), and its four open contract gaps are now closed (#145).
3. **JavaScriptCore runtime + WeebCentral port** (~2w) — **Wave 1 done. Wave 2: S4 merged, S5
   parked.**
4. **Repo format + installer** (~1–1.5w).
5. **Theme engines** (~1w for Madara, then days each) — Madara alone is 29 sites.
6. **Launch prep** (~1w).

## Where Phase 3 stands — seven of twelve acceptance criteria closed

The plan is `docs/superpowers/plans/2026-09-03-phase-3-jsc-runtime.md`: seven slices, the
dependency graph, wave order, per-slice model/provider guidance, and worker briefs. **Spec
Section 15's twelve acceptance criteria are the definition of done**, and each is owned by exactly
one slice.

| Slice | Criteria | PR | State |
|---|---|---|---|
| S2 — domain wire schemas + adapters | 3, 4 | #137 | merged |
| S1 — manifest & declaration validation | 2, 9 | #139 | merged |
| S3 — WebKit isolation spike | 6 (cookies), 8 | #140 | merged |
| S4 — JSC runtime core + bridge | 7 | #144 | **merged `7b7427a`** |
| S5 — host capabilities | 5, 6 (storage), 11 | — | **parked, uncommitted** |

**Criteria still unowned by merged code: 1, 5, 10, 11, 12** (plus 6-storage) — S5 and Wave 3.

Unit suite on `main`: **942 tests, 937 passed, 0 failed, 5 skipped.** SwiftLint clean.

## What is owed

### 1. S5 is parked mid-implementation on a Codex usage limit — resume it

Codex hit its 5-hour usage limit. **The work is on disk and uncommitted** in
`~/orca/workspaces/Manga-Reader/phase3-s5-host-capabilities`:

```
 M MangaCarta.xcodeproj/project.pbxproj
?? MangaCarta/Services/HostBrowser.swift
?? MangaCarta/Services/HostCapabilityTypes.swift
?? MangaCarta/Services/HostHTTPClient.swift
?? MangaCarta/Services/HostJSONValueConverter.swift
?? MangaCarta/Services/HostLogger.swift
?? MangaCarta/Services/HostStorage.swift
?? MangaCarta/Services/HostURLPolicy.swift
?? MangaCartaTests/HostCapabilityTests.swift
```

**Nothing may rebase, checkout, or clean that worktree until Codex resumes.** Uncommitted work is
safe where it sits and nowhere else.

Run `run_f1c064acb57c`, coordinator handle `term_15c0eb64-b03c-4606-add4-e337286e7ea7`, S5 dispatch
`ctx_296bc5d9671d`. **Record that handle** — after a runtime restart every orchestration command
needs it.

**`HostJSONValueConverter.swift` was checked 2026-09-04 (16:00) and is fine — keep it.** It is
the legitimate adapter direction, not the second `JSONValue` conversion path S5 was told not to
write. The two halves compose with no overlap:

| | signature | owner |
|---|---|---|
| `ExtensionJSBridge.jsonValue(from:)` | `JSValue` → Foundation `Any` | S4, merged in #144 |
| `HostJSONValueConverter.convert(_:)` | Foundation `Any` → `JSONValue` | S5 |

The file says so itself in its header — *"S4 owns the raw JSValue bridge; this converter
deliberately starts at Foundation."*

Two things were decided for S5 mid-flight and sent as orchestration messages. **Both are now
recorded in #145's PR body**, because a decision that lives only in a message queue is not
recorded:

- **`JSONValue` lives on `main`** at `MangaCarta/Models/JSONValue.swift`, landed by S1/S2. S5
  consumes it and declares no second copy. (An earlier message wrongly told S5 that S4 owned it and
  to read S4's worktree; that was corrected.)

  **Correction, 2026-09-04:** this used to say "S4 extends it with `init?(converting:)`." **It does
  not.** `JSONValue.swift` on `main` has no such initialiser — S4 shipped `jsonValue(from:)` on
  `ExtensionJSBridge` instead, returning Foundation rather than `JSONValue`. The claim was written
  from the dispatch message rather than from merged code, which is the same mistake as reading a
  strict-grammar rule out of a PR body instead of out of `HostAPIVersion` (gap 2 below). It matters
  because it was the only reason to suspect S5's converter of being a duplicate: there is nothing
  for it to duplicate.
- **The cover-URL policy changed under S5 while it was writing `URLPolicy`** — see ADR-0024 below.

### 2. Supervision protocol, unchanged and still load-bearing

When a slice reports done, in this order:

1. `git -C <worktree> status` and the terminal preview — **the dispatch status lies.**
2. Rebase onto `main` and expect a `project.pbxproj` conflict if a peer landed first; the
   resolution is **keep-both**.
3. Re-run the **full** `MangaCartaTests` bundle after that rebase and read the totals from the
   result bundle.
4. Only then merge, and check the PR body names a test per acceptance criterion it claims.

S4 went through exactly this and passed cleanly: rebase `3f281c1` → `ba0386e`, no conflict, 942
tests green, PR body naming nine tests against the nine clauses of criterion 7.

**New failure mode learned today: a worker can block silently while reporting `live`.** S5 asked
the coordinator a design question and sat in a durable `ask --resume` wait for ~18 minutes with an
empty worktree, heartbeating `live` the whole time. There is no live coordinator to answer unless a
human looks. **Add `orca orchestration check --terminal <handle> --types question` to every
supervision pass**, not just to the pass after a `worker_done`.

**Keep supervision cheap.** The default pass is `check` plus `git -C <worktree> status -sb`. A full
`worker-read` returns whole transcripts with clipped-but-huge tool inputs; read one only to
diagnose a stall or judge a design question.

### 3. Contract gaps 1–4 are closed — #145, merged

All four are in `main`. Three were documentation; the fourth changed behaviour.

- **Gap 1** — §1.2's canonical declaration example omitted `hostAPI`. Amendment 1.
- **Gap 3** — `warnings` existed only on `Page<T>`, leaving criterion 3 untestable for three of
  five result types. Amendment 2 states what S2 already built: every validated result carries
  warnings. **This was the consequential one.**
- **Gap 2** — `hostAPI` version strings had no grammar. Amendment 3 states S1's strict rule, which
  was **read out of `HostAPIVersion` rather than taken from #139's PR body**.
- **Gap 4** — **ADR-0024**, `docs/adr/0024-a-bad-cover-costs-the-cover-not-the-feed.md`. §10
  rejected the whole operation on a policy-invalid cover while dropping a malformed one with a
  warning, so one `http://` cover erased an otherwise usable feed. A policy-invalid **optional
  cover** now drops the field with the new `policy_invalid_url` warning code. **Unchanged:** page
  URLs, browser URLs and network request URLs still reject the operation.

Amendments are numbered in document order, not in the order the gaps were resolved.

### 4. Issue #134 — closed. Read this before trusting a UI test again

**Closed 2026-09-04 by #146 (part 1) and #148 (part 2).** Nothing is owed. It is kept here at
length because it changed how this repository treats its UI tests, and that is not obvious from
the diff.

**#134 had three causes, not the one its own text guessed at.** Credentials and live data were
both wrong.

**Cause 1 — stale matchers (#146).** Three sites matched `label CONTAINS "CH·"`. No such element
has existed since `1b31432` (#103), which made the whole chapter row one accessibility element
labelled `"Chapter 124, Title, September 1 2026, Unread"` — deliberately, since a middle dot is
not a word VoiceOver can announce. `CH·` is still *drawn*; XCUITest matches the label. All three
go through one `chapterRow(number:)` helper now.

**Cause 2 — the live catalog moved (#148).** `testADR0018Decision1ResumeFromHistoryKeepsTheId`
read **Junjou Romantica** purely to displace Berserk from the top of history. WeebCentral stopped
carrying chapters for it: the series page is alive (52 KB, correct `<title>`) with **zero**
`/chapters/` links, and `/full-chapter-list` returns the same 427-byte stub a *nonexistent* id
returns. The same code path returns 556 chapters for Wind Breaker, so this was never scraping rot
and never the app. The test's own comment recorded the diligence — *"Junjou Romantica was checked
against `/chapter` with `translatedLanguage[]=en` before being used"* — true when written, false
now, with nothing able to notice.

The leg no longer names a title. `displaceUsingAnyLibraryTitle` walks the library grid and takes
the first card that yields a readable chapter, skipping the subject and any title whose source
carries none. **Repointing at Wind Breaker was rejected** — it resets the clock until the next
licensor pulls one.

**Cause 3 — found while fixing the other two, and the most instructive.** Two tests in the
*hermetic* suite were also red: `testTheBrowseSourceListSaysWhichSourceIsActive` and
`testChoosingAPreferredSourceMovesTheSelection`, both naming `browseSource.MangaDex` /
`preferredSource.MangaDex`. That is true of the production registry and **never** of the fixture
they launch with, which registers `Update Fixture` alone. They passed only while `SettingsView`
still reached for `SourceRegistry.shared` behind the injected registry's back. **Removing that
singleton (#130/#131) made Settings honest and broke them** — the registry-injection refactor's
one unnoticed casualty, three days old. They match by identifier namespace now.

**The standing decision, implemented in #148:** the UI target is split into a live half and a
hermetic half, and only the hermetic half is a merge condition.

- **`UpdatesUITests` and `SourcePreferenceUITests` now run on every PR** — a new `ui-tests` job in
  `.github/workflows/ci.yml`. They launch with `-uitest-updates-state`, which swaps in a fixture
  registry and isolated storage, so they make no network request. **8m3s on CI's runner.**
- **Everything in `MangaCartaUITests.swift` stays out of the must-be-green set**, and that file's
  header now says why: those tests go red two ways — a real regression, and a catalog that moved —
  and **a gate that cannot tell those apart teaches people to ignore it.** They are a local,
  run-by-name gate.
- **Moving a test between the two halves is a claim.** Into the hermetic set: that it makes no
  network request. Out of it: that it cannot be written without live data.

The lesson worth carrying past #134: **do not name live data in a test that does not measure it.**
Both cause 2 and cause 3 are the same mistake against different fixtures.

### 5. Live-verify MAL progress push — the user's to run

Built, wired, tested (`MALProgressCoordinator`, `MALProgressOutbox`, the Settings toggle and queue
status). What no unit test can show: **sign in on a device, read a chapter to the end, and confirm
the number moves on myanimelist.net.** `scripts/mal_live_write.py` pokes the API directly if the
in-app path needs isolating.

`testLiveHorimiyaCompletionPushesProgress` is gated behind `TEST_RUNNER_MAL_LIVE_WRITE=1` and
skips by default — so it is **not** among #134's failures, and never was.

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
**Neither is closed:** a trait being present is not VoiceOver speaking it.

Close #90 when every row has a verdict, **not** when every defect is fixed.

Items 5 and 6 both want a device in hand; doing them in one sitting is worth more than doing them
well apart.

### 7. Naming debt, small and deliberate

`-uitest-updates-state` seeds a fixture that has nothing to do with updates (`two-listings`). One
seeding path with isolated storage was judged worth more than a tidier spelling; rename it if a
third unrelated state appears.

## Launch blockers that are not features

- **No app icon.** `AppIcon.appiconset/` holds only `Contents.json`. Being outsourced — **order it
  early so it is not the long pole.** Unchanged across seven handoffs now. This is the one blocker
  that cannot be compressed by working harder later. It needs the *MangaCarta* name on it.
- **The MAL privacy-label recheck — now #149**, so it stops riding along in handoffs that get
  archived. `PrivacyInfo.xcprivacy` shipped (#128) with one boundary deliberately unresolved:
  optional MAL sync sends completed-reading progress to the reader's own authenticated account.
  #128 treats that as user-authorized account functionality rather than collection by this app,
  but says outright it should be rechecked against Apple's broader definition.
- **Adult-source gating** — settled by ADR-0022. Not a blocker, just a thing not to undo.
- No listing screenshots, privacy-policy URL, App Store description, or TestFlight run.
- **The name — first pass done, now #150.** No App Store app is named MangaCarta (the iTunes
  Search API fuzzy-matches on "manga" and returns ~46 others; the exact name is absent), and no
  trademark surfaced. **The one thing worth a second look:** "Magna Carta" *is* live in software —
  Magna Carta Technologies LLC holds an AR-software registration and ships `Magna Carta AR` — and
  an examiner weighs similarity of appearance and sound. A musician also uses MangaCarta on
  Spotify/SoundCloud/TikTok; different class, so not a bar, but they own the search results. This
  was public web and API searching, **not a clearance search**; `tmsearch.uspto.gov` has no open
  API endpoint.

## Dispatch mechanics

```sh
orca orchestration run-create --from <coordinator handle> --objective "<objective>" --json
orca orchestration task-create --from <coordinator handle> --spec "<full brief>" --json
orca orchestration worker-start --from <coordinator handle> --task <id> \
  --worktree id:<repo-id>::<path> --agent <codex|claude> --model <id> --effort high --json
orca orchestration check --terminal <coordinator handle> --types worker_done,escalation,question --json
orca orchestration reply --id <msg_id> --from <coordinator handle> --run <run_id> --body "<answer>"
orca orchestration send --from <handle> --run <run_id> --to dispatch:<ctx_id> --subject "..." --body "..."
orca worktree rm --worktree path:<abs path> --json
```

Each of these cost real time when it was learned.

- Selectors need an `id:` prefix — `--repo id:<uuid>`, `--worktree id:<repo-id>::<path>`. The error
  names neither the flag nor the fix. `orca worktree rm` also accepts `path:<abs path>`.
- **`--from <coordinator handle>` is needed from the very first command.** Outside a live Orca
  terminal, `run-create` itself fails `no_active_sender_terminal`; later `worker-start`s fail
  `consumer_fenced`. Get the handle from `orca terminal list --json`.
- **Flag spellings differ per subcommand.** `worker-stop`/`worker-read`/`worker-abandon` take
  `--dispatch` and **reject** `--from`; `task-update` takes `--id`, not `--task`; `check` takes
  `--terminal`, not `--from`; **`run-show` takes `--id` and rejects `--terminal`.**
- **Split every parallel wave across providers.** Wave 1 lost both Claude workers to a session
  limit while they reported `live`; Wave 2 lost its Codex worker to a 5-hour usage limit. **Both
  providers have now stalled a wave**, in different ways, and both stalls were silent.
- **Default `--model` to something cheap; make Opus high earn its place.** **Fable is not available
  on this account** — a worker dispatched on `claude-fable-5-1` parks at an unconfirmed launch
  prompt instead of failing.
- **A launched worker may sit at a confirmation prompt without ever starting**, reporting `ready`
  and `live` with only the seed message in its transcript.
- **A worker can also block on its own question** and report `live` forever. See item 2.
- **`--setup skip` is rejected when the worktree already exists.** It applies only to worktrees
  `worker-start` creates itself.
- **Changing a worker's model means abandon, not stop.** `worker-abandon --dispatch <id>` →
  `task-update --from <coordinator> --id <task> --status ready` → a fresh `worker-start`.
- If the Orca runtime restarts, every command needs `--terminal <coordinator handle>`.
- `check --wait` ending in `runtime_unavailable` is the app restarting, not a worker failure.
- **Start every independent worker before the first wait**, or the work serializes.
- **A `worker_done` is not a merge**, and it is not a green suite either.
- **A worker's green run can go red when the next slice merges.** Re-run after every rebase.

## Gotchas

Re-verify any that becomes load-bearing rather than trusting this list.

- **A passing test is not evidence until you have seen it fail.** Applied twice today: the ADR-0024
  test was confirmed red against the old throwing branch, and the `CH·` fix was confirmed by a
  previously-failing test flipping green.
- **Never run two `xcodebuild` invocations against the simulator at once.** A second one produces
  `Executed 0 tests` plus a named failing test and a `DebuggerLLDB.DebuggerVersionStore.StoreError`
  — which looks exactly like a real failure and is not. This cost a full 20-minute run today.
- **Do not pipe an `xcodebuild` run through `tail`.** The failure list is what you need and it is
  what `tail` throws away. Redirect the whole log to a file. This also cost a full run today.
- **`app.debugDescription` in an assertion message is how UI-test failures become diagnosable.**
  It is what separated #134's two causes. #146 adds one to `readFirstChapter`.
- **Squash merges make the commit graph lie about what is merged.** The PR state is the only
  reliable check.
- **File:line citations rot within one session.** Cite living documents by *term or section*.
- **Changing an accessibility label silently breaks XCUITests.** They match the *label*, not the
  drawn text. **This is no longer hypothetical: it is #134 cause 1, and it went unnoticed for two
  weeks.** CI now runs the two hermetic suites (#148), so this class of break turns something red
  on a PR at last — but only for what those two cover.
- **A test that names live data will eventually fail for a reason that is not a defect.** #134
  causes 2 and 3, against a live catalog and against a fixture registry respectively. Ask what the
  test *measures*; anything else it names should come from whatever is actually there.
- **Removing a singleton can break tests that were passing for the wrong reason.** The
  registry-injection refactor (#130/#131) made two Settings tests honest and red at the same
  moment, and nothing noticed for three days because CI ran no UI suite.
- **`curl` cannot reproduce the app's WeebCentral browse or search paths.** The site is
  HTMX-rendered and behind Cloudflare; a search URL returns only the page shell. The
  `/series/{id}/full-chapter-list` partial *is* fetchable directly, which is what made #134's cause
  2 provable — get real ids from the simulator's `works.json`, not by guessing.
- **A bare accessibility query can match the wrong list.** Settings has two lists of source names;
  rows are namespaced `browseSource.` and `preferredSource.`.
- **CI is a major version behind local** — `macos-15` → Xcode 16.4 / Swift 6.0 vs local 26.x / 6.2.
  Treat isolated conformances, `nonisolated(nonsending)`, `@concurrent` and `Task.immediate` as
  unavailable. S4 was the slice most at risk and stayed clear of all of them.
- **CI's SwiftLint is not this machine's either.**
- **`AppComposition.init` sits right at SwiftLint's body-length limit.** Extract rather than inline.
- **A wedged simulator looks exactly like a failing suite.** `** TEST FAILED **` with no failing
  test named is `Application failed preflight checks` / `Busy`. `xcrun simctl boot "iPhone 17 Pro"`
  and re-run. **Do not erase the device** — it holds the seeded fixture, and erasing has already
  destroyed `works.json` once.
- **The simulator's `works.json` is a usable source of truth for real source ids.** It lives under
  `.../Devices/<UDID>/data/Containers/Data/Application/<app>/Library/Application Support/`, **not**
  `Documents/`. Bundle id is `Elias-Magdaleno.Manga-Reader` — deliberately not renamed with the app.
- **`project.pbxproj` churns under you** whenever Xcode has the project open. Check
  `git diff --stat` immediately before `git add`.
- **`Secrets.xcconfig` is gitignored**, so a fresh worktree fails to build with "Unable to open base
  configuration reference file" until you copy it in. This is not a broken branch.
- **`TEST_RUNNER_`-prefixed shell variables reach the hosted unit bundle**, not just UI tests.
- **Recorded so nobody retries them** (from the S3 spike): a `WKURLSchemeHandler` response reaches
  the navigation-response delegate downgraded to a bare `NSURLResponse` with **every header
  stripped**, and `loadSimulatedRequest` does not run the response-policy step at all.
- **Branch protection does not stop this account** — `enforce_admins: false`. Ask first.
- **Do not stack PRs** — a child closes unrecoverably when its base is deleted.
- **A full CI run takes ~12 minutes.** `gh pr merge --auto` beats waiting.
- **Target the iPhone 17 Pro simulator** on every `xcodebuild` — it holds the seeded fixture.
- **Test totals come from the result bundle, not the log tail.**
  `xcrun xcresulttool get test-results summary --path <bundle>`.

## Repository state

- `main` at `90f15e5`. PRs #144, #145, #146 and #148 all merged today.
- `gh issue list`: **#90** (VoiceOver, ready-for-human), **#149** (MAL privacy-label recheck) and
  **#150** (name clearance). **#134 is closed.**
- Unit suite `MangaCartaTests`: **942 tests, 937 passed, 0 failed, 5 skipped.** Hermetic UI suites:
  **11 of 11 green**, locally and on CI. The live suites in `MangaCartaUITests.swift` are no longer
  a merge condition and were not swept — the leg-C test was run by name and passes. SwiftLint clean.
- **CI now has three jobs**, not two: SwiftLint, `Build & unit tests`, `Hermetic UI tests`.
- Orca worktrees under `~/orca/workspaces/Manga-Reader/`: **`phase3-s5-host-capabilities` holds
  live uncommitted work — do not touch it.** `phase3-s4-jsc-runtime` is merged and removable.
  `phase3-s1-manifest` and `phase3-s3-webkit-spike` were removed today.
  `Manga-Reader-worktree-helper` at the repo root is unrelated, from 2026-08-21, and was left alone.
- `docs/superpowers/handoff/` holds this file and `archive/` (76 archived handoffs plus its
  README). Two `.md` files at this level means someone skipped the rule.
