# Home and Library Updates — Design Brief

## Job and audience

A returning reader opens Manga Reader after time away and needs to answer one question immediately:
“What changed in titles I follow?” The surface operates as a calm personal dashboard before it
becomes a discovery catalog. New readers and readers with no updates still receive useful
recommendations and source-wide browsing without seeing an empty updates shell.

## Outcome and proof

- When actionable saved-title updates exist, Home leads with a compact personal Updates summary and
  the most recently discovered Works. One action opens the full Library Updates view.
- Library makes total unread chapters, newly discovered chapters, last successful check, refresh
  activity, and stale/partial failure visibly distinct.
- Opening an updated Work lands on its chapter list. It never skips unread chapters or treats viewing
  the list as reading them.
- The UI consumes Work-level update presentation. Provider Listings may explain availability or
  failures, but never create duplicate title-level update rows.

## Selected direction

Ink & Seal remains the visual authority. Updates use the metaphor of a newly arrived issue: cover,
title, a literal “N unread chapters” label, and a restrained `NEW` seal for newly discovered state.
Home is a deliberate blend in this order: personal updates when present, personalized
recommendations, then active-source discovery. The focal moment is a single, legible updates header
that pairs freshness language with a visible refresh action.

On Home, the personal summary is intentionally finite rather than another endless equal-weight rail:
show up to five updated Works, then a “View all updates” action. In Library, Updates is a first-class
filter beside All and user collections; selecting it shows saved Works with unread chapters, ordered
by most recent discovery and then title.

## Scope and boundaries

- This brief defines foreground presentation and the view-facing contract only.
- ADR-0021 remains the authority for source-aware polling, baselines, scheduling, local
  notifications, notification authorization, deep links, persistence, muting, and adult copy.
- Do not implement background tasks, notification APIs, polling, or a replacement for the broken
  multi-source refresh in this refinement sequence.
- Existing Start, Continue, next-chapter, reread, read/unread, collection, and source behavior remains
  unchanged.

## States and ranges

- **No saved Works:** explain that Library keeps followed titles current and provide direct Browse
  and Search actions; do not show freshness claims.
- **Saved, no baseline yet:** “Not checked yet” with a visible foreground refresh action.
- **Fresh, no updates:** “Checked recently · No new chapters” without manufacturing an Updates rail.
- **One to five updated Works:** show each Work directly on Home.
- **More than five:** show five plus the total in “View all N updates.”
- **Refreshing:** preserve current content, expose progress, disable duplicate refresh requests, and
  announce completion.
- **Partial failure:** retain known updates and say which sources need another foreground check; one
  failed Listing never erases a Work-level update learned from another trusted Listing.
- **Stale:** use honest relative language such as “Last checked yesterday,” never a delivery promise.
- **Newly discovered vs unread:** `NEW` presentation can clear when the chapter list is viewed; unread
  counts clear only when chapters are completed or manually marked.

## Interaction and layout

- Home’s Updates header contains a literal title, total unread count, relative freshness, and a
  44-point refresh button. Each updated Work is one navigation target with a spoken label that
  includes title and unread count.
- Library’s Updates filter is reachable in the existing collection/filter bar and exposes selected
  state without relying on vermilion alone. Its label is “Updates,” never a bare number.
- Compact widths use cover-led rows or a horizontally scrollable summary; accessibility text sizes
  stack metadata below titles. iPad uses a readable adaptive grid or two-pane navigation rather than
  stretching phone cards.
- Refresh completion and recoverable errors are announced. Focus remains on the refresh control for
  status-only changes and moves to an error action only when the user must intervene.
- Reduce Motion replaces spatial banner movement with opacity or no animation.

## View-facing contract

The eventual implementation should supply a presentation model at the Work boundary with, at
minimum:

- stable Work identity and display manga;
- unread chapter count;
- newly discovered chapter count and newest discovery date;
- last successful check date;
- freshness state (`notChecked`, `refreshing`, `fresh`, `stale`, `partialFailure`);
- optional source-specific recovery summaries;
- notification mute state, only after ADR-0021 implements it.

Views must not derive Work update identity by counting Listing rows, consulting the globally active
browse source, or equating `newly discovered` with `isRead`.

## Open implementation decisions

- The exact Work-level chapter-frontier representation and cross-source equivalence algorithm.
- The threshold at which “recently” becomes a concrete relative date; it must be centralized and
  testable.
- Whether the full Updates destination is a Library filter, a dedicated navigation destination, or
  both. The first implementation should prefer the existing Library topology unless real content
  ranges prove it insufficient.
