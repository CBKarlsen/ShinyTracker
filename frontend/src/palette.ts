/**
 * 🎨 App Color Palette — Pro Tracker Dark Mode
 *
 * To retheme the app, only edit the values in `brand` below.
 */

// ── Raw brand colors ─────────────────────────────────────────────────────────
export const brand = {
  blue: "#3B82F6",     // vibrant blue      → primary actions (+1 Button)
  slate: "#0F172A",    // deep dark slate   → main app background
  surface: "#1E293B",  // lighter slate     → cards and modals
  emerald: "#10B981",  // bright green      → success / "Found It!"
} as const;

// ── Derived semantic tokens ───────────────────────────────────────────────────
export const colors = {
  // Surfaces
  bgDefault: brand.slate,     // Deep dark background
  bgPaper: brand.surface,     // Slightly lighter for cards to pop
  bgSubtle: "#334155",        // Hover states or subtle inputs

  // Brand
  primary: brand.blue,
  primaryLight: "#60A5FA",    // Lighter blue for hover states
  accent: brand.emerald,

  // Borders & dividers
  border: "#334155",          // Subtle divider line

  // Text
  textPrimary: "#F8FAFC",     // Crisp off-white for high readability
  textSecondary: "#94A3B8",   // Muted gray-blue for Game/Method text

  // Status
  success: brand.emerald,
  error: "#EF4444",           // Crisp red
  warning: "#F59E0B",         // Amber/Gold
} as const;

/**
 * CSS variable map.
 * Keys become --color-<key> on :root.
 */
export const cssVars: Record<string, string> = {
  // Brand primitives
  "blue": brand.blue,
  "slate": brand.slate,
  "surface": brand.surface,
  "emerald": brand.emerald,

  // Semantic aliases
  "bg": colors.bgDefault,
  "bg-paper": colors.bgPaper,
  "bg-subtle": colors.bgSubtle,
  "primary": colors.primary,
  "primary-light": colors.primaryLight,
  "accent": colors.accent,
  "border": colors.border,
  "text": colors.textPrimary,
  "text-secondary": colors.textSecondary,
  "success": colors.success,
  "error": colors.error,
  "warning": colors.warning,
};