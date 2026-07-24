# ADR-0005 — Resolution failures are user-correctable via a manual link override

- **Status:** Accepted (2026-07-24)
- **Related:** ADR-0001 (Work vs Listing), ADR-0004 (fulfillment routing)

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
