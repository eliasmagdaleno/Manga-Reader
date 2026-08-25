//
//  CollectionManagementView.swift
//  Manga-Reader
//
//  Sheet UI to manage library collections: create custom collections, toggle visibility,
//  rename custom collections, and reorder collections.
//

import SwiftUI

struct CollectionManagementView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var newCollectionName = ""
    @State private var editingCollectionId: String? = nil
    @State private var editingCollectionName = ""
    @State private var showingRenameAlert = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        TextField("New Collection Name", text: $newCollectionName)
                            .textFieldStyle(.plain)
                            .submitLabel(.done)
                            .onSubmit(addCollection)

                        Button("Add") {
                            addCollection()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Ink.seal)
                        .disabled(newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } header: {
                    Text("Create Collection")
                } footer: {
                    Text(
                        "Default collections (Reading, On Hold, Planned, Dropped) can be toggled on or off. "
                            + "Swipe a custom collection left to delete or rename."
                    )
                }

                Section {
                    ForEach(library.collections) { collection in
                        collectionRow(for: collection)
                    }
                    .onMove { indices, newOffset in
                        library.moveCollection(fromOffsets: indices, toOffset: newOffset)
                    }
                } header: {
                    HStack {
                        Text("Collections")
                        Spacer()
                        EditButton()
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Ink.seal)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Manage Collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Ink.seal)
                }
            }
            .alert("Rename Collection", isPresented: $showingRenameAlert) {
                TextField("Collection Name", text: $editingCollectionName)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    if let id = editingCollectionId {
                        library.renameCustomCollection(id: id, newName: editingCollectionName)
                    }
                }
            } message: {
                Text("Enter a new name for this collection.")
            }
        }
    }

    @Environment(\.editMode) private var editMode

    private func startRename(_ collection: LibraryCollection) {
        editingCollectionId = collection.id
        editingCollectionName = collection.name
        showingRenameAlert = true
    }

    private func addCollection() {
        let trimmed = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation {
            library.addCustomCollection(name: trimmed)
            newCollectionName = ""
        }
    }

    // MARK: - Row View

    @ViewBuilder
    private func collectionRow(for collection: LibraryCollection) -> some View {
        CollectionRowView(
            collection: collection,
            startRename: { startRename(collection) }
        )
    }
}

struct CollectionRowView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.editMode) private var editMode
    let collection: LibraryCollection
    let startRename: () -> Void

    @State private var inlineName: String = ""
    @State private var showingDeleteConfirm = false

    var body: some View {
        let isEditing = editMode?.wrappedValue.isEditing == true

        Group {
            if isEditing {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if collection.isSystem {
                            Text(collection.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(Ink.primary)
                            Text("DEFAULT")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Ink.tertiary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Ink.surfaceAlt))
                        } else {
                            TextField("Collection Name", text: $inlineName)
                                .font(.body.weight(.medium))
                                .foregroundStyle(Ink.primary)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { saveInlineRename() }
                                .onDisappear { saveInlineRename() }
                        }
                    }

                    let itemCount = library.items(in: collection.id).count
                    Text("\(itemCount) title\(itemCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(Ink.tertiary)
                }
            } else {
                Toggle(isOn: Binding(
                    get: { collection.isEnabled },
                    set: { library.setCollectionEnabled(id: collection.id, isEnabled: $0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(collection.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(collection.isEnabled ? Ink.primary : Ink.tertiary)

                            if collection.isSystem {
                                Text("DEFAULT")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Ink.tertiary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(Ink.surfaceAlt))
                            }
                        }

                        let itemCount = library.items(in: collection.id).count
                        Text("\(itemCount) title\(itemCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(Ink.tertiary)
                    }
                }
                .tint(Ink.seal)
            }
        }
        .padding(.vertical, 2)
        .onAppear {
            inlineName = collection.name
        }
        .onChange(of: editMode?.wrappedValue.isEditing) { editing in
            if editing == false {
                saveInlineRename()
            } else {
                inlineName = collection.name
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !collection.isSystem {
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !collection.isSystem {
                Button {
                    startRename()
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .tint(Ink.seal)
            }
        }
        .contextMenu {
            if !collection.isSystem {
                Button {
                    startRename()
                } label: {
                    Label("Rename Collection", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete Collection", systemImage: "trash")
                }
            }
        }
        .alert("Delete Collection?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                withAnimation {
                    library.deleteCustomCollection(id: collection.id)
                }
            }
        } message: {
            Text("Are you sure you want to delete '\(collection.name)'? This action cannot be undone.")
        }
    }

    private func saveInlineRename() {
        if !collection.isSystem && inlineName != collection.name {
            library.renameCustomCollection(id: collection.id, newName: inlineName)
        }
    }
}

#Preview {
    CollectionManagementView()
        .environmentObject(LibraryStore())
}
