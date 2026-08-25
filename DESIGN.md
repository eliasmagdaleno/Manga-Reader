---
name: Manga Reader — Ink & Seal
description: A native manga-reading system shaped by warm paper, dark ink, and restrained vermilion seals.
colors:
  paper: "#FBFAF8"
  paper-dark: "#141318"
  surface: "#FFFFFF"
  surface-dark: "#1D1C22"
  surface-recessed: "#F1EEE9"
  surface-recessed-dark: "#26242C"
  ink: "#17140F"
  ink-dark: "#F3F1EC"
  ink-secondary: "#6B655C"
  ink-secondary-dark: "#A6A199"
  ink-tertiary: "#756E64"
  ink-tertiary-dark: "#AAA49B"
  hairline: "#E5E0D7"
  hairline-dark: "#2E2C34"
  seal: "#B93624"
  seal-dark: "#FF6B55"
  seal-wash: "#FBE7E2"
  seal-wash-dark: "#3A1F1B"
typography:
  display:
    fontFamily: "New York, serif"
    fontWeight: 700
  body:
    fontFamily: "SF Pro, sans-serif"
    fontSize: "17pt"
    fontWeight: 400
  metadata:
    fontFamily: "SF Mono, monospace"
    fontWeight: 600
    letterSpacing: "0.5pt"
rounded:
  stamp: "4pt"
  cover: "8pt"
  control: "9pt"
  action: "12pt"
spacing:
  chip: "8pt"
  rail: "14pt"
  page: "20pt"
  section: "30pt"
components:
  stamp-neutral:
    backgroundColor: "{colors.surface-recessed}"
    textColor: "{colors.ink-secondary}"
    typography: "{typography.metadata}"
    rounded: "{rounded.stamp}"
    padding: "3pt 6pt"
  stamp-seal:
    backgroundColor: "{colors.seal-wash}"
    textColor: "{colors.seal}"
    typography: "{typography.metadata}"
    rounded: "{rounded.stamp}"
    padding: "3pt 6pt"
  source-chip-active:
    backgroundColor: "{colors.seal-wash}"
    textColor: "{colors.seal}"
    typography: "{typography.metadata}"
    rounded: "{rounded.control}"
    padding: "7pt 11pt"
---

# Design System: Manga Reader — Ink & Seal

## Overview

**Creative North Star: "Ink & Seal"**

Ink & Seal treats the app as a carefully printed reading companion rather than a generic media catalog. Warm paper and near-black ink form the quiet field; cover art supplies most of the color; a vermilion seal marks only meaningful status, selection, and action. The interface is comfortably sparse, cover-led, and unmistakably native.

The brand layer lives in serif display moments, monospaced metadata stamps, hairline-framed cover plates, and screentone placeholders. System navigation, controls, text styles, safe areas, zooming, and gestures retain iOS behavior. Accessibility adaptations must preserve this authored layer without freezing its measurements.

**Key Characteristics:**

- Warm paper and ink surfaces with a complete near-black dark appearance.
- A single, scarce vermilion accent inspired by a printer's seal.
- Serif titles paired with system body text and monospaced metadata.
- Cover-led composition, generous gutters, fine frames, and manga screentone texture.
- Native interaction structure with branded details rather than custom platform replacements.

## Colors

The palette is warm, restrained, and semantic: paper establishes atmosphere, ink establishes hierarchy, and the seal calls attention.

### Primary

- **Vermilion Seal:** The sole accent for primary actions, selected states, unread/new markers, progress, and the small section-header tick. Its dark counterpart becomes slightly brighter to retain presence on near-black surfaces.

### Neutral

- **Warm Paper:** The root light background; never pure clinical gray.
- **Night Ink:** The root dark background; near-black with a subtle plum warmth rather than absolute black.
- **Fresh Sheet:** Raised cards, bars, and sheets.
- **Recessed Paper:** Placeholders, neutral stamps, and passive chips.
- **Primary Ink:** Titles and essential content.
- **Secondary Ink:** Authors, descriptions, and supporting copy.
- **Tertiary Ink:** Low-priority metadata only; it must still meet the applicable contrast target.
- **Hairline:** Printed-plate frames, dividers, and quiet boundaries.

**The One Seal Rule.** Vermilion is the only brand accent. Do not introduce competing accent colors for categories or decoration.

**The Contrast Before Patina Rule.** Warmth and subtlety never justify unreadable text; strengthen a semantic role before sacrificing legibility.

## Typography

**Display Font:** New York through SwiftUI's serif system design

**Body Font:** San Francisco through semantic SwiftUI text styles

**Label/Mono Font:** SF Mono through SwiftUI's monospaced system design

**Character:** Editorial serif titles make screens feel printed and collected; highly legible system body text carries reading and controls; terse monospaced labels behave like chapter, volume, and library stamps.

### Hierarchy

