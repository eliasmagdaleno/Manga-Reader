# Manga Card Title Truncation Design

## Context
In the horizontal rails (like "For You" and "Popular" on the Home screen), `MangaCoverCard` currently limits manga titles to exactly 2 lines. Because Light Novels and some Manga titles can be excessively long, these titles were being aggressively truncated with an ellipsis, making them unreadable.

We needed a solution that increases legibility for long titles without breaking the clean, uniform horizontal alignment of the rails (e.g. we want the metadata stamps like "Because you read..." to still align horizontally across the bottom).

## Decisions Made
Following a grilling session, we aligned on the following requirements:
1. **Dynamic Font Scaling**: We will retain the strict 2-line vertical space reservation to guarantee that all cards share the exact same height and keep their metadata stamps aligned perfectly. However, we will allow the font to dynamically scale down (shrink) to fit more words into those 2 lines before truncating.
2. **Fallback Truncation**: If a title is so exceptionally long that it still cannot fit within the 2 lines even after shrinking to the minimum allowed scale, we will fall back to truncating with an ellipsis (`...`) at the end. 

## Implementation Details
In `MangaCoverCard.swift`, we append a `.minimumScaleFactor(0.75)` modifier to the title text. This tells SwiftUI to scale the font down to up to 75% of its original size before it resorts to truncating the text. The `.lineLimit(2, reservesSpace: true)` will be maintained.
