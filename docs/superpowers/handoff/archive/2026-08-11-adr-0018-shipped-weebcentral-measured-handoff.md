# Session Handoff — 2026-08-11: ADR-0018 shipped, WeebCentral measured, ADR-0016's trigger fired

**Audience:** the next session. Supersedes `2026-08-10-basis-line-and-adr-0017-verified-handoff.md`,
whose pickup list is drained: item 1 (merge PR #38) merged as `8a37687`, item 2 (`malId` on
`LibraryItem`) shipped as ADR-0018 — **but not where that handoff said to put it**, see below.

## State

| | |
|---|---|
| `main` | **`ac011a0`** — "Measure whether WeebCentral is resolvable at all (#40)", clean |
| Open PRs | **none** |
| ADRs | 0001–0015 Accepted (0015 amended 7 & 8), 0016 Rejected, 0017 Accepted + verified, **0018 Accepted** |
| Tests | **450**, 1 skipped, 0 failures |
| Branch `mangadex-alt-titles` | still on `origin` (`19a6ecd`), still unmerged — **but newly relevant**, see below |

Merged this session: **#38** (basis line, was already open), **#39** (ADR-0018), **#40** (measurement doc).

## What shipped

### ADR-0018 — an authoritative external id is not a resolution question (#39)

MangaDex returns `links.mal` in the `/manga` response the app **already fetches**. The whole chain
to consume it existed end to end — `MangaDexAPI:109` decodes it, `WorkStore.mint:114` absorbs it,
`MALEntityResolver:59` short-circuits on it — except `ReadingEntry` had no field, so
`resolveSignals()` rebuilt every listing with `malId: nil` and the queue recovered the id by fuzzy
search. **We were running a fuzzy match to recover an id the API handed us.**

Two consequences of one decision:

1. **`ReadingEntry.malId`** — defaulted `var`, populated at the single write site
   (`HistoryStore:145`), passed through `resolveSignals()`. New reads only; no backfill.
2. **`suppresses()` guard** — a Work carrying a `mal` id is no longer suppressed by an
   `.unmatched` refusal. That fingerprint is the title count, and learning an id adds no title, so
   a re-read previously left the Work refused for the rest of its 14-day TTL *while holding the
   right answer*.

**The prior handoff said to put `malId` on `LibraryItem`. That was wrong** — `LibraryItem` never
reaches `resolveSignals()`, because saved-but-unread items are deliberately excluded from the
profile. It went on `ReadingEntry`, which is the path that was actually measured as broken.

**Watch this:** consequence 2 also feeds `tagBlocked` (`AppComposition:114`), so ADR-0015's
"cannot be matched" notice stops appearing for such a Work and it rejoins the taste profile. That
is intended and documented, but it lands in the branch with no automated coverage.

**Not verified in the app.** Recorded as Hazard 3 in the ADR deliberately. Accepted on a traced
call chain and five unit tests, each red before its fix.

### The WeebCentral measurement (#40)

`docs/superpowers/specs/2026-08-11-weebcentral-resolvability-measurement.md`, harness at
`scripts/wc_resolve.py`.

**WeebCentral is resolvable: 47 of 64 real titles, 47 correct, 0 wrong.** So ADR-0015's
`noTaggableSignal` on the seeded library was an artifact of the three placeholders having invented
titles — the open question from the last two handoffs is now closed.

## The finding that matters most, and is NOT acted on

**15 of the 16 refusals are threshold misses (top < 0.90), not ambiguity ties.** Only `Xia Ke Xing`
tied. That is **ADR-0016's revisit trigger, verbatim**, as quoted in ADR-0017:

> Refusals persist with a top MAL candidate scoring below 0.90 rather than tying — that is a reach
> failure, not a collision, and it is the evidence ADR-0016 needed and never had. Reopen it.

MangaDex holds a **verified-correct** id for 5 of the 16.

**Why this does not contradict the two observations that rejected ADR-0016:** both were made on
*MangaDex-sourced* titles, which carry `links.mal` already and never needed a bridge. ADR-0016 was
measured on the one source for which it is structurally unnecessary. These measured different
things.

**Do not un-reject ADR-0016.** The record of why it was rejected on MangaDex evidence is worth
keeping. A revival is a new ADR (0019) that supersedes it.

**And 0019 is not writable yet.** The blocker is named in the doc: **cost is unmeasured.** ADR-0016
was rejected partly on 2–5 extra requests per refusal, and this measured recoverability only.
Writing the revival on half the ledger repeats ADR-0016's original mistake — it was built before it
was measured.

## What to do first

1. **The cost measurement.** Bounded: run the 16 refusals (listed in the measurement doc) through
   the bridge path and count requests per recovery. `scripts/wc_resolve.py` already has the titles,
   the matcher, and working MangaDex/MAL calls. That produces the other half of the ledger and
   makes ADR-0019 writable either way it comes out.
2. Then decide on ADR-0019, with `mangadex-alt-titles` as the pre-built implementation.

## Also open, unchanged

- In-app verification of ADR-0018. The seeded sim (`iPhone 17`, `2A0D54DF-…`) still holds the
  history and still holds a Work refused on `Wind Breaker` — which is the `.unmatched` tie the new
  guard must *not* touch, so it is a ready-made fixture for both sides of the change.
- More Like This reverse-resolution beyond MangaDex-only.
- No automated coverage of `HomeView`'s rail branch or `MangaDetailView`'s notice branch — still
  deliberate, reasoning in `AppCompositionTests`' header.
- **Standing constraint:** the extension/repo system and comix.to shelved since 2026-07-21.

## Method worth reusing

- **Validate a ported matcher against results the app itself produced, before trusting a number
  from it.** The Python port was checked against four ADR-0017 in-app results — including
  reproducing Wind Breaker's refusal at its exact 1.00/1.00 tie — and only then used. A harness
  that reproduces the app's *refusals* is worth more than one that reproduces its successes.
- **Machine-pick the sample.** Hazard 2 (hand-picked titles skewed toward the effect) has recurred
  in every prior measurement. Two cohorts from WeebCentral's own sort, no human selection. The deep
  slice then resolved *better* than the popular page — the opposite of the prediction, which is
  exactly the kind of result hand-picking would have hidden.
- **Never report a recovery count without a correctness check behind it.** 37 ids checked against
  MangaDex `links.mal`, the other 10 by hand.
- `curl` reaches `weebcentral.com/search/data` with the pinned UA — no WebView, no Cloudflare
  challenge, on this date. It returns 32 rows per page regardless of `limit`.
- `api.mangadex.org` still rejects Python's `urllib` TLS; shell out to `curl`. Still true.

## Gotchas

- **`gh pr view --json statusCheckRollup` returns `conclusion` as an empty string, not `null`,
  while a job runs.** A `.conclusion // "PENDING"` jq guard therefore does **not** fire, and a
  wait-loop exits early reporting success on a job that is still running. Key the loop on `.status`
  (`IN_PROGRESS`/`QUEUED`) instead. This produced a false "CI green" claim in this session.
- `project.pbxproj` churned once during an `xcodebuild` run with Xcode open and was reverted before
  staging. The CLAUDE.md warning earned again. No new files needed `pbxproj` edits this session —
  the ADR/doc/script are not compiled, and the tests went into existing files.
- Getting a **genuine** red matters: the engine test first failed as a *compile error*, which proves
  nothing. Adding the field first, then re-running, produced a real `XCTUnwrap` failure on the
  round-trip — that is the red worth having.
