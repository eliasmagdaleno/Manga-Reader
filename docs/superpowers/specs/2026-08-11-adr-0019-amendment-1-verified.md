# ADR-0019 Amendment 1 verified in the app — 2026-08-11

**Question.** Amendment 1 registered, before the run: *on a fresh cohort of at least 10 refusals, at
least 2 recover and 0 recovered ids are wrong.* Does the MangaDex bridge do that in the running app?

**Answer.** Yes. On a fresh 96-title WeebCentral library, **25 refusals, 8 recovered, 0 wrong.**
Every recovered Work's refusal record cleared on the next pass. The recovery rate — 32% — lands
within a point of the offline measurement's 31%, which was not required and is not what was being
tested.

**One leg is not verified: the gate.** Reported below as *not observed*, not as passed. See
"What could not be verified" — the reason is structural and worth reading.

The protocol is `2026-08-11-adr-0019-amendment-1-run-protocol.md`, committed in `a635308` **before
any cohort was fetched or any Work seeded**, and amended once in `01bde8c` **before pass 1**.

## Setup

Simulator `iPhone 17` / `2A0D54DF-…` — the same one ADR-0017 and ADR-0018 were verified on, so its
three invented placeholder refusals were already present and are **excluded from the cohort
denominator by name**, as the protocol required.

| | |
|---|---|
| Cohort rule | WeebCentral `sort=Popularity`, offsets 0/32/64 — 96 titles, **every one seeded, none inspected first** |
| Seeded | 96 Works, `externalIds: {}`, one `knownTitles` entry each |
| Pre-existing | 7 MangaDex Works (all carrying `mal`), 3 placeholders |
| Instrument | `VerificationSwitches.swift`, `#if DEBUG`, two environment variables |

**The cohort is not reproducible** and that is a known property, not a defect: WeebCentral's
ordering shifts daily. Re-deriving by offset draws different titles.

### Why the run needs two passes

The bridge is live in shipped code, so **refusals the bridge recovers never appear as refusals at
all** — there is no way to observe "a refusal that then recovers" in a single pass. So:

1. **Pass 1, bridge off** (`ADR0019_BRIDGE=off`). Drain to quiescence. The refusals recorded here
   **are the cohort**, and it closes at the end of this pass.
2. **Delete `upgrade-attempts.json`, and nothing else.** A pass-1 `.unmatched(knownTitlesCount:)`
   suppresses re-attempt for the full 14-day TTL while the title count is unchanged
   (`UpgradeAttemptMemory.suppresses`), so pass 2 would otherwise never reach the bridge and would
   report **zero recoveries for a reason having nothing to do with the bridge**. Deleting is
   legitimate on ADR-0007's own delete test — this file lives apart from `works.json` precisely
   because losing it costs nothing but time. `works.json` carried over untouched, so both passes ran
   on the same Works with the same titles.
3. **Pass 2, bridge on**, with `ADR0019_BRIDGE_LOG` armed.

## Results

**Pass 1 — bridge off, cohort closed**

| | |
|---|---|
| Resolved by MAL alone | **70 of 96** |
| Refusals, `.unmatched` | 28 total → **25 cohort** (3 placeholders excluded) |
| `.absentFromProvider` | 1 — *Mocha the Cat and His Forever Family*, resolved to mal 180219 with no AniList entry. **Correctly not a refusal**: it is a fetch failure, not a resolution one |

25 clears the ≥10 floor with margin.

**Pass 2 — bridge on**

| | |
|---|---|
| Cohort refusals recovered | **8 of 25 (32%)** |
| Recovered ids wrong | **0 of 8** |
| Still refused | 17 |
| Bridge queries issued | 28 — **1.08 per refusal**, matching the scoped 1.00 (WeebCentral publishes no alt titles, so the `min(knownTitles, 3)` fan-out never binds) |
| Refusal records cleared | **8 of 8** |

### The recovered ids, every one hand-checked

Checked against the series on MyAnimeList — **not** against MangaDex, which produced the id and
cannot also confirm it.

| MAL | MAL title | Seeded WeebCentral title | Basis |
|---|---|---|---|
| 13853 | Alexandros: Sekai Teikoku e no Yume | Alexandros - Dream for World Conquest | Yasuhiko Yoshikazu; Alexander the Great, 2003 — a literal translation of the same title |
| 146287 | Level 1 kara Hajimaru Shoukan Musou the Comic | Level 1 kara Hajimaru Shoukan Musou… | exact |
| 137200 | Mo Dao Zu Shi | The Grandmaster of Demonic Cultivation | the seeded title is a verbatim MAL synonym |
| 19205 | Kaichou-san Chi no Koneko | Kaichou-san no Koneko | same series; MAL lists the seeded spelling among its synonyms |
| 90759 | Oudou Rakudo no Vigilante | The Vigilante of the Kingcraft Paradise | MAL's own English title is *Vigilante the Kingcraft Paradise* |
| 25848 | Hana | Hana (MATSUMOTO Taiyou) | **author-disambiguated**: MAL author is Matsumoto Taiyou |
| 24943 | Kimi to Boku no Ashiato: Time Travel Kasuga Kenkyuusho | Kimi to Boku no Ashiato - Time Travel… | exact |
| 35475 | G | G (KOIKE Keiichi) | **author-disambiguated**: MAL author is Koike Keiichi |

