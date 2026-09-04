# ADR-0024 — A policy-invalid cover URL costs the cover, not the feed

- **Status:** Accepted (2026-09-04)
- **Related:** ADR-0001, ADR-0003
- **Amends the reading of:** `docs/superpowers/specs/2026-09-02-host-api-design.md` §10 (URL policy)

## Context

The Host API design's §10 makes every URL an Extension hands the host absolute-HTTPS-only, and
sorts failures into two kinds:

> Malformed optional cover URLs drop that field with a warning; policy-invalid URLs and all
> invalid page or browser URLs reject the operation. This distinction keeps cosmetic damage
> recoverable without silently weakening the reader or navigation boundary.

So a cover that fails to parse is cosmetic and survivable, but a cover that parses and then
violates the declared `assetOrigins` — an `http://` scheme, a CDN host nobody declared — rejects
the whole operation it arrived in.

That collides with §2.1, which exists to prevent exactly this outcome:

> This narrow partial-success rule prevents one damaged card from erasing an otherwise usable
> feed while keeping schema drift visible.

The two rules meet on a real, ordinary input. A source redesigns and starts serving covers from
a new CDN, or serves one card's cover over `http://`. Under §2.1 the feed survives with a
warning. Under §10 the reader gets an error screen and a browse tab that shows nothing, because
of one image on one card out of forty.

This was found reading the design before Wave 1 and recorded as contract gap 4. S2 implemented
the literal reading — `ExtensionDomainSchemas` threw `invalid_response` on a policy-invalid
cover — and its PR body flagged that the reading was worth revisiting rather than settling.

The asymmetry that decides it: **the host never loads a rejected URL under either rule.** A
policy-invalid cover is refused by `assetURL` before anything fetches it. So the choice is not
between loading and not loading a suspect URL. It is only about what else the refusal destroys.

## Decision

**A policy-invalid *optional cover* URL drops the field with a warning and keeps the item.**
It is treated exactly as a malformed one, with a distinct warning code so the two remain
distinguishable to a Source author.

**Everything else in §10 is unchanged and still rejects the operation**: every page URL, every
browser `webURL`, and every network request URL. The relaxation is scoped to the one field that
is optional and cosmetic in the first place.

Concretely, in `ExtensionDomainSchemas`:

- `ExtensionValidationWarningCode` gains `policyInvalidURL` (`"policy_invalid_url"`), alongside
  the existing `malformedURL`.
- The `.policyInvalid` branch on `coverURL` appends that warning instead of throwing.

## Consequences

A Source that starts serving covers from an undeclared origin degrades to a feed of cards with
missing cover art, plus one warning per card, instead of an unusable browse tab. That is the
same failure mode as a source that simply has no cover for a title, which the app already
handles.

The warning channel becomes the thing that makes this visible rather than silent, which raises
the stakes on contract gap 3 — three of the five result types have nowhere to put warnings in
the spec as written. This decision assumes warnings are carried uniformly, as S2 implemented
them.

A Source author who misconfigures `assetOrigins` now gets a quieter failure than before: covers
vanish rather than the operation failing loudly. The distinct `policy_invalid_url` code is what
keeps that diagnosable — it says "your policy rejected this", not "your URL was broken", and
those want different fixes.

**Rejected:** dropping the whole *item* rather than the field. It is a third behaviour for the
same class of damage, and it loses a title the reader can otherwise open and read — the cover is
not why the card exists.

**Rejected:** leaving §10 as written and documenting the reading. This is the one of the five
contract gaps where the literal reading produces a worse app, not merely an underspecified one.
