# Session Handoff — 2026-08-17: search-input width measured, both arms passed, ADR is next

**Audience:** the next session. Supersedes
`2026-08-15-reverse-resolution-measured-feature-a-rejected-handoff.md`, whose queued item — the
matcher-width protocol — was **retargeted and run**. Read the retarget before doing anything with
its conclusion; the handoff you are superseding queued a question this session found to be the wrong
one.

## State

| | |
|---|---|
| `main` | **`7595e4c`**, unchanged — nothing merged this session |
| Branch | **`search-input-width-protocol`**, 4 commits ahead, pushed |
| PR | **[#54](https://github.com/eliasmagdaleno/Manga-Reader/pull/54)** — open, **must merge with a merge commit, not a squash** |
| Tests | 468 unit, untouched — **no app code was changed this session** |
| ADRs | 0018 and 0019 unchanged. **A new ADR is the next task** |
| Deadlines | none |

## The one thing that will cost you if you skip it

**PR #54 must land as a merge commit.** All four commits are load-bearing evidence: the protocol
(`aa4c8eb`) and Amendment 1 (`8bf39e8`) were written before any request was sent, and the write-up
cites commit order as the proof. PR #52's squash already collapsed this once for the previous
protocol. `gh pr merge --merge`, not the default.

## What was found

### The queued question was the wrong one, and that is the durable finding

The last handoff queued **matcher input width** (`allTitles` vs one title inside `bestMatch`), on the
strength of a post-hoc 41 → 55 gain. Reading the code first killed it:

1. **`MALEntityResolver` is already wide on both sides** — `sourceTitles: work.knownTitles` against
   `titles(of:) = [title] + altTitles` (`:131`, `:221`, `:227`, `:254`). The premise that ADR-0019's
   bridge runs a narrow matcher is **false**.
2. **Where the matcher is narrow (`MoreLikeThis.pickMatch`), it barely fires** — the exact-`malId`
   arm short-circuits **90 of 100** rows.
3. **The 41 → 55 gain was path-bound** to WeebCentral candidates, i.e. rejected feature A.

So the lever moved one over, to **search-input width**: how many spellings get *searched*, not how
many titles get compared. A second query changes which candidates come back, feeding the strong arm.

**Matcher width is not refuted — it is immaterial on shipped paths.** If feature A ever reopens it
becomes live again and needs its own protocol.

### Both arms passed every registered gate

`docs/superpowers/specs/2026-08-15-search-input-width-measured.md`. Harness:
`scripts/search_width.py`. Raw data: `docs/superpowers/measurements/search-width/`.

| Gate | Floor | MAL | AniList |
|---|---|---|---|
| n | ≥ 60 unresolved | 60 | 60 |
| Recovery rate | ≥ 15% | **75.0%** (45/60) | **65.0%** (39/60) |
| Cost | ≤ 10 req per recovered card | **1.76** | **3.0** |
| Wrong strong-arm picks | 0 | 0 | 0 |
| Net recall | positive | +45 | +38 |

Both stopped on `target-unresolved`; the 1500-query cap was untouched.

**83 of 84 recoveries came through the exact-`malId` arm.** Reach, not matching. `Mugen no Juunin`
recovers via *Blade of the Immortal*; `Kaikan♥Phrase` via *Sensual Phrase* — the exact rows the
previous session flagged as "MangaDex plainly carries these, the query is what failed."

**N = 3.** Query 2 captures 86% of recoveries, query 3 → 94%, queries 4–5 buy 5 cards of 84.
`titleSearchLimit = 3` was inherited by convention and is now evidenced.

**The protocol expected to fail on cost and did not.** It inherited feature A's ~10% ceiling, but
one-to-three extra MangaDex queries on rows that already missed is not A's scraped-source round trip
on every detail-page open.

## What is queued

### An ADR proposing the widened search, at N = 3

The measurement licenses a design, not a decision. Three questions it deliberately did not answer:

1. **Where the fan-out fires** — inline on detail-page open, or queued through the upgrade drain
   (ADR-0019's precedent). At ~0.2 extra requests per row overall, inline is now arguable where it
   was not.
2. **`MALReverseResolver.resolve(works:limit:)`'s `.first` reduction** (`:108`). The *search*
   widens; whether the **cache key** does is separate, and getting it wrong means either re-searching
   resolved rows or caching under a spelling that varies.
3. **Whether the fuzzy arm should be reached at all on the widened path.** It produced the run's only
   wrong pick and 1 of 84 recoveries. Disabling it would have cost 1 and prevented 1 — n=1 both ways,
   settles nothing, but it is the cheapest question in the data and an ADR should not skip it.

## Things that will cost you time if rediscovered

### One wrong pick, and the registered gate could not see it

`Kyoukaisenjou no Horizon` (MAL 24464) recovered via **fuzzy** match onto a MangaDex entry publishing
`links.mal = 37783` — MangaDex authoritatively contradicting the match (ADR-0018).

The gate was phrased **"wrong strong-arm picks"**, and the first scorer implemented exactly that:
it inspected the one arm where a wrong pick is *structurally impossible*, and reported zero. The
protocol's "labels are free, no adjudication needed" argument holds **only for strong-arm
recoveries**. Scoring now classifies by arm: strong-arm correct by construction, fuzzy wrong when the
entry publishes a conflicting id, unlabeled when it publishes none (0 rows in both arms).

### Three instrument failures, one family

All three produced **confident numbers over a fabricated frame** rather than raising:

1. **MAL answers 30x under sustained load, and a 30x is also how a merged id answers.** The previous
   runs' scar list recorded only the second reading. The first MAL pass filed **108 unique ids as
   merged**, produced **zero hop-2 rows** — the whole point of Amendment 1 — and exited clean. Every
   one answered `200` on a quiet retry. The tell was in the artifact: id 583 appeared as both a
   successful row *and* a skip. Now retried with exponential backoff before being called merged.
2. **AniList reports 429 as a JSON error body, not a transport failure.** Its limit is per-minute, so
   backoff is 20s+, not milliseconds. Killed the 40-pair draw at pair 30.
3. **The wrong-pick gate above.**

**The rule: assert the frame you got is the frame you asked for** — row count, hop distribution, pair
count — before trusting anything computed from it. A correct MAL frame is 639 rows / 532 hop-2 / 0
skips; the broken one was 107 / 0 / 108.

### Amendment 2 was written after seeing numbers, and says so

Amendment 1 (frames) preceded every request. **Amendment 2 (AniList 20 → 40 pairs) did not** — the
20-pair arm had been scored, at 55 unresolved against a floor of 60. The extension was mechanical
(next pairs by the seed weight fixed in Amendment 1) and **changed nothing**: 65.0% vs 65.5%, cost
3.0 vs 2.92, zero wrong picks both. Pre-extension artifacts are committed as
`measure_al_20pairs.json` / `score_al_20pairs.json`.

**A reader who discounts that arm to "descriptive, n=55" is not making an error**, and the write-up
says so. Do not quietly promote it.

### The 30 adjudication pairs are *still* unspent

Third consecutive protocol to complete without touching them. The one cell adjudication could have
spoken to — a fuzzy recovery onto an entry publishing no `links.mal` — was empty in both arms. That
is partly luck, given the gap above.

## Also open

- **`MAL_CLIENT_ID`**: the key in `Secrets.xcconfig` works (this run made ~1,900 MAL calls on it).
  Whether the **old** key's app entry was deleted at myanimelist.net/apiconfig is **still
  unverified** — carried from the last handoff, unchanged.
- **Measurement artifacts are getting large.** This run added **1.4 MB / 61k lines** of JSON to
  `docs/superpowers/measurements/`. Consistent with how reverse-reach was committed, so it was kept —
  but whether these belong in git is worth deciding **before** the next protocol, not after.
- No agy review exists for this branch's commits — nothing was built.
- ADR-0018 **Decision 2** remains unverified and is not verifiable through the app (Hazard 1).
- No automated coverage of `HomeView`'s rail branch or `MangaDetailView`'s notice branch —
  deliberate, reasoning in `AppCompositionTests`' header.
- Extension/repo system and comix.to shelved since 2026-07-21.

## Sim state

**Unchanged.** Nothing was built, run, or driven in the simulator — the whole measurement ran in
Python against live APIs. `works.json` was **read** for seeds (107 Works, 86 with a MAL id) and not
written. History remains at 25 entries; `upgrade-attempts.json` still carries its declared hand edit.
