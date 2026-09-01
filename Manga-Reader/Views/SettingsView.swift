//
//  SettingsView.swift
//  Manga-Reader
//

import SwiftUI
import UserNotifications

struct SettingsView: View {
    @AppStorage(appearanceStorageKey) private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage("settings.showAdultSources") private var showAdultSources = false
    @AppStorage(UpdateNotifier.notificationsEnabledKey) private var notificationsEnabled = true
    @ObservedObject private var registry = SourceRegistry.shared
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var works: WorkStore
    @EnvironmentObject private var updates: UpdateStateStore
    @Environment(\.openURL) private var openURL
    @State private var showingCollectionsSheet = false
    @State private var notificationSummary = NotificationAuthorizationSummary.notRequested

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Gutter.section) {

                    VStack(alignment: .leading, spacing: 14) {
                        InkSectionHeader("Library", eyebrow: "Organization")
                        Button {
                            showingCollectionsSheet = true
                        } label: {
                            HStack {
                                Text("Manage Collections")
                                    .font(.subheadline)
                                    .foregroundStyle(Ink.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(Ink.tertiary)
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal, Gutter.page)
                            .padding(.vertical, 15)
                        }
                        .buttonStyle(.plain)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Ink.surface))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Ink.hairline, lineWidth: 1))
                        .padding(.horizontal, Gutter.page)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        InkSectionHeader("Appearance", eyebrow: "Theme")
                        AppearancePicker(selection: $appearanceRaw)
                            .padding(.horizontal, Gutter.page)
                        Text("Follows your device by default. Choose Light or Dark to pin it.")
                            .font(.footnote)
                            .foregroundStyle(Ink.tertiary)
                            .padding(.horizontal, Gutter.page)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        InkSectionHeader("Updates", eyebrow: "Library")
                        VStack(spacing: 0) {
                            aboutRow("In-app", inAppUpdateStatus)
                            Divider().overlay(Ink.hairline).padding(.leading, Gutter.page)
                            aboutRow("System notifications", notificationStatusText)
                            Divider().overlay(Ink.hairline).padding(.leading, Gutter.page)
                            Toggle("Notify about new chapters", isOn: $notificationsEnabled)
                                .font(.subheadline)
                                .tint(Ink.seal)
                                .padding(.horizontal, Gutter.page)
                                .frame(minHeight: 50)
                                .onChange(of: notificationsEnabled) { _, enabled in
                                    if enabled { Task { await requestNotificationsIfNeeded() } }
                                }
                            if effectiveNotificationSummary == .unavailable {
                                Divider().overlay(Ink.hairline).padding(.leading, Gutter.page)
                                Button("Open System Settings", systemImage: "gear", action: openSystemSettings)
                                    .font(.subheadline)
                                    .foregroundStyle(Ink.seal)
                                    .padding(.horizontal, Gutter.page)
                                    .frame(minHeight: 50)
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 14).fill(Ink.surface))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Ink.hairline, lineWidth: 1))
                        .padding(.horizontal, Gutter.page)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        InkSectionHeader("Sources", eyebrow: "Content")
                        // Labelled because there are now two lists of source names in this
                        // section. Leaving the first one bare made it the ambiguous one the
                        // moment the second gained a heading.
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Browse source")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Ink.primary)
                            Text("Which source Home and Search show.")
                                .font(.footnote)
                                .foregroundStyle(Ink.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Gutter.page)

                        VStack(spacing: 0) {
                            let visible = registry.visibleSources(includeAdult: showAdultSources)
                            ForEach(Array(visible.enumerated()), id: \.element.id) { idx, source in
                                if idx > 0 {
                                    Divider().overlay(Ink.hairline).padding(.leading, Gutter.page)
                                }
                                let isActive = source.id == registry.activeSourceID
                                Button {
                                    registry.activeSourceID = source.id
                                } label: {
                                    HStack {
                                        Text(source.name)
                                            .font(.subheadline)
                                            .foregroundStyle(Ink.primary)
                                        Spacer()
                                        if isActive {
                                            Image(systemName: "checkmark").foregroundStyle(Ink.seal)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .padding(.horizontal, Gutter.page)
                                    .padding(.vertical, 15)
                                }
                                .buttonStyle(.plain)
                                // Same treatment as the preferred-source rows below, which
                                // had it from the start. Left bare, this row reads as a name
                                // and a stray checkmark — and the checkmark is the half
                                // carrying which source you are actually browsing.
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(source.name)
                                // Namespaced for the same reason the list below is: two lists
                                // of the same source names, and a bare name matches whichever
                                // comes first.
                                .accessibilityIdentifier("browseSource.\(source.name)")
                                .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 14).fill(Ink.surface))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Ink.hairline, lineWidth: 1))
                        .padding(.horizontal, Gutter.page)

                        // Hidden when nothing is registered for it to gate — a switch that
                        // changes nothing invites a hunt for the behaviour it is supposed to
                        // control. The stored preference is left alone, so this reappears
                        // with its previous value if an adult source is ever registered.
                        // See ADR-0022.
                        if registry.hasAdultSource {
                            Toggle("Show adult sources", isOn: $showAdultSources)
                                .font(.subheadline)
                                .tint(Ink.seal)
                                .padding(.horizontal, Gutter.page)
                                .onChange(of: showAdultSources) { _, newValue in
                                    registry.enforceAdultGating(includeAdult: newValue)
                                }
                        }

                        PreferredSourcePicker(sources: registry.visibleSources(
                            includeAdult: showAdultSources))
                    }

                    MALAccountSettingsView()

                    VStack(alignment: .leading, spacing: 14) {
                        InkSectionHeader("About", eyebrow: "Info")
                        VStack(spacing: 0) {
                            aboutRow("Sources", registry.sources.map(\.name).joined(separator: " · "))
                            Divider().overlay(Ink.hairline).padding(.leading, Gutter.page)
                            aboutRow("Version", "0.1 · WIP")
                        }
                        .background(RoundedRectangle(cornerRadius: 14).fill(Ink.surface))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Ink.hairline, lineWidth: 1))
                        .padding(.horizontal, Gutter.page)
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
            .background(Ink.background)
            .navigationTitle("Settings")
            .task { await refreshNotificationSummary() }
            .sheet(isPresented: $showingCollectionsSheet) {
                CollectionManagementView()
            }
        }
    }

    private func aboutRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Ink.primary)
            Spacer()
            Text(value)
                .font(.inkMono(12, weight: .medium))
                .foregroundStyle(Ink.secondary)
        }
        .padding(.horizontal, Gutter.page)
        .padding(.vertical, 15)
    }

    private var inAppUpdateStatus: String {
        let summaries = LibraryUpdatesPresentation.summaries(
            works: works, library: library, history: history, updates: updates)
        guard !library.items.isEmpty else { return "No saved titles" }
        guard summaries.contains(where: { $0.freshness != .notChecked }) else { return "Not checked yet" }
        let count = summaries.count(where: { $0.newlyDiscoveredCount > 0 })
        return count == 1 ? "1 title with updates" : "\(count) titles with updates"
    }

    private var notificationStatusText: String {
        switch effectiveNotificationSummary {
        case .notRequested: "Not requested"
        case .enabled: "Allowed"
        case .unavailable: "Unavailable"
        }
    }

    private func refreshNotificationSummary() async {
        if let fixtureSummary = Self.uiTestNotificationSummary {
            notificationSummary = fixtureSummary
            return
        }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral:
            notificationSummary = .enabled
        case .notDetermined:
            notificationSummary = .notRequested
        default:
            notificationSummary = .unavailable
        }
    }

    private var effectiveNotificationSummary: NotificationAuthorizationSummary {
        Self.uiTestNotificationSummary ?? notificationSummary
    }

    private static var uiTestNotificationSummary: NotificationAuthorizationSummary? {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uitest-updates-state") ? .notRequested : nil
#else
        nil
#endif
    }

    private func requestNotificationsIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
        }
        await refreshNotificationSummary()
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

