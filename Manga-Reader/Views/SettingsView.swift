//
//  SettingsView.swift
//  Manga-Reader
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(appearanceStorageKey) private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage("settings.showAdultSources") private var showAdultSources = false
    @ObservedObject private var registry = SourceRegistry.shared
    @State private var showingCollectionsSheet = false

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
                        InkSectionHeader("Sources", eyebrow: "Content")
                        VStack(spacing: 0) {
                            let visible = registry.visibleSources(includeAdult: showAdultSources)
                            ForEach(Array(visible.enumerated()), id: \.element.id) { idx, source in
                                if idx > 0 {
                                    Divider().overlay(Ink.hairline).padding(.leading, Gutter.page)
                                }
                                Button {
                                    registry.activeSourceID = source.id
                                } label: {
                                    HStack {
                                        Text(source.name)
                                            .font(.subheadline)
                                            .foregroundStyle(Ink.primary)
                                        Spacer()
                                        if source.id == registry.activeSourceID {
                                            Image(systemName: "checkmark").foregroundStyle(Ink.seal)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .padding(.horizontal, Gutter.page)
                                    .padding(.vertical, 15)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 14).fill(Ink.surface))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Ink.hairline, lineWidth: 1))
                        .padding(.horizontal, Gutter.page)

                        Toggle("Show adult sources", isOn: $showAdultSources)
                            .font(.subheadline)
                            .tint(Ink.seal)
                            .padding(.horizontal, Gutter.page)
                            .onChange(of: showAdultSources) { _, newValue in
                                registry.enforceAdultGating(includeAdult: newValue)
                            }
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
}

/// Three seal-highlighted cards: System / Light / Dark. The signature control
/// for the dark-mode feature.
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
    SettingsView()
}
