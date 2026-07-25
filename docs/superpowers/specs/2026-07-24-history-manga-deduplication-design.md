# History Deduplication Design

## Context
When a user reads multiple chapters of the same manga on the same day, the `HistoryView` currently displays a separate entry for each chapter read. The user requested that if the same manga is read multiple times within the same day, there should only be one entry for that manga representing the most up-to-date reading session.

## Decisions Made
Following a brief grilling session, we aligned on the following requirements:
1. **Most Recent Chapter**: When deduplicating entries for the same manga on the same day, the entry should display the chapter read *most recently* (e.g. if a user reads Chapter 10, then rereads Chapter 1, it should show Chapter 1).
2. **Per-Day Entries**: If a user reads the same manga across multiple days (e.g., Today and Yesterday), they should have separate entries for each day.
3. **Data Preservation**: To ensure that the underlying read status of older chapters is not lost, we will preserve all history entries in `HistoryStore.entries`. The deduplication will happen purely visually at the presentation layer (`HistoryView`), so that only the most recent entry per manga is shown in the list.

## Proposed Changes
Update `HistoryView.groupedEntries` to deduplicate by `mangaId` within each day's bucket. Since `history.entries` is already sorted chronologically (newest first), we can simply keep the first occurrence of each `mangaId` we encounter within each day bucket.

```swift
    private var groupedEntries: [(key: String, value: [ReadingEntry])] {
        var order: [String] = []
        var buckets: [String: [ReadingEntry]] = [:]
        
        for entry in history.entries {
            let key = Self.dayLabel(entry.updatedAt)
            if buckets[key] == nil { buckets[key] = []; order.append(key) }
            
            // Deduplicate by mangaId within the same day
            if !(buckets[key]?.contains(where: { $0.mangaId == entry.mangaId }) ?? false) {
                buckets[key]?.append(entry)
            }
        }
        return order.map { ($0, buckets[$0]!) }
    }
```
*Note: Because `buckets[key]` is an array, `contains` is O(N). Since the number of entries per day is relatively small, this is acceptable, but we could also use a Set to track seen manga IDs per day if performance becomes a concern.*
