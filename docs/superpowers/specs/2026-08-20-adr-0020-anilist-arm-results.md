# Results — ADR-0020 in the app (AniList arm)

Run 2026-08-20 against the protocol registered in
[`2026-08-20-adr-0020-anilist-arm-protocol.md`](2026-08-20-adr-0020-anilist-arm-protocol.md)
(commit `17c9140`, before any instrumented launch).

Raw data: [`../measurements/adr0020-anilist-arm/`](../measurements/adr0020-anilist-arm/) —
`reverse.log` (42 rows), the pool record the run built, and the rail screenshot.

## Verdict in one line

**The AniList arm's floor was not met and the arm stays under-observed — but not because the
fixture is thin.** The pool's targets were resolved, within the same session, by the MAL arm
through the shared reverse cache before the pool ever reached `searchWidening`. Two of twelve
pool targets entered the widening path at all. Meanwhile the run **closed ADR-0020's one open
claim**: the N = 3 bound was observed binding.

## Frame, reconciled before anything is computed (claim 1)

| | |
|---|---|
| Log rows | 42 |
| Distinct `malId` targets | 36 (6 targets logged twice or more — concurrent resolution of the same id) |
| Pool candidates built this run | 12, all resolved |
| Pool targets that produced a trace row | **2** (`436` Uzumaki, `149` BLAME!) |
| Rows holding >= 2 spellings — the only ones that *can* widen | 4 |
| Rows with `fetchedTitles: true` (MAL arm's extra request) | 2 |

**Where the other ten pool targets went.** They were already in `EntityResolutionStore`'s
reverse cache by the time the pool asked, put there by the MAL arm earlier in the same
session. The tell is the spelling count: a pool target is built from `AniListWork.knownTitles`
(romaji + english + native + synonyms) and carries several, while every one of those ten
appears in the log with **exactly one** spelling — the MAL-arm shape, since MAL's nested
recommendation nodes carry a single title. Berserk (`mal=2`) appears four times, all
single-spelling.

Both consumers share one `MALReverseResolver` by construction (`AppComposition` builds one and
hands it to both), and both feed the same For You rail, so the overlap is not a coincidence of
this fixture: the pool and MAL recommendations are drawn from the same taste, so they *ask about
the same popular titles*, and whichever asks first pays. This run, the MAL arm asked first.

That is a finding about the arm, not an instrument failure, so the numbers below stand — but
they describe **2 observed AniList targets**, and nothing here is a rate.

## Against the registered claims

**1. Frame asserted first — met.** Reconciled above, including the shortfall's cause.

**2. >= 5 baseline-unresolved on this arm — NOT MET.** Two AniList-attributable targets, of
which **one** missed on its first spelling. Per the protocol this is reported as an
**inadequate observation of the arm**, not as a failure of the ADR. It is not retried by
redrawing the fixture, which would be selecting on the outcome.

**3. >= 1 recovery — observed, but its gate is unmet.** The one AniList target that missed
baseline recovered: `mal=149`, **BLAME!**, five spellings held, two searches issued, recovered
at query 2 through the exact-`malId` arm. Three recoveries occurred across the whole log.

**4. Full chain end to end, card on screen — met, on a MAL-arm row.** `mal=658`, *Mugen no
Juunin*: baseline search on the romaji title missed, query 2 went out as **"Blade of the
Immortal"**, a candidate publishing `mal=658` came back, it was recorded resolved — and the
card is **first in the For You rail** in `for-you-rail.png`, captioned "Because you read
Vagabond". This is ADR-0020's own motivating example, recovered and rendered.

The AniList arm's own recovery (BLAME!) is evidenced **in the log only**. It is in the pool
record the run built, but the rail scrolls horizontally and the screenshot does not show it, so
the visual half is claimed for the MAL arm and not for this one.

**5. The N = 3 bound — MET, binding.** `mal=38`, **+Anima**: four spellings held
(`+Anima`, `+ANIMA`, `Plus Anima`, `Parallel +Anima`), **exactly three searches issued**,
recovered at query 3. This is the shape both MAL runs looked for and did not find: a target
that held more spellings than the cap allowed, was stopped at three, and still recovered — not
a target that merely spent what it had. It is a MAL-arm row, and it satisfies ADR-0020's own
revisit trigger, *"if a widened row is ever seen recovering at query 3 in the wild"*.

**6. Precision, by arm.** All three recoveries came back through the exact-`malId` arm, so
their correctness is **structural under Decision 4 and is not evidence** — as the protocol says
in advance. Exactly one **baseline fuzzy** resolution occurred, the only kind that can be
wrong:

- `mal=22` (Rurouni Kenshin) → MangaDex `754a46fa-62fa-457a-bc3b-4f31bf1373d4`. Hand-checked:
  that entry is titled *Rurouni Kenshin: Meiji Kenkaku Romantan*, year 1994, which is the same
  series. **It publishes no `links.mal`**, so the check rests on title-and-year identity rather
  than on an authoritative id. Recorded as correct, and recorded as unconfirmable the strong way.

## What blocked the first two attempts, and why it matters beyond this run

The first two launches produced an **empty log** with a fully built pool. The cause was the
reverse cache: `entityResolution.reverseCache` held **107 entries** in the app's defaults,
survivors of earlier sessions, so every target was answered without a search. ADR-0020
Decision 3 anticipates this exactly — *"a seeded sim whose reverse cache is already full of
narrow misses — clear the cache in the fixture, which is a test-fixture problem and not an app
one"* — and clearing it is what produced the run above.

**The seeding tool should be doing that.** `SimulatorSeed` clears the three keys it writes and
nothing else, so a re-seeded fixture inherits whatever resolution answers the container already
had. A fixture that silently disables the path under test is worse than an empty one. Fixed
separately from this run, since changing the fixture mid-protocol is exactly what the
registration discipline exists to prevent.

A third trap, unrelated but worth recording: `xcrun simctl get_app_container booted` resolves
against **whichever** device is booted. An `iPhone 17 Pro` had been booted by Xcode, so the
first inspection read an unseeded container from a different device entirely.

## What this run does not decide

- **The AniList arm's recovery behaviour at any scale.** Two targets. The arm's *code path* is
  the one the MAL arm already discharged; what stays unobserved is how often the pool reaches
  it in the wild — and this run suggests the answer is "less often than the pool's size
  implies", because the MAL arm resolves the overlap first.
- **Cost.** This arm spends no `mangaDetail` by construction; the two `fetchedTitles: true`
  rows are both MAL-arm rows, which is the expected reading and not a rate-limit tell here.
