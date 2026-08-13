# ADR-0019 Amendment 1 — run protocol, committed before the run

**Written and committed before any cohort was fetched, any Work was seeded, or any drain was
run.** That ordering is the instrument, not paperwork: Amendment 1 exists because Decision 6
registered a number the fixture could not produce, and the correction is only worth anything if
this file predates the data. `git log` is the evidence.

## What is being verified

Amendment 1's registered claim, verbatim:

- **On a fresh cohort of at least 10 refusals: at least 2 recover, and 0 recovered ids are wrong.**
- The full chain observed: refusal → bridge fires → MangaDex entry matched → `links.mal` taken →
  id written to the Work → refusal cleared on the next pass.
- **The gate observed refusing**: a MangaDex-sourced Work in the same library issues no bridge
  request.
- Every recovered id hand-checked against the series.

Not being verified: the offline 5-of-16 rate. It stands on the harness that produced it and is not
re-measured here (Amendment 1's "a rate is not what an in-app run measures").

## Cohort rule — fixed now, applied without filtering

WeebCentral, `sort=Popularity`, `offset=0`, `limit=80`, via
`https://weebcentral.com/search/data` — the same endpoint `scripts/wc_resolve.py` uses.

**Every title returned is seeded. None is inspected, scored, or dropped first.** Selecting titles
after seeing whether they resolve would make the recovery count meaningless, which is the same
failure mode Amendment 1 was written to correct one level up. 80 rather than 64 because the offline
refusal rate was 25% and the floor is 10 refusals; 80 clears it with margin without depending on
the rate reproducing.

The cohort is **not reproducible** — WeebCentral's ordering shifts daily. That is a known and
accepted property, recorded in ADR-0019's Sample honesty section.

### Amendment A (before pass 1) — `limit` is capped at 32, so the cohort paginates

**`limit=80` and `limit=32` return the identical response**, byte for byte: 159,456 bytes, 32 unique
series. The endpoint caps a page at 32 and ignores anything larger. The rule above could not have
been executed as written.

The cohort rule becomes: **`sort=Popularity`, `offset=0`, `32`, `64`** — three pages, 96 titles,
every one seeded, still nothing inspected or dropped.

**Why this is not the failure this protocol exists to prevent.** No resolution outcome had been
observed when this was found — page 1 had been seeded and nothing had been drained, with the bridge
switch untouched. This changes *how many* titles are drawn by a rule that was already fixed; it does
not change *which* titles, and it cannot be steered by a result that does not exist yet. The
distinction that matters is between a rule that turned out to be inexecutable and a rule adjusted
after seeing what it produced. This is the first, and it is committed before pass 1 for the same
reason the original was committed before the fetch.

The 31 Works from page 1 are already seeded and are kept: the amended rule includes page 1 unchanged.

**Worth carrying past this run:** a `limit` silently capped by the server is the same defect class as
MangaDex's `/chapter` cap, which this project already knows about. Neither endpoint errors — both
just hand back less than asked. Count what came back; never assume `limit` was honored.

## Method

The bridge is already live in shipped code, so a refusal cohort cannot be observed by simply
running the app: refusals that the bridge recovers never appear as refusals. The run therefore
takes two passes over the same Works.

1. **Pass 1 — bridge off.** `MALEntityResolver.noBridge` injected via a `#if DEBUG` environment
   switch. Drain to quiescence. The refusals recorded in `upgrade-attempts.json` **are the
   cohort**, and the cohort is closed at the end of this pass.
2. **Delete `upgrade-attempts.json`.** A pass-1 `.unmatched(knownTitlesCount:)` record suppresses
   re-attempt for the full 14-day TTL while the title count is unchanged, so pass 2 would never
   reach the bridge. Deleting is legitimate rather than a workaround: ADR-0007's delete test is the
   reason this file lives apart from `works.json` — "delete it and lose nothing but time."
   **Nothing else is touched.** `works.json` carries over untouched, so pass 2 runs on the same
   Works, with the same `knownTitles`, in the same state.
3. **Pass 2 — bridge on**, default wiring. Drain to quiescence.
4. **Compare.** A pass-1 refusal that now carries `externalIds.mal` is a recovery.

### Seeding

The 80 Works are planted directly into `works.json` in the shape `LibraryStore.toggle` →
`WorkStore.mint(from:)` produces for a WeebCentral listing:
`{id, listings: [{sourceId: "weebcentral", mangaId: <real ULID>}], externalIds: {}, displayTitle,
knownTitles: [<the one real title>]}`.

**Why planting is honest here and was not for ADR-0018.** The previous session refused to plant,
because what it was verifying *was* the minting path — planting would have proved the guard in a
state the app cannot produce. Here the subject is the resolver and the bridge, which consume a Work
and never see how it was minted. WeebCentral publishes no alt titles, so a minted Work carries
exactly one `knownTitles` entry; the planted shape is therefore not an approximation of the real
one, it is the same. **This is checked, not asserted**: one title from the cohort is minted through
the real UI path (`Add to Library`) and its stored entry diffed against a planted one before pass 1
begins. If they differ in any field the resolver reads, the run stops and the seeding is redone
through the UI.

Real ULIDs and real titles are used — both scraped live from the listing above — so the Works are
openable in the app and the bridge is searching the strings WeebCentral actually publishes.

### The gate

Pass 2 logs every bridge query title to a file (`#if DEBUG`, same switch). The gate holds if no
MangaDex-sourced Work's title appears in that log while WeebCentral titles do.

**Stated in advance, because it may not be observable:** the gate only *has* something to refuse if
some MangaDex-sourced Work in the library reaches the bridge decision point — that is, misses on
MAL. ADR-0017's novel filter removed most MangaDex refusals, so there may be none. If no
MangaDex-sourced Work misses on MAL during pass 2, **this leg is reported as not observed, and is
not substituted with a weaker one.** It is not evidence of the gate working that nothing was
refused when nothing asked.

## Failure conditions, registered

- **Fewer than 10 refusals in pass 1** → the cohort is too small; report that and do not run the
  comparison as if the floor were met.
- **Zero recoveries on ≥10 refusals** → **the mechanism is falsified.** That is the outcome this
  protocol exists to make possible, and it gets written up as such rather than explained away.
- **Any recovered id wrong on hand-check** → the 0-wrong half fails, independently of the count.

## Hand-checking

Each recovered id is checked by opening `myanimelist.net/manga/<id>` and confirming the series
matches the WeebCentral title — against the series, not against MangaDex, since MangaDex's
`links.mal` is what produced the id and cannot also confirm it.
