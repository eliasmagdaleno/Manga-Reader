# ADR-0019 — the gate observed refusing (2026-08-13)

Closes the one leg Amendment 1 registered that the 2026-08-11 run could not deliver. Protocol,
registered before either fixture was added, and amended before the logged drain:
`2026-08-13-adr-0019-gate-run-protocol.md`.

## The observation

One drain, one process, both Works attempted **one second apart**:

| Work | Listing | Attempted | Outcome | **Bridge queries logged** |
|---|---|---|---|---|
| **Dyo Adélfia** | `mangadex / 347c8a31-…` | 22:34:38 UTC | `.unmatched(1)` | **0** |
| **Koi Inu** (control) | `weebcentral / 01J76XYBCVMXT396YDSP40ZW0D` | 22:34:39 UTC | `.unmatched(7)` | **3** — `Koi Inu`, `こいいぬ`, `Koiinu` |

Both were refused. Only one asked MangaDex. That difference is the gate
(`MALEntityResolver.swift:163`) — and it is the whole point that **both outcomes are identical**:
the query is the only thing that separates "declined to ask" from "asked and found nothing", which
is the same reasoning the gate's two unit tests use.

The control also grew from 1 known title to 7 (`Puppy Love`, `코이이누`, `犬系男子戀愛中`,
`Щенячья любовь`), so the bridge was not merely reached but did its work — the run does not rest on
a log line alone.

**Amendment 1's gate leg is met. ADR-0019 is now verified in full**, its Decision 6 claim
(2026-08-11) and its gate claim (today).

## Why the subject qualifies

`isBridgeable` is `!work.listings.contains { $0.sourceId == mangadex }`. Watching it return false
needs a Work that gets past everything before it: a MangaDex Listing, **no** authoritative `mal` id
(or ADR-0018 short-circuits at the top of `resolve`), and **no** confident MAL match (or it returns
before the gate). A MangaDex title whose `links.mal` is simply absent is exactly that — and is the
one case ADR-0019 Decision 2 says the rejected source-allowlist alternative would get wrong. The
fixture is the decision's own example, not a contrivance.

Such titles are not rare: **36 of 60** recent MangaDex entries carried no `links.mal`.

## The first attempt failed, and the failure is the more useful result

The run was executed twice. The first attempt is reported because it invalidated a *method*, not
just a fixture.

**What happened.** The intended control, `Guyabano Holiday`, resolved on MAL (`mal: 121435`) and so
never needed the bridge; it logged nothing. The subject had meanwhile been attempted during the
*seeding* test, before `ADR0019_BRIDGE_LOG` was set, and its refusal then TTL-suppressed it — so the
logged drain that followed attempted nothing and wrote no log file at all. Two silent fixtures, one
empty log, and nothing whatsoever established.

**The method that was wrong.** Both fixtures had been chosen by asking MAL's `q=` endpoint and
judging the top hits unrelated. But MAL holds an entry titled exactly `Guyabano Holiday`
(`グヤバノ・ホリデー`) that its own search does not surface for that string. **Absence from MAL's
`q=` results is not absence from MAL.** No fixture can be established as a MAL miss that way.

**The correction.** Use Works *this app has already refused* — the 17 WeebCentral refusals from the
Amendment 1 run are empirical misses measured by the same matcher. Their only obstacle was TTL
suppression, lifted by removing exactly two entries from `upgrade-attempts.json` (the subject, so it
re-attempted under logging, and `Koi Inu`). That hand edit was **declared in the protocol before it
was made**; it lifts suppression only, and touches neither `works.json`, the resolver, nor the gate.
`Othello` was left alone as ADR-0018 leg B's fixture.

A near-miss worth naming: had the first attempt's empty log been read as "the gate refused", it
would have been a clean, believable, entirely wrong pass — the subject was never even asked. **A
control that is proven to log is what makes the subject's silence mean anything**, which is why the
protocol registered "the control resolves" as a named failure mode in advance.

## Method

1. Two UI tests (`testADR0019SeedGateSubject`, `testADR0019SeedGateControl`) add the fixtures via
   `Add to Library`; `LibraryStore.toggle` mints the Work and no chapters are needed. One fixture per
   test on a fresh launch — driving both in one pass required Search → Detail → Home → another
   source chip → Search, and the second search field never returned.
2. The drain runs under `xcrun simctl launch` with
   `SIMCTL_CHILD_ADR0019_BRIDGE_LOG=<container>/gate-run.log`, **not** another `xcodebuild test`: a
   reinstall moves the data container, and the log path is fixed at launch. The queue starts on
   `.active` (`Manga_ReaderApp.swift:67`).
3. `ADR0019_BRIDGE` is left unset — the bridge must be **live**. This run is about who asks.

Reproducing it needs `VerificationSwitches.swift`, which is deleted in the same change as this
write-up per its own deadline; recovering it is `git show` on this commit's parent.
