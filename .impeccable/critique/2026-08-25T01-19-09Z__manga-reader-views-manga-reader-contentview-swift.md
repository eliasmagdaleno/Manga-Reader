---
target: all of the app after the Impeccable sequence
total_score: 32
max_score: 40
na_heuristics:
p0_count: 0
p1_count: 3
timestamp: 2026-08-25T01-19-09Z
slug: manga-reader-views-manga-reader-contentview-swift
---
# Whole-App Post-Pass Design Critique

## Design Health Score

| # | Heuristic | Score | Key issue |
|---|---|---:|---|
| 1 | Visibility of system status | 3 | Loading, progress, refresh, and unread states are clearer; personal freshness is still not prominent on Home. |
| 2 | Match with the real world | 4 | Ink, seal, chapter, volume, and reading-progress language fit manga reading naturally. |
| 3 | User control and freedom | 3 | Reversible read state and reader exit are good; recommendation and history controls remain less visible. |
| 4 | Consistency and standards | 4 | Shared tokens, components, and native navigation form a coherent system. |
| 5 | Error prevention | 3 | Destructive actions are confirmed, but undo remains limited after some state changes. |
| 6 | Recognition rather than recall | 3 | Chapter hints and visible refresh help; reader chrome and some contextual actions still require discovery. |
| 7 | Flexibility and efficiency | 3 | Resume, batch read actions, and adaptive grids help repeat use; source behavior still has multiple meanings. |
| 8 | Aesthetic and minimalist design | 4 | The app feels authored and product-specific, with restrained manga-print references. |
| 9 | Error recovery | 3 | Adjacent retries and actionable empty states improved recovery; raw service errors can still leak through. |
| 10 | Help and documentation | 2 | Local cues improved, but the app still lacks a concise mental model for sources and reader gestures. |
| **Total** |  | **32/40** | **Strong authored foundation with a remaining Home hierarchy problem.** |

## Design Specificity Verdict

The interface feels made for this manga reader rather than transferable to a generic media app. Ink & Seal has real component-level expression: paper fields, restrained vermilion seals, serif display hierarchy, mono metadata, cover-led cards, and reading-specific state language. The main structural caveat is that Home still reads as a sequence of similarly weighted catalog rails, while the product's most specific promise—resuming and catching up—has less visual authority.

## Overall Impression

This pass materially improved accessibility, recovery, and discoverability without erasing the existing identity. The next meaningful improvement is not another layer of styling; it is a clearer hierarchy for returning readers.

## What's Working

1. Ink & Seal is now documented and expressed consistently in reusable primitives.
2. The detail-to-reader loop communicates Start, Continue, reread, chapter state, and unread state well.
3. Empty, error, refresh, and accessibility states now offer clearer next actions.

## Priority Issues

### [P1] Home still dilutes reading urgency

Repeated equal-weight rails make provider discovery dominate personal momentum. When ADR-0021 is implemented, create one singular continue/catch-up region rather than adding another rail. Suggested command: `$impeccable shape`.

### [P1] Important secondary controls remain partially hidden

Recommendation actions, history details, and tap-to-reveal reader chrome still depend on discovery. Preserve the gestures as shortcuts, but add contextual affordances or a lightweight first-run cue. Suggested command: `$impeccable onboard`.

### [P1] Accessibility adaptation is improved but not exhaustive

Semantic typography, adaptive grids, reduced motion, and larger controls are strong gains. Fixed horizontal rails and compact source chips still deserve hands-on large-text and VoiceOver verification on every primary task. Suggested command: `$impeccable adapt`.

### [P2] Source selection still carries multiple meanings

Home, Search, and Settings all expose sources, but as global browse state, local query scope, and configuration. The new labels help; a durable product-level source model would reduce the remaining conceptual load. Suggested command: `$impeccable clarify`.

### [P2] Undo is weaker than confirmation

The app prevents destructive mistakes well, but recovery after a mistaken non-destructive state change is less consistent. Consider transient undo where it does not conflict with persistence semantics. Suggested command: `$impeccable harden`.

## Cognitive Load and Persona Red Flags

- **Jordan, first-time reader:** repeated Home rails and hidden reader chrome make the first mental model slower than necessary.
- **Sam, weekly returning reader:** the app still makes catch-up compete with catalog browsing rather than leading with it.
- **Alex, accessibility user:** source chips and fixed horizontal rails need device-level VoiceOver and accessibility-size validation beyond source inspection.

## Minor Observations

- Metadata density is appropriate on detail screens but should remain subordinate on browse cards.
- Adult-source controls should remain visibly separate from ordinary source scope.
- User-facing network errors should continue moving from raw transport wording to task-oriented recovery copy.

## Questions to Consider

- When ADR-0021 lands, can personal updates replace hierarchy rather than merely add content?
- Should Source remain a first-class user concept, or become advanced configuration over time?
- Which single reader gesture most needs a one-time coach without disturbing immersion?
