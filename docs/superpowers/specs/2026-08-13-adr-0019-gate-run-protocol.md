# ADR-0019 — the gate leg, run protocol (2026-08-13)

Registered **before** either fixture was added to the app. The leg Amendment 1 asked for and the
2026-08-11 run could not deliver: **the gate has never been observed refusing.**

## Why the last run could not do this

Every MangaDex-sourced Work in the library already carried a `mal` id, so `resolve` returned at its
first line via ADR-0018's fast path and nothing reached `isBridgeable`
(`MALEntityResolver.swift:163`). **Nothing was refused because nothing asked.** Recorded then as
*not observed*, deliberately not as passed.

## What the gate needs to be seen doing

`isBridgeable` is `!work.listings.contains { $0.sourceId == mangadex }`. To watch it return false,
the Work must get *past* everything before it — so it needs, all at once:

1. a **MangaDex** Listing (or the gate is irrelevant),
2. **no** authoritative `mal` id (or ADR-0018 short-circuits at the top of `resolve`), and
3. **no confident MAL match** (or it resolves and returns before line 144).

A MangaDex title whose `links.mal` is simply absent is exactly that Work, and ADR-0019's Decision 2
names it as the one case the rejected source-allowlist alternative would get wrong. So this is not a
contrived fixture — it is the case the decision was written for.

**The observation is the request, not the result.** Both configurations return nil, so only a logged
query distinguishes "declined to ask" from "asked and found nothing" — the same reasoning the gate's
two unit tests use. `VerificationSwitches` logs each bridge query via `ADR0019_BRIDGE_LOG`.

**A gate that never fires is indistinguishable from an absent one**, so a silent log alone proves
nothing: a control that *does* bridge has to run in the same drain.

## Fixtures, pinned now

| Role | Title | Id | Why it qualifies |
|---|---|---|---|
| **Subject** | Dyo Adélfia | `mangadex / 347c8a31-7d0b-4250-b240-4aa7e2fd72f1` | no `links.mal`; MAL returns only *Adelaide*, *Boku no Adelia*, *Selfish Romance* |
| **Control** | Guyabano Holiday | `weebcentral / 01J76XYFWD7H55VKCWTYGFGTZY` | not in the seeded cohort, so no attempt record and no TTL suppression; MAL returns only *Shissou Holiday*, *Holiday Love*, *Holiday* |

Both MAL-checked against the v2 API before selection. **A MAL query sent without a client id returns
a body with no `data` key**, which reads as a confirmed miss — assert on `data` being present, or
fixture selection silently invents its own result.

The control has to be a *fresh* WeebCentral title: the sim's 17 refused ones were checked
2026-08-11 and stay TTL-suppressed until ~08-25, so they would log nothing and the control would be
silently absent.

## The predictions

1. **The gate refuses.** No line in the bridge log matches any of Dyo Adélfia's known titles.
2. **The control bridges.** At least one line matches `Guyabano Holiday`. Without this, prediction 1
   is unfalsifiable.
3. **The subject is refused, not resolved.** Dyo Adélfia's Work ends the drain with
   `externalIds: {}` and an `.unmatched` attempt record.

**Registered failure modes, so neither can be reinterpreted afterwards:**

- **MAL matches Dyo Adélfia confidently.** Then it resolves, never reaches the gate, and the leg is
  *again* not observed. That is a fixture failure, not a gate failure, and must be reported as
  "still not observed" — not quietly reframed.
- **MAL matches Guyabano Holiday.** Then the control is silent, no query is logged for it, and the
  whole run is inconclusive regardless of what the subject did.

## Method

1. One UI test adds both fixtures through `Add to Library` — `LibraryStore.toggle` mints the Work,
   and no chapters are needed.
2. **Do not** set `ADR0019_BRIDGE`. The bridge must be **live**; this run is about who asks, not
   about closing a cohort.
3. Drain via `xcrun simctl launch` with `SIMCTL_CHILD_ADR0019_BRIDGE_LOG=<container>/gate-run.log`
   rather than another `xcodebuild test` — a reinstall moves the data container, and the log path is
   fixed at launch. The queue starts on `.active` (`Manga_ReaderApp.swift:67`).
4. Resolve the container path immediately before launching; **its UUID changes on every install**
   even though the data migrates.
5. Read `gate-run.log`, `upgrade-attempts.json` and `works.json` afterwards.

`upgrade-attempts.json` is **not** deleted — nothing here needs a closed cohort, and deleting it
would destroy both this run's control status and ADR-0018 leg B's fixture.
