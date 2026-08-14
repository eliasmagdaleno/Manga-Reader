# Measurement protocol — can reverse resolution reach beyond MangaDex?

**Registered 2026-08-13, before any measurement was taken.** The commit order is the evidence.
Nothing in this document reports a result; the run that fills it in is a separate commit.

## The question

`MALReverseResolver` maps a MAL id back to an openable title by searching **MangaDex only** — its
injected `search` / `fetchByIds` default to `MangaDexAPI` statics, and `ReverseResolution` stores a
single `resolved(mangaDexId:)`. A "More Like This" recommendation that MangaDex does not carry
therefore disappears from the rail even when WeebCentral has it.

Two different features hide under "beyond MangaDex-only", and they were separated deliberately:

- **A — recall.** Recover cards MangaDex cannot serve, by falling back to another source.
- **B — affinity.** Open a card on the source the user prefers, *even when MangaDex could serve it*.

**This protocol is about A. B is a separate ADR** and is not measured here. B raises questions A
does not (what "prefers" means; whether one rail may show a work twice from two sources), and
answering them is cheaper once A's feasibility is known.

## Why measure before designing

The cards A adds are, by construction, the ones we are least sure about.

`MoreLikeThis.pickMatch` has two arms. The **strong** arm is an exact `malId` hit among the search
candidates — available on MangaDex because MangaDex publishes `links.mal`. The fuzzy title matcher
is the fallback. **WeebCentral publishes no external ids** — the premise of both ADR-0018 and
ADR-0019 — so reverse-resolving MAL → WeebCentral has *only* the fuzzy arm, with nothing to confirm
against.

It is also the harder direction. ADR-0019 measured WeebCentral's refusals as **reach failures** —
15 of 16 were threshold misses, spellings MAL's search cannot find. Going the other way, MAL's
title is the string typed into WeebCentral's search, and the same spelling gap applies.

The project has been here before. ADR-0016 was **rejected on measurement**, and that rejection is
still the more valuable half of its record. Replicating the matcher against live APIs is what
killed a fully-built ADR once already; this protocol is that technique applied before the build
rather than after.

## Design

### Sample

The sim's library Works as seeds (107 available). For each, **MAL's per-title recommendations** —
the exact input `MoreLikeThisProvider.recommendations(for:)` consumes, so the measurement runs on
the real distribution rather than a synthetic title list. Deduplicate by MAL id across seeds.

### Two populations, split by asking MangaDex first

| Population | Definition | Labels |
|---|---|---|
| **Easy** | MangaDex returns a candidate whose `links.mal` equals the target id | Authoritative (ADR-0018), and MangaDex's full alt-title set comes free |
| **Hard** | MangaDex returns no confident candidate | None — this is the population the feature exists for |

### The matcher runs identically on both

Search WeebCentral `/search/data` with **MAL's primary title only**, run the replicated
`MALTitleMatcher` + `pickMatch` logic, record pick-or-refusal. The matcher never sees MangaDex's
titles. That is what keeps the Easy labels non-circular — they come from a source the matcher had
no access to.

### Labelling

- **Easy:** a pick is correct if it normalizes to any title in MangaDex's alt-title set. Strict
  normalized comparison — **deliberately not the fuzzy matcher**, or the matcher would be grading
  itself.
- **Hard:** human adjudication of **30 picks** sampled at random.

### What each number answers

| Number | Population | Meaning |
|---|---|---|
| Precision | Easy | **Upper bound.** These are the well-known, cleanly-romanized titles; the matcher will not do better than this anywhere else |
| Yield = picks ÷ population | Hard | Whether the feature recovers enough cards to be worth a scraped-source round trip. **Needs no adjudication** |
| Precision | Hard | What the 30 pairs buy — accuracy on the population that actually matters |

## Pre-registered gates

Each is a number the run produces and which can come out either way.

### Stage C — the kill gate, on Easy

**Precision ≥ 0.95, over ≥ 80 picks.**

Stricter than the 0.90 the feature itself must clear, and deliberately so: Easy is an upper bound.
A matcher managing only 0.90 on the easy titles will be *below* the feature's floor on the hard
ones, so shipping on that number would mean shipping on a figure already known not to apply.

Below 0.95 → **stop**. The finding is that the matcher needs work first — not that the feature is
wrong.

### Stage A — on Hard, both required

- **Yield ≥ 15%**, over a hard population of **≥ 100** recommendations. Under 15% the rail gains
  roughly one card per eight recommendations, which does not pay for a scraped-source round trip on
  every detail-page open however accurate it is.
- **Precision ≥ 27 of 30** adjudicated picks.

### Inconclusive — declared now, not later

If Easy yields **< 80 picks**, or Hard **< 100 recommendations**, the run reports its n and renders
**no verdict**. Naming this before the numbers exist is what stops it becoming an escape hatch when
they come back ugly. ADR-0019's Decision 6 had to be amended into a claim its run could falsify;
this is that lesson applied in advance.

## Execution notes — three scars from the last two runs

1. **Assert MAL responses contain a `data` key.** A request sent without a client id returns a body
   with no `data`, which a naive script reports as "no results" — i.e. as a clean confirmed miss.
   `Secrets.xcconfig` is at the **repo root**.
2. **WeebCentral over plain `curl` works as of 2026-08-13** — `/search/data` with a pinned UA
   returned real results, no challenge. This can stop being true at any moment, and it **does not
   degrade gracefully**: a challenge page produces refusals indistinguishable from real misses. The
   script must detect a challenge and **abort rather than record**. Fallback is driving it in-app,
   the way the ADR-0019 gate run did.
3. **Record pick, refusal, and search-failure as three separate outcomes**, mirroring
   `MALReverseResolver`'s own cache-write discipline (`.resolved` / `.unresolved` / *nothing* on
   throw). Searched-and-missed and search-threw are different facts, and collapsing them is exactly
   how the ADR-0019 gate run produced a believable wrong answer on its first attempt.

## What this protocol does not decide

- **The cache shape.** If A proceeds, `ReverseResolution.resolved(mangaDexId:)` has to become
  source-qualified, and the open question is whether one MAL id keeps one winner or records an
  outcome *per source* — a MangaDex miss should not suppress a WeebCentral attempt. Deferred to the
  design that follows a passing run.
- **When the fallback runs.** Inline on detail-page open versus queued through the upgrade drain
  (ADR-0019's precedent for expensive resolution). A cost question, answerable once yield is known.
- **Feature B** in any respect.