**The last two are the ones that would have been easiest to wave through.** `Hana` and `G` are
single common words; a title check alone proves nothing about them. Both were confirmed on author,
and both matched the parenthetical WeebCentral publishes for exactly this reason.

### The chain, observed

Amendment 1 asked for the full chain, not just the endpoints:

| Step | How it was observed |
|---|---|
| refusal | pass 1's `upgrade-attempts.json`, 25 `.unmatched` cohort entries |
| bridge fires | 28 lines in the query log, **all 28 WeebCentral titles** |
| MangaDex entry matched → `links.mal` taken | spot-checked independently: `api.mangadex.org` returns `links.mal = 13853` for *Alexandros* and `19205` for *Kaichou-san Chi no Koneko* — the exact ids the app wrote |
| id written to the Work | `externalIds.mal` present on all 8 in pass-2 `works.json` |
| refusal cleared on the next pass | all 8 absent from pass-2 attempt memory |

The middle step is spot-checked on two of eight, not all eight. A `title=Hana` query against
MangaDex with `limit=5` does not surface the match the app found, so that one is **not** traced to
its MangaDex entry — its correctness rests on the author hand-check instead.

## What could not be verified

**The gate — not observed, and not substitutable.**

All 28 bridge queries were WeebCentral titles and no MangaDex-sourced Work was ever queried. That
sounds like the gate holding, and it is **not** evidence that it does. All 7 MangaDex Works in the
library already carry `mal` ids, so `resolve` returns them at its first line via ADR-0018's fast
path — they never reach `isBridgeable` at all. **Nothing was refused because nothing asked.**

The protocol registered this possibility in advance, before knowing it would happen, precisely so it
could not be quietly upgraded afterwards into "the gate was observed refusing." It was not. The gate
remains covered by its two unit tests, which assert on `bridgeSearch` going uncalled and each carry
a control that does bridge.

Verifying it in-app needs a MangaDex-sourced Work that **misses on MAL** — and ADR-0017's novel
filter is what makes those rare. That is a pleasant reason for a verification gap and it is still a
gap.

**Not attempted:** ADR-0018's Decision 1 in-app leg. The seeded library now contains 96 real,
openable WeebCentral titles and 17 of them are still refused, so the re-readable refused Work it has
been blocked on for two sessions now exists. It stays open.

## Found on the way

- **WeebCentral's `search/data` silently caps a page at 32.** `limit=80` and `limit=32` return the
  identical 159,456-byte response. No error — just less than asked. Same defect class as MangaDex's
  `/chapter` cap, which this project already knew about. **Count what came back; never assume
  `limit` was honored.** Cost: one protocol amendment, caught before pass 1 only because the seeding
  script printed its own count.
- **A UI-minted WeebCentral Work acquired a `provider: mangadex` snapshot with 4 genres and 0 tags,
  while `externalIds` stayed empty.** A source-level detail snapshot is not a resolution. Anything
  counting resolution must count `externalIds.mal`; counting snapshot presence would have reported a
  false positive here.
- **99 seeded WeebCentral Works were 98 after the drain.** One pair merged — `WorkStore`'s aliasing
  doing its job on two listings of one series. Not chased down; noted because a seeded count that
  does not survive a drain would otherwise look like data loss.
- **One seeded title, `Shadow (Haejin`, is truncated** by the scraper's regex where the real source
  parser would not truncate. It is in the still-refused 17. It makes recovery marginally *harder*,
  never easier, so it cannot have inflated the result — but the seeding script is not a faithful
  substitute for `WeebCentralSource`'s own extraction and should not be treated as one.

## Method worth reusing

- **When the feature under test is live, observing its input may require turning it off.** The
  two-pass shape was not a convenience; a single pass cannot see a refusal that the bridge already
  dissolved. The instrument that makes the "before" state observable is part of the experiment.
- **Name the way the experiment can produce a false negative, in advance, in writing.** Here it was
  attempt-memory suppression: pass 2 would have reported a clean, believable zero. It was written
  into the protocol before the run and into the handoff, because it is the kind of thing that is
  obvious once and invisible later.
- **A protocol can be amended before a pass without being corrupted — the test is whether an outcome
  exists yet to steer it.** `limit` capping at 32 was a rule that could not be executed, found with
  nothing drained and the bridge switch untouched. Amending in its own commit, before pass 1, keeps
  the distinction legible in `git log` rather than resting on a claim in prose.
- **Hand-check the ambiguous cases on something other than the title.** Two of eight recoveries were
  single common words. Author was the independent axis; without it, "0 wrong" would have been an
  assertion rather than a check.
- **An unobserved leg is a result.** The gate had nothing to refuse because ADR-0017 removed the
  refusals it would have refused. Reporting that as a pass would have been the same category error
  Amendment 1 exists to correct — one level down, and much harder to notice.
