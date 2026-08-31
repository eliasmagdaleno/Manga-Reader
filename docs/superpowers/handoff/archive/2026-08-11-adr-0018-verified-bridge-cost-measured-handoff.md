# Session Handoff — 2026-08-11 (afternoon): ADR-0018 verified, the bridge ledger is complete

**Audience:** the next session. Supersedes `2026-08-11-adr-0018-shipped-weebcentral-measured-handoff.md`,
whose pickup list is drained: item 1 (the cost measurement) is done, item 2 (decide ADR-0019) is now
**unblocked and is the whole of what's next**.

## State

| | |
|---|---|
| `main` | **`2c97569`** — "Tell the agent skills where this repo keeps its issues and its language (#43)", clean |
| Open PRs | **one** — the cost measurement branch, see below |
| ADRs | 0001–0015 Accepted (0015 amended 7 & 8), 0016 Rejected, 0017 Accepted + verified, **0018 Accepted + amended + verified in-app** |
| Tests | **452**, 1 skipped, 0 failures |
| Branch `mangadex-alt-titles` | still on `origin` (`19a6ecd`), unmerged, and now **fully measured on both axes** |

Merged this session: **#42** (ADR-0018 verification), **#43** (agent-skills config).

## What shipped

### ADR-0018 verified in the app — Hazard 3 closed for Decision 3 (#42)

`docs/superpowers/specs/2026-08-11-adr-0018-in-app-verification.md`.

On the seeded sim, a refused `Wind Breaker` Work acquired `mal: 133081` through an ordinary
`Add to Library`, and the next launch cleared its refusal and left it holding **28 AniList tags**.
The placeholder control was untouched. Full chain: guard releases → queue reconsiders → resolver
short-circuits → AniList fetch → `memory.forget`.

**Amendment 1 was written before the run**, stating the prediction, and it corrects two things the
prior handoff had wrong:

- **`Wind Breaker` is the positive fixture, not the negative control.** Its 1.00/1.00 tie is why it
  was refused and is irrelevant to whether an authoritative id ends the refusal. The negative
  control is a placeholder title.
- **The guard's trigger is the common case, not an edge one.** Every Work minted from history before
  Decision 1 came out id-less, so re-acquiring an id is ordinary. An earlier trace in this session
  concluded the guard was *unreachable*; that was wrong, and the record of why is in the amendment.

**Scope, stated because it is easy to over-read:** this verifies **Decision 3**. **Decision 1's
in-app leg is not verified** and cannot be on that sim — no refused Work there is re-readable
(`Wind Breaker` has no chapters on MangaDex; the other three refusals are invented titles).

**A real bug fell out of it.** `ReadingEntry.asManga` (`HistoryView.swift:140`) hardcoded
`malId: nil`, and that is the `Manga` the resume path hands to `HistoryStore.record`. So ADR-0018's
"the id arrives naturally as titles are read again" was false on the route a re-read actually takes.
Fixed, two tests. `BookmarksView.asManga` keeps its `nil` and is correct — `LibraryItem` has no id
to carry, per Scope — with a comment so it doesn't get "fixed".

### The bridge cost measurement — both gates pass (open PR)

`docs/superpowers/specs/2026-08-11-bridge-cost-measurement.md`, harness `scripts/bridge_cost.py`.

**Thresholds were committed in their own commit (`a1312aa`) before the run**, so they could not be
adjusted to fit the answer. Results in `a87421e`.

| Metric | Gate | Measured |
|---|---|---|
| Extra requests per recovered id | ≤ 10 | **5.2** |
| Extra requests per library title | ≤ 1.0 | **0.41** |
| Per refusal | reported | 1.62 |
| Recovered | | **5 of 16, 5 correct, 0 wrong** |

Round A cost exactly **1 request for all 16** — WeebCentral publishes no alt titles, so the
`min(knownTitles, 3)` fan-out never binds. **ADR-0016's assumed 2–5 per refusal was an overestimate
for this shape of Work.**

### Agent skills configured (#43)

