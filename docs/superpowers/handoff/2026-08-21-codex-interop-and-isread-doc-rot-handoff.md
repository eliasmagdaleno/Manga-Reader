# Handoff — Codex interop, and the `isRead` doc rot

Session of 2026-08-21 (early). **Updated later the same day: PR #70 merged as `13346d7`, and
`main` is now there.** Nothing from this session is left open except this handoff itself.

(As originally written this said `main` was at `eb8a2de` with #70 open — true at the time,
and corrected here rather than left to rot, which is the very lesson below.)

## The one-paragraph version

A Codex session now works this repo alongside Claude Code, and the two share a single
checkout — which already caused a branch to switch mid-commit. The docs the two agents read
had silently diverged: `AGENTS.md` was a byte-identical copy of `CLAUDE.md` carrying a wrong
definition of `isRead`, introduced by the session that changed `isRead` and never went back.
PR #70 corrects the definition and replaces the copy with a symlink so the two cannot drift
again. The MAL OAuth subsystem is Codex's, in progress on `mal-oauth-progress-plan`.

## Merged: PR #70

[#70](https://github.com/eliasmagdaleno/Manga-Reader/pull/70) — `codex-docs-sync`, three
changes in one commit (`5ff46cb`):

1. **`isRead` corrected in `CLAUDE.md`.** It read "opened or manually marked". True when
   written on 2026-08-20, invalidated by #65 later the same day, never updated. It is now a
   completed entry (`ReadingEntry.isComplete`) or a manual mark.
2. **`AGENTS.md` is now a symlink to `CLAUDE.md`** (mode `120000`). It was byte-identical
   below its header, so it was a copy, not a Codex-specific document — and the stale line is
   what a copy costs. The header is now tool-agnostic.
3. **The shared skill installation is committed** — eight Swift/iOS skills under
   `.agents/skills/`, the `.claude/skills/` symlinks into them, and `skills-lock.json`.

Merged as `13346d7` on 2026-08-21, both CI checks green; `codex-docs-sync` is deleted. If the
symlink ever turns out wrong for Codex, replace it with a real file — don't reintroduce a copy.

## The gotcha that matters most: one checkout, two agents

`orca worktree ps` shows a **single** worktree at `/Users/eliasmagdaleno/Manga-Reader`. Both
agents work there. Observed consequences this session:

- The branch switched from `codex-docs-sync` to `mal-oauth-progress-plan` **mid-session**,
  under a running Claude Code session. Work survived only because it was already committed
  and pushed.
- Files that were untracked one minute were tracked-on-another-branch the next, so they
  vanish from the working tree on checkout. That is normal git, but it reads as data loss.
  Verify with `git ls-tree -r --name-only <branch>` before concluding anything is gone.

**Before `git add`, always check `git branch --show-current`.** Commit early. Better: give
each agent its own worktree —
`orca worktree create --name <task> --no-parent --json` — and the collision stops.

Orca notes: executable resolves to plain `orca` here (macOS, no `ORCA_CLI_COMMAND`). Load the
version-matched guide with `orca skills get orca-cli` rather than recalling flags; they change
between releases. A worktree id is a two-part address, `<repoId>::<path>` — copy it whole.

## The lesson: absence and staleness rot silently

Two days running, the same failure in a different costume:

- 2026-08-20: `CLAUDE.md` claimed per-chapter read/unread marks did not exist. They had
  shipped five weeks earlier. A handoff repeated the claim and pointed a session at
  already-built work.
- 2026-08-21: `CLAUDE.md` claimed `isRead` meant "opened". The session that wrote that line
  changed the meaning in its very next PR and never revisited the line — then it was copied
  into `AGENTS.md`, reaching a second agent.

Nothing fails when a doc goes stale, which is exactly why it does. Memory
`verify-absence-claims-before-building` covers the first case. The second adds: **when you
change a behaviour, grep the docs for the old description in the same commit.**

## What Codex owns

`mal-oauth-progress-plan` carries `6f47072` (design) and `56800b5` (completion-trigger
semantics), with research, spec, and plan under `docs/superpowers/`. Do not commit to that
branch or edit those files without coordinating.

The MAL design's write trigger is transition to `ReadingEntry.isComplete`. Note the seeded
fixture moved under #65: **14 of 18 history entries are complete**, four are mid-chapter
(Kingdom 3/6, Kaguya-sama ch2 3/19, +2). Anything asserting "18 read" will see 14; that is
not a regression.

## What is worth doing next

1. ~~Merge or close #70.~~ Done — `13346d7`.
2. **Give each agent its own Orca worktree**, so the shared-checkout collisions stop.
3. **Let Codex finish the MAL subsystem**; the four product decisions in the 2026-08-21 MAL
   handoff (push-only vs import, auto-add, manual-mark sync, monotonicity) may still be
   unanswered — check before implementation starts.
4. **Reverse resolution beyond MangaDex** stays parked — measured and rejected 2026-08-15.
