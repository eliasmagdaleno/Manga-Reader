# ADR-0019 — Bridging resolution for sources that publish no external ids

- **Status:** **Accepted (2026-08-11)**, pending the acceptance evidence registered in Decision 6
- **Amends:** [ADR-0016](0016-mangadex-as-a-resolution-bridge.md) — by **activating the reopening
  clause ADR-0016 wrote for itself**. It does **not** supersede or un-reject it: 0016 stays
  Rejected-for-MangaDex, and its rejection is the more valuable half of the record
- **Related:** [ADR-0017](0017-excluding-novels-from-mal-resolution-candidates.md) (the cheaper fix
  that dominates on MangaDex, and still does), [ADR-0018](0018-an-authoritative-external-id-is-not-a-resolution-question.md)
  (the authoritative-id rule this composes with rather than duplicates),
  [ADR-0008](0008-upgrade-queue-resolution-and-drain.md) (the single-route "resolution always goes
  through MyAnimeList" rule, which this genuinely qualifies),
  [ADR-0009](0009-upgrade-queue-construction.md) (`knownTitles` monotonicity, which the harvest feeds)

## Why now: a pre-registered condition fired

ADR-0016 was rejected on measurement, and it named the one thing that would reopen it:

> **If ADR-0017 ships and refusals persist with `.unmatched` outcomes whose top MAL candidate scored
> *below* 0.90 rather than tying**, that is a reach failure, and this ADR is the thing to reopen.

ADR-0017 shipped. The 2026-08-11 WeebCentral resolvability measurement (N=64) found **15 of 16
refusals are threshold misses, not ambiguity ties.** That is the clause, verbatim, firing.

This matters more than the cost numbers do. The gates passing only **removed a blocker** — it was
never an argument to write this ADR. The argument is that 0016 pre-registered a falsifiable
condition, on a source it had not measured, and the condition came true. Declining now would mean
the clause was decoration.

**Note the diagnosis is the reverse of 0016's, and that is the point.** On MangaDex the refusals
were ambiguity ties caused by novel twins, which is why a `media_type` filter beat a bridge for
free. On WeebCentral they are reach failures — spellings MAL's search cannot find. Same mechanism,
different source, different reason. 0016 was wrong about *why*; it was not wrong about *what the
mechanism does*.

## The evidence

Two measurements, both offline, both against live APIs, both with their thresholds committed
**before** the run (`a1312aa` precedes `a87421e` in history, deliberately):

| | |
|---|---|
| Refusals recovered | **5 of 16 — 5 correct, 0 wrong** |
| Library effect | 64-title WeebCentral library goes **47 → 52** resolved (73% → 81%) |
| Unreachable | **11 of 16**, under any version of this proposal |
| Extra requests per recovered id | **5.2** as measured (gate: ≤ 10); **3.2** as scoped below |
| Extra requests per library title | **0.41** (gate: ≤ 1.0) |
| Round A cost | exactly **1 request per refusal** — WeebCentral publishes no alt titles, so the `min(knownTitles, 3)` fan-out never binds |

**What a recovered id buys, in user-visible terms:** five titles stop showing
`UnmatchedTitleNotice` in More Like This and start contributing tags to the For You taste profile.
That is the number this decision should be judged on — "+5 rails on a 64-title library, 11 titles
still unmatchable" — not the request counts. If that framing does not justify a second resolution
path, passing the cost gates should not rescue it.

**Sample honesty.** One source, one cohort, one day. WeebCentral's popularity ordering shifts, so
re-deriving the cohort by offset will not reproduce it. `docs/superpowers/specs/2026-08-11-bridge-cost-measurement.md`
and the WeebCentral resolvability doc hold the method.

## Decisions

### 1. Ship the bridge, for sources that publish no external ids

MyAnimeList is asked first. When it produces no confident match, MangaDex is searched by title and
`links.mal` is taken off the entry that matches. This qualifies ADR-0008's single-route rule: MAL is
still the only catalog *searched for an answer*; MangaDex is asked for an id it already holds.

### 2. The gate is the **Work**, not the source

Run the bridge only when the Work has no authoritative external id, and is not one MangaDex already
serves.

The first half is free — ADR-0018 already returns an authoritative id at the top of `resolve`, so
such a Work never reaches the bridge. The second half is the real gate, and it excludes the
**circular** case: MangaDex publishes `links.mal` on the entry the app already fetched, so its
absence there is an *answer*, not a gap. Searching MangaDex for a title MangaDex handed us cannot
produce a link it declined to publish. It can only spend requests and, worse, match some other
series' entry.

**Phrased against the Work rather than against a registry of bridgeable sources on purpose.** A new
source needs no registration to benefit, and this composes with ADR-0018 instead of restating what
it knows. The rejected alternative — a source-level allowlist — differs in exactly one case, a
MangaDex title whose `links.mal` is simply absent, and gets it wrong: it would let that title pay
the toll for a question already answered.

Mirrored on the Listing-level path (ADR-0016 Decision 7), which has no Work and so keys on
`sourceId` directly. That path stays bridged at all because the 2026-08-08 device check established
the two resolvers are independent and can disagree; leaving one bridged and the other not would
widen a gap that has already cost a session.

### 3. Round A only — the re-search is not carried over

ADR-0016's Decision 6 re-searched MAL with the spellings harvested from a MangaDex entry that
carried no `links.mal`. Measured: it **fired 4 times, spent 10 of the pass's 26 requests (38%), and
recovered nothing.** Dropping it takes the bridge to **1.00 request per refusal and 3.2 per
recovered id** with no measured loss.

**This is lack of evidence, not refutation, and the distinction is load-bearing.** Four firings is a
sample of four. Round B's premise — that a harvested spelling is missing *evidence* rather than a
second guess at the same question — is still sound. It was tested on the one source where it could
not possibly help: WeebCentral publishes no alt titles, so the harvest was thin by construction.
**Revisit it on a source that does publish alt titles**, where the fan-out it feeds has something to
work with.

### 4. The harvest stays, and must not be cut with the re-search

When MangaDex identifies the right series but it carries no `links.mal`, the spellings are still
harvested and returned to the caller.

They cost **zero requests** — they are already in the response — and growing `knownTitles` is what
reopens an `.unmatched` fingerprint on a later pass. So a Work the bridge cannot resolve today still
ends the pass richer, and may resolve itself later without the bridge.

The harvest and the re-search read as one feature and are not. A characterization test
(`testBridgeHarvestsSpellingsWithoutReSearchingMAL`) pins both halves in opposite directions:
restoring the re-search fails one assertion, pruning the harvest fails another.

### 5. A bridge asserts only the **id**, never a Listing

Carried unchanged from ADR-0016. The bridge has just identified a MangaDex Listing for this Work and
does **not** record the link. That is the authoritative cross-source claim a **manual link override**
makes (ADR-0005, still parked), and this is a fuzzy match.

### 6. Acceptance evidence, registered before the run

The offline measurement is what licenses this ADR; it cannot also be what accepts it. The evidence
is the app doing it, in the shape ADR-0018's verification used:

- **Registered prediction, now, unadjustable: 5 of 16 refusals recover, all correct.**
- A WeebCentral library on the seeded simulator, refusal count before and after a background pass,
  with every recovered id hand-checked against the series.
- **Deadline: ~2026-08-23**, when the seeded sim's remaining refusals age out of their 14-day TTL.
  After that the fixture is gone and this has to be re-seeded.

Registering the number is the whole mechanism. A prediction adjusted after seeing the result is not
a prediction — the same reason the cost thresholds were committed in their own commit.

## What would reverse this

- The in-app run recovering **materially fewer than 5**, which would mean the offline harness models
  something the app does not.
- Any **wrong** id. Precision-bias is not negotiable; a false link is worse than a refusal, and 0-for-16
  wrong is the result that made this shippable.
- A second source measuring near-zero recovery, which would make this a WeebCentral special case
  rather than a rule about sources that publish no ids.

## Standing rule this does not break

**ADR-0016 is not un-rejected.** Its record — a bridge designed, grilled, built with eleven tests,
then killed by one live response body that a `media_type` filter answered for free — is the most
expensive lesson in `docs/adr/`, and it stays intact and Rejected. This ADR revives the
*implementation*, on a *different source*, for the *opposite reason*. Per `docs/agents/domain.md`,
that is what a revival looks like here: a new ADR, not an edit to an old one.
