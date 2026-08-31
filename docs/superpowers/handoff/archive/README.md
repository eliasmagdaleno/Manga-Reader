# Handoff archive — historical records

**Do not work from anything in this directory.**

Each file here is a snapshot addressed to one specific next session, written in the present
tense as a statement of what was true at the time. That session has already run. A document
here saying "two PRs are open", "nothing is owed", or "run this before building X" is
describing a repository that no longer exists.

The live handoff — if there is one — is the single `.md` file in the parent directory.
`ls docs/superpowers/handoff/*.md` answers "what is current?", and the answer is one file or
none.

## Why this directory exists

Doc rot hit this repository five times, always the same way: a document asserting as current
something that had stopped being true. Four instances were merely wrong. The fifth, on
2026-08-31, changed what an agent *did* — a session read a stale handoff top-down, believed an
issue was open and had been auto-closed, and reopened it publicly on a false premise before
catching the error.

Marking each file consumed by hand was the previous convention. Sixty of sixty-six carried no
such marker, which is the evidence that a rule depending on memory does not hold. Currency is
now a fact about **location** instead of a promise about content: writing a new handoff moves
the old one here, and anything still owed is carried forward into the new document rather than
left behind in this one.

That rule is in `CLAUDE.md`, under "Handoffs".
