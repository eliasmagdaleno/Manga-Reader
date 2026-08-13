//
//  VerificationSwitches.swift
//  Manga-Reader
//
//  Debug-only instrument for the ADR-0019 Amendment 1 verification run
//  (`docs/superpowers/specs/2026-08-11-adr-0019-amendment-1-run-protocol.md`).
//
//  **Why this exists at all.** The bridge is live in shipped code, so refusals the bridge
//  recovers never appear as refusals — and Amendment 1's claim is about refusals that
//  *then* recover. Observing that needs a pass with the bridge off to close a cohort, and
//  a pass with it on to see what clears. There is no way to get the first pass out of the
//  app without a seam.
//
//  **Why `#if DEBUG` rather than a launch argument alone.** A release build cannot take
//  this path at all — the code is not in it. The switch is read from the environment, so
//  nothing in the app's own state or UI can reach it either; it takes an `xcodebuild` /
//  `simctl` invocation that deliberately sets the variable. With neither variable set, the
//  graph `AppComposition` builds is unchanged: `resolver` stays nil and
//  `MetadataUpgradeQueue` builds its own exactly as before.
//
//  This is a measuring instrument, not a feature flag. It has no product meaning, and it
//  should be deleted when the runs it serves are written up — see the amendment's deadline.
//

#if DEBUG
import Foundation

enum VerificationSwitches {
    /// `ADR0019_BRIDGE=off` injects a bridge that finds nothing, closing a refusal cohort
    /// that the live bridge would otherwise have dissolved.
    private static var bridgeDisabled: Bool {
        ProcessInfo.processInfo.environment["ADR0019_BRIDGE"] == "off"
    }

    /// `ADR0019_BRIDGE_LOG=<path>` appends one line per bridge query. This is what the
    /// gate leg is observed through: the gate holds if no MangaDex-sourced Work's title
    /// appears here. Logging the *request* rather than the result is deliberate and is the
    /// same reasoning the gate's unit tests use — both configurations return nil, so only
    /// the query distinguishes "declined to ask" from "asked and found nothing".
    private static var bridgeLogPath: String? {
        ProcessInfo.processInfo.environment["ADR0019_BRIDGE_LOG"]
    }

    /// The resolver the run needs, or **nil when neither variable is set** — which is the
    /// production case, and leaves `MetadataUpgradeQueue` to build its own.
    @MainActor
    static func resolver() -> MALEntityResolver? {
        let disabled = bridgeDisabled
        let logPath = bridgeLogPath
        guard disabled || logPath != nil else { return nil }

        let bridge: MALEntityResolver.BridgeSearch = { title in
            if let logPath {
                let line = "\(Date().timeIntervalSince1970)\t\(title)\n"
                if let handle = FileHandle(forWritingAtPath: logPath) {
                    handle.seekToEndOfFile()
                    try? handle.write(contentsOf: Data(line.utf8))
                    try? handle.close()
                } else {
                    try? Data(line.utf8).write(to: URL(fileURLWithPath: logPath))
                }
            }
            // Logged *before* the guard, so a query that the switch suppresses is still
            // visible as having been asked for. Nothing in the run depends on that today;
            // it matters if a future pass logs with the bridge off.
            if disabled { return [] }
            return try await MALEntityResolver.liveBridgeSearch(title)
        }

        // `.shared` for the same load-bearing reason `MetadataUpgradeQueue` documents:
        // `EntityResolutionStore` reads UserDefaults once in `init`, so any other instance
        // is frozen at launch and the free cache fast path silently dies (ADR-0010).
        return MALEntityResolver(store: .shared, bridgeSearch: bridge)
    }
}
#endif
