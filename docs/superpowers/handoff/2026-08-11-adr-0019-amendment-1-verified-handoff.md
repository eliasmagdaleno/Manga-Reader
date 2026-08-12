# Session Handoff — 2026-08-11 (night): ADR-0019 verified in the app, the gate leg still open

**Audience:** the next session. Supersedes `2026-08-11-adr-0019-shipped-handoff.md` — its sole
deadlined item, "seed a real WeebCentral library and run Amendment 1", is **done and passed** — and
supersedes this session's own mid-task handoff.

## State

| | |
|---|---|
| Branch | **`adr-0019-amendment-1-run`**, 3 commits ahead of `0ccde90`, **not yet pushed / no PR** |
| Tests | **468**, 1 skipped, 0 failures — unchanged |
| ADRs | 0019 now **Accepted and verified**, with one leg recorded as not observed |
| Sim | `2A0D54DF-…` now holds a **96-title WeebCentral library**, 17 still-refused |
| `project.pbxproj` | churned on its own and was reverted; **check it before every `git add`** |

Three commits, deliberately in this order — the ordering is the evidence, not bookkeeping:

1. `a635308` — the protocol, before any cohort was fetched
2. `01bde8c` — one amendment, before pass 1, with nothing drained
3. `8ad2736` — the run and its results

## The result

**Amendment 1's registered claim was met.** Registered floor: ≥2 recoveries, 0 wrong, on ≥10
refusals. Actual, on a fresh 96-title WeebCentral cohort seeded unfiltered:

| | |
|---|---|
| Cohort refusals | **25** (3 known placeholders excluded by name) |
| Recovered | **8 (32%)** |
| Wrong | **0 of 8**, every one hand-checked |
| Refusal records cleared | 8 of 8 |
| Bridge cost | 28 queries / 25 refusals = **1.08 per refusal** |

Full write-up, including the per-id hand-check table:
`docs/superpowers/specs/2026-08-11-adr-0019-amendment-1-verified.md`.

**Do not cite the 32% as confirming the offline 31%.** Different cohort, different instrument; the
agreement is a coincidence and Amendment 1's whole argument is that an in-app run measures a
mechanism rather than a rate. The ADR says this in its own Outcome section for the same reason.

## What is still open — and the first one is the real item

**1. The gate has never been observed refusing.** This is the one leg Amendment 1 asked for that the
run did not deliver. Every MangaDex-sourced Work in the library already carried a `mal` id, so
`resolve` returned at its first line via ADR-0018's fast path and none ever reached `isBridgeable`.
**Nothing was refused because nothing asked.** It is recorded as *not observed*, not as passed, and
the protocol registered that possibility in advance so it could not be quietly upgraded later.

Verifying it needs a **MangaDex-sourced Work that misses on MAL** — which ADR-0017's novel filter
made rare, so this is a pleasant reason for a gap and still a gap. The instrument for it is already
in the tree (below). Until then the gate rests on its two unit tests, which assert `bridgeSearch`
goes uncalled and each carry a control that does bridge.

**2. ADR-0018 Decision 1's in-app leg — now unblocked for the first time.** It has been stuck two
sessions on "no refused Work on this sim is re-readable." The sim now has **17 still-refused, real,
openable WeebCentral titles**. Pick one with chapters, read it, and check the history entry carries
the id its source published.

**3. `VerificationSwitches.swift` is a debt with a trigger.** `#if DEBUG`, returns nil unless
`ADR0019_BRIDGE` / `ADR0019_BRIDGE_LOG` is set, so the shipped graph is unchanged and a release build
does not contain it. **Kept rather than deleted on purpose** — it is exactly what item 1 needs, and
rebuilding it is ~40 lines of rediscovery. **Delete it once the gate leg is verified, or at
~2026-08-23 if it is not.** It is a measuring instrument; it has no product meaning and must not
acquire one.

Also unchanged from the previous handoff: More Like This reverse resolution beyond MangaDex-only; no
automated coverage of `HomeView`'s rail branch or `MangaDetailView`'s notice branch; extension/repo
system and comix.to shelved since 2026-07-21.

## If this run ever has to be repeated

The method is in the protocol doc; these are the two things that will silently ruin it.

- **Two passes are structural.** The bridge is live, so refusals it recovers never appear as
  refusals. Pass 1 with `ADR0019_BRIDGE=off` exists only to close a cohort.
- **Delete `upgrade-attempts.json` between passes, and only that file.** A pass-1
  `.unmatched(knownTitlesCount:)` suppresses re-attempt for the full 14-day TTL while the title count
  is unchanged, so pass 2 would report **zero recoveries for reasons having nothing to do with the
  bridge** — a clean, believable, entirely wrong result. This is the single most dangerous failure
  mode of the design.

`scripts/adr0019_seed.py` seeds the cohort; `testMintOneWeebCentralWorkThroughTheRealPath` is the
control that licenses planting rather than hand-adding.

## Gotchas found this session

- **WeebCentral's `search/data` silently caps a page at 32.** `limit=80` and `limit=32` return the
  identical 159,456-byte response — no error, just less than asked. Paginate by `offset`. Same defect
  class as MangaDex's `/chapter` cap. **Count what came back.**
- **A source detail snapshot is not a resolution.** A UI-minted WeebCentral Work carried a
  `provider: mangadex` snapshot with 0 tags and empty `externalIds`. Count `externalIds.mal`;
  counting snapshot presence reports false positives.
- **MyAnimeList blocks scraping** — `myanimelist.net/manga/<id>` returns an empty `<title>` to curl.
  Hand-check through the v2 API with the client id from `Secrets.xcconfig`, and **URL-encode the
  braces** in `fields=authors{...}` or the shell mangles it into invalid JSON.
- **Hand-check ambiguous titles on an axis other than the title.** Two of the eight recoveries were
  single common words (`Hana`, `G`); author is what actually confirmed them.
- **WeebCentral loaded in the sim with no Cloudflare challenge**, and `curl` reached it unchallenged.
  Do not budget for the challenge sheet until it appears.
- `project.pbxproj` churned with no `xcp` involved, exactly as CLAUDE.md warns. Reverted.
