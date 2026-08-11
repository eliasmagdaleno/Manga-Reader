# What does the MangaDex bridge cost? — measurement, 2026-08-11

**Question.** The 2026-08-11 resolvability measurement found ADR-0016's revisit trigger firing on
WeebCentral: 15 of 16 refusals are threshold misses, and MangaDex holds a verified-correct id for 5
of them. It measured *recoverability only*. ADR-0016 was rejected partly on **2–5 extra requests per
refusal**, and nothing has touched that number since. Writing the revival ADR on half the ledger
would repeat ADR-0016's original mistake — it was built before it was measured.

So: what does the bridge actually cost, per refusal and per library?

---

## Pre-commitment

**Written before the harness was run, and committed separately from the results.** The point of
this section is that the measurement can come out against the bridge. A threshold chosen after
seeing the number is not a threshold.

### The request sequence being counted

Read off `origin/mangadex-alt-titles`, the pre-built implementation — not an idealised bridge.
`MALEntityResolver.bridged(sourceTitles:)`:

1. **Round A** — `min(knownTitles, titleSearchLimit=3)` calls to `MangaDexAPI.searchManga(title:)`,
   unioned into one pool by listing id.
2. The pool is **partitioned** on `malId != nil`. The id-bearing side is matched first.
   - **Match → done.** Extra cost = Round A.
   - **No id-bearing match** → the id-less side is matched, to find "right series, no MAL link".
3. **Round B** — only when step 2 identified a series with no id: harvest its alt titles, keep the
   spellings not already known, and re-search **MAL** with `min(newSpellings, 3)` more calls.
   Extra cost = Round A + Round B.
4. Nothing matched → extra cost = Round A.

**Worst case 6 extra requests, best case 1.** The bridge runs only *after* MAL's own round has
failed, so none of the pre-existing MAL searches count as bridge cost — they are spent either way.

### Metrics

- **Gating: extra requests per *recovered id*.** This is the only figure that trades cost against
  benefit. Requests-per-refusal flatters the bridge, because 11 of the 16 cannot recover at all
  under any version of this proposal and still pay the toll.
- **Gating: extra requests per library sync**, expressed per library title. This is the figure a
  user experiences; the per-refusal figure is an implementation detail.
- **Reported, not gating: added wall-clock** to a queue drain. It matters, but the queue is paced
  and runs in the background, so latency is not what would kill this.

### Thresholds

| Metric | Fails if | Why this line |
|---|---|---|
| Extra requests per recovered id | **> 10** | The MAL happy path resolves a title in ~1 request. A bridge that needs more than ten to buy one id is spending an order of magnitude more per answer than the mechanism it supplements — and it can only ever reach 5 of these 16. |
| Extra requests per library title | **> 1.0** | Above this the bridge more than doubles the request cost of a resolution pass over the library. That is the point at which it stops being a fallback and becomes the second pipeline that ADR-0016's Scope objection was about. |

**Both must pass.** Either one failing is a decision not to write ADR-0019 as a revival — the
measurement then supports leaving ADR-0016 rejected on cost grounds, which is a real and useful
outcome, not a failed session.

If both pass, ADR-0019 becomes writable. Passing is **not** an argument that it should be written;
it removes the blocker, and the decision is still a decision.

### Prediction

Recorded so the run can surprise us. WeebCentral publishes no alternate titles, so a refused Work
here has exactly **one** known title — meaning Round A should be **1 request**, not the 2–5 ADR-0016
assumed. Round B should be rare, firing only where MangaDex carries the series without a `mal` link.
Expected outcome: **well under both thresholds**, with the honest caveat that a one-title Work is
the cheapest possible case and a merged multi-title Work would cost up to 6.

---

## Results

_(To be filled in by the run. Nothing above this line changes afterwards.)_
