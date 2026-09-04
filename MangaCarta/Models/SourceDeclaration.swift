//
//  SourceDeclaration.swift
//  MangaCarta
//
//  A validated Source declaration — the record that says "this Source uses that engine
//  with this configuration". The Host API design's "Source declaration" section owns the
//  wire shape; this file owns the Swift value it becomes once every rule has been met.
//
//  An instance of this type is a Source the host has already agreed to register: its
//  capabilities satisfy the registration invariants, its origins are canonical HTTPS,
//  its adult class is stated, and its declared Host API range intersects this build's.
//  Nothing here is optional-because-we-were-unsure; everything absent has a stated
//  fail-closed meaning at the validator.
//

import Foundation

/// The installer-minted, repository-qualified identity of an installed Source.
///
/// The design's "Identity lifecycle" section makes the installer the owner of repository
/// identity: it combines that with the immutable `localId` to produce this id. The exact
/// encoding is private to the host. **Extension code and the UI receive this value and
/// must never construct or parse it** — the same `localId` from a different repository is
/// a different Source, and that only holds while nobody reads structure into the string.
///
/// The minting itself belongs to the installer (a later phase). This type is the seam:
/// validation takes an already-minted id as an input.
struct QualifiedSourceID: Hashable, Sendable {
    /// Opaque to everything but the installer. Store it, compare it, log it; never take
    /// it apart.
    let rawValue: String
}

/// The operations a Source may declare, named exactly as the design's "Entry points"
/// table names them.
enum SourceOperation: String, CaseIterable, Hashable, Sendable {
    case search
    case popular
    case newTitles
    case latestUpdates
    case tagBrowse
    case detail
    case chapters
    case pages
    case webURL

    /// "`search`, `detail`, `chapters`, and `pages` are required for a browsable/readable
    /// Source". Order is the reporting order when several are missing.
    static let requiredForReading: [SourceOperation] = [.search, .detail, .chapters, .pages]

    /// "at least one of `popular`, `newTitles`, or `latestUpdates` is required for Home
    /// discovery". These are also the only operations that can carry a presentation
    /// record, because they are the only ones that surface as a feed.
    static let discoveryFeeds: [SourceOperation] = [.popular, .newTitles, .latestUpdates]
}

/// The declared capability flags. Absence means unsupported, never "assume yes" — the
/// runtime calls only declared capabilities.
struct SourceCapabilities: Equatable, Sendable {
    private let enabled: Set<SourceOperation>

    init(enabled: Set<SourceOperation>) {
        self.enabled = enabled
    }

    func supports(_ operation: SourceOperation) -> Bool {
        enabled.contains(operation)
    }

    var missingReadingCapabilities: [SourceOperation] {
        SourceOperation.requiredForReading.filter { !supports($0) }
    }

    var hasDiscoveryFeed: Bool {
        SourceOperation.discoveryFeeds.contains(where: supports)
    }
}

/// The design's "Adult classification": required, and fail-closed. A missing or
/// unrecognized value prevents registration; it never defaults to `none`. Repository
/// review may strengthen a declaration but never weaken it.
enum AdultClassification: String, Equatable, Sendable {
    case none
    case mixed
    case adultOnly
}

/// The design's "Language contract" modes.
enum LanguageMode: String, Equatable, Sendable {
    case fixed
    case selectable
    case mixed
}

/// Canonicalized BCP 47 tags plus the mode that says how the host may use them. The host
/// never passes a language outside this set, and an unavailable one is an error rather
/// than a silent substitution.
struct LanguagePolicy: Equatable, Sendable {
    let mode: LanguageMode
    let tags: [String]
}

/// The declared HTTPS origins, by role. An omitted list denies that role rather than
/// opening it — see the "URL policy" section, which allows cross-origin CDN delivery
/// only when it is declared.
struct NetworkPolicy: Equatable, Sendable {
    let httpOrigins: [String]
    let browserOrigins: [String]
    let assetOrigins: [String]
}

/// The design's "Source-authored presentation" badge enum.
enum FeedBadge: String, Equatable, Sendable {
    case none
    case new
}

/// Semantics for one feed. The host still owns layout, rail count, order, typography,
/// color, accessibility wording and fallback copy; missing text uses host-localized
/// defaults rather than anything the Source chose.
struct FeedPresentation: Equatable, Sendable {
    let title: String?
    let eyebrow: String?
    let badge: FeedBadge
}

struct SourcePresentation: Equatable, Sendable {
    let feeds: [SourceOperation: FeedPresentation]

    /// The declared image-prefetch width, already clamped into the host's range. It is a
    /// hint, not an instruction: "Manifest concurrency values are hints clamped by the
    /// host." `nil` means the declaration asked for nothing and the host's own default
    /// applies.
    let imagePrefetchConcurrencyHint: Int?

    static let empty = SourcePresentation(feeds: [:], imagePrefetchConcurrencyHint: nil)
}

/// Host-side bounds applied while validating a declaration.
enum SourceDeclarationLimits {
    static let localIDLength = 1...64
    static let nameScalars = 80
    static let engineScalars = 64
    static let presentationTextScalars = 80

    /// OPEN EVIDENCE GATE. The design's first deliberately open gate is "exact request,
    /// response, CPU, wall-clock, storage, log, and concurrency limits", to be settled by
    /// the profiling corpus its "Scheduling, budgets, and cancellation" section names —
    /// the WeebCentral port, a configured Madara engine across at least three sites, one
    /// JSON API Source, low-memory devices, slow networks, Cloudflare, and background
    /// expiration. This clamp is provisional and deliberately conservative: it is the
    /// widest value the compiled sources already use, not a measured one. The behaviour
    /// that is NOT provisional is that a declaration is clamped rather than obeyed.
    static let imagePrefetchConcurrency = 1...8
}

/// A Source declaration that has passed every rule in the Host API design and may be
/// registered.
struct SourceDeclaration: Equatable, Sendable {
    /// Supplied by the installer, never derived from anything in the declaration.
    let qualifiedId: QualifiedSourceID
    /// Immutable across updates. Identity, unlike `name`.
    let localId: String
    /// Display text. Not identity: nothing may key off it.
    let name: String
    let engine: String
    /// The engine's private vocabulary, carried verbatim. Unknown keys survive *here*
    /// and nowhere else in the record.
    let configuration: JSONValue
    let adult: AdultClassification
    let capabilities: SourceCapabilities
    let languages: LanguagePolicy
    let network: NetworkPolicy
    let presentation: SourcePresentation
    let hostAPI: HostAPIVersionRange
    /// The highest version this build implements that lies inside `hostAPI`.
    let selectedHostAPIVersion: HostAPIVersion
}
