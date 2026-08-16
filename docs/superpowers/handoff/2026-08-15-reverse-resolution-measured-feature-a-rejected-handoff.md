# Session Handoff — 2026-08-15: reverse resolution measured, feature A rejected

**Audience:** the next session. Supersedes
`2026-08-13-reverse-resolution-measurement-protocol-handoff.md`, whose only queued item — the
registered-but-unrun measurement — is now run and written up.

## State

| | |
|---|---|
| `main` | **`7595e4c`**. PR #52 merged, both checks green (build+unit 3m24s, SwiftLint 16s) |
| Branches | none open; `reverse-resolution-measurement-protocol` deleted on merge |
| Tests | 468 unit, unchanged — **no app code was touched this session** |
| ADRs | 0018 and 0019 both verified, unchanged. No new ADR written |
| Next work | a **second measurement**, registered from scratch. Nothing is deadlined |

## What closed

### Feature A — recall via a WeebCentral fallback — is rejected

Write-up: `docs/superpowers/specs/2026-08-15-reverse-resolution-beyond-mangadex-measured.md`.
Harness: `scripts/reverse_reach.py`. Raw data: `docs/superpowers/measurements/reverse-reach/`.

**The pre-registered gates never resolved.** Easy produced 42 picks against a floor of 80; Hard
produced 10 recommendations against a floor of 100. Both fall under the inconclusive clause the
protocol declared in advance. The Easy precision figure of 0.976 **is not a pass** — it is a
number taken on half the required sample, and the write-up says so in those words. Do not let a
later reading promote it.

**The feature died on a ceiling instead.** Of the 107 recommendation slots the entire library
produces, MangaDex already resolves 90. A perfect matcher recovering every Hard row adds **10
cards**, against a scraped-source round trip on every detail-page open — and this run already
recovered 6 of them. The 90:10 ratio rests on n=100 and is the most solid number the run produced,
despite not being one of the gates.

Two facts make that ceiling generous, and both belong in any reopening argument:

- **Hard means "MangaDex returned no confident candidate", which is not "MangaDex lacks it."** Two
  of the ten are *Blade of the Immortal* and *Rurouni Kenshin*, which MangaDex plainly carries;
  they are Hard because `searchManga(limit: 20)` did not surface a `links.mal` match in 20 results.
  The real catalogue gap is smaller than 10, and some of those cards are better won by fixing the
  MangaDex query than by adding a source.
- **49 of 86 seeds return no MAL recommendations at all.** The rail is empty for 57% of the library
  no matter how many sources exist. That is the larger hole and it is not a sources problem.

**Feature B (affinity) is untouched and still unmeasured.** It was split off deliberately in the
protocol; its population is every card rather than the 10 misses, so the ceiling argument that
killed A does **not** transfer to it. Anyone picking B up starts from the protocol's framing, not
from this rejection.

**The 30 adjudication pairs were never spent.** Stage A never opened, and there were only six Hard
picks to sample. The user's agreement to eyeball 30 pairs is still available.

## What is queued

### The matcher is reading one title when it could read five

This is the session's most valuable finding and it is **post-hoc — a question, not a result.** It
is recorded in the write-up's final section with that label, and it must keep it.

The protocol inherited ADR-0019's diagnosis that WeebCentral's failures are **reach** failures,
spellings search cannot find. **In this direction that is wrong, and the evidence is direct:**

| Searched with MAL's primary title | WeebCentral returns |
|---|---|
| `Shingeki no Kyojin` | Attack on Titan |
| `Mugen no Juunin` | Blade of the Immortal |
| `Otoyomegatari` | A Bride's Story |

Search reached every one. The **matcher** then compared MAL's romaji against WeebCentral's English
display title — similarity **0.222** for the first — and refused. The two sources name the same
work in different languages and `pickMatch` sees one title from each side.

Re-running the matcher offline with MAL's `allTitles` against the same candidates: Easy picks go
**41 → 55** with precision holding at **54/55**; Hard goes 6 → 7. That is +34% recall at no
measurable precision cost, on 97 of the 100 rows (3 MAL ids answer 307 and were skipped).

