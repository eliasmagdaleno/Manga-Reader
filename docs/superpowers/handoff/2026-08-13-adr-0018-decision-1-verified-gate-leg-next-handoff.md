# Session Handoff — 2026-08-13: ADR-0018 and ADR-0019 both fully verified

**Updated later the same session — the gate leg below is now DONE.** See
`docs/superpowers/specs/2026-08-13-adr-0019-gate-verified.md`: `Dyo Adélfia` (MangaDex, no
`links.mal`) was refused with **0** bridge queries while the control `Koi Inu` was refused after
**3**, one second apart in the same drain. `VerificationSwitches.swift` is deleted per its deadline.
The first attempt failed — the intended control resolved on MAL, because **absence from MAL's `q=`
search is not absence from MAL** — and that is the most reusable finding here. PR #49 carries both
legs. Everything below is the state as of mid-session; its "Next" section is now history.

## (original) ADR-0018 fully verified, the ADR-0019 gate leg is next

**Audience:** the next session. Supersedes `2026-08-11-adr-0019-amendment-1-verified-handoff.md` —
its items 1 and 2 are the only live work, and **item 2 is now done**.

## State

| | |
|---|---|
| `main` | PR #48 **merged** (`8294963`). CI was still running when this session started, not green as that handoff's table claimed — it passed, then merged. |
| Branch | **`adr-0018-decision-1-run`**, pushed — **[PR #49](https://github.com/eliasmagdaleno/Manga-Reader/pull/49) open**, CI not yet checked. Two commits: protocol (`45d540d`), then run (`cce2eb0`). |
| Tests | **468**, 467 passed, 1 skipped, 0 failures — unchanged |
| ADRs | 0018 Hazard 3 **fully closed**; 0019's gate leg still **not observed** |
| Sim | `2A0D54DF-…`, history now **19 entries**, works/attempts untouched |

**First thing to do: check PR #49's CI and merge it.** Nothing below depends on it.

## Done this session — ADR-0018 Decision 1, verified in the app

Write-up: `docs/superpowers/specs/2026-08-13-adr-0018-decision-1-verified.md`. Protocol, registered
before the run: `docs/superpowers/specs/2026-08-13-adr-0018-decision-1-run-protocol.md`.

Three UI-test instruments, run A→B→C one at a time, all three predictions held:

| Leg | Route | Observed |
|---|---|---|
| A | Berserk from Search | `malId: 2` on the new entry |
| B | Othello, WeebCentral | `malId: null`, Work still `externalIds: {}` and refused |
| C | Berserk resumed from History | 3 **new** entry UUIDs, all `malId: 2` |

**Two things worth carrying forward:**

- **The three-session block was misdiagnosed.** The leg never needed a re-readable *refused* Work —
  it needed a re-readable Work whose *source publishes an id*. Berserk qualified the whole time. The
  WeebCentral seeding only unblocked leg B, the half that verifies nothing anyone doubted.
- **Leg C needed leg B between it and leg A.** `record` updates the newest entry in place when manga
  and chapter match, so Berserk had to be displaced or `malId` survives because nothing touched it.
  The check is on the entry UUID being new, not on the value.

## Next — ADR-0019's gate leg (the one real open item)

**The gate has never been observed refusing.** Amendment 1 asked for it; the run could not deliver
because every MangaDex-sourced Work in the library already carried a `mal` id, so `resolve` returned
at its first line and nothing reached `isBridgeable` (`MALEntityResolver.swift:163`).

**What it needs:** a **MangaDex-sourced Work with no `links.mal` that MAL also misses**. Then, in one
drain with `ADR0019_BRIDGE_LOG=<path>` set, that Work's titles must appear **zero** times in the log
while a non-MangaDex control's titles do appear. Logging the *request* is the point — both
configurations return nil, so only the query distinguishes "declined to ask" from "asked and found
nothing". `VerificationSwitches.swift` is the instrument and is already in the tree.

### Fixture-finding got this far

**The MangaDex side is solved.** ~36 of 60 recent MangaDex titles carry no `links.mal`, so candidates
are plentiful. Verified against the MAL v2 API that these return only unrelated fuzzy hits, which the
precision-biased matcher should refuse:

| Candidate | MangaDex id | MAL's nearest hits |
|---|---|---|
| **Dyo Adélfia** (preferred) | `347c8a31-7d0b-4250-b240-4aa7e2fd72f1` | Adelaide, Boku no Adelia, Selfish Romance |
| Waka World I: Beginning | `40dde950-00ba-4df3-9551-e0616d4578e9` | Green Worldz, L Change the WorLd |
| Illushia. | `5d043940-2ea1-43f5-b9af-be4c3a5a710f` | Mushishi, /Blush-DC |

Reach it by `Add to Library` from Search — no chapters needed; `LibraryStore.toggle` mints the Work.
Beware the accent in `Adélfia` when typing the query; search `Dyo` and pick the result.

**The control is the unsolved half.** It must be a **non-MangaDex Work that actually issues a bridge
query in the same drain**, and that is harder than it sounds:

- The sim's 17 refused WeebCentral Works are **TTL-suppressed until ~2026-08-25** (`checkedAt`
  ~08-11), so they will not re-attempt and will log nothing.
- A *fresh* WeebCentral title only reaches the bridge if MAL misses it too — if MAL matches, it
  resolves with no query and is not a control at all. So the control needs the same MAL-miss check
  the MangaDex fixture got.
- The alternative — surgically deleting **one** entry from `upgrade-attempts.json` to reopen a
  known-refused WeebCentral Work — is viable and cheaper, but it is hand-editing the app's store
  mid-run. **If you do it, declare it in the protocol and do not pick Othello** (that is leg B's
  fixture, still needed if PR #49's run is ever re-examined).

Register the protocol **before** touching the sim, as the last two runs did. The ordering of commits
is the evidence.

## Gotchas found this session

- **The sim's data container UUID changes on every install.** Resolve it by newest mtime; a pinned
  path threw a `FileNotFoundError` mid-run that looked briefly like the seeded fixtures had been
  wiped. They had not. Helper pattern: glob
  `.../Data/Application/*/Library/Preferences/Elias-Magdaleno.Manga-Reader.plist`, take newest.
- **History lives in `UserDefaults`, not a JSON file** — key `history.entries`, in the app's
  `Elias-Magdaleno.Manga-Reader.plist`. `works.json` / `upgrade-attempts.json` are in
  `Library/Application Support`.
- **A MAL API call with an empty client id returns a body with no `data` key**, which a naive script
  reports as "no results" — i.e. as a *confirmed miss*. That is a fixture-selection result that is
  clean, believable and entirely wrong. Assert on the presence of `data`, not on its emptiness.
  `Secrets.xcconfig` is at the **repo root**, not under `Manga-Reader/`.
- **`MAL_CLIENT_ID` was printed to the 2026-08-13 session transcript** while chasing the above.
  Nothing was committed or sent anywhere, but rotating it is cheap.
- `project.pbxproj` churned on its own again right after the #48 merge and was reverted. As always.

## Also open, unchanged

- **`VerificationSwitches.swift`** — delete once the gate leg is verified, or at ~**2026-08-23**
  regardless. It is a measuring instrument with no product meaning.
- **The three new UI tests carry the same debt shape** — instruments pinned to the seeded sim and
  live network; leg B's fixture expires ~2026-08-23. Raised as a review question on PR #49 rather
  than decided.
- More Like This reverse resolution beyond MangaDex-only; no automated coverage of `HomeView`'s rail
  branch or `MangaDetailView`'s notice branch; extension/repo system and comix.to shelved since
  2026-07-21.
