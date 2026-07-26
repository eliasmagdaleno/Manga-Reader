---
name: grill-with-docs
description: A relentless interview to sharpen a plan or design, which also creates docs (ADR's and glossary) as we go.
disable-model-invocation: true
---

Run a `/grilling` session, using the `/domain-modeling` skill.

## This repo's conventions override the skills' defaults

`domain-modeling` assumes a root `CONTEXT.md` and ships its own `ADR-FORMAT.md` /
`CONTEXT-FORMAT.md`. **This repo does it differently. Follow what's here, not those templates.**

- **The glossary is `docs/glossary.md`**, not `CONTEXT.md`. Do not create a `CONTEXT.md`.
  Same discipline — a glossary and nothing else, no implementation detail — different path.
- **ADRs live in `docs/adr/`**, numbered `NNNN-kebab-title.md`, continuing the existing sequence.
- **Match the house ADR format**, which is denser than the skill's template. Read a recent one
  (`0007-work-shape-and-lifecycle.md`, `0008-upgrade-queue-resolution-and-drain.md`) before
  writing a new one. It carries:
  - a `Status` / `Amends` / `Related` header block,
  - a `## Context` section that pins **facts verified live**, dated, marked *do not re-derive*,
  - one `###` per decision, each stating the rejected alternative **and the argument that beat
    it** — not just what was chosen,
  - explicit **`Accepted cost:`** callouts where a decision knowingly gives something up,
  - `## Hazards` and `## Revisit triggers` at the end.
- **Cite `file.swift:line` when a decision rests on what the code actually does.** Claims about
  current behaviour get checked against the code, not recalled.
- **Amend rather than supersede** when a new ADR changes part of an older one, and say so in the
  `Amends` header — see ADR-0007's in-place amendment of ADR-0002.

`domain-modeling` says to offer ADRs sparingly (hard to reverse, surprising without context, a
real trade-off). **That still applies.** A grilling session does not automatically owe an ADR;
several decisions in one session usually belong in one.

## Working style for this repo

- **Prose at the forks, not `AskUserQuestion` prompts.**
- **Lead with the question.** State the ask in a few lines and stop — evidence and option
  analysis go *after* it, or wait until asked. A long preamble buries what's being decided.
- Give rationale as you go; the user is learning SWE from this project and wants the reasoning,
  not just the conclusion.
