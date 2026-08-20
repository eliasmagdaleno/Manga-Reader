# ADR-0020 in the app — the enriched draw recovers, and claim 4 still does not bind

**Runs [Protocol Amendment 1](../plans/2026-08-19-adr-0020-in-app-run-protocol-amendment-1.md)**,
registered in its own commit (`b95c861`) before this launch, over the base protocol
`2026-08-19-adr-0020-in-app-run-protocol.md`. Raw log:
`docs/superpowers/measurements/adr0020-in-app/run3-enriched.log`.

**Verdict: claims 1, 2, 3, 5, 6 and 7 met; claim 4 not met.** Fourteen targets that missed on
their first spelling recovered on a widened query, in the app, on live network, through the real
UI. The N = 3 cap did not bind — every widened row recovered at query 2 — so the one claim run 1
failed on a thin fixture is now failing on a fixture that is not thin.

## Claims

| # | Registered claim | Outcome |
|---|---|---|
| 1 | ≥ 5 targets `baseline-unresolved` | **Met — 14** |
| 2 | ≥ 1 recovers through a widened query | **Met — 14 of 14** |
| 3 | Full chain observed end to end | **Met in the log** — every recovery carries the MangaDex id it resolved to. Not confirmed *visually*; see "The screenshots do not show the cards" |
| 4 | N = 3 bound observed **binding** (a target with ≥ 4 spellings issuing exactly 3 searches) | **Not met** — no such row. Five targets carried ≥ 4 spellings and all five recovered at query 2 |
| 5 | Every recovery classified by arm; fuzzy recoveries hand-checked | **Met** — all 14 recoveries are `exact`; the run's only two `fuzzy` rows are baseline resolutions, hand-checked below |
| 6 | No post-hoc seed swaps | **Honoured** — the seed array is unchanged since `268a286`, committed before launch |
| 7 | All 15 targets reported | **Met** — 14 recovered, 1 never observed, named below |

## The frame

Asserted before anything was computed from it.

| | |
|---|---|
| Seeds opened | **13 of 13** — one screenshot attachment per seed |
| Rows | **72** |
| Unique MAL ids | **72** — no double-count |
| Outcomes | 58 `baseline-resolved`, **14 `recovered`**, 0 `unresolved` |
| Arms | 70 `exact`, 2 `fuzzy` — zero fuzzy *recoveries* |
| Rows spending the MAL arm's extra request | **14** — exactly the rows that missed |
| Searches per row | 58 × 1, 13 × 2, 1 × 3 |

**The log file is cumulative and was not cleared.** The container carried run 1's 19 ids, so the
raw file on the simulator held 91 lines. The 72 above are the file minus run 1's id set; the
`unresolved` Katanagatari row belongs to run 1 and is not counted here. Run 1's ids being resident
also means any of those 19 recurring under a run-2 seed would be served from cache and log nothing
— none of the 15 amendment targets is in that set, so the claim rows are unaffected.

`fetchedTitles: true` on exactly the 14 widened rows and on no other row is Decision 2's
"paid by rows that missed" rule, observed a second time and now at n = 14.

## Every target, against the amendment's table (claim 7)

| target | MAL | spellings | searched | outcome |
|---|---|---|---|---|
| Mugen no Juunin | 658 | 4 | 2 | recovered @ 2 |
| Red | 12713 | 3 | 3 | **recovered @ 3** |
| Kindaichi Shounen no Jikenbo | 393 | 4 | 2 | recovered @ 2 |
| Q.E.D. | 3153 | 5 | 2 | recovered @ 2 |
| X | 27 | 2 | 2 | recovered @ 2 |
| Futago | 16732 | 4 | 2 | recovered @ 2 |
| The One | 3715 | 2 | 2 | recovered @ 2 |
| Shinseiki Evangelion | 698 | 3 | 2 | recovered @ 2 |
| Blood+ | 747 | 2 | 2 | recovered @ 2 |
| Kaikan♥Phrase | 678 | 4 | 2 | recovered @ 2 |
| Cosplay★Animal | 5734 | 6 | 2 | recovered @ 2 |
| Otoko no Isshou | 21659 | 4 | 2 | recovered @ 2 |
| Ahiru no Ouji-sama | 714 | 3 | 2 | recovered @ 2 |
| Love♥Monster | 1237 | 2 | 2 | recovered @ 2 |
| **Teppen!** | **10776** | — | — | **never observed** |

