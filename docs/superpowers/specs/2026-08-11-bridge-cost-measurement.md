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

**Both thresholds pass, comfortably.** Harness: `scripts/bridge_cost.py`, run once against the live
MangaDex and MAL APIs over the same 16 refusals.

| Metric | Threshold | Measured | |
|---|---|---|---|
| Extra requests per **recovered id** | ≤ 10 | **5.2** | pass |
| Extra requests per **library title** | ≤ 1.0 | **0.41** | pass |
| Extra requests per refusal | _(reported)_ | 1.62 | |
| Total extra requests | | 26 (16 MangaDex + 10 MAL) | |
| Recovered | | **5 of 16, 5 correct, 0 wrong** | |

**The prediction held.** Round A cost exactly **1 request** for all 16 — WeebCentral publishes no
alternate titles, so each Work has one known title and the `min(knownTitles, 3)` fan-out never
binds. ADR-0016's assumed **2–5 extra requests per refusal** was an overestimate for this shape of
Work: the measured figure is 1.62, and the 0.62 above 1.0 is entirely Round B.

### Per-refusal detail

| Title | Outcome | A | B | id |
|---|---|---|---|---|
| Xia Ke Xing | recovered round A | 1 | 0 | 18497 |
| The Vigilante of the Kingcraft Paradise | recovered round A | 1 | 0 | 90759 |
| Junjou Romantica | recovered round A | 1 | 0 | 765 |
| The Grandmaster of Demonic Cultivation | recovered round A | 1 | 0 | 137200 |
| Level 1 kara Hajimaru Shoukan Musou ~…~ | recovered round A | 1 | 0 | 146287 |
| Koi Inu | round B missed | 1 | 3 | — |
| Ling Bao Zhi | round B missed | 1 | 3 | — |
| Sozo no Eterunite | round B missed | 1 | 2 | — |
| Together with Zun-chan! | round B missed | 1 | 2 | — |
| Vairocana | identified, no new titles | 1 | 0 | — |
| Sweet HR | no match | 1 | 0 | — |
| Kin no Tamago (Katsuwo) | no match | 1 | 0 | — |
| Yoruhime-sama | empty pool | 1 | 0 | — |
| Beyond Virtual | empty pool | 1 | 0 | — |
| Brothers (NARUSE Yoshiki) | empty pool | 1 | 0 | — |
| Miquiztli | empty pool | 1 | 0 | — |

**Correctness checked, not assumed.** All five recovered ids match the independently-derived
`links.mal` column in the resolvability measurement exactly. Five recoveries, five correct, none
wrong — the same rule that measurement set, that a recovery count without a correctness check
behind it is worth less than no number.

**Every recovery came from Round A.** Round B — harvest MangaDex's alt titles, re-search MAL —
fired four times, cost 10 of the 26 requests (38% of total spend), and **recovered nothing**. It is
the entire reason the per-refusal figure exceeds 1.0.

### Wall-clock

**Reported, not gating.** Not separately instrumented; the honest derivation is request count times
round-trip. Measured MangaDex RTT over five calls: median **0.40s** (range 0.06–0.43). None of the
bridge's requests pass through `AniListRateLimiter` — it wraps only the AniList fetch
(`MetadataUpgradeQueue.swift:200`) — so the bridge is unpaced and adds roughly **26 × 0.4s ≈ 10s**
across a 64-title library drain, in the background, spread over the whole pass. Not a factor.

## What the numbers do and do not license

**They remove the cost blocker on ADR-0019.** That is all. Passing a threshold is not an argument
that the bridge should be built; it is the removal of the reason it could not be considered. The
decision is still a decision, and it is now takeable on a complete ledger:

- **Benefit:** 5 of 16 refusals recover, all correct. A 64-title WeebCentral library goes from
  47 resolved to 52.
- **Cost:** 26 extra requests per full pass, 0.41 per library title, ~10s of background wall-clock.
- **Still refused:** 11 of 16. MangaDex either does not carry them or carries them with no
  `links.mal`, and no version of this proposal reaches them.

**A live question this raises for ADR-0019: drop Round B.** It cost 38% of the spend and recovered
nothing here. On this evidence the bridge is *cheaper and no less effective* as Round A alone —
1.00 extra requests per refusal, 3.2 per recovered id. Four cases is a small sample to kill a
mechanism on, and Round B is ADR-0016's Decision 6 with its own reasoning, so this is a question for
the ADR rather than a conclusion. But it should not be carried over unexamined.

## Hazards

1. **One known title per Work is the cheapest possible case.** WeebCentral publishes no alternates.
   A Work merged across sources, or one that has already harvested spellings, fans out to
   `min(knownTitles, 3)` and can cost up to 6. The measured 1.62 is a floor for this source, not a
   general figure — and notably, a Work whose titles grew *because* of a previous bridge harvest is
   more expensive on its next pass. That feedback is unmeasured.
2. **Round A cost is bounded by construction, so the interesting variance is all in Round B.**
   Round B fired on 4 of 16 here. A source whose titles more often match MangaDex variants carrying
   no `mal` link would fire it more often and shift the per-refusal figure up.
3. **The harness truncated a title on its first run, and it cost a recovery.** The resolvability
   doc's table abbreviates `Level 1 kara Hajimaru Shoukan Musou ~…~` with an ellipsis; copying that
   into the input list scored 0.4-ish against MangaDex's full title and produced a spurious
   `no-match`. With the real title it ties at 1.000 and recovers in one request. **A source title is
   an input, not prose** — the fix is in the script with a comment, but the near-miss is the hazard:
   the first run reported 4 recoveries and would have understated the benefit by 20% had the
   discrepancy against the known ground truth of 5 not been chased.
4. **Same port, same caveat as before.** The matcher is `wc_resolve.py`'s, validated against four
   in-app ADR-0017 results. A divergence from `MALTitleMatcher.swift` remains invisible from here.
5. **Requests are counted, not the app's actual HTTP.** The harness replicates
   `bridged(sourceTitles:)`'s sequence from the branch; it does not run the Swift. A caching or
   dedupe path in `MangaDexAPI` that the read missed would make the real cost lower, never higher.