- **Display:** Bold serif, used for manga titles, section titles, and quiet empty-state headings. It scales relative to the nearest semantic text style.
- **Headline:** Semibold system or serif text for compact hierarchy inside native rows and cards.
- **Body:** Semantic Body for descriptions and sustained reading; it remains the accessibility baseline.
- **Label:** Semibold monospaced text with modest tracking, usually uppercase, for short metadata such as chapter numbers, status, counts, and source stamps.

**The Editorial Moment Rule.** Serif belongs to identity-bearing titles, not every label or control.

**The Stamp Is Metadata Rule.** Monospaced uppercase treatment is reserved for terse facts. Never set explanatory sentences in the stamp voice.

**The Text Style Rule.** Brand type must derive from Dynamic Type text styles; fixed point sizes are not part of the durable system.

## Layout

The base rhythm uses a generous page gutter, compact rail spacing, and visibly larger separation between major sections. Horizontal cover rails emphasize browsing; grids adapt their column count and cover size to available width and Dynamic Type instead of preserving a phone-shaped fixed count. At accessibility sizes, horizontal hero compositions become vertical and secondary metadata may wrap beneath the primary task.

iPhone and iPad share the visual language, not identical geometry. iPad surfaces use readable maximum widths, adaptive grids, and balanced negative space. Immersive reader layout derives from its container and safe-area geometry, never the global screen bounds.

## Elevation & Depth

Ink & Seal is flat by default. Tonal surface changes and one-point hairlines establish most hierarchy; short, soft shadows are reserved for cover plates and genuinely floating reader or action surfaces. Shadows are ambient, never glossy or dramatic.

**The Printed Surface Rule.** If a hairline or tonal step communicates containment, do not add a shadow.

**The Cover Plate Exception.** Covers may carry a small downward shadow because they are treated as physical printed objects above the page.

## Shapes

Corners are gently softened rather than pill-heavy: metadata stamps use tight four-point corners, covers and compact controls use roughly eight to nine points, and prominent action or floating surfaces use about twelve points. Capsules are reserved for small badges whose silhouette carries meaning. Hairline outlines reinforce the printed-plate language.

## Components

### Buttons

- **Shape:** Native control behavior with gently rounded branded surfaces for prominent actions.
- **Primary:** Vermilion fill with a high-contrast label; preserve at least a 44-point interaction region.
- **Secondary:** Paper or seal-wash fill with a hairline; use vermilion only when state or action warrants it.
- **Focus / State:** Use native pressed, focus, disabled, and accessibility semantics. Never rely on color alone to communicate selection.

### Chips

- **Style:** Compact logo-and-label or text-only controls with a paper surface and hairline.
- **State:** Active chips use seal wash, vermilion text and outline, plus selected semantics; inactive chips use secondary ink.

### Cards / Containers

- **Corner Style:** Gently rounded cover plates and restrained content containers.
- **Background:** Paper or raised surface, with recessed paper for placeholders.
- **Shadow Strategy:** Cover art may use a short ambient shadow; ordinary containers remain tonal and framed.
- **Border:** One-point semantic hairlines.
- **Internal Padding:** Follow the shared page, rail, and section rhythm rather than one-off spacing.

### Inputs / Fields

- **Style:** Native search and input controls, recolored through semantic Ink & Seal roles.
- **Focus:** Preserve native focus, keyboard, clear, validation, and accessibility behavior.
- **Error / Disabled:** Pair semantic state with explanatory text and an adjacent recovery action when recovery exists.

### Navigation

Use native tab, navigation-stack, toolbar, sheet, and full-screen-cover structures. Top-level destinations may use large titles; detail screens use inline titles. Brand is expressed inside content and tint, never by replacing native navigation behavior.

### Section Header

A narrow vermilion tick, optional uppercase metadata eyebrow, and serif title establish a section. The eyebrow must add information such as ordering, source, or count; it never repeats the title.

### Screentone Placeholder

A recessed paper field with restrained halftone dots stands in for unavailable or loading cover art. It is a signature manga texture, not a general-purpose background pattern.

### Cover Card

Cover art is the primary visual element, framed with a hairline and a soft physical shadow. A two-line serif title maintains rhythm, while optional metadata and unread badges use the stamp and seal vocabulary.

## Do's and Don'ts

### Do:

- **Do** let cover art provide the screen's visual variety while the surrounding interface stays calm.
- **Do** use semantic, appearance-aware colors and verify light, dark, increased-contrast, and differentiate-without-color states.
- **Do** derive branded typography and layout metrics from Dynamic Type and available container size.
- **Do** retain native controls, navigation, focus, gestures, and zoom physics.
- **Do** use screentone texture sparingly for manga-specific placeholders and loading surfaces.

### Don't:

- **Don't** add gradients, glass effects, competing accents, or decorative shadows.
- **Don't** use vermilion as ambient decoration or for low-priority metadata.
- **Don't** turn every label into uppercase monospaced text.
- **Don't** preserve a fixed phone composition on iPad or at accessibility text sizes.
- **Don't** hide a primary task behind a gesture without a visible and VoiceOver-operable route.
