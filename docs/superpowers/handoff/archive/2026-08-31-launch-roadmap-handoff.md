# Handoff — a launch roadmap, and Phase 1 started

Date: 2026-08-31 (night)
Repository: `/Users/eliasmagdaleno/Manga-Reader`
Branch: `docs/launch-roadmap-2026-08-31` off `main` at `bf3ac42`.

**This is the live handoff, and it is the whole of what is outstanding.** Writing a new one
means `git mv`-ing this into `archive/` first and carrying forward whatever below is still
true. That is the convention (`CLAUDE.md` → "Handoffs").

This document supersedes the accessibility handoff, whose two owed threads are carried forward
below unchanged in substance. What is new is a **launch roadmap** the user asked for, and the
research behind it.

## The goal, in the user's words

Ship to the App Store. Three features named as the priorities: **MAL progress push**,
**switching sources from the manga detail page**, and **user-installable extensions in the
shape Paperback has**. An icon is being outsourced. The user initially asked for three weeks,
then dropped the fixed deadline in favour of a sequence that is actually achievable.

## Two corrections that reshaped the plan

Both were mine, made earlier in the same session, and both are the kind of error that survives
into a plan if nobody writes them down.

**MAL progress push is already built.** I reported it missing off a grep for `pushProgress` /
`updateMyListStatus`; the real method is `updateProgress`. What actually exists on `main`:
`MALProgressCoordinator` (serial drain, pause/retry, defer-and-promote for Works that have not
yet learned a MAL id), `MALProgressOutbox` (durable queue, backoff, keyed per user),
a "Sync reading progress" toggle plus queue status in `MALAccountSettingsView`, wired through
`AppComposition`, covered by `MALProgressCoordinatorTests`, `MALProgressOutboxTests`,
`MALReadingProgressTests`. Landed as tasks 8 and 10 of
`docs/superpowers/plans/2026-08-21-mal-oauth-progress.md`.

**What is actually owed on it is a live end-to-end check** against the user's real MAL account,
on a device: read a chapter to the end, confirm the chapter number moves on myanimelist.net.
Unit tests cannot show that. `scripts/mal_live_write.py` exists for poking the API directly if
the in-app path needs isolating.

**Source switching is half-built, not unbuilt.** `Work.listings: [ListingKey]` already exists
and `WorkStore` already merges listings onto a Work. What is missing is ADR-0004's *ranking* and
the picker UI — `MangaDetailView` currently renders a static `SourceStamp` (line ~151).

The lesson is the one already in memory as `verify-absence-claims-before-building`: grep is not
reading, and an absence claim about your own codebase needs the same proof as one you read in a
doc.

## Catalog research — the finding that reorders the extension work

The user's worry: "people won't want to use the app if I have significantly less sources."
Fair, so I went and counted. (Note: MangaDex is a *single source*, not an aggregator — it has no
source list underneath it. The comparison that matters is Paperback.)

Current-generation Paperback registry is **Inkdex**, and it is organised **by site theme**, not
by site. Counts from each repo's `src/` on 2026-08-31, excluding `generic`/`tests`/`utils`:

| Repo | Sources | Examples |
|---|---|---|
| `inkdex/general-extensions` | 23 | MangaDex, MangaFire, Mangago, Mangapill, Webtoon, MangaPlus, **WeebCentral**, Comix, FlameComics, MangaKatana, RoyalRoad |
| `inkdex/madara-extensions` | 29 | Toonily, HiperDex, KunManga, MangaReadOrg, ManhuaPlus, ManhwaClub/Raw/Top, ToonGod, WebtoonXYZ |
| `inkdex/mangastream-extensions` | 7 | Thunderscans, SushiScans, LelManga, RageScans, DrakeScans, ManhwaX |
| `inkdex/mangabox-extensions` | 4 | MangaKakalot, MangaNato, MangaNelo, MangaBat |
| `inkdex/liliana-extensions` | 3 | MangaKoma, ManhuaPlus, Raw1001 |
| `inkdex/mangaworld-extensions` | 2 | MangaWorld, MangaWorldAdult |

