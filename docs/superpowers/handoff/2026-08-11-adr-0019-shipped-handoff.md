# Session Handoff — 2026-08-11 (evening): ADR-0019 shipped, the bridge is live and scoped

**Audience:** the next session. Supersedes `2026-08-11-adr-0018-verified-bridge-cost-measured-handoff.md`,
whose pickup list is drained: its sole item — "decide ADR-0019" — is decided, built, and merged.

**The one thing with a deadline is in "What to do first". Everything else can wait.**

## State

| | |
|---|---|
| `main` | **`bd317a5`** — "Bridge MAL resolution for sources that publish no external ids (ADR-0019) (#45)", clean |
| Open PRs | **none** |
| ADRs | 0001–0015 Accepted (0015 amended 7 & 8), **0016 Rejected + forward-pointer to 0019**, 0017 Accepted + verified, 0018 Accepted + amended + verified in-app, **0019 Accepted, acceptance evidence pending** |
| Tests | **468**, 1 skipped, 0 failures (was 452) |
| Branch `mangadex-alt-titles` | **consumed.** Rebased into #45; the remote branch can be deleted |

## What shipped — ADR-0019 (#45)

`docs/adr/0019-bridging-resolution-for-sources-that-publish-no-external-ids.md`.

The MangaDex bridge is live for sources that publish no external ids. Four commits: the three
original `mangadex-alt-titles` commits rebased, then Round B's cut, then the scope gates, then the
ADR. The build→reject→revive arc is deliberately visible in history.

