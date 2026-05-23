---
name: ShinyTracker
description: Sleek gamer-dashboard tracking shiny Pokémon hunts
colors:
  primary: "#f5c661"
  secondary: "#7b9bff"
  neutral-bg: "#060608"
  surface: "#111118"
  success: "#6ee7a2"
  danger: "#ff7373"
typography:
  display:
    fontFamily: "Space Grotesk, system-ui, sans-serif"
    fontSize: "1.75rem"
    fontWeight: 700
    lineHeight: 1.2
  body:
    fontFamily: "Inter Tight, system-ui, sans-serif"
    fontSize: "0.95rem"
    fontWeight: 400
    lineHeight: 1.5
  mono:
    fontFamily: "JetBrains Mono, ui-monospace, monospace"
    fontSize: "0.875rem"
rounded:
  sm: "6px"
  md: "10px"
  lg: "14px"
  xl: "20px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "16px"
  lg: "24px"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.neutral-bg}"
    rounded: "{rounded.sm}"
    padding: "8px 16px"
  card-container:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.md}"
    padding: "24px"
---

# Design System: ShinyTracker

## 1. Overview

**Creative North Star: "Trainer Command Center"**

Trainer Command Center is a data-dense monitoring panel designed for high-focus, keyboard-first, and late-night hunting sessions. The layout emphasizes data density, structural clarity, and efficient shortcuts, mirroring the aesthetic precision of professional tools like Linear and Raycast. By using a void-black canvas with selective neon glowing highlights for rare milestones, it eliminates eye strain during long sessions while providing a premium, gamer-native atmosphere.

**Key Characteristics:**
- High data density optimized for clean observability.
- Keyboard-centric navigation and shortcuts.
- Void-black dark mode interface with neon status highlights.
- Ambient glow states for active interactions.

## 2. Colors

The color palette centers on a void-black background paired with high-contrast, premium accents that denote shiny rarity and UI state.

### Primary
- **Sparkle Gold** (#f5c661): Used for active hunts, primary success markers, and rare shiny events. Emits a soft ambient glow.

### Secondary
- **Lure Blue** (#7b9bff): Used for primary interface actions, navigation tabs, and active state indicators.

### Neutral
- **Void Black** (#060608): The base canvas background color. Reduces eye strain.
- **Deep Slate** (#0b0b10): Sub-layer background for structural panels.
- **Surface Slate** (#111118): The main background for cards and interactive containers.
- **Card Slate** (#181822): Elevated card background for focused interactive widgets.
- **Parchment White** (#f4f2ec): Standard high-contrast text color.
- **Muted Ink** (#b6b5c0): Secondary body text and labels.
- **Dim Ink** (#6e6d78): Disabled states, inactive parameters, and placeholder text.
- **Subtle Divider** (#1a1a22): Subtle 1px borders separating grid cells and layout segments.

**The One Sparkle Rule.** Neon glowing elements must be used selectively (≤10% of the screen area). The primary Sparkle Gold glow is reserved for active targets and rare milestones; diluting it with general usage is forbidden.

## 3. Typography

**Display Font:** "Space Grotesk" (with system-ui, sans-serif)
**Body Font:** "Inter Tight" (with system-ui, sans-serif)
**Label/Mono Font:** "JetBrains Mono" (with ui-monospace, monospace)

The typography is built around clean, geometric display headers contrasted with highly legible, modern sans-serif body copy and monospace tracking statistics.

### Hierarchy
- **Display** (bold (700), 1.75rem, 1.2): Title headers, big stats, active hunt counters.
- **Headline** (semibold (600), 1.35rem, 1.3): Component headings, modal titles.
- **Title** (medium (500), 1.1rem, 1.4): Card titles, active game badges.
- **Body** (regular (400), 0.95rem, 1.5): Standard reading text, descriptive paragraphs. Max line length is 70ch.
- **Label** (monospace, 0.875rem, normal): Small parameters, encounters/hour pace, odds calculations, and hotkey labels.

## 4. Elevation

ShinyTracker uses tonal layering combined with ambient neon glowing borders to indicate depth and user focus. Background elements layer from Void Black up to Card Slate, utilizing sharp 1px borders instead of heavy drop shadows.

### Shadow Vocabulary
- **Gold Glow** (`box-shadow: 0 0 0 1px #f5c66155, 0 0 24px -8px #f5c661`): Active target card glow.
- **Blue Glow** (`box-shadow: 0 0 0 1px #7b9bff55, 0 0 24px -8px #7b9bff`): Interactive panel focus glow.

**The Ambient State Rule.** Containers are flat at rest. Glowing borders and shadows are strictly reactive and appear only during active hunting or component hover/focus states to direct user attention.

## 5. Components

All components are sleek, slightly rounded, and feature micro-transitions for responsive feedback.

### Buttons
- **Shape:** Subtle rounded corner (6px)
- **Primary:** Sparkle Gold background with Void Black text. Up to 8px 16px padding.
- **Secondary:** Surface Slate background with Parchment White text and a 1px Subtle Divider border.
- **Hover / Focus:** CSS transition of 0.2s ease. Primary scales slightly and intensifies glow; secondary shifts border to Lure Blue.

### Cards / Containers
- **Corner Style:** Medium rounded corner (10px)
- **Background:** Surface Slate (#111118)
- **Shadow Strategy:** Flat at rest; glows gold or blue when active/focused.
- **Border:** 1px Subtle Divider (#1a1a22)
- **Internal Padding:** Medium padding (24px)

### Inputs / Fields
- **Shape:** Subtle rounded corner (6px)
- **Style:** Deep Slate background with a 1px Subtle Divider border. Text is Parchment White.
- **Focus:** Border shifts to Lure Blue with a subtle blue glow. Transition is 0.15s ease.

### Navigation
- **Style:** Sticky topbar and left-aligned sidebar. Tabs use Lure Blue indicator borders. Hovering tabs transition from Muted Ink text to Parchment White.

## 6. Do's and Don'ts

### Do:
- **Do** use JetBrains Mono for all numeric statistics, odds calculations, and pace parameters to ensure strict tabular alignment.
- **Do** apply `--glow-gold` exclusively to the active Pokémon tracking card to emphasize its role as the focus of the application.
- **Do** design layout spacing with strict vertical rhythm using spacing scale steps (8px, 16px, 24px).

### Don't:
- **Don't** use standard white cards or pure grey backgrounds; all neutrals must be tinted with deep slate and void tones.
- **Don't** use side-stripe borders (e.g. `border-left` or `border-right` thicker than 1px) to indicate card category. Use tags or subtle background tints instead.
- **Don't** introduce nested card structures; use border dividers or tonal differences inside a single card container.
- **Don't** create multi-step modals for simple two-step selections. Show inline previews or collapsable sections instead.
