# ADR-0006 — Multiple Collections Support in Library View

- **Status:** Accepted (2026-07-24)
- **Supersedes:** nothing
- **Related:** ADR-0001 (work vs listing identity)

## Context

Currently, `LibraryStore` stores saved manga as a flat, single list (`LibraryItem`). Users can only save or unsave a manga. As users' libraries grow, they need ways to categorize manga into statuses (e.g., Reading, On Hold, Planned, Dropped) as well as custom user-defined lists (e.g., "Favorites", "Webtoons").

The initial prompt requested:
- Default collections: Reading, On Hold, Planned, Dropped.
- Ability to create custom collections.
- Ability to optionally disable default collections.

Through domain grilling, we resolved key architectural and UX decisions:
1. **Multi-assignment model**: A saved manga can belong to multiple collections simultaneously (e.g., both "Reading" and "Favorites").
2. **"All Manga" view**: The Library tab displays an "All Manga" tab first, followed by enabled collection tabs.
3. **Default collection customization**: Default collections have fixed names, can be reordered and enabled/disabled, but cannot be deleted or renamed. Custom collections can be created, renamed, reordered, disabled, and deleted.
4. **Disabled collection behavior**: Disabling a collection hides it from the Library view without deleting item assignments. Items stay in the disabled collection in storage and reappear if re-enabled.
5. **Collection deletion behavior**: Deleting a custom collection removes its ID from items. If an item has 0 collections remaining, it is removed from the library.
6. **Quick-add UX**: In `MangaDetailView`, single-tapping "Add to Library" adds the manga to the primary "Reading" collection. Long-pressing or tapping the menu option opens a collection picker.

## Decision

1. Introduce `LibraryCollection` struct to represent both system (default) and custom collections:
   - `id: String` (e.g., `"reading"`, `"on_hold"`, `"planned"`, `"dropped"`, or a unique UUID for custom collections).
   - `name: String`
   - `isSystem: Bool`
   - `isEnabled: Bool`
   - `sortOrder: Int`

2. Update `LibraryItem`:
   - Add `collectionIds: Set<String>` property.
   - Provide backward-compatible decoding: existing persisted items without `collectionIds` automatically migrate to `collectionIds = ["reading"]`.

3. Enhance `LibraryStore`:
   - Store and persist collections (`collections.items` key) alongside saved items (`library.items`).
   - Default initial collections: Reading (order 0), On Hold (order 1), Planned (order 2), Dropped (order 3) — all enabled by default.
   - Provide APIs: `toggleCollection(manga:collectionId:)`, `addToCollection(mangaId:collectionId:)`, `removeFromCollection(mangaId:collectionId:)`, `addCustomCollection(name:)`, `renameCustomCollection(id:newName:)`, `setCollectionEnabled(id:isEnabled:)`, `deleteCustomCollection(id:)`, `reorderCollections(ids:)`.

4. UI Components & Flow:
   - **`BookmarksView`**: Render a top horizontal collection tab picker ("All Manga", "Reading", "On Hold", ..., + custom collections). Filtering active view by selected tab.
   - **`MangaDetailView`**: Update "Add to Library" button to support primary quick-add to "Reading" and menu/sheet selection for managing multiple collection memberships.
   - **`CollectionManagementView`**: Present a sheet accessible from Library view header gear icon and Settings tab to reorder, toggle, rename, create, and delete collections using native iOS swipe actions (swipe left to delete or rename) and long-press context menus.

## Consequences

- Existing saved items are preserved and assigned to the default "Reading" collection seamlessly upon app launch.
- Users can organize complex libraries across multiple built-in or custom collections.
- Clean separation between collection state and item metadata.
