# ADR-0005 — Resolution failures are user-correctable via a manual link override

- **Status:** Accepted (2026-07-24), amended 2026-08-08 — **the decision stands, the target moved
  and the build is blocked on a report.** See "Amendment (2026-08-08)" below
- **Related:** ADR-0001 (Work vs Listing), ADR-0004 (fulfillment routing), ADR-0015 (ships the
  visibility half of this decision for the total-failure case, and names this ADR as its first
  revisit trigger)

## Amendment (2026-08-08)

This ADR was grilled against the call sites it commits to, on the handoff's recommendation that it
be built next. **It is not being built next**, and two things in it are wrong. The decision itself —
keep the precision bias, give the user an override — is unchanged.

**1. The target is Work → MAL id, not Listing → Work.** As written, this ADR is about linking a
Listing to a Work: two sources' pages for the same manga, collapsed by hand. The primitive for that
is `WorkStore.merge(_:into:)` (`:243`), whose own comment already anticipates "a manual link arrives
after both Works already exist". But that is not the failure the app observes. `SourceRegistry`
registers exactly two sources (`:46`) — MangaDex, which hands over `attributes.links.mal` for free
and never reaches the title matcher, and WeebCentral, which does. So every silently-unresolved Work
today failed at **Work → MAL id**, recorded as `UpgradeAttemptMemory.unmatched(knownTitlesCount:)`
and surfaced by ADR-0015's notice. The primitive is `setExternalIds(_:on:)` (`:230`), not `merge`.

The Context below argues from "under ADR-0003 the number of sources is meant to grow substantially".
That growth is **shelved deliberately since 2026-07-21** (the extension/repo system and comix.to).
The Listing → Work case is therefore not a near-term failure; it is a real one that has not arrived.

**2. It is blocked on a report, not pending.** ADR-0015 set the standard for its own mixed-library
hazard: not due until *reported* as bad output rather than inferred from reading the code. The same
test applies here, and this ADR fails it — the failure was derived from reading `MALTitleMatcher`,
not from anyone hitting it.

**What survives and is worth building before any of the above:** the *visibility* requirement. This
ADR's first implied requirement — failures must become visible — is half-shipped. ADR-0015 covers
the total-failure case (every Work untaggable → a notice). The **per-item** case does not: three
untaggable Works beside twenty taggable ones clears the gate, builds a rail, and leaves the omission
exactly as silent as it was before. That gap is small, needs no override store and no picker UI, and
is what this ADR's argument actually earns today.

**Revisit when** a Work's absence from recommendations is reported as wrong, or when a third source
lands and the Listing → Work case stops being hypothetical.

## Context

`MALTitleMatcher` is deliberately **precision-biased**: normalized Levenshtein, exact-match-wins,
a 0.90 threshold and a 0.05 ambiguity guard, returning `nil` rather than guessing. That is the
right bias — a wrong link corrupts identity, history, and recommendations, while a missing link
merely omits something.

But the failure is **silent**. A Listing that doesn't resolve simply never appears: no error, no
log, no UI. Today, with MangaDex handing over `malId` for free (`attributes.links.mal`) and only
one scraped source, that is tolerable. Under ADR-0001 every non-MangaDex Listing is linked by
fuzzy title match, and under ADR-0003 the number of sources is meant to grow substantially. Silent
non-resolution then becomes both the most common failure and the least visible one — and per
ADR-0004 it degrades routing invisibly, since an unresolved Listing cannot be ranked.

Alternate titles, romanization differences, and regional retitling (the "Attack on Titan" /
"Shingeki no Kyojin" class of problem) mean this is a permanent condition, not a bug to be fixed
by a better matcher.

## Decision

**Keep the precision bias, and give the user a manual override.** Where the app cannot confidently
link a Listing to a Work, the user can establish the link by hand, and the override is persisted
and authoritative over any future automatic match.

Implied requirements:

- Failures must become **visible** — an unresolved Listing needs somewhere to be seen. Silent
  omission with a manual override the user never knows to reach for is no better than silent
  omission.
- The override store must survive cache invalidation. `EntityResolutionStore` currently expires
  misses after 14 days and keeps hits forever; a **manual link is not a cache entry** and must
  never be evicted or overwritten by a later automatic match.
- The reverse operation — *unlinking* a wrong automatic match — is the same feature and should
  ship with it.

## Consequences

- New UI surface (link/unlink a Listing to a Work) plus a persisted override store.
- The matcher can stay conservative permanently; there is now an escape hatch, so raising recall
  at the cost of precision is never the answer to a complaint.
- Manual links are user data with no backup path — the app has no cross-device sync, so a
  reinstall loses them. Acceptable for now; worth revisiting if sync ever lands.
