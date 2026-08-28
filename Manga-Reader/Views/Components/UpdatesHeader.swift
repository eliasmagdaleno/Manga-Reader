import SwiftUI

struct UpdatesHeader: View {
    let totalUnread: Int
    let lastChecked: Date?
    let isRefreshing: Bool
    let refresh: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Gutter.rail) {
            VStack(alignment: .leading, spacing: 3) {
                Text("UPDATES")
                    .font(.inkMono(11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Ink.seal)
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(Ink.secondary)
            }

            Spacer(minLength: Gutter.rail)

            Button("Refresh Updates", systemImage: "arrow.clockwise", action: refresh)
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
                .disabled(isRefreshing)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint("Checks saved titles for new chapters")
                .accessibilityIdentifier("updatesRefreshButton")
        }
        .padding(.horizontal, Gutter.page)
    }

    private var statusText: String {
        if isRefreshing { return "Checking saved titles…" }
        guard let lastChecked else { return "Not checked yet" }
        let relative = lastChecked.formatted(.relative(presentation: .named))
        if totalUnread == 0 { return "Last checked \(relative) · No new chapters" }
        return "\(totalUnread) unread · Last checked \(relative)"
    }

    private var accessibilityLabel: String {
        isRefreshing ? "Refreshing updates" : "Refresh updates. \(statusText)"
    }
}