**Why this matters beyond the rejected feature:** the single-title input is a documented parked
residual in `MALReverseResolver.resolve(works:limit:)`, and **ADR-0019's bridge already runs this
matcher against a source with no external ids**, where the fuzzy arm is the only arm. If the gain
holds there it is a recall improvement on a path already shipped.

**Why it is not actionable yet**, all three reasons, none of them optional:

1. Post-hoc, on data gathered to answer a different question.
2. Graded by the strict-label method, which the Easy artifact already proved conservative — a wrong
   pick can hide behind a missing MangaDex spelling.
3. Widening the source side raises the false-match rate in general (ADR-0008's whole reason for the
   ambiguity guard). A 55-pick sample cannot speak to that risk.

**The next task is a registered protocol for the matcher's input width, on ADR-0019's actual path,
with adjudicated labels.** The 30 unspent pairs are the obvious budget. Register before measuring,
as before.

## Things that will cost you time if rediscovered

Four are baked into `scripts/reverse_reach.py` as aborts rather than comments, but know them:

1. **WeebCentral publishes an explicit "No results found" alert.** This is what makes pick /
   refusal / search-failure *positively* decidable rather than inferred from an empty body. Anything
   matching neither results nor that alert aborts.
2. **Result items are `article.flex.gap-4` and each contains two further `<article>` cover blocks.**
   Matching to the next `</article>` truncates every item before its title link and yields zero
   candidates — silently, and looking exactly like a site redesign. Items are delimited by the next
   matching *start* tag.
3. **Python's `str.isalnum()` is true for CJK.** A hand-rolled "keep alphanumerics" encoder put raw
   multibyte on the wire and MangaDex answered 400 — on precisely the Japanese-titled
   recommendations the measurement most needed. Percent-encode UTF-8 bytes.
4. **MAL answers 307 on some merged ids, and following the redirect hangs.** The harness aborts
   loudly, which is correct, but a long run can die 90 rows in.

**WeebCentral answered plain `curl` with the pinned UA for the whole run — 0 search failures in 100
searches, no challenge.** That was true on 2026-08-13 and still true 2026-08-15. It can stop at any
time and does not degrade gracefully; the fallback remains driving it in-app.

## Also open

- **`MAL_CLIENT_ID` was rotated this session — but the rotation is unconfirmed.** A new key is in
  `Secrets.xcconfig` (gitignored, verified live against `/manga/2`). The old key was overwritten
  before it could be tested, so **whether the old app entry was actually deleted at
  myanimelist.net/apiconfig is unverified**. If it was not, the old key is still live and the debt
  is not paid. MAL has no visible "regenerate" action; the path is create-new-then-delete-old.
- **The new key was pasted into the session transcript**, which is the same exposure that created
  the original rotation debt on 2026-08-12. It is a public client identifier, not a secret — the
  cost is rate-limit consumption, not account access — but if the transcript matters, rotate once
  more and enter the value via an editor or `!` prefix rather than chat.
- **The squash merge collapsed the pre-registration evidence.** Both the protocol and the write-up
  cite commit order as proof the protocol predates the numbers. On `main` that is now one commit;
  the ordering survives in PR #52's commit list (`d513410`, pushed 2026-08-14). For future
  measurement branches, a merge commit preserves it directly in `main`.
- **No agy review exists for `7595e4c`.** The hook fires on local commits and this landed via
  GitHub's squash, so no review file was produced. Nothing is stuck.
- ADR-0018 **Decision 2** remains unverified and is not verifiable through the app (Hazard 1,
  accepted by name).
- No automated coverage of `HomeView`'s rail branch or `MangaDetailView`'s notice branch —
  deliberate, reasoning in `AppCompositionTests`' header.
- Extension/repo system and comix.to shelved since 2026-07-21.

## Sim state

**Unchanged.** Nothing was built, run, or driven in the simulator this session — the whole
measurement ran in Python against live APIs. History remains at 25 entries with the Junjou
Romantica entry from 2026-08-13; `upgrade-attempts.json` still carries its declared hand edit;
`Othello` untouched. `works.json` was **read** for seeds (107 Works, 86 with a MAL id) and not
written.
