# Measured — can reverse resolution reach beyond MangaDex?

**Run 2026-08-15**, against the protocol registered 2026-08-13 in
[`2026-08-13-reverse-resolution-beyond-mangadex-measurement-protocol.md`](2026-08-13-reverse-resolution-beyond-mangadex-measurement-protocol.md).
Harness: `scripts/reverse_reach.py`. Raw data: `docs/superpowers/measurements/reverse-reach/`.

**Outcome: feature A is not being built.** The pre-registered gates came back **inconclusive on
n**, twice over — but the run answered the *decision* anyway, by a route the protocol did not
anticipate, and the reason is a ceiling rather than an accuracy failure.

The run also turned up something worth more than the feature it was measuring. It is post-hoc and
is labelled as such at the bottom.

## What the gates say

| Population | n | picks | refusals | search failures | precision |
|---|---|---|---|---|---|
| **Easy** | 90 | 42 | 48 | 0 | **0.976** |
| **Hard** | 10 | 6 | 4 | 0 | not adjudicated |

- **Stage C** required precision ≥ 0.95 over **≥ 80 picks**. Precision cleared it; **42 picks did
  not**.
- **Stage A** required a Hard population of **≥ 100**. It is **10**.

Both fall under the inconclusive clause, which named these exact thresholds before any number
existed. **No verdict is rendered on either gate**, and the 0.976 is not a pass — it is a
number taken on half the required sample.

The 30-pair adjudication was **never requested**: it is Stage A work, Stage A never opened, and
there were only six Hard picks to sample from. The user's agreement to eyeball 30 pairs is unspent.

### The one Easy "wrong" is a labelling artifact

WeebCentral returned `Boku no Hatsukoi wo Kimi ni Sasagu`; MangaDex spells it
`Boku no Hatsukoi **o** Kimi ni Sasagu`. The pick is correct and the label is wrong.

Strict normalized comparison was chosen over the fuzzy matcher precisely so the matcher could not
grade itself, and this is that choice's cost, paid as designed. **True Easy precision is 42/42.**
Recorded because a future reader comparing 0.976 against the 0.95 gate should know the real figure
is higher, and that it still does not matter — n was the binding constraint, not accuracy.

## Why the feature is dead anyway: the ceiling

The protocol asked whether the matcher is *accurate enough*. The run answered a prior question:
**there is almost nothing for it to do.**

| | |
|---|---|
| Library Works | 107 |
| …carrying a MAL id | 86 |
| …that returned **any** MAL recommendation | **37** |
| Unique recommendations, deduped | 107 (100 in the shipped top-8) |
| …**MangaDex already resolves** | **90** |
| …left for a second source to recover | **10** |

Feature A's ceiling — perfect matcher, zero false positives, every Hard row recovered — is **10
cards across the entire library**, bought with a scraped-source round trip on every detail-page
open. The measured 6 of 10 is most of that ceiling already.

The 90:10 split rests on n = 100 and is the most solid number the run produced, despite not being
one of the gates. Widening the frame from the shipped top-8 to the full recommendation list adds
**seven rows** — the sample frame is exhausted, and no rerun of these stages enlarges it.

### Hard is not "MangaDex lacks it"

Hard means *MangaDex returned no confident candidate* — which conflates a catalogue gap with a
search miss. Two of the ten are `Mugen no Juunin` and `Rurouni Kenshin: Meiji Kenkaku Romantan`,
both of which MangaDex certainly carries; they are Hard because `searchManga(limit: 20)` did not
surface a `links.mal` match in its first 20 results.

This is faithful to the app — that call *is* what the app makes — but it means the true catalogue
gap is **smaller than 10**, and the ceiling above is generous. Some of feature A's ten cards would
be better recovered by fixing the MangaDex query than by adding a source.

### The bigger hole is not sources at all

**49 of 86 seeds returned zero MAL recommendations.** "More Like This" is empty for 57% of the
library regardless of how many sources are wired in. Any effort aimed at making the rail appear
more often belongs there, not here.

## Verdict

**Do not build feature A.** Not because the matcher failed — on the evidence here it is accurate —
but because the reachable population is ~10 cards and the cost is a scraped round trip per detail
open. This is ADR-0016's pattern for the second time: the measurement, not the build, settled it,
and it settled it *before* the build this time.

