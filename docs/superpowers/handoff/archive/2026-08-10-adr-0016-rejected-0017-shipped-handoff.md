# Session Handoff — 2026-08-10: ADR-0016 built and rejected, ADR-0017 shipped

**Audience:** the next session. Supersedes `2026-08-08-per-item-visibility-handoff.md`, whose two
pickup items are both done and on `main`.

**Work in flight:** two committed, unpushed branches. One is meant to merge; one is a museum piece.

## State

| | |
|---|---|
| `main` | **`7f9831f`** — "Say why a title is missing from recommendations (#36)", clean |
| Branch **`mal-novel-filter`** | `825cfda` — **this is the one to push.** 440 tests / 1 skipped |
| Branch **`mangadex-alt-titles`** | `70bae88`, `b57be7c`, `19a6ecd` — **rejected work, kept deliberately.** Do not merge |
| ADRs | 0001–0015 Accepted; **0016 Rejected**; **0017 Accepted** |

## What happened, in one paragraph

The prior handoff's list was drained, so the session went looking for the next thing and asked a
better question than the one it started with: instead of building more UI to *explain* that the
recommender can't tag a title, why is it failing at all? That produced ADR-0016 (resolve MAL ids
through MangaDex as a fallback), which was designed, grilled, written up in eight decisions,
corrected once on measured data, and fully implemented with eleven tests. Then its own acceptance
criterion — a before/after refusal count — was run, and **it said don't ship it**. A five-line filter
beat it. That filter is ADR-0017 and it is what's on `mal-novel-filter`.

## The finding, because it is the useful part

Measured against the live MAL and MangaDex APIs over twelve scraping-style titles, using a harness
that replicates `MALTitleMatcher` exactly (same normalization, Levenshtein, 0.90 threshold, 0.05
margin):

| Configuration | Refused | Extra requests per refusal |
|---|---|---|
| MAL only (what `main` does today) | **6 / 12** | — |
| MAL + ADR-0016's bridge | **3 / 12** | 2–5 |
| **MAL with novels filtered out** (ADR-0017) | **2 / 12** | **0** |

The bridge's marginal contribution *on top of* the filter is **zero**.

**Why:** every one of the six refusals was an **ambiguity-guard rejection, not a threshold miss** —
and the tie was usually a novel:

```
Solo Leveling   121496 manhwa  vs  119184 novel   ← same title
ORV             132214 manhwa  vs  143441 novel   ← same title
Mount Hua       146878 manhwa  vs  161366 novel   ← same title
Wind Breaker    103237 manhwa  vs  133081 manga   ← two real comics
```

MAL files novels under `/manga` and an adaptation carries its source novel's title. `MALTitleMatcher`
was never weak — it was correctly reporting a collision in MAL's catalog. The bridge recovered three
of these only because MangaDex indexes comics, so the novel twin is absent from its results;
`media_type` excludes them directly, for free, in a response the app already fetches.

Every id recovered in every configuration was verified to be the right series. No false matches.
`Wind Breaker` stays refused under everything, correctly.

**The lesson, stated plainly because it recurred:** the failure was diagnosed from the *shape of the
code* instead of from one live response body. That is the same error ADR-0015 recorded six times and
ADR-0016's own Amendment recorded a seventh. This was the eighth, and the most expensive, because it
survived all the way through implementation.

## What to do first

1. **Push `mal-novel-filter` and open a PR.** Committed, green locally, nothing blocks it.
2. **Then watch what the remaining refusals look like.** ADR-0017's revisit trigger is specific: if
   Works stay refused with a top MAL candidate scoring **below 0.90** rather than tying, that is a
   *reach* failure — the thing ADR-0016 assumed and never found — and ADR-0016 is what to reopen.
   The branch is sitting there for exactly that.

## `mangadex-alt-titles` — why it still exists

Three commits: ADR-0016 + glossary, `altTitles` decoded onto `Manga`, and the bridge itself
(partitioned matching, title harvesting, `WorkStore.noteTitles`, 11 tests, 2 mutation checks). All
green. **It is kept because the caveat on the rejection is real**: twelve hand-picked titles skewed
toward Korean webtoons, which is exactly where novel adaptations are common and so exactly where that
collision would dominate. A Japanese-scanlation-heavy library might show the reach failures the
bridge fixes. Deleting the branch would mean rebuilding it to find out.

Do not merge it without a measurement that justifies it.

## Method worth reusing

The measurement harness (`bridge_measure.py`) was scratchpad-only and is gone, but the approach is
the durable part and it beat the in-app device check on cost by a wide margin:

- Replicate the pure matcher in Python — `normalize`, Levenshtein similarity, threshold, ambiguity
  margin — and drive it against the **live** APIs. It answers "would the app resolve this?" in
  seconds per title, with no simulator, no seeding, no `UserDefaults` hex payloads.
- **Verify every recovered id by fetching its detail and reading the title back.** A recovery count
  that includes false matches is worse than no measurement.
- **Count errors as errors.** The first run reported "6 recovered" because SSL failures against
  MangaDex were being counted as successes. The number was wrong in the flattering direction, which
  is the direction to distrust.
- `api.mangadex.org` **rejects Python's `urllib` TLS handshake** (`TLSV1_ALERT_PROTOCOL_VERSION`)
  while `curl` negotiates fine. Shell out to `curl` for MangaDex.
- MAL's client id is in `Secrets.xcconfig` (gitignored), readable for this kind of harness.

## Gotchas

The prior handoffs' lists still apply. Nothing new about `project.pbxproj` this session — it was
checked before every `git add` and never churned, because no files were added to non-synchronized
groups.

One new one: **`MALEntityResolver`'s `search` seam is injected in tests, so any filter applied inside
`MyAnimeListAPI.searchManga` is invisible to resolver tests.** ADR-0017 Decision 2 accepts this
openly and puts `excludingNovels` in a pure function with its own tests as the mitigation. If a
future filter goes in the same place, it needs the same treatment.

## Also open, unchanged

- **The "N of M titles" notice** — a line under the For You rail saying how much of the library it is
  actually based on. Designed in this session's grilling and deliberately **demoted**: fixing the
  recommender was the better use of the time, and the notice is now less urgent because ADR-0017
  reduces the population it would be describing. Still worth building; it is also the thing that
  would *show* whether ADR-0017 worked, in the app rather than in a harness.
- `malId` on `LibraryItem` so saved seeds skip the title search. This was the agreed item after the
  bridge, and it survives the bridge's rejection untouched — it is about not re-deriving an id the
  app already had.
- More Like This reverse-resolution beyond MangaDex-only.
- No automated coverage of `HomeView`'s rail branch or `MangaDetailView`'s notice branch — both
  deliberate, reasoning in `AppCompositionTests`' header.
- **ADR-0015's mixed-library hazard.** Its "not due until reported" standard was found to be
  unsatisfiable here — the library is seeded test data and the app is not read in earnest, so the
  report will never arrive. Recorded in ADR-0016's Hazard 3. The gate is not "not yet", it is
  "never", and work in this area is now judged on cost and on whether the failure is silent.
- **Standing constraint:** the extension/repo system and comix.to are shelved since 2026-07-21.
