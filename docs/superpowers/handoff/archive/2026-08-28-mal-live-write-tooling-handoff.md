# MAL live-write tooling landed; issue #93 needs one human run

Date: 2026-08-28
Repository: `/Users/eliasmagdaleno/Manga-Reader`
Issues: GitHub #93 (open), #90 (parked)
Branch: `main` at `b7e2bc9`

## Resume here

Fire the live MAL write and record the result, which is all that keeps **#93** open.
From the **main checkout** (not a worktree — see Gotchas):

```sh
scripts/mal_oauth_token.py       # opens MAL, click Allow, paste the redirect back
export MAL_ACCESS_TOKEN=...      # the line it prints
scripts/mal_live_write.py fire   # snapshot -> run the test -> restore
```

Needs the iPhone 17 Pro simulator free, and deliberate approval: it writes to a real
MyAnimeList account. Then comment the outcome on #93 and close it.

**This run is also the first real exercise of both scripts.** Their network legs — MAL's
authorize page, the token exchange, and the GET/PATCH/DELETE against the list — were never
executed, because doing so requires the real account. If something is wrong, that is where
it surfaces: a 400 at token exchange, or a 401 from the harness.

## What this session did

Three PRs, all merged, all chosen specifically to avoid the ADR-0021 work in flight:

| PR | Commit | What |
|---|---|---|
| #96 | `5c3290b` | `scripts/mal_live_write.py` — read-before/restore-after harness |
| #97 | `8368c18` | ADR-0010 Amendment 1 — a cited file no longer exists |
| #98 | `b7e2bc9` | `scripts/mal_oauth_token.py` — mints the token #96 needs |
| #100 | open | ADR-0011 note — its new provider shipped under a different name |

### The harness (#96)

`snapshot` records the title's `my_list_status` into `.mal-live-write/` (gitignored);
`restore` PATCHes all ten writable fields back, or DELETEs the entry if none existed before;
`fire` does snapshot → test → restore **and restores even when the test fails**, which is the
whole point — a UI run that dies halfway is exactly what strands the account at chapter 124.
"No entry existed" is recorded separately from the entry's values, so restore deletes rather
than writing zeroes.

### The OAuth helper (#98)

The app's token lives in the simulator keychain, unreachable from a shell, so this runs the
flow by hand. MAL supports only PKCE `plain` (already recorded at `MALOAuth.swift:14`), which
makes the verifier the entire binding between request and redirect — so the returned `state`
is checked before anything is exchanged. The token is printed, never written to disk.

### The docs-rot pass (#97)

Checked every backticked file path and identifier in `docs/adr/`, `docs/glossary.md`,
`docs/agents/`, and `CLAUDE.md` against the tree. **One real finding:** ADR-0010 cited
`MyAnimeListDebugView.swift:138` twice in the present tense as the live counter-example
motivating its decision, but that file was deleted in `342514a` (#27). Citations moved to past
tense; Amendment 1 records the deletion. The decision is unaffected.

Re-verified as still accurate, so nobody need re-check: 60s idle interval and the
three-consecutive-failure breaker (`MetadataUpgradeQueue.swift:63,317`), the 14-day
attempt-memory TTL (`UpgradeAttemptMemory.swift:46`), AniList's measured 30/min
(`AniListRateLimiter.swift:6`).

### The ADR voice audit (#100)

Separated *proposal voice* from *fact voice* across ADRs 0011–0014 — the follow-up #97's grep
could not do. Two kinds of missing identifier are harmless: a name proposed and then implemented
differently is history, and a name in a Context section describes the world before the change.

**One fact-voice miss.** ADR-0011 names `AniListTagCandidateProvider`; it shipped as
`AniListCandidateProvider` (`AniListCandidateProvider.swift:26`). Everything else that sentence
claims is true of the code — third provider, `ani` slot of `CompositeCandidateProvider`
(`CandidateProvider.swift:192`, wired at `AppComposition.swift:243-251`), shared limiter — so #100
appends a note rather than revising the decision. It matters because ADR-0011 is Accepted and not
superseded, so it reads as current architecture.

**The other three are clean.** 0012 and 0013 carry `amended by ADR-0013` / `amended by ADR-0014`
headers, framing their Context sections correctly; 0014's misses are in `Beat:` (rejected
alternative) passages and struck text; several names were never ours (`ScrollPosition.scrollTo`,
`onGeometryChange`, `TaskGroup`, `ModelActor`); and `reverseResolveViaSearch` was already
discharged by ADR-0011's own 2026-08-04 amendment.

**Conclusion:** ADRs 0011–0014 are trustworthy as current references, with the one exception fixed.
Nothing further is owed there — don't re-run this audit.

## Gotchas

- **`Secrets.xcconfig` is gitignored, so it exists only in the main checkout.** A worktree has
  no copy, and `mal_oauth_token.py` cannot find the client id there. Run it from the main
  checkout or pass `MAL_CLIENT_ID=...`.
- **`gh pr merge --delete-branch` fails here while another worktree holds `main`.** It prints
  `fatal: 'main' is already used by worktree at ...`. **The merge itself succeeds** — only the
  local cleanup fails, and it looks like a failed merge. Merge without the flag and delete the
  branch separately.
- The live test's env var must be a **shell** variable with the `TEST_RUNNER_` prefix, which
  `xcodebuild` strips; passing it as a build-setting argument silently does nothing. `fire`
  already does this correctly. Measured in #93 — don't re-derive it.

## Not done, and why

- **#90 (VoiceOver traversal)** — parked deliberately. It touches the same target as the
  in-flight ADR-0021 work. Start it once #92 lands, with the `ios-accessibility` skill.
- **ADR voice audit** — *done*, in #100. See below.
- **CLAUDE.md's "Current state"** still says refresh is manual and "nothing polls for new
  chapters." ADR-0021 invalidates that; the line belongs to whoever lands #92.

## State of the tree

At the time of writing, the main checkout is on `main` at `a97d0b8` — **four commits behind
origin** — and carries the uncommitted ADR-0021 (#92) implementation, Tasks 1–7 done and Task 8
(seeded-simulator UI verification) next per
`docs/superpowers/handoff/archive/2026-08-28-adr-0021-task-8-next-handoff.md`. Nothing this session
touched `Manga-Reader/` source, so merging `main` in should be clean: two scripts, a
`.gitignore` line, an ADR, and a comment-only edit to `Manga_ReaderUITests.swift`.