**Feature B (affinity) is untouched by this.** B was split off deliberately and is not measured
here; nothing above bears on it. B's population is every card, not the 10 MangaDex misses, so the
ceiling argument that kills A does not transfer.

**What would reopen A:** a library whose recommendations MangaDex resolves materially worse than
90%. That is a property of the user's library, not of the code, so the reopening test is to re-run
`seeds` → `split` and look at the ratio — roughly ten minutes, no adjudication.

## Post-hoc: the matcher is reading one title when it could read five

**Not pre-registered. Exploratory. This is a question, not a result** — it needs its own protocol
before it justifies a build, and it is recorded here so the observation is not lost.

The protocol inherited ADR-0019's diagnosis that WeebCentral's failures are **reach** failures —
spellings search cannot find. **In this direction that is wrong.** WeebCentral's search finds these
titles fine:

| Searched with MAL's title | WeebCentral returns |
|---|---|
| `Shingeki no Kyojin` | Attack on Titan |
| `Mugen no Juunin` | Blade of the Immortal |
| `Otoyomegatari` | A Bride's Story |

Search reached every one. The **matcher** then compared MAL's romaji primary title against
WeebCentral's English display title — `shingeki no kyojin` vs `attack on titan`, similarity
**0.222** — and refused. The two sources simply name the same work in different languages, and
`pickMatch` sees one title from each side.

That single-title input is a **known, documented residual**: `MALReverseResolver.resolve(works:limit:)`
records that `knownTitles` carries romaji/english/native/synonyms but only the primary reaches
`pickMatch`. It was parked because widening it changes matching behaviour. Here is what it changes,
re-running the matcher offline against the same WeebCentral candidates with MAL's `allTitles`
(97 of the 100 rows; 3 MAL ids answer 307 redirects and were skipped):

| Population | picks, primary title only | picks, MAL `allTitles` | precision (strict labels) |
|---|---|---|---|
| Easy (n=87) | 41 | **55** | 54/55 |
| Hard (n=10) | 6 | 7 | — |

**+34% recall on Easy at no measurable precision cost**, and the one miss is the same `wo`/`o`
labelling artifact as before.

This matters to shipped code, not to the rejected feature: **ADR-0019's bridge already runs this
matcher against a source that publishes no external ids**, where the fuzzy arm is the only arm. If
the same gain holds there, it is a recall improvement on a path already in the app.

Three reasons it is not actionable as it stands. It is post-hoc on data gathered to answer a
different question. Precision was graded with the strict-label method, which the Easy artifact
already showed to be conservative — a wrong pick could hide behind a missing MangaDex spelling. And
widening the source side raises the false-match rate in general (ADR-0008's reasoning for the
ambiguity guard); this measured a 55-pick sample, not that risk.

**Next step, if pursued: a registered protocol for the matcher's input width, measured on
ADR-0019's actual path with adjudicated labels.** The 30 unspent adjudication pairs are the obvious
budget.

## Harness notes

`scripts/reverse_reach.py` runs as five checkpointed stages (`seeds`/`recs`/`split`/`wc`/`score`)
and a `selftest` that checks the ported matcher against the Swift assertions. Four things it
learned the hard way, all now enforced rather than remembered:

1. **WeebCentral publishes an explicit "No results found" alert**, so pick / refusal /
   search-failure are decided on positive evidence and anything unrecognized aborts. Scar 3 is
   structural now.
2. **Result items are `article.flex.gap-4` containing two further `<article>` cover blocks.**
   Matching to the next `</article>` truncates each item before its title link and returns zero
   candidates — silently, and looking exactly like a site redesign.
3. **`str.isalnum()` is true for CJK**, so a hand-rolled "keep alphanumerics" encoder put raw
   multibyte characters on the wire and MangaDex answered 400 — on precisely the Japanese-titled
   recommendations this measurement most needed. Percent-encode UTF-8 bytes.
4. **MAL answers 307 for some merged ids**, and following the redirect hangs. The harness aborts
   loudly rather than recording a miss, which is the correct failure but worth knowing before a
   long run.

WeebCentral answered plain `curl` with the pinned UA for the entire run — **0 search failures in
100 searches**, no challenge encountered.
