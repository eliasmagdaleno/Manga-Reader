# Handoff — accessibility work shipped; two threads owed, both needing a human first

Date: 2026-08-31 (evening)
Repository: `/Users/eliasmagdaleno/Manga-Reader`
Branch: `main`, clean. No open PRs.

**This is the live handoff, and it is the whole of what is outstanding.** If you write a new
one, `git mv` this into `archive/` first and carry forward whatever below is still true.
That is the convention (`CLAUDE.md` → "Handoffs"); it shipped today, and this document is the
second thing to obey it. The one it replaces went stale within three hours — it said PR #113
was open — which is the rot working exactly as predicted, caught by the rule instead of by a
reader.

## What shipped today

| PR | What | Landed |
|---|---|---|
| **#110** | `SectionHeaderPresentation` — header trait on all 15 section headings | `670187c`, closed #108 |
| **#111** | `InkLoading` — seven unlabelled spinners now say what they load | `286063d`, closed #109 |
| **#112** | `scripts/voiceover-pass.sh` — walks the manual pass row by row | `d590fab` |
| **#113** | handoff archive convention — 66 files moved, rule in `CLAUDE.md` | `e23bdba` |

Unit suite on `main`: **603 pass, 0 failures**, 2 skipped.

## What is owed

### 1. The manual VoiceOver pass — #90, and it is the user's to run

Open, `ready-for-human`, **no row has a verdict yet**. Everything a code change can do for it
is done; none of it closes the issue. There is no results file in `docs/accessibility/` yet,
which is how you can tell at a glance that the pass has not started.

Run `./scripts/voiceover-pass.sh` from the repo root. It parses the checklist at runtime, takes
pass/fail/skip per row, writes `docs/accessibility/voiceover-results-<date>.md`, and resumes
where it stopped. It needs a real iPhone — VoiceOver in the simulator differs on the rotor and
on focus restoration, which is most of what these rows test.

Rows most needing eyes, all reasoned from code and never observed: **4.3** (are the custom read
actions still reachable now the row is one element?), **6.5** (are the reader pages reachable
at all?), **7.2** (#110 changed it — the Headings rotor should now have stops), **7.5** and
**7.6** (rotation and accessibility text sizes; not auditable from code at all).

Close #90 when every row has a verdict, **not** when every defect is fixed. A row that turns
out fine is still a result.

### 2. The duplication shape of doc rot — untouched, and it is agent work

#113 fixed only *snapshots that never expire*. The other shape is **the same fact in two
places, one of them updated** — three of the five known instances: `AGENTS.md` vs `CLAUDE.md`
(fixed by symlink), `CLAUDE.md`'s "Current state" going false the moment ADR-0021 merged, and
two memory files carrying a rule that had reversed.

The work: audit the durable docs against reality — `CLAUDE.md`, `DESIGN.md`, `PRODUCT.md`,
`README.md`, `docs/glossary.md` (~400 lines), `docs/agents/*.md`, and the memory files in
`~/.claude/projects/-Users-eliasmagdaleno-Manga-Reader/memory/`. Every factual claim about the
code should be grep-verifiable *now*.

**ADRs are the exception** — dated decision records, supposed to freeze. Amend, as ADR-0019
amendment 1 does; never "correct" one.

Worth deciding before starting: whether the fix is a one-time audit or something structural,
the way #113 was for snapshots. A one-time audit produces instance six eventually.

## Mistakes from this session, because both are repeatable

**Reopened #90 on a false premise.** The handoff I read at startup said it was open; it had
been closed manually the day before. I inferred an auto-close from `(#90)` appearing in PR
*titles* — a title reference closes nothing, and the close event showed `actor: eliasmagdaleno,
commit: null`. Corrected publicly on the issue. Fifth doc-rot instance, and the first that
changed what an agent *did* rather than what a document said; that is the argument #113 rests on.

**Filed #109 from a grep instead of from reading.** Ten unlabelled `ProgressView()` sites,
three of which already had labels. Caught and corrected before implementing, but the memory
`verify-absence-claims-before-building` covers exactly this — and it applies to absence claims
*you* make, not only ones you read.

## Gotchas, each re-verified today rather than copied forward

- **Changing an accessibility label silently breaks XCUITests.** They match and parse the
  *label*, not the drawn text, and CI runs neither affected suite. This is why #110 put the
  section eyebrow in the accessibility *value*: four assertions match headings by drawn text
  (`app.staticTexts["MyAnimeList"]`, `["More Like This"]`, `["Keep your library current"]`,
  `["Updates"]`), and folding it into the label would have broken all four silently. Grep the
  UI tests before touching any label.
- **CI is a major version behind local** — `macos-15` → Xcode 16.4 / Swift 6.0 vs local 26.x /
  6.2 (confirmed in `.github/workflows`). Green locally is not evidence for CI on new syntax.
- **Branch protection does not stop this account** — `enforce_admins: false`, required checks
  are "Build & unit tests" and "SwiftLint" (confirmed via the API today). A direct push to
  `main` lands and waives both. The PR flow is convention, not enforcement; ask first.
- **`project.pbxproj` churns under you** whenever Xcode has the project open. Check `git diff
  --stat` immediately before `git add`, not after. It bit this session: `xcp add-file` showed
  40 lines of unrelated churn, and re-running it after `git checkout` gave the clean 4-line
  insert.
- **A full CI run takes ~12 minutes.** `gh pr merge --auto` is better than waiting on it.

## Repository state

- `main` at `e23bdba`, working tree clean.
- `gh issue list`: **#90 only**. `gh pr list`: **empty**.
- Local branches: `main` plus a `worktree-helper` worktree. Nothing stale.
- `docs/superpowers/handoff/` holds this file and `archive/` (67 files). If it ever holds two
  `.md` files, someone skipped the rule.