`docs/agents/{issue-tracker,triage-labels,domain}.md` + an `## Agent skills` section in CLAUDE.md.
GitHub via `gh`; default triage labels (checked against the repo — `wontfix` already exists and
matches, the other four don't and have no differently-named equivalents); domain docs point at
`docs/glossary.md`, **not** `CONTEXT.md`. Installed `triage`, `to-spec`, `to-tickets`, `wait-what`,
`writing-for-agents`, `resolving-merge-conflicts` from `mattpocock/skills`.

## What to do first

**Decide ADR-0019.** The ledger is complete for the first time — recoverability *and* cost — and
`mangadex-alt-titles` is the pre-built implementation. What the numbers license, precisely:

- **Benefit:** 5 of 16 refusals recover, all correct. A 64-title WeebCentral library goes 47 → 52.
- **Cost:** 26 extra requests per pass, 0.41 per library title, ~10s of background wall-clock.
- **Unreachable:** 11 of 16, under any version of the proposal.

Passing the gates **removes the blocker; it is not an argument to write the ADR.** Three things the
ADR has to actually decide:

1. **Drop Round B?** It fired 4 times, spent **10 of the 26 requests (38%)**, and **recovered
   nothing**. Round A alone would be 1.00 requests per refusal and 3.2 per recovered id — cheaper
   and, on this evidence, no less effective. Four cases is thin evidence to kill ADR-0016's
   Decision 6 on, so it is a question, not a conclusion. Do not carry it over unexamined.
2. **Is 5-of-16 worth a second resolution path at all?** The honest framing: this buys five titles
   on a 64-title library and leaves eleven refused.
3. **Scope it to sources that publish no external ids.** MangaDex-sourced titles carry `links.mal`
   already (ADR-0018) and must not pay the toll.

**Do not un-reject ADR-0016.** A revival is ADR-0019 superseding it; the record of why it was
rejected on MangaDex evidence is the valuable part. This is now written into `docs/agents/domain.md`
as a standing rule.

## Also open, unchanged

- **Decision 1's in-app leg**, unit-tested only. Not verifiable on the current sim.
- More Like This reverse-resolution beyond MangaDex-only.
- No automated coverage of `HomeView`'s rail branch or `MangaDetailView`'s notice branch — still
  deliberate, reasoning in `AppCompositionTests`' header.
- **Standing constraint:** the extension/repo system and comix.to shelved since 2026-07-21.
- **Expiring fixture:** the seeded sim (`2A0D54DF-…`) still holds 3 refusals (the placeholders),
  ageing out of their 14-day TTL **~2026-08-23**. `Wind Breaker`'s is gone — this session's run
  consumed it, correctly.

## Method worth reusing

- **Commit the threshold before the measurement, in its own commit.** A threshold picked after
  seeing the number is not a threshold. `a1312aa` precedes `a87421e` in history, which is the whole
  point of splitting them.
- **Chase a discrepancy against known ground truth before believing your own harness.** The cost run
  first reported **4** recoveries where the resolvability measurement had established **5**. The
  cause was mine: the input list copied a title the earlier doc had *truncated with an ellipsis*.
  The short form scores far below threshold; the real one ties MangaDex at 1.000 and recovers in one
  request. Unchased, this would have understated the benefit by 20%. **A source title is an input,
  not prose.**
- **Enumerate the writers before declaring a code path dead.** "How does a refused Work ever get an
  id?" first traced to *it can't*. Listing the three writers of `externalIds` found the path — and
  it was the common case.
- **A compile error is not a red.** The `asManga` test first failed to build (`fileprivate`).
  Widening access and re-running produced `("nil") is not equal to ("Optional(133081)")`, which is
  the red worth having. Same lesson as the previous session, learned again.
- **Resolve a simulator's data container by `MCMMetadataIdentifier`, never by remembering the UUID.**
  It changed twice during this session as builds reinstalled the app. The data survived both times;
  a hardcoded path would not have.

## Gotchas

- **`gh pr view --json statusCheckRollup` again, a second failure mode.** The known one is
  `conclusion` returning `""` rather than `null` while a job runs. The new one: a transient
  `tls: failed to verify certificate` makes the query return **empty**, and a loop keyed on
  "no rows are IN_PROGRESS" reads empty as done and reports a false green. Key on `.status` **and**
  require non-empty output before deciding. This produced a premature green claim in this session,
  caught on re-run.
- `project.pbxproj` did not churn this session. No new files needed it — the docs and script are not
  compiled, and both tests went into existing files.
- The MAL client id lives in `Secrets.xcconfig` as `MAL_CLIENT_ID`; `scripts/bridge_cost.py` takes it
  as `argv[1]`. Pass it via a shell variable, never inline.
- `api.mangadex.org` still rejects Python's `urllib` TLS; shell out to `curl`. Still true.
- WeebCentral's popularity ordering **shifts day to day** — the offset-400 page no longer contains
  the titles the 2026-08-11 morning run drew from it. Re-deriving a cohort by offset will not
  reproduce the same sample.
