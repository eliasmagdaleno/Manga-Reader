# Handoff — MyAnimeList OAuth and reading-progress tracking next

Session of 2026-08-21. The simulator-fixture cleanup is complete; the next product
subsystem in the original roadmap is MyAnimeList account authentication and reading-progress
tracking. Start with a design/spec session. There is no approved implementation spec yet.

## Start here

1. Finish [PR #68](https://github.com/eliasmagdaleno/Manga-Reader/pull/68) before branching.
   It is a clean draft from `seed-history-dates` at `727e2ed`; SwiftLint and Build & unit
   tests both pass. It makes fixture history span realistic dates and is unrelated to MAL
   authentication.
2. Return to updated `main`, create a new design branch, and verify the current MAL OAuth and
   manga-list API contract against **official MyAnimeList documentation**. Treat endpoint,
   PKCE, callback, token-expiry, and list-update details in old notes as unverified until then.
3. Write the design to `docs/superpowers/specs/`, get the product decisions below settled,
   then write a task-by-task implementation plan in `docs/superpowers/plans/`.

Completion criterion for the fresh session: an approved design that accounts for every auth
state, progress trigger, conflict rule, credential-storage boundary, and failure/retry path.
Do not begin production implementation while those decisions are implicit.

## Why this is next

The original source-abstraction roadmap names five ordered subsystems:

1. source abstraction — shipped;
2. a second source — shipped (WeebCentral);
3. cross-source search — shipped;
4. **MyAnimeList tracking — next**;
5. discovery and reading-taste data visualization — later.

The read-only MAL client, cross-source entity resolution, More Like This, and the MAL-backed
For You blend have all shipped. The unchecked boxes in the old implementation-plan files are
stale bookkeeping, not unfinished work. The two roadmap sources that exposed the missing next
step are outside `docs/`:

- `/Users/eliasmagdaleno/.claude/projects/-Users-eliasmagdaleno-Manga-Reader/memory/multi-source-roadmap.md`
- `/Users/eliasmagdaleno/.claude/projects/-Users-eliasmagdaleno-Manga-Reader/memory/recommender-roadmap.md`

Repository pointers: `README.md` still lists MAL OAuth/progress under Deferred, and
`docs/superpowers/specs/2026-07-14-source-abstraction-design.md` contains the five-part order.

## Existing MAL and reading seams

- `Manga-Reader/Models/MyAnimeListAPI.swift` is read-only. Its generic request helper sends
  `X-MAL-CLIENT-ID`; it has no bearer-token path, account models, token refresh, or write
  endpoints. Preserve the public read-only behavior used by entity resolution and recommendations.
- `MALClientID` is supplied through the gitignored `Secrets.xcconfig` and merged through
  `Manga-Reader/Info.plist`. Do not replace this with `INFOPLIST_KEY_MALClientID`: arbitrary
  custom keys are not synthesized by that build setting in this project.
- `Manga.malId` and `Work.externalIds.mal` already carry canonical MAL identity. MangaDex
  listings usually provide it directly; scraped sources may acquire it through the metadata
  upgrade queue. A progress write needs an authoritative MAL id and must have an honest state
  when none exists.
- `HistoryStore.record` is the single progress-persistence door. `ReadingEntry.isComplete`
  means `pageCount > 0 && page >= pageCount - 1`; opening a chapter no longer marks it read.
- `ReaderView.recordProgress` calls the store throughout reading. Do not emit a network write
  for each page callback. Design a durable, deduplicated boundary around chapter completion.
- `HistoryStore`, `WorkStore`, and `MetadataUpgradeQueue` are owned by `AppComposition` /
  `Manga_ReaderApp`; app backgrounding already flushes local stores. Authentication and sync
  services should be composed and testable rather than reached through new globals.
- Settings currently has Library, Appearance, Sources, and About sections. It is the natural
  account/sign-in surface, but the design must decide the exact signed-out, authorizing,
  signed-in, expired, and error presentations.

## Product decisions the design must settle

### Authentication

- Use the current MAL-supported native-app OAuth flow and PKCE requirements as documented
  officially. Decide callback routing and whether `ASWebAuthenticationSession` is the host.
- Store refresh/access credentials in Keychain, not UserDefaults or repository files. Define
  logout, revoked authorization, refresh failure, cancellation, and reinstall behavior.
- Decide whether sign-in is optional (the existing reader must remain fully usable signed out),
  and what user identity/account metadata is shown in Settings.

### What “reading progress” means

- Choose the write trigger. The strongest existing local signal is transition to
  `ReadingEntry.isComplete`; page turns and merely opening a chapter are not completion.
- Reconcile local chapter numbers (`Chapter.number` is a `String` and can be decimal, special,
  missing, or non-numeric) with MAL's current progress representation. Specify behavior for
  chapter `0`, `12.5`, extras, one-shots, unknown totals, and rereads before coding.
- Define monotonicity. A stale local event must not move remote progress backwards. Decide
  whether manual mark-read actions publish, whether mark-unread can decrement MAL, and whether
  “mark all below” produces one coalesced update or no remote mutation.
- Decide which library/list status accompanies progress (`reading`, `completed`, etc.), when a
  title is added to the MAL list, and whether completion follows known chapter totals.

### Sync direction and durability

- The roadmap says “OAuth + push reading-progress tracking”; keep v1 push-only unless the user
  explicitly expands scope. Importing/pulling the MAL list is a separate conflict-resolution
  product problem.
- A transient network failure must not lose completed progress. Design an on-disk outbox keyed
  by MAL id with monotonic coalescing, retry/backoff, cancellation, and foreground/background
  behavior. Reuse the queue vocabulary from `MetadataUpgradeQueue` where helpful, without
  coupling unrelated responsibilities.
- Define permanent failures (revoked token, invalid id, rejected progress) separately from
  transient transport/rate-limit failures and give the user a recoverable, non-spammy signal.
- Decide whether updates wait until an unresolved Work gains a MAL id. If they do, identify the
  event that releases queued progress after metadata upgrade.

### Testability and privacy

- Put URLSession/auth presentation/Keychain/time behind narrow protocols. Unit tests must not
  need live credentials or mutate the user's real Keychain/MAL list.
- Test PKCE and callback validation as pure logic where possible; test token refresh
  single-flight behavior, outbox persistence/coalescing, retry classification, logout cleanup,
  and completion-trigger idempotence.
- Live verification performs an external write to the user's MAL account. Preview the exact
  title/progress mutation and obtain explicit approval immediately before that run; use a title
  whose prior remote state is known and restore it afterward if the protocol requires cleanup.

## Scope guardrails

Keep the first design centered on optional sign-in plus reliable push-only progress. These are
separate roadmap items unless the user deliberately pulls them in:

- pulling/importing a MAL library and bidirectional conflict resolution;
- cross-device sync for the app's own History/Library/Works;
- social features, scores, reviews, or favorites;
- reading-taste visualization (roadmap subsystem 5);
- hot-loadable JavaScript sources, comix.to, or additional native sources;
- reverse resolution beyond MangaDex, which was measured and rejected on 2026-08-15.

## Repository and simulator state

- Current branch when this handoff was written: `seed-history-dates`, tracking origin, commit
  `727e2ed`; PR #68 is open as a clean draft with both checks green.
- Required test destination: `platform=iOS Simulator,name=iPhone 17 Pro`; always include
  `-parallel-testing-enabled NO` for `xcodebuild test`.
- The iPhone 17e simulator was deleted. The iPhone 17 Pro is the sole seeded project fixture.
- The Pro fixture has 22 Works (20 AniList-resolved), 18 history entries over 18 dates, and a
  passing AniList pool gate. Its pre-reseed backup is
  `.simulator-backups/2026-08-21-043643/` (gitignored).
- The working tree also contains user-owned skill installation changes (`skills-lock.json`,
  `.agents/skills/`, `.claude/skills/`, and untracked `AGENTS.md`). Preserve them and stage only
  files belonging to the MAL branch.

## First useful questions for the user

The fresh design session should lead with these choices:

1. Is v1 strictly push-only, or should signing in also import the user's MAL manga list?
2. Should completing a chapter automatically add an absent title to the MAL list as “reading”?
3. Should manual mark-read actions sync, or only chapters actually completed in the reader?
4. Is MAL progress allowed to move backwards after mark-unread/rereading, or always monotonic?

Everything else can be derived or researched after these four product decisions are explicit.
