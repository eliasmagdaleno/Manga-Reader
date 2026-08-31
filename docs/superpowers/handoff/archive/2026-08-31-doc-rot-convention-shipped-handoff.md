# Handoff — handoff rot fixed structurally; the duplication half is still owed

Date: 2026-08-31
Repository: `/Users/eliasmagdaleno/Manga-Reader`
Branch: `main`, plus one open PR (**#113**) described below.

**This is the live handoff. It is the whole of what is outstanding, not the newest slice** —
that is now the convention, and this document is its first application. If you write a new
one, `git mv` this into `archive/` and carry forward anything below that is still true.

## Land PR #113 first

`gh pr view 113`. It is docs-only: 66 handoffs moved to `docs/superpowers/handoff/archive/`,
the rule added to `CLAUDE.md` under "Handoffs", plus `archive/README.md`.

**This document lives on that branch, not on `main`** — writing it on `main` would have put it
beside 66 unmoved files and conflicted with the move. So merge #113 and this handoff arrives
with it. Do not cherry-pick one without the other.

## What shipped this session

| PR | What | State |
|---|---|---|
| **#110** | `SectionHeaderPresentation` — the header trait, so the Headings rotor has stops | merged `670187c`, closed #108 |
| **#111** | `InkLoading` — seven unlabelled spinners now say what they are loading | merged `286063d`, closed #109 |
| **#112** | `scripts/voiceover-pass.sh` — walks the manual VoiceOver pass row by row | merged `d590fab` |
| **#113** | this convention | **open** |

Unit suite on merged `main`: **603 pass, 0 failures**, 2 skipped.

## What is actually owed

### 1. The manual VoiceOver pass — issue #90, and it is the user's, not yours

Still open, `ready-for-human`, and **no row has a verdict yet**. Every code-side defect §7
turned up is fixed; none of that closes it. Run `./scripts/voiceover-pass.sh` from the repo
root — it parses `docs/accessibility/voiceover-manual-checklist.md` at runtime, takes
pass/fail/skip per row, writes `docs/accessibility/voiceover-results-<date>.md`, and resumes
where it stopped.

Rows most needing eyes, because they were reasoned from code and never observed: **4.3** (are
the custom read actions still reachable now the row is one element?), **6.5** (are the reader
pages reachable at all?), and now **7.2** (#110 changed it — the Headings rotor should have
stops it did not have before). Close #90 when every row has a verdict, **not** when every
defect is fixed.

### 2. The duplication shape of doc rot — untouched

#113 fixes only *snapshots that never expire*. The other shape is **the same fact in two
places, one updated**: three of the five known instances. `AGENTS.md` vs `CLAUDE.md` (fixed by
symlink), `CLAUDE.md`'s "Current state" going false when ADR-0021 merged, and two memory files
carrying a rule that had reversed.

The work: audit the durable docs against reality — `CLAUDE.md`, `DESIGN.md`, `PRODUCT.md`,
`README.md`, `docs/glossary.md` (~400 lines), `docs/agents/*.md`, and the memory files under
`~/.claude/projects/-Users-eliasmagdaleno-Manga-Reader/memory/`. Every factual claim about the
code should be grep-verifiable *now*.

**ADRs are the exception.** They are dated decision records and are supposed to freeze. Do not
"correct" one — amend it, as ADR-0019 amendment 1 does.

### 3. §7 rows 7.5 and 7.6 are device-only

Rotation and accessibility text sizes. Not auditable from the code; they are rows in the pass
above, not separate work.

## What this session got wrong, because it will save you the same hour

**I reopened #90 on a false premise.** The handoff I read at startup said it was open; it had
been closed manually the day before. I inferred an auto-close from `(#90)` appearing in PR
*titles* — a title reference closes nothing, and the close event showed `actor: eliasmagdaleno,
commit: null`. Corrected publicly on the issue. This is the fifth doc-rot instance and the
first that changed what an agent *did*, which is the whole argument behind #113.

**I filed #109 from a grep instead of from reading.** Ten unlabelled `ProgressView()` sites,
three of which already had labels. Corrected before implementing. The repo memory
`verify-absence-claims-before-building` says exactly this; it applies to "this is missing"
claims you make yourself, not just ones you read.

## Gotchas that remain true

- **Changing an accessibility label silently breaks XCUITests.** They match and parse the
  *label*, not the drawn text, and CI runs neither affected suite. Grep the UI tests first.
  This is why #110 put the section eyebrow in the accessibility *value*: four assertions match
  headings by their drawn text (`app.staticTexts["MyAnimeList"]`, `["More Like This"]`,
  `["Keep your library current"]`, `["Updates"]`), and folding the eyebrow into the label would
  have broken all four with nothing to catch it. Verified by running one of them.
- **CI's toolchain is a major version behind local** — `macos-15` → Xcode 16.4 / Swift 6.0 vs
  local 26.x / 6.2. Green locally is not evidence for CI when the change uses newer syntax.
- **Branch protection does not stop this account** (`enforce_admins: false`). A direct push to
  `main` lands and waives both checks. The PR flow is the convention; ask first.
- **`project.pbxproj` churns under you** whenever Xcode has the project open. Check
  `git diff --stat` immediately before `git add`, not after. It bit this session: an `xcp
  add-file` produced 40 lines of unrelated churn, and re-running it after `git checkout` gave
  the clean 4-line insert.

## Repository state

- `main` at `d590fab`; working tree clean.
- `gh issue list`: **#90 only**. `gh pr list`: **#113 only**.
- Local branches: `main`, `docs/handoff-archive-convention` (#113), and a `worktree-helper`
  worktree. The four stale branches the previous handoff listed are gone.
