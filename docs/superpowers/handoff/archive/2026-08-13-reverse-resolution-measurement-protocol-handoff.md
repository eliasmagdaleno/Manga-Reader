# Session Handoff — 2026-08-13 (late): UI-test expiry closed, reverse-resolution measurement registered

**Audience:** the next session. Supersedes `2026-08-13-both-adrs-verified-handoff.md`, whose one
dated item is now closed.

## State

| | |
|---|---|
| `main` | **`1f14a50`**. PRs #50 and **#51** both merged, CI green on each |
| Branches | none open |
| Tests | 468 unit (467 passed, 1 skipped); **2** UI instruments remain, neither expiring |
| ADRs | 0018 and 0019 both verified in full — unchanged |
| Next work | a **measurement**, not a feature. Protocol registered, not yet run |

**Nothing is deadlined.** The expiry that was the last handoff's only dated item is gone — the
expiring tests were deleted rather than re-pointed.

## What closed

### The UI-test expiry (PR #51)

Answered **per leg**, because the legs had different shelf lives — not for the set as a whole.

| Test | Disposition |
|---|---|
| ADR-0018 leg A | kept, unchanged — fixture is Berserk, never expired |
| ADR-0018 leg B | **deleted** — needed a WeebCentral title *still under refusal*, a 14-day property |
| ADR-0018 leg C | kept, **rewritten standalone** |
| ADR-0019 seed subject + control | **deleted** — asserted nothing; their drain has run and is written up |

**Leg C would have broken silently.** It depended on leg B only as a *displacer* — pushing Berserk
off the top of history so the resume writes a new entry instead of updating in place. Deleting B
without noticing would have left a green test measuring nothing. It now displaces Berserk itself
with a MangaDex title.

The rewrite was **re-run, not just re-compiled**, and the first attempt failed usefully: the initial
displacer was Wind Breaker, already in the library. Search found it, the detail page opened
correctly, and it carries `0 AVAILABLE / No chapters yet.` in English. **A displacer needs readable
chapters, which is not the same as existing** — and the failure surfaced as a chapter-row timeout
indistinguishable from a Cloudflare/network flake. Junjou Romantica was checked against `/chapter`
with `translatedLanguage[]=en` before use.

Both run write-ups carry an **appended disposition note** rather than an edit — they record what
happened, not current state. Each names `git show 7f434b8` as the recovery point.

## What is queued, and what shape it is in

### The next task is a measurement with registered gates

`docs/superpowers/specs/2026-08-13-reverse-resolution-beyond-mangadex-measurement-protocol.md`,
registered before any number was taken. **Read it first; this section is only orientation.**

The feature under question is **A — recall**: recover "More Like This" cards MangaDex cannot serve
by falling back to WeebCentral. **B — affinity** (open a card on the source the user *prefers*, even
when MangaDex could serve it) was split off deliberately and is a separate ADR, not measured here.

The reason it is a measurement and not a design: `pickMatch`'s **strong arm is an exact `malId` hit**
among the candidates, which exists on MangaDex because MangaDex publishes `links.mal`. WeebCentral
publishes no external ids, so MAL → WeebCentral has **only the fuzzy title matcher, with nothing to
confirm against** — and ADR-0019 already measured that direction's failures as reach failures, i.e.
spellings that do not survive the round trip. The cards this feature adds are the ones we are least
sure about.

Method is **C then A**: an automatic screen on the population where MangaDex resolves authoritatively
(labels borrowed from MangaDex's alt-title set, which the matcher never sees — that is what keeps it
non-circular), and *only if that survives*, human adjudication of 30 pairs from the population that
actually matters. The user has agreed to eyeball **30 pairs** — that number is what the sample size
was designed around; do not silently ask for more.

Gates, all pre-registered: **Easy precision ≥ 0.95 over ≥ 80 picks** (kill gate, stricter than the
feature's own floor precisely because Easy is an upper bound); **Hard yield ≥ 15% over ≥ 100
recommendations** and **≥ 27 of 30** adjudicated correct. **Inconclusive is a declared third
outcome** with its own n thresholds, so it cannot be invented after the numbers look bad.

### Three things that will cost you time if rediscovered

1. **MAL without a client id returns a body with no `data` key**, which a naive script reports as a
   clean confirmed miss. Assert `data` is present. `Secrets.xcconfig` is at the **repo root**.
2. **WeebCentral `/search/data` answered plain `curl` on 2026-08-13** — pinned UA, real results, no
   challenge. Verified this session, so the Python replication is feasible *today*. It can stop
   being true at any moment and **does not degrade gracefully**: a challenge page yields refusals
   indistinguishable from real misses. Detect and abort; the fallback is driving it in-app the way
   the ADR-0019 gate run did.
3. **Pick, refusal, and search-failure are three outcomes, not two.** Collapsing the last two is
   exactly how the ADR-0019 gate run produced a believable wrong answer on its first attempt.

## Also open, unchanged and undated

- **`MAL_CLIENT_ID` rotation.** Printed into a transcript on 2026-08-12 while chasing a MAL search
  finding. Nothing committed or transmitted; rotating is a two-minute job and it stays on every list
  until done. **The measurement run needs this key** — rotate before, not during.
- ADR-0018 **Decision 2** remains unverified and is not verifiable through the app. A wrong
  `links.mal` becoming a confidently wrong answer is Hazard 1, accepted by name.
- No automated coverage of `HomeView`'s rail branch or `MangaDetailView`'s notice branch — still
  deliberate, reasoning in `AppCompositionTests`' header.
- Extension/repo system and comix.to shelved since 2026-07-21.
- `project.pbxproj` can churn on its own with no `xcp` involved. Check `git diff --stat` before every
  `git add`, as CLAUDE.md says. It did **not** churn this session.

## Sim state

Unchanged from the last handoff except through leg C's re-run: history is now **25 entries**, and the
sim gained **Junjou Romantica** reading history it did not have before. `upgrade-attempts.json` still
carries the declared hand edit described in the previous handoff. `Othello` remains untouched.
