# ADR-0022 — The release build ships no adult source, and hides the control for one

- **Status:** Accepted (2026-08-31)
- **Related:** ADR-0003, ADR-0016

## Context

The app has a third source — an adult one — built and working. It lives only on the local-only
`nhentai` branch and has never been pushed or merged. The gating machinery for it, however,
shipped to `main` long ago as part of extension-system Phase 1: `MangaSource.isNSFW`,
`SourceRegistry.visibleSources(includeAdult:)`, `enforceAdultGating(includeAdult:)`, and a
"Show adult sources" toggle in Settings backed by `settings.showAdultSources`.

Both registered sources declare `isNSFW = false`. So the build that would go to review today
already contains a Settings switch that changes nothing observable.

The first submission of an unknown app is the point of maximum review scrutiny and minimum
accumulated goodwill. Adult content is not forbidden on the App Store, but it is the single
largest review risk this app carries, and it is a risk taken on behalf of a source that is not
on the critical path for anything: Phases 2–5 are the extension system, and once that ships an
adult source is something a reader installs rather than something the app ships.

The decision is worth making **now** rather than at submission, because the cost being avoided
is entanglement. Every subsequent phase that treats the adult source as present — a theme
engine that assumes it, a repo listing that includes it, a test fixture that registers it — makes
removal more expensive. That accrues whether or not anyone has touched the code, which is exactly
the kind of cost a written decision made early is for.

## Decision

**The release build registers no source whose `isNSFW` is true.**

Enforced by *not merging* — the `nhentai` branch stays local-only, as it always has. No build
configuration, no compile-time flag, no release-only exclusion path.

**And Settings hides the "Show adult sources" toggle while no registered source declares
`isNSFW`.** A control that changes nothing is worse than no control: it invites a reviewer to go
looking for the behaviour it is supposed to gate, which is the exact attention this decision
exists to avoid, and it is equally confusing to a reader who flips it and sees nothing happen.
The toggle's stored preference is untouched — hiding the control does not clear it — so a build
that registers an adult source shows the switch again with its previous value intact.

## Alternatives considered

**Ship it gated behind the existing opt-in.** The machinery is real and the content is behind a
default-off switch. Rejected: a default-off switch is not a defence at review time, since a
reviewer's job is to find what is behind it, and the goodwill spent is spent on the submission
that can least afford it.

**A build-configuration exclusion — a release flag that strips adult sources even if one is
registered.** Rejected as a mechanism built to defend against a merge that *is itself* the
decision. It is cheaper not to merge than to build a machine that survives merging by mistake,
and the machine would need its own tests and its own maintenance through Phases 2–5.

**Leave the toggle visible.** Rejected for the reason in the Decision. It was left visible only
because nothing prompted a look at it once the adult source moved to a private branch.

## Consequences

- The public release ships MangaDex and WeebCentral. Nothing else changes about them.
- **The gating machinery stays.** `isNSFW`, `visibleSources(includeAdult:)` and
  `enforceAdultGating(includeAdult:)` are not deleted, and they keep their tests. This decision
  reverses by registering a source — it does not require rebuilding what would then be needed.
- Once the extension system ships, an adult source becomes a thing a reader installs. That is a
  different decision, about what the installer permits and what a repo may list, and it should be
  made in that context rather than inherited from this one. Expect to revisit this at Phase 4.
- Anyone reading `SettingsView` will find a toggle rendered conditionally for a reason that is
  not local to the file. The condition cites this ADR.