**Why it shipped, and this is the part not to garble:** ADR-0016 pre-registered its own reopening
condition — *refusals that are threshold misses rather than ambiguity ties*. The WeebCentral
measurement found **15 of 16 refusals are exactly that**. The clause fired. The cost gates passing
only removed a blocker; they were never the argument. **The diagnosis is the reverse of 0016's** —
on MangaDex the refusals were novel-twin ambiguity ties (ADR-0017's filter still dominates there);
on WeebCentral they are reach failures. Same mechanism, different source, opposite reason.

| | |
|---|---|
| Recovered | **5 of 16 — 5 correct, 0 wrong** |
| Library effect | 64-title WeebCentral library **47 → 52** resolved |
| Cost as scoped | **1.00 req/refusal**, 3.2 per recovered id, 0.41 per library title |
| Unreachable | 11 of 16, under any version |

### The four decisions, in one line each

1. **Ship it, Round A only.** Qualifies ADR-0008's single-route rule: MAL is still the only catalog
   *searched for an answer*; MangaDex is asked for an id it already holds.
2. **Gate on the Work, not a source allowlist** — `isBridgeable` excludes Works MangaDex already
   serves, because `links.mal`'s absence on an entry the app already fetched is an *answer*, not a
   gap. Composes with ADR-0018 rather than duplicating it; a new source needs no registration.
   Mirrored on the Listing path, which has no Work and keys on `sourceId`.
3. **Round B (0016's Decision 6) dropped** — 4 firings, 38% of requests, zero recoveries. **Lack of
   evidence, not refutation.** It was tested on the one source that publishes no alt titles, so the
   harvest it feeds was thin by construction. Revisit on a source that does.
4. **The harvest stays.** Zero requests, and growing `knownTitles` is what reopens an `.unmatched`
   fingerprint later. `testBridgeHarvestsSpellingsWithoutReSearchingMAL` pins both halves in
   opposite directions — restoring the re-search fails one assertion, pruning the harvest fails
   another. **They read as one feature and are not.**

## What to do first

**Decide what ADR-0019's Decision 6 can honestly be, then run it — before ~2026-08-23.**

Decision 6 registered, before the fact and unadjustably, that **5 of 16 refusals recover, all
correct**, to be verified in-app on the seeded sim. **That evidence cannot be produced by the
current fixture, and this was spotted after the ADR was written, not before:**

- The sim's 3 surviving refusals are the **invented placeholder titles** — unresolvable by
  construction, which is exactly why they were chosen as controls.
- `Wind Breaker`, the one real refusal, was **consumed by the previous session's ADR-0018 run**,
  correctly.
- The 16-refusal cohort is **not reproducible** — WeebCentral's popularity ordering shifts daily, so
  re-deriving it by offset draws different titles.

So the realistic in-app run verifies **that the mechanism fires and recovers correct ids**, not the
5-of-16 rate — which stays an offline claim. **Amend Decision 6 to say that plainly, in writing,
before the run**, the same discipline that governed the thresholds and the prediction. Silently
running a weaker check against a stronger registered claim is the failure mode this whole ADR chain
exists to prevent.

Doing this needs a **real WeebCentral library seeded on the sim**. That same seeding is what
**ADR-0018's Decision 1 in-app leg** has been blocked on for two sessions — no refused Work on the
current sim is re-readable. **Do them as one piece of work.**

Deadline is the seeded sim's 14-day TTL, ~**2026-08-23**. After that the fixture is gone and
everything above needs re-seeding anyway.

## Also open, unchanged

- **More Like This reverse resolution beyond MangaDex-only.** More Works are resolvable now; reverse
  resolution is what turns a resolved Work back into something openable.
- No automated coverage of `HomeView`'s rail branch or `MangaDetailView`'s notice branch — still
  deliberate, reasoning in `AppCompositionTests`' header.
- **Standing constraint:** the extension/repo system and comix.to shelved since 2026-07-21.
- `origin/mangadex-alt-titles` is now redundant and can be deleted.

## Method worth reusing

- **A rejected ADR's reopening clause is a real instrument, and it only works if you honor it.**
  0016 wrote a falsifiable condition on a source it had not measured; the condition came true a day
  later. Declining then would have made the clause decoration. Write these clauses, and check them.
- **`git merge-tree` reporting no conflicts is not proof of a clean rebase.** It reported zero. The
  real rebase produced three. Do the trial merge.
- **A textual merge can hide a semantic one.** `testAProseTwinIsWhatRefusesTheWorkNotTheThreshold`
  merged cleanly and did not compile: it called `malId(for: Work)`, which the branch renames to
  `resolve(_:)`. Worse, once repaired it needed `noBridge` injected or an ADR-0017 *unit* test would
  have hit the live network — because a Work-level miss now falls through to a bridge whose default
  is live. **Check what a rebased branch changed about the API the merged-in tests call.**
- **Assert on the request, not the result, when both configurations return the same result.** Both
  gate tests return nil either way; only `bridgeSearch` going uncalled distinguishes "declined to
  ask" from "asked and found nothing". Each carries a control that *does* bridge, so a gate that
  never fired would fail.
- **Cut a feature at its seam, not at its name.** "Drop Round B" would have taken the harvest with
  it — free, and the part that pays for itself. Naming the two halves separately, and pinning them
  with one inverted test, is what kept it.
- **Separate the record from the revival.** 0016 keeps its rejection and its lesson; 0019 is a new
  file. Per `docs/agents/domain.md`, that is what a revival looks like here.

## Gotchas

- `gh pr view --json statusCheckRollup` — the two known failure modes still stand (`conclusion: ""`
  while running; empty output on a transient TLS failure reading as a false green). This session
  keyed on `.status` **and** required non-empty output, and got a legitimate green.
- **`gh pr merge --delete-branch` fails to delete a local branch checked out in a worktree.** The
  merge itself succeeds; only the cleanup errors. `git worktree remove --force` then `git branch -D`.
- `project.pbxproj` did not churn this session — no new compiled files; the ADR is a doc and both
  tests went into `Manga_ReaderTests.swift`.
- SourceKit reports `No such module 'XCTest'` and missing types for files edited inside a git
  worktree. **Spurious** — the worktree is outside Xcode's index. `xcodebuild` in the worktree is
  the real signal.
- Copy `Secrets.xcconfig` into a worktree before building there, and delete it before committing.
- `api.mangadex.org` still rejects Python's `urllib` TLS; shell out to `curl`. Still true.
