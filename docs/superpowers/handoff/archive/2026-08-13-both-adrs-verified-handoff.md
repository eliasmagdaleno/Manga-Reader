# Session Handoff — 2026-08-13 (evening): ADR-0018 and ADR-0019 both verified in full

**Audience:** the next session. Supersedes `2026-08-13-adr-0018-decision-1-verified-gate-leg-next-handoff.md`
(written mid-session; its "Next" section was completed before the session ended) and
`2026-08-11-adr-0019-amendment-1-verified-handoff.md` (both of its open items are done).

## State

| | |
|---|---|
| `main` | **`7f434b8`**. PR #48 and **PR #49** both merged today, CI green on the head commit of each. |
| Branches | none open |
| Tests | **468**, 467 passed, 1 skipped, 0 failures |
| ADRs | **0018 verified in full** (Hazard 3 closed); **0019 verified in full** (gate leg closed) |
| Instrument | `VerificationSwitches.swift` **deleted** per its own deadline |
| Sim `2A0D54DF-…` | 107 Works, 20 refused, 19 history entries, `upgrade-attempts.json` edited by hand (declared — see below) |

**There is no deadlined work outstanding.** The one dated item is a cleanup, not a task: see
"The expiry" below.

## What closed today

### ADR-0018 Decision 1 — history carries the id its source published

`docs/superpowers/specs/2026-08-13-adr-0018-decision-1-verified.md`, protocol registered first.

| Leg | Route | Observed |
|---|---|---|
| A | Berserk from Search | `malId: 2` |
| B | Othello, WeebCentral | `malId: null`, Work still refused |
| C | Berserk resumed from History | 3 **new** entry UUIDs, all `malId: 2` |

The seeded pre-0018 Berserk entry survives beneath the new ones under the same `mangaId`, still
`malId: null` — the before/after is on disk, not asserted.

**Decision 2 is still unverified and is not verifiable this way.** A wrong `links.mal` becoming a
confidently wrong answer is Hazard 1, accepted by name.

### ADR-0019 — the gate observed refusing

`docs/superpowers/specs/2026-08-13-adr-0019-gate-verified.md`. One drain, both refused, one second
apart:

| Work | Listing | Outcome | Bridge queries |
|---|---|---|---|
| Dyo Adélfia | `mangadex` | `.unmatched(1)` | **0** |
| Koi Inu (control) | `weebcentral` | `.unmatched(7)` | **3** |

Identical outcomes; only one asked MangaDex. The control also grew 1 → 7 known titles, so the bridge
was working rather than merely reached.

## The three findings worth carrying, in order of how much they will cost you

**1. Absence from MAL's `q=` search is not absence from MAL.** The gate run's first attempt failed
because its control resolved — MAL holds an entry titled exactly `Guyabano Holiday` that its own
search does not return for that string. **No fixture can be established as a MAL miss by looking at
`q=` results.** Use Works this app has already refused; those are misses measured by the same
matcher. Related: a MAL request sent **without a client id** returns a body with no `data` key, which
a naive script reports as "no results" — i.e. as a confirmed miss. Assert `data` is present.
`Secrets.xcconfig` is at the **repo root**.

**2. A silent instrument proves nothing without a control that is proven to speak.** That first
attempt produced an empty bridge log — which looks exactly like "the gate refused." It wasn't: the
subject had been attempted during *seeding*, before logging was enabled, and its refusal then
TTL-suppressed it, so the logged drain asked nothing at all. Both fixtures silent, log empty, and a
clean believable pass available for the taking. The control is what makes silence mean something.

**3. Verification-by-plist beats verification-by-UI when the field is never rendered.** `ReadingEntry.malId`
appears nowhere on screen, so the UI tests only *drive*; the evidence is
`history.entries` in the app's `UserDefaults` plist. Two mechanics that will bite: the sim's **data
container UUID changes on every install** (resolve by newest mtime — a pinned path threw a
`FileNotFoundError` that looked like wiped fixtures), and `HistoryStore` flushes on `.background`, so
**every test must press home** or it loses its own evidence.

## Sim state, including one hand edit

The sim is not pristine and the next run should know exactly how:

- **`upgrade-attempts.json` was hand-edited** — two entries removed (`Dyo Adélfia`, `Koi Inu`) to
  lift TTL suppression so both would re-attempt under logging. Declared in the protocol *before* it
  was done; it lifts suppression only and touches neither `works.json`, the resolver, nor the gate.
  Backup of the pre-edit file: **scratchpad only, gone with the session.**
- **`Othello` was deliberately left alone** — it is ADR-0018 leg B's fixture.
- `Guyabano Holiday` sits in the library resolved (`mal: 121435`). It is not a control and is not
  counted as one.
- Library now holds `Dyo Adélfia`, `Guyabano Holiday`, `Junjou Romantica`, `Wind Breaker`.

## The expiry — the only dated item

The **five UI tests added today are instruments, not CI tests**: pinned to this sim and to live
network. Their WeebCentral fixtures age out with the 14-day TTL **on or about 2026-08-25**, after
which they fail for fixture reasons rather than logic ones.

Decide before then whether they are deleted or re-pointed. This was raised as an open review question
on PR #49 rather than decided unilaterally. `testADR0018Decision1MangaDexReadWritesThePublishedId`
(leg A) is the one that does **not** expire — its fixture is Berserk.

## Also open, unchanged and undated

- **More Like This reverse resolution beyond MangaDex-only.** More Works resolve now; reverse
  resolution is what turns a resolved Work back into something openable.
- No automated coverage of `HomeView`'s rail branch or `MangaDetailView`'s notice branch — still
  deliberate, reasoning in `AppCompositionTests`' header.
- Extension/repo system and comix.to shelved since 2026-07-21.
- `project.pbxproj` churned on its own twice today with no `xcp` involved, and was reverted both
  times. Check `git diff --stat` before every `git add`, as CLAUDE.md says.
- **`MAL_CLIENT_ID` was printed into this session's transcript** while chasing finding 1. Nothing was
  committed or transmitted; rotating it is cheap.
