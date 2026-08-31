# Session Handoff — 2026-08-08: composition coverage + per-item visibility

**Audience:** the next session. Supersedes `2026-08-08-adr-0015-shipped-queue-drained-handoff.md`,
whose "what to pick up" recommendation this session **overturned** — see below before acting on it.

**Work in flight:** one committed, unpushed branch — `per-item-visibility` (`888e404`).

## State

| | |
|---|---|
| `main` | **`3e04fcc`** — "Test the composition root, and stand ADR-0005 down (#35)", squashed, CI green |
| Branch | `per-item-visibility` at `888e404`, committed, **not pushed, no PR** |
| Tests | **436 pass / 1 skipped / 0 failures** on the branch |
| ADRs | 0001–0015 Accepted; 0005 amended twice today (target moved, then first requirement shipped) |

## What this session did

Two things, both starting from the previous handoff's recommendation to build ADR-0005.

**1. Stood ADR-0005 down, and covered the composition root (merged, PR #35).** Grilling ADR-0005
against the call sites said *don't build it*: it describes Listing → Work, but `SourceRegistry`
registers two sources and MangaDex hands over `malId` free, so every silently-unresolved Work today
failed at **Work → MAL id** — `setExternalIds`, not the `merge` the old handoff cited as evidence
*for* picking it up. Its premise (ADR-0003's growing source count) is shelved. It fails ADR-0015's
own "reported, not inferred" standard. The decision stands; the target moved and the build is
blocked on a report.

Alongside it, `AppComposition` extracted the object graph out of `Manga_ReaderApp.init` with storage
injectable, and `AppCompositionTests` builds the real graph against a temp directory. This closed a
gap that mattered: deleting `tagBlocked:` from the root broke **none** of the 433 tests, because
every engine test builds its own graph. Mutation-checked.

**2. Shipped the per-item visibility gap (`888e404`, unpushed).** `UnmatchedTitleNotice` in
`MangaDetailView`'s "More Like This" slot, for a Work the drain has refused. One method
(`RecommendationEngine.isUnmatchable`) wrapping the same `tagBlocked` closure the rail state uses, so
the two surfaces cannot disagree. Statement only, no action. Full reasoning is in ADR-0005's
amendment and in the commit message.

## What the device check corrected — the part worth carrying

The design premise was "the More Like This section is empty for this title, from the same cause."
**That is not automatic.** `MoreLikeThisProvider` resolves through `MALEntityResolver.malId(for:)`,
which is **Listing-keyed** and independent of the Work-level `UpgradeAttemptMemory` the drain writes.
They agree in the ordinary case — a Work minted from one Listing carries that Listing's title, so both
matchers see the same string — but they are two resolvers and can differ. The notice is gated on the
rail being empty **and** the Work being refused, never the refusal alone.

## Device-check gotchas, learned the hard way

The recipe in the prior handoff works, but three fixture mistakes each produced a convincing wrong
answer before being caught. All three cost a full run:

- **Opaque *ids* are not enough — the titles must be unmatchable too.** Matching is by title. Seeding
  real titles ("Kagurabachi") with opaque ids gets a fully populated More Like This rail, because MAL
  matches the title fine. Use invented titles ("Zurnak Vhelli").
- **Do not reuse `mangaId`s across seeds.** `EntityResolutionStore` is keyed `sourceId:mangaId` and
  **keeps hits forever**, so a second seed under the same id inherits the first one's resolution and
  shows a *different* title's recommendations. Looks exactly like a bug. Uninstall the app or use
  fresh ids.
- **A history row taps through to the Reader, not Detail.** Detail is behind the row's context menu
  ("View Manga Details"), so a UI test must `press(forDuration:)` first.

Two more:

- **`app.otherElements["…"]` does not resolve for a plain SwiftUI `VStack` carrying only an
  accessibility identifier.** The assertion fails while the view renders perfectly — a false
  negative. This is already documented at `Manga_ReaderUITests.swift:140` for the same reason; trust
  the screenshot. The device check "failed" on every run and was correct every time.
- **The drain re-creates `upgrade-attempts.json` by itself.** Deleting the file as a negative control
  does not work — the queue re-refuses genuinely unmatchable titles within seconds. This turned out
  to be *better* evidence than the hand-written fixture, since the state was produced by the real
  drain. For a true negative, use a title MAL *can* match.

## What to pick up

1. **Push `per-item-visibility` and open a PR.** It is committed and green locally; nothing else
   blocks it.
2. **Then re-examine what the notice's copy promises.** It says reading the title "isn't shaping your
   For You recommendations". That is true of an untagged Work, but the Work still contributes
   *engagement weight* (`TasteProfile.swift:110`) — ADR-0015's own Context calls this out: "it looks
   like signal and counts as none." The sentence is right about the tag axis and loose about
   everything else. Worth one honest look, not a rewrite by reflex.
3. **The mixed-library hazard is unchanged** and still not due until reported — but this notice makes
   it *reportable* for the first time, which is a real change in its status.

## Also open, unchanged

- `malId` on `LibraryItem` so saved seeds skip the title search; More Like This reverse-resolution
  beyond MangaDex-only.
- No automated coverage of `HomeView`'s rail branch or of `MangaDetailView`'s new branch. Both are
  deliberate — see `AppCompositionTests`' header for the reasoning.
- **Standing constraint:** the extension/repo system and comix.to are shelved since 2026-07-21.

## Machine-migration leftovers

- **`xcp` was not installed on this machine** — the `CLAUDE.md` workflow assumes it. Installed here
  (1.2.1, the version that doc verified). `NEW-MAC-SETUP.md` in `~/Downloads` is still stale and does
  not mention it.
- `project.pbxproj` churned again during plain `xcodebuild` runs: 34 lines of synchronized-group
  reformatting on a change that needed **zero** pbxproj edits. Reverted before committing. Check
  `git diff --stat` before every `git add` — the caveat in `CLAUDE.md` is accurate.