**≈68 sources.** Older independent repos remain in use on 0.8: `thenetsky/netskys-extensions`
(14 — MangaFox, MangaHere, Mangahub, Dynasty Scans, MangaDemon…), `xonlyfadi` (7 — ComicK, TCB
Scans, MangaFreak, Voyce.Me…), `pandeynmn` (2 — ReaperScans, Zero Scans), plus NSFW-only repos.
Fetch any of them as `<pages-url>/0.8/versioning.json` to re-count; the 0.9 manifest is a
different format and is **not** at that path — I did not find it, so treat the 0.9 numbers above
as directory counts rather than manifest counts.

**55 of the ~68 are generic-theme sites.** Madara, MangaStream, MangaBox, Liliana and
MangaWorld are off-the-shelf CMS themes that scanlation sites deploy unmodified. Each of those
repos holds exactly one real parser (`generic`) plus a small per-site config — typically a base
URL and a few selectors.

**The consequence for the host API, and it is the load-bearing one:** catalog parity is not 68
scrapers. It is roughly **5 theme engines + 23 bespoke sources**, where a new Madara site is a
config file. So the host API must be designed from day one for **an extension that takes
configuration**, not only one-extension-per-site. Retrofitting that is the kind of API churn
ADR-0003 warns kills extension systems.

The hard part is already done here: `WebViewService` beats Cloudflare, which is what actually
kills scrapers.

## The roadmap

No fixed deadline; sequenced by dependency. Ranges are working estimates, not commitments.

