import Foundation

/// Placeholder thresholds for ADR-0021. None has been measured on a device.
/// Revisit them with measured device data if background runs expire before useful
/// coverage or source rate limits reject the requested cadence.
enum UpdateTuning {
    static let freshWindow: TimeInterval = 6 * 60 * 60
    static let staleAfter: TimeInterval = 24 * 60 * 60
    static let recentEngagementWindow: TimeInterval = 14 * 24 * 60 * 60
    static let backgroundRequestInterval: TimeInterval = 4 * 60 * 60
    static let backgroundRunDeadline: TimeInterval = 25
    static let deadlineSafetyMargin: TimeInterval = 2
    static let backgroundMaxWorks = 20
    static let backoffBase: TimeInterval = 15 * 60
    static let backoffCeiling: TimeInterval = 6 * 60 * 60
    static let maxNotifiedChaptersPerWork = 12
    static let homeSummaryLimit = 5
}
