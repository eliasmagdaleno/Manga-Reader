# ADR-0004 — Fulfillment: most complete English chapter run wins; MangaDex breaks ties

- **Status:** Accepted, with a required fallback (2026-07-24)
- **Related:** ADR-0001 (Work vs Listing), ADR-0002 (catalog), ADR-0005 (manual link override)

## Context

Once a Work has several Listings (ADR-0001), opening it must choose one. The user's stated
preference: the source with the **most complete chapter availability in English**, using MAL /
AniList's known chapter total as the reference for "how many are out"; MangaDex preferred when
two sources tie.

## Decision

Rank a Work's Listings by **English chapter completeness**, then prefer MangaDex on a tie.

```
1. count each Listing's distinct English chapters
2. rank by that count, descending
3. equal counts → prefer MangaDex; then by source registration order
```

MangaDex-first is a **quality** preference (better scans, better metadata, no ads), not an
availability one — so it only applies at equal completeness. A source with materially more
chapters wins over MangaDex.

## The reference total does not work as stated — required fallback

Verified live against AniList on 2026-07-24:

| Work | `status` | `chapters` |
|---|---|---|
| Solo Leveling | `FINISHED` | 201 |
| Jujutsu Kaisen | `FINISHED` | 272 |
| **One Piece** | **`RELEASING`** | **`null`** |

**Ongoing series report `chapters: null`.** The metadata providers only know a total once a
series has finished — and ongoing series are exactly the case where sources diverge on how
current they are. A finished series is either complete on a source or it isn't; the routing
decision barely matters. For One Piece it matters every week, and that is precisely where the
reference total is unavailable.

So the policy is:

- **Reference total known** (`FINISHED`, non-null `chapters`): completeness is
  `sourceChapters / total`, and a source at 100% can short-circuit the comparison.
- **Reference total unknown** (`RELEASING`, null): **the sources define the frontier.** Rank by
  raw English chapter count — whoever has the most is by definition the most current. No
  provider call is needed or useful.

The provider total therefore *refines* the ranking when available; it is never required for it.

## Consequences and open questions

- **Cost.** Counting chapters per Listing means asking every candidate source for a chapter list.
  With many installed extensions that is N network round-trips before a detail page can render.
  **Lazy (on detail open, with a spinner) vs eager (background, cached) is undecided** and is a
  latency decision users feel directly. A cached count with a TTL is the likely answer.
- **Counts are not trustworthy across sources, and that risk is accepted.** Sources split
  chapters differently, host duplicate uploads, and mix languages, so a source that lists every
  chapter three times can win a route it shouldn't. Cross-source count *normalization* is
  explicitly **not** attempted: when the true total is unknowable anyway (the `RELEASING` case
  above), a naive "highest count wins" is a reasonable estimator, and the cost of being wrong is
  low **because the user can correct it in one tap** (below). Revisit only if bad routes turn out
  to be common in practice.
- **The user can switch source from the manga detail page.** This is promoted from a nice-to-have
  to a *load-bearing requirement*: it is the mitigation that makes the naive count acceptable. The
  detail page shows which Listing is being served and offers the alternatives, so a stale
  auto-pick costs a tap rather than a bug report.
- **Source reliability should be learned from those switches.** When a user switches away from
  source A to source B for a Work, that is direct evidence B was more current. Aggregated per
  source, it becomes a reliability prior feeding step 2 of the ranking. Prefer learning this
  **implicitly from switch events** over an explicit "flag this source" control: it needs no UI,
  cannot be forgotten, and every user correction improves routing for free. An explicit flag can
  come later as a secondary signal if the implicit one proves too sparse.
- **Silent non-resolution interacts with this.** A Listing that never resolved to the Work
  (ADR-0005) is invisible to routing — it cannot be ranked, so the "best" source may simply never
  be considered. Routing quality is bounded by resolution quality.
- The chosen Listing should be **visible and overridable in the UI**. An automatic choice the
  user cannot see or change is indistinguishable from a bug when it picks badly.
