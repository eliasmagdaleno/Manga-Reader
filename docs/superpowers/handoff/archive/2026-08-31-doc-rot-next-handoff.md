# Handoff — tackle doc rot, systematically

Date: 2026-08-31
Repository: `/Users/eliasmagdaleno/Manga-Reader`
Branch: `main` (clean) — plus one open PR, **#107**, described below.

## Why this exists

The previous session fixed six VoiceOver accessibility defects (PRs #102–#106, all merged) and
then, correcting its own freshly-merged handoff, hit the **fourth** instance of the same
pattern in this repo: a document asserting as current something that had stopped being true.
The user's call was to stop treating these one at a time and attack the pattern itself.

**Nothing about the accessibility work is owed.** That thread is closed out — see
`2026-08-30-voiceover-accessibility-labels-handoff.md`, and note its own correction banner.

## First: land or close PR #107

`gh pr view 107`. It corrects four stale claims in yesterday's handoff (chiefly that issue #90
is "still open" — it was closed manually at 2026-08-30 20:28 UTC, no linked commit, because
every PR used `Refs #90` rather than a closing keyword).

It is docs-only and self-contained. Merge it before starting, or fold its content into whatever
larger cleanup you choose — but do not leave it open and then edit the same file, or you will
be resolving a conflict against your own correction.

## The finding that should shape the plan

The rot is **structural, not careless**. Run this:

```sh
ls docs/superpowers/handoff/*.md | wc -l          # 65
grep -l "consumed" docs/superpowers/handoff/*.md | wc -l   # 5
```

**Sixty of sixty-five handoffs carry no expiry marker**, and they are written in the present
tense as statements of current state. Two samples, both long dead, both still reading as live
instructions:

- `2026-07-25-session-handoff.md`: *"`main` is at `61d852a`. **Two PRs are open** and were both
  green-or-pending at handoff time."*
- `2026-08-24-impeccable-sequence-next-handoff.md`: *"There is **no active implementation
  task**. Run the Impeccable sequence below before planning or building ADR-0021."* ADR-0021
  shipped on 2026-08-30.

A handoff is a **snapshot addressed to one specific next session**. Once that session acts, the
document becomes a historical record — but nothing in the format says so, so every one of them
keeps presenting itself as current to whoever greps `docs/` next. That is the generator of the
rot, and the reason fixing instances individually has not worked four times running.

The convention for marking one consumed already exists and reads well —
`2026-08-28-adr-0021-task-8-next-handoff.md` is the model. It is simply applied by hand, and
usually only to the document the *next* session happened to open.

## The four known instances, for pattern-checking

1. **`AGENTS.md` vs `CLAUDE.md`** (before 2026-08-21) — separate files, the copy went stale
   about what `isRead` means. Fixed by making `AGENTS.md` a symlink.
2. **`CLAUDE.md` "Current state"** (`f82c99c`, 2026-08-30) — *"refreshing content is manual …
   nothing polls for new chapters"* went false the moment ADR-0021 merged.
3. **Memory files** (2026-08-30) — `no-parallel-test-clones` had reversed; `ui-verification-technique`
   carried a second stale copy of the same rule.
4. **The VoiceOver handoff** (2026-08-31, PR #107) — asserted an issue was open that had been
   closed an hour before the document merged.

Note the shape: **1, 2 and 3 are duplication** — the same fact written in two places, one of
which was updated. **4 is staleness by design** — a snapshot that never expires. A fix aimed
only at one shape will not catch the other.

## Suggested approach, in the order I would do it

This is a suggestion, not a plan of record — **brainstorm it with the user before building.**
The user explicitly wants this tackled as a pattern, so the framing question is *"what stops
the fifth instance"*, not *"which docs are wrong today"*.

1. **Sweep the handoffs (mechanical, low risk, high value).** Banner-mark the 60 unmarked ones
   as historical. Most can be judged from their own date plus `git log`. This is a good
   subagent-parallel task — the judgement per file is small and independent.
2. **Audit the durable docs against reality** — `CLAUDE.md`, `DESIGN.md`, `PRODUCT.md`,
   `README.md`, `docs/glossary.md` (400 lines), `docs/agents/*.md`. Every factual claim about
   the code should be grep-verifiable *now*. The existing memory `verify-absence-claims-before-building`
   already says to grep before trusting a doc's claim that something is missing; this is the
   same check run offensively.
   ADRs are the exception: they are dated decision records and are *supposed* to freeze. Do not
   "correct" an ADR — amend it, which the repo already does (see ADR-0019 amendment 1).
3. **Then prevention, chosen deliberately.** Options worth weighing rather than assuming:
   a marker in the handoff template that names what would falsify it; a `docs/superpowers/handoff/archive/`
   directory so currency is a location rather than a promise; a check that greps handoffs for
   references to closed issues and merged PRs; or simply the rule that writing a handoff
   consumes the previous one. Cheapest thing that breaks the generator wins — this repo does
   not need a framework.

## Gotchas carried forward

- **CI's toolchain is a major version behind local.** `macos-15` → Xcode 16.4 / Swift 6.0;
  local is 26.x / 6.2. Irrelevant to a docs-only change, but it is what makes "green locally"
  not evidence. In `CLAUDE.md`'s Commands section.
- **Branch protection does not stop this account** (`enforce_admins: false`). A direct push to
  `main` lands and waives both checks. Treat the PR flow as the convention and ask first.
- **`project.pbxproj` can churn under you** whenever Xcode has the project open. Check
  `git diff --stat` immediately before `git add`, not after.
- **Changing an accessibility label silently breaks XCUITests** — they match and parse the
  label, not the drawn text, and CI runs neither affected suite. Grep the UI tests first.
  (Cost a rewrite in PR #104.)

## Repository state

- `main` at `8bd9219`; working tree clean; `gh issue list` empty; PR #107 open.
- Four stale local branches worth deleting: `docs/voiceover-session-handoff`,
  `fix/history-and-update-row-accessibility-90`, `fix/reader-and-toolbar-accessibility-90`,
  `fix/settings-evidence-screenshots`.
- Issue **#90** is closed but its manual VoiceOver pass was **never run**. If the on-device
  work still matters, it needs a reopened or fresh issue; the checklist is at
  `docs/accessibility/voiceover-manual-checklist.md`.