Fifteen rows, fourteen recoveries, no losses. Every one of the fourteen came back through the
`exact`-`malId` arm, which is the strong form: the widened query returned a MangaDex entry whose
own `links.mal` equals the target, so no fuzzy judgement was involved in any recovery.

**Teppen! (10776) never appeared.** Its seed, *Never Give Up!*, opened and its other target
(*The One*, 3715) recovered from that page — so this is not a seed failure. The target left the
top 8 between the pre-check and the run, or fell outside the slice
`MoreLikeThisProvider.topRecommendations` takes. Per claim 7 it is reported as never observed, not
as a loss and not dropped from the denominator.

### The two fuzzy rows, hand-checked (claim 5)

Both are baseline resolutions on the first spelling, not recoveries:

- MAL 22 *Rurouni Kenshin: Meiji Kenkaku Romantan* → `754a46fa-…` — correct.
- MAL 86769 *Kusuriya no Hitorigoto* → `e18fe8c6-…` — correct.

Neither needed adjudication under claim 5, which governs fuzzy *recoveries*; there were none.

## Why claim 4 still fails, and why that is worth saying

The amendment picked five targets carrying ≥ 4 spellings precisely so a third search could be
observed stopping at the cap. All five recovered on their **second** spelling. The single 3-search
row, *Red*, holds exactly three spellings — the same shape as run 1's Katanagatari, and the same
reason it does not count: it spent everything it had rather than being stopped at N = 3.

This is not a defect in the fixture. It is a finding: **when MAL's English or Japanese title finds
the MangaDex entry at all, it finds it immediately.** The distribution is concentrated at query 2,
which is also why the offline cost figure of 3.09 requests is an upper bound in practice rather
than a typical case. A row that reaches a third search and recovers appears to be rare enough that
a 13-seed enriched draw does not contain one.

Claim 4 asks for the cap to be observed *binding* — a ≥ 4-spelling target searching three times and
stopping. Nothing here shows that, and the unit test that covers the truncation rule is not a
substitute for it in this protocol. It is reported not met.

## The screenshots do not show the cards

Thirteen screenshots were attached, one per seed, and **none of them show the More Like This rail**.
The scroll loop exits as soon as `app.staticTexts["More Like This"].exists` is true, and XCUITest
reports a lazily-built element as existing while it is still below the fold — both inspected shots
(*Vagabond*, *Kimi wa Pet*) are framed at the top of the detail page, with the rail's header just
appearing behind the tab bar in the second.

So claim 3's resolution half is fully evidenced by the log — 14 recovered rows each carrying the
MangaDex id the widened query returned — and its *visual* half is not evidenced at all. The fix, if
a future run wants the picture, is to scroll until the rail's first cell is `isHittable` rather than
until its header `exists`.

## What this run does not show

Restated from the amendment, before anyone reads a rate out of the table above: this cohort was
**assembled from rows a previous offline measurement already scored as baseline-unresolved**. The
14/14 recovery figure describes the cohort and nothing else. It is not a recovery rate for the wild,
and the offline 3.09 remains the only cost figure.

What it shows is mechanism, which is what Decision 5 asks for: the widening in `MALReverseResolver`
fires in the shipped app, on live network, through the real UI, spends its extra request only on
rows that missed, and turns rows that genuinely miss into resolved MangaDex entries.

## Afterwards — what replaced the instrument

With the run written up, `VerificationSwitches` and the `trace` calls inside
`MALReverseResolver.searchWidening` are **deleted**, as that file's own header always said they
would be. Nothing measures the path from inside the type any more.

What stands in their place is `testADR0020WidenedCardsAppearInTheRail`, which asserts the
user-visible half the log could not: that the fourteen recovered targets appear as **cards** in
their seeds' rails, by MangaDex display title. Its scroll loop waits for the rail to be *hittable*
rather than merely to `exist`, which is the fix for this run's screenshot gap — the attachments now
show the rail.

Its floors are deliberately below 100%: ≥ 10 of 13 rails brought on screen, ≥ 10 of 14 cards found.
MAL's recommendation ordering shifts under the app, and a title with hundreds of chapters can
outrun the scroll budget before the rail is reached — *Never Give Up* does, which is why reaching a
rail is scored separately from opening a detail page. Neither condition says anything about
widening, and neither should redden a build.