**Phase 1 — finish what is nearly done (~1 week). STARTED, see below.**
Detail-page source picker per ADR-0004; live-verify MAL sync on device; run the VoiceOver pass
(#90) while a device is in hand anyway.

**Phase 2 — host API design (~1–1.5 weeks).** Spec plus an ADR amending 0003. The forever
contract, and the phase least worth rushing. Deliverable: an API validated on paper against
both WeebCentral *and* a Madara config.

**Phase 3 — JavaScriptCore runtime + WeebCentral port (~2 weeks).** Build the bridge; port
`WeebCentralSource` from Swift to a JS extension. Identical behaviour is what proves the API.

**Phase 4 — repo format + installer (~1–1.5 weeks).** Add-repo-by-URL, install, remove, update.
Deliberately boring.

**Phase 5 — theme engines (~1 week for Madara, then days each).** Madara first: 29 sites.

**Phase 6 — launch prep (~1 week).** `PrivacyInfo.xcprivacy`, icon integration, screenshots,
privacy-policy URL, TestFlight soak.

**≈8–9 weeks of focused work.** The three-week version only exists if extensions are cut, which
defeats the catalog-breadth goal that motivated them.

### Decision recorded: keep MangaDex built-in

ADR-0003 concludes "ship zero built-in aggregator sources." **Do not follow that literally
without revisiting it**, because ADR-0016 makes MangaDex the *resolution bridge* that mints MAL
ids — which powers For You, More Like This, and the progress sync above. An empty reader with no
built-in MangaDex silently guts three shipped subsystems. Recommended and agreed in discussion:
keep MangaDex built-in, make extensions **additive**, revisit only if App Review forces it.
This is not yet written as an ADR amendment; Phase 2 should do that.

## Launch blockers that are not features

- **No app icon.** `Manga-Reader/Assets.xcassets/AppIcon.appiconset/` holds only
  `Contents.json`. Being outsourced — order it early so it is not the long pole.
- **No `PrivacyInfo.xcprivacy` anywhere in the project.** Required at submission; `UserDefaults`
  and file-timestamp APIs both need declared reason codes.
- **Adult-source gating is the single largest review risk.** The Settings toggle that reveals
  adult sources needs a decision before submission. The adult source itself lives only on the
  local-only `nhentai` branch (never pushed) — so "drop it from the release build" is close to
  free today and gets more expensive later.
- No listing screenshots, no privacy-policy URL, no App Store description, no TestFlight run.
- `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1` — fine, but bump deliberately.

## Carried forward, still owed

### 1. The manual VoiceOver pass — #90, and it is the user's to run

Open, `ready-for-human`, **no row has a verdict yet**. No results file in `docs/accessibility/`,
which is how you can tell at a glance the pass has not started. Everything a code change can do
for it is done.

Run `./scripts/voiceover-pass.sh` from the repo root. It parses the checklist at runtime, takes
pass/fail/skip per row, writes `docs/accessibility/voiceover-results-<date>.md`, and resumes
where it stopped. It needs a **real iPhone** — simulator VoiceOver differs on the rotor and on
focus restoration, which is most of what these rows test.

Rows most needing eyes, all reasoned from code and never observed: **4.3** (are the custom read
actions still reachable now the row is one element?), **6.5** (are the reader pages reachable at
all?), **7.2** (#110 changed it — the Headings rotor should now have stops), **7.5** and **7.6**
(rotation and accessibility text sizes; not auditable from code at all).

Close #90 when every row has a verdict, **not** when every defect is fixed. A row that turns out
fine is still a result.

### 2. The duplication shape of doc rot — untouched, agent work

#113 fixed only *snapshots that never expire*. The other shape is **the same fact in two places,
one of them updated** — three of the five known instances.

The work: audit the durable docs against reality — `CLAUDE.md`, `DESIGN.md`, `PRODUCT.md`,
`README.md`, `docs/glossary.md`, `docs/agents/*.md`, and the memory files under
`~/.claude/projects/-Users-eliasmagdaleno-Manga-Reader/memory/`. Every factual claim about the
code should be grep-verifiable *now*.

**ADRs are the exception** — dated decision records, supposed to freeze. Amend, as ADR-0019
amendment 1 does; never "correct" one.

Worth deciding before starting: whether the fix is a one-time audit or something structural, the
way #113 was for snapshots. A one-time audit produces instance six eventually.

Note this handoff adds a sixth instance to fix: `CLAUDE.md`'s "Current state" says "Content
refresh is no longer manual-only", while `PRODUCT.md` still says "Content refresh is currently
user-initiated." ADR-0021 shipped; `PRODUCT.md` did not hear about it.

## Gotchas

Carried forward and still true; re-verify rather than trusting this list if one becomes
load-bearing.

- **Changing an accessibility label silently breaks XCUITests.** They match and parse the
  *label*, not the drawn text, and CI runs neither affected suite. Four assertions match
  headings by drawn text (`app.staticTexts["MyAnimeList"]`, `["More Like This"]`, `["Keep your
  library current"]`, `["Updates"]`). Grep the UI tests before touching any label.
- **CI is a major version behind local** — `macos-15` → Xcode 16.4 / Swift 6.0 vs local 26.x /
  6.2. Green locally is not evidence for CI on new syntax. Isolated conformances,
  `nonisolated(nonsending)`, `@concurrent`, `Task.immediate` are unavailable.
- **Branch protection does not stop this account** — `enforce_admins: false`; required checks
  are "Build & unit tests" and "SwiftLint". A direct push to `main` lands and waives both. The
  PR flow is convention, not enforcement; ask first.
- **`project.pbxproj` churns under you** whenever Xcode has the project open. Check `git diff
  --stat` immediately before `git add`, not after.
- **A full CI run takes ~12 minutes.** `gh pr merge --auto` beats waiting.
- **Target the iPhone 17 Pro simulator** on every `xcodebuild` — it holds the seeded fixture.

## Repository state

- `main` at `bf3ac42`; this branch `docs/launch-roadmap-2026-08-31` off it.
- `gh issue list`: **#90 only**. `gh pr list`: empty at the time of writing.
- Unit suite on `main`: **603 pass, 0 failures**, 2 skipped.
- `docs/superpowers/handoff/` holds this file and `archive/` (68 files). If it ever holds two
  `.md` files, someone skipped the rule.