/// Three seal-highlighted cards: System / Light / Dark. The signature control
/// for the dark-mode feature.
/// The fulfillment preference (ADR-0004 Amendment 1), which is **not** the browse source
/// above it. Browsing is "whose feed am I looking at"; this is "when several sources have
/// the same manga, whose scans do I want". Two lists of source names one after another
/// would be confusing without the caption saying which question each answers.
private struct PreferredSourcePicker: View {
    let sources: [MangaSource]
    @EnvironmentObject private var preferences: SourcePreferenceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preferred source")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Ink.primary)
            Text("When several sources carry the same manga, read it from this one. "
                 + "It only settles ties — a source with more chapters still wins.")
                .font(.footnote)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                // "No preference" is a real row rather than an absent selection. Without it
                // there is no way back to the automatic behaviour once a source is picked,
                // and the default would be indistinguishable from a deliberate choice.
                row(title: "No preference", detail: "Prefer MangaDex", isSelected: preferences.primarySourceId == nil) {
                    preferences.primarySourceId = nil
                }
                ForEach(sources, id: \.id) { source in
                    Divider().overlay(Ink.hairline).padding(.leading, Gutter.page)
                    row(title: source.name, detail: nil,
                        isSelected: preferences.primarySourceId == source.id) {
                        preferences.primarySourceId = source.id
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(Ink.surface))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Ink.hairline, lineWidth: 1))
        }
        .padding(.horizontal, Gutter.page)
        .padding(.top, 6)
    }

    private func row(title: String, detail: String?, isSelected: Bool,
                     select: @escaping () -> Void) -> some View {
        Button(action: select) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(Ink.primary)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(Ink.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(Ink.seal)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, Gutter.page)
            .padding(.vertical, 15)
        }
        .buttonStyle(.plain)
        // One element, one sentence. Left to itself the row reads as two separate texts
        // plus a bare checkmark, and the checkmark is the half that carries the state.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail.map { "\(title), \($0)" } ?? title)
        // Namespaced because Settings shows two lists of source names — the browse source
        // above, this preference below — and a bare name matches the wrong one.
        .accessibilityIdentifier("preferredSource.\(title)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

private struct AppearancePicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 10) {
            ForEach(AppearanceMode.allCases) { mode in
                let isSelected = selection == mode.rawValue
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = mode.rawValue }
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(isSelected ? Ink.seal : Ink.secondary)
                        Text(mode.label)
                            .font(.inkMono(11, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(isSelected ? Ink.primary : Ink.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isSelected ? Ink.sealSoft : Ink.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(isSelected ? Ink.seal : Ink.hairline,
                                          lineWidth: isSelected ? 1.5 : 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    let works = WorkStore()
    SettingsView()
        .environmentObject(LibraryStore(works: works))
        .environmentObject(HistoryStore(works: works))
        .environmentObject(works)
        .environmentObject(UpdateStateStore(works: works))
}
