# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`docs/glossary.md`** — this repo's glossary. It plays the role the skills' templates call
  `CONTEXT.md`; the name differs because the glossary predates this setup and its ADR links are
  relative to `docs/`. There is no `CONTEXT.md` and none is wanted.
- **`docs/adr/`** — read ADRs that touch the area you're about to work in. Numbered `0001`–`nnnn`,
  and several carry amendments appended after acceptance, so read a whole file rather than its
  Decision section alone.

Single-context repo: one glossary, one ADR directory, both at the paths above. No `CONTEXT-MAP.md`,
no per-context ADR directories.

If a file doesn't exist, **proceed silently**. Don't flag its absence; don't suggest creating it
upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and
`/improve-codebase-architecture`) creates and extends these lazily, when terms or decisions
actually get resolved.

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a
test name), use the term as defined in `docs/glossary.md`. Don't drift to synonyms the glossary
explicitly avoids — several entries carry an explicit `_Avoid_:` line naming the wrong words.

The distinctions the glossary is most load-bearing about, and the ones most often got wrong:

- **Work** vs **Listing** — a Work is the series independent of source; a Listing is one source's
  copy of it. The `Manga` struct is a Listing despite its name.
- **Work id** — locally minted, immutable, never derived from an external id.
- **Display title** vs **known titles** — the first is sticky and never overwritten by a provider;
  the second accumulates and is matcher fuel.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing
language the project doesn't use (reconsider) or there's a real gap (note it for
`/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (Work identity) — but worth reopening because…_

Two repo-specific rules on top of that:

- **A rejected ADR stays rejected.** Reviving a rejected decision is a *new* ADR that supersedes it,
  not an edit to the old one — the record of why it was rejected is the valuable part. ADR-0016
  (rejected) and its intended successor are the standing example.
- **An ADR's "revisit triggers" section is a contract.** If evidence you produce matches a trigger
  verbatim, say so and name the ADR, even when acting on it is out of scope for what you were asked.
