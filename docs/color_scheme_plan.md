# Color Scheme Implementation Plan — SISS_1 Flutter App

---

## 1. The New Color Palette

| Token | Hex | Usage |
|---|---|---|
| `primary` | `#4ADE80` | Buttons, active states, key highlights |
| `onPrimary` | `#03341F` | Text/icons ON top of primary color |
| `secondary` | `#ECFCCB` | Subtle backgrounds, chip fills, soft highlights |
| `onSecondary` | `#365314` | Text/icons ON top of secondary color |
| `accent` | `#F59E0B` | Warnings, temperature, amber alerts |
| `background` | `#F8FFF8` | Scaffold background (whole app) |
| `surface` | `#FFFFFF` | Cards, dialogs, bottom sheets |
| `text` | `#1A2E1F` | All body & heading text |

---

## 2. How to Read This Plan

Each section covers **one file**. For every color change, three things are stated:
- **What** the element is (e.g. `ElevatedButton background`)
- **Current value** (what the code has now)
- **New value** (what to replace it with)

Changes that require no logic edits — only color swaps — are marked `[COLOR ONLY]`.  
Changes that also need a minor structural tweak are marked `[COLOR + TWEAK]`.

---

## 3. File: `lib/theme.dart`

This is the **single source of truth** for all colors. All other files should pull from here via `Theme.of(context)` — so getting this right fixes most of the app automatically.

### 3.1 — Static color constants

```dart
// CURRENT
static const Color primary     = Color(0xFF16A34A);
static const Color background  = Color(0xFFF9FAFB);
static const Color surface     = Colors.white;
static const Color textPrimary = Color(0xFF111827);
static const Color textSecondary = Color(0xFF6B7280);
static const Color error       = Color(0xFFDC2626);

// NEW — replace with:
static const Color primary      = Color(0xFF4ADE80);
static const Color onPrimary    = Color(0xFF03341F);   // NEW — add this
static const Color secondary    = Color(0xFFECFCCB);   // NEW — add this
static const Color onSecondary  = Color(0xFF365314);   // NEW — add this
static const Color accent       = Color(0xFFF59E0B);   // NEW — add this
static const Color background   = Color(0xFFF8FFF8);
static const Color surface      = Color(0xFFFFFFFF);
static const Color text         = Color(0xFF1A2E1F);   // renamed from textPrimary
static const Color textMuted    = Color(0xFF4A6741);   // replaces textSecondary (muted green-toned)
static const Color error        = Color(0xFFDC2626);   // unchanged
```

### 3.2 — `ColorScheme`

```dart
// CURRENT
colorScheme: const ColorScheme.light(
  primary: primary,
  secondary: Color(0xFF2563EB),
  surface: surface,
  error: error,
),

// NEW
colorScheme: const ColorScheme.light(
  primary: primary,
  onPrimary: onPrimary,
  secondary: secondary,
  onSecondary: onSecondary,
  surface: surface,
  onSurface: text,
  error: error,
  tertiary: accent,           // accent maps to tertiary in Material 3
),
```

### 3.3 — `AppBarTheme`

```dart
// CURRENT
appBarTheme: const AppBarTheme(
  backgroundColor: surface,
  foregroundColor: textPrimary,
  ...
),

// NEW  [COLOR ONLY]
appBarTheme: const AppBarTheme(
  backgroundColor: surface,
  foregroundColor: text,      // #1A2E1F instead of #111827
  ...
),
```

### 3.4 — `TextTheme`

```dart
// CURRENT  — textPrimary used throughout
// NEW      — replace all textPrimary → text, textSecondary → textMuted  [COLOR ONLY]

headlineLarge:  TextStyle(color: text, ...)
headlineMedium: TextStyle(color: text, ...)
titleLarge:     TextStyle(color: text, ...)
bodyLarge:      TextStyle(color: text, ...)
bodyMedium:     TextStyle(color: textMuted, ...)
```

### 3.5 — `ElevatedButtonTheme`

```dart
// CURRENT
backgroundColor: primary,      // #16A34A
foregroundColor: Colors.white,

// NEW  [COLOR ONLY]
backgroundColor: primary,      // #4ADE80
foregroundColor: onPrimary,    // #03341F (dark text on light green button)
```

### 3.6 — `BottomNavigationBarTheme` — ADD THIS (currently missing)

```dart
// ADD to ThemeData:
bottomNavigationBarTheme: const BottomNavigationBarThemeData(
  backgroundColor: surface,
  selectedItemColor: primary,     // #4ADE80
  unselectedItemColor: textMuted, // #4A6741
),
```

### 3.7 — `SliderTheme` — ADD THIS (used in crop profiles)

```dart
// ADD to ThemeData:
sliderTheme: SliderThemeData(
  activeTrackColor: primary,        // #4ADE80
  thumbColor: onPrimary,            // #03341F
  overlayColor: primary.withValues(alpha: 0.15),
  inactiveTrackColor: secondary,    // #ECFCCB
),
```

---

## 4. File: `lib/router.dart`

### 4.1 — `DrawerHeader` background

```dart
// CURRENT
decoration: BoxDecoration(color: Color(0xFF16A34A)),
child: Text('Navigation', style: TextStyle(color: Colors.white, ...)),

// NEW  [COLOR ONLY]
decoration: BoxDecoration(color: AppTheme.onPrimary),  // #03341F — deep dark green
child: Text('Navigation', style: TextStyle(color: AppTheme.primary, ...)),  // #4ADE80 bright green text
```

### 4.2 — `BottomNavigationBar`

```dart
// CURRENT — hardcoded colors
selectedItemColor: const Color(0xFF16A34A),
unselectedItemColor: Colors.grey,

// NEW  [COLOR ONLY] — use theme tokens
selectedItemColor: AppTheme.primary,    // #4ADE80
unselectedItemColor: AppTheme.textMuted, // #4A6741
```

---

## 5. File: `lib/screens/dashboard_screen.dart`

### 5.1 — `_StatCard` icon colors

Each stat card has a hardcoded `color:` passed to the icon. Map them to the new palette:

| Card | Current Color | New Color | Reason |
|---|---|---|---|
| Soil Moisture | `Colors.blue` | `AppTheme.primary` (`#4ADE80`) | It's the core moisture metric — use primary |
| Temperature | `Colors.orange` | `AppTheme.accent` (`#F59E0B`) | Accent is amber/orange — perfect for heat |
| Humidity | `Colors.lightBlue` | `Color(0xFF22D3EE)` | Keep cyan-ish, it's a water/air metric |
| Rain (raining) | `Colors.indigo` | `Color(0xFF6366F1)` | Keep indigo for active rain state |
| Rain (dry) | `Colors.amber` | `AppTheme.accent` (`#F59E0B`) | Sunny/dry — accent amber works |

`[COLOR ONLY]` for all above.

### 5.2 — Pump Activity icons

```dart
// CURRENT
Icon(LucideIcons.power,    color: Colors.green)
Icon(LucideIcons.powerOff, color: Colors.red)

// NEW  [COLOR ONLY]
Icon(LucideIcons.power,    color: AppTheme.onPrimary)  // #03341F dark green = pump ON
Icon(LucideIcons.powerOff, color: AppTheme.error)       // #DC2626 red = pump OFF (unchanged)
```

### 5.3 — `CircularProgressIndicator` (loading state)

```dart
// CURRENT — uses default theme color (was blue tinted)
// NEW  [COLOR ONLY]
CircularProgressIndicator(color: AppTheme.primary)
```

---

## 6. File: `lib/screens/irrigation_screen.dart`

### 6.1 — Chart line & fill color

```dart
// CURRENT
color: Colors.green,
color: Colors.green.withValues(alpha: 0.2),  // fill under line

// NEW  [COLOR ONLY]
color: AppTheme.primary,                              // #4ADE80
color: AppTheme.primary.withValues(alpha: 0.15),      // lighter fill
```

### 6.2 — Chart icon

```dart
// CURRENT
Icon(LucideIcons.droplets, color: Colors.green)

// NEW  [COLOR ONLY]
Icon(LucideIcons.droplets, color: AppTheme.primary)
```

### 6.3 — Threshold reference line (if present)

Any horizontal threshold line on the chart should use `AppTheme.accent` (`#F59E0B`) — it's a warning/boundary indicator.

---

## 7. File: `lib/screens/weather_screen.dart`

### 7.1 — Rain probability text & icon

```dart
// CURRENT
Icon(LucideIcons.cloudRain, color: Colors.blue)
TextStyle(color: Colors.blue)

// NEW  [COLOR ONLY]
// Rain is water → use primary green family. But we want it to stand out as a warning:
Icon(LucideIcons.cloudRain, color: Color(0xFF22D3EE))  // cyan-ish, water feel
TextStyle(color: Color(0xFF0891B2))                     // darker cyan for readability
```

### 7.2 — "Rain warning" banner

```dart
// CURRENT
color: Colors.blue.shade50,
border: Border.all(color: Colors.blue.shade200),
Icon(LucideIcons.info, color: Colors.blue),
TextStyle(color: Colors.blue)

// NEW  [COLOR + TWEAK]
// Repaint as a secondary-toned soft banner
color: AppTheme.secondary,              // #ECFCCB pale green
border: Border.all(color: AppTheme.onSecondary.withValues(alpha: 0.4)),  // #365314 soft
Icon(LucideIcons.info, color: AppTheme.onSecondary),   // #365314
TextStyle(color: AppTheme.onSecondary)                 // #365314
```

### 7.3 — Temperature display

The big temperature number has no color set currently (inherits textPrimary).

```dart
// NEW  [COLOR ONLY] — make it stand out using accent
TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: AppTheme.accent)
```

---

## 8. File: `lib/screens/pump_control_screen.dart`

### 8.1 — Pump ON button

```dart
// CURRENT (assumed green ElevatedButton from theme)
// NEW  [COLOR ONLY] — explicitly set to match new primary
ElevatedButton.styleFrom(
  backgroundColor: AppTheme.primary,    // #4ADE80
  foregroundColor: AppTheme.onPrimary,  // #03341F
)
```

### 8.2 — Pump OFF button

```dart
// CURRENT — likely Colors.red or error color
// NEW  [COLOR ONLY] — keep error red, no change needed
ElevatedButton.styleFrom(
  backgroundColor: AppTheme.error,      // #DC2626
  foregroundColor: Colors.white,
)
```

### 8.3 — Pump status indicator (ON/OFF badge or icon)

```dart
// When pump is ON:
color: AppTheme.primary       // #4ADE80 bright

// When pump is OFF:
color: AppTheme.textMuted     // #4A6741 muted
```

---

## 9. File: `lib/screens/crop_profiles_screen.dart`

### 9.1 — Crop icon

```dart
// CURRENT
Icon(LucideIcons.sprout, color: Colors.green)

// NEW  [COLOR ONLY]
Icon(LucideIcons.sprout, color: AppTheme.onPrimary)  // #03341F deep green — feels earthy
```

### 9.2 — Dry threshold slider

The slider now gets its colors from `SliderTheme` in `theme.dart` (added in step 3.7) — no per-screen change needed.

```dart
// CURRENT — hardcoded
activeColor: Colors.brown.shade400,

// NEW  [COLOR + TWEAK] — remove the hardcoded activeColor and let the theme handle it
// Just delete the activeColor line; SliderTheme in theme.dart will apply:
//   activeTrackColor: primary (#4ADE80)
//   thumbColor: onPrimary (#03341F)
```

### 9.3 — Save button

Inherits `ElevatedButtonTheme` from `theme.dart` — no change needed here once theme is updated.

### 9.4 — Crop type chips/selection cards

```dart
// Selected crop chip:
backgroundColor: AppTheme.secondary,     // #ECFCCB
labelStyle: TextStyle(color: AppTheme.onSecondary),  // #365314

// Unselected:
backgroundColor: AppTheme.surface,       // #FFFFFF
labelStyle: TextStyle(color: AppTheme.textMuted),
```

---

## 10. File: `lib/screens/water_usage_screen.dart`

### 10.1 — Chart line & fill

```dart
// CURRENT
color: Colors.blue
color: Colors.blue.withValues(alpha: 0.2)

// NEW  [COLOR ONLY]
// Water usage → use a teal/cyan to distinguish from soil moisture (which is primary green)
color: Color(0xFF22D3EE)
color: Color(0xFF22D3EE).withValues(alpha: 0.15)
```

### 10.2 — "Weekly Trend" total text

```dart
// CURRENT
TextStyle(color: Colors.blue)

// NEW  [COLOR ONLY]
TextStyle(color: Color(0xFF0891B2))  // darker cyan, matches chart line
```

### 10.3 — Chart icon

```dart
// CURRENT
Icon(LucideIcons.barChart2, color: Colors.blue)

// NEW  [COLOR ONLY]
Icon(LucideIcons.barChart2, color: Color(0xFF22D3EE))
```

### 10.4 — Efficiency score display

```dart
// Score is 0–100%. Color it contextually:
// 0–40%  → AppTheme.error        (#DC2626) red
// 41–70% → AppTheme.accent       (#F59E0B) amber
// 71–100%→ AppTheme.primary      (#4ADE80) green
```

---

## 11. File: `lib/screens/fertigation_screen.dart`

### 11.1 — Flask icon

```dart
// CURRENT
Icon(LucideIcons.flaskConical, color: Colors.purple)

// NEW  [COLOR + TWEAK]
// Purple clashes with the palette — switch to accent amber (fertilizer = nutrients = warm tone)
Icon(LucideIcons.flaskConical, color: AppTheme.accent)  // #F59E0B
```

### 11.2 — "Nutrition Status: Good" text

```dart
// CURRENT
TextStyle(color: Colors.green)

// NEW  [COLOR ONLY]
TextStyle(color: AppTheme.onSecondary)  // #365314 — dark earthy green
```

### 11.3 — "Log Fertilizer Application" button

```dart
// CURRENT
ElevatedButton.styleFrom(backgroundColor: Colors.purple)

// NEW  [COLOR + TWEAK]
// Remove hardcoded purple; use accent amber for nutrient/fertilizer actions
ElevatedButton.styleFrom(
  backgroundColor: AppTheme.accent,   // #F59E0B
  foregroundColor: AppTheme.onPrimary, // #03341F dark text on amber
)
```

---

## 12. File: `lib/screens/alerts_screen.dart`

### 12.1 — Alert severity colors

Alerts have three severity levels. Map them consistently:

| Severity | Current (assumed) | New |
|---|---|---|
| Info | `Colors.blue` | `AppTheme.secondary` bg + `AppTheme.onSecondary` text |
| Warning | `Colors.orange` | `AppTheme.accent` (`#F59E0B`) |
| Critical/Error | `Colors.red` | `AppTheme.error` (`#DC2626`) — unchanged |

### 12.2 — Pump ON alert icon

```dart
// NEW  [COLOR ONLY]
Icon(LucideIcons.power, color: AppTheme.primary)    // #4ADE80
```

### 12.3 — Pump OFF / fault alert icon

```dart
// NEW  [COLOR ONLY]
Icon(LucideIcons.powerOff, color: AppTheme.error)   // #DC2626
```

### 12.4 — Rain detected alert

```dart
// NEW  [COLOR ONLY]
Icon(LucideIcons.cloudRain, color: Color(0xFF22D3EE))  // cyan water tone
```

---

## 13. File: `lib/screens/settings_screen.dart`

### 13.1 — Sign Out button

```dart
// CURRENT
ElevatedButton.styleFrom(
  backgroundColor: Colors.red.shade50,
  foregroundColor: Colors.red,
)

// NEW  [COLOR ONLY] — keep red intent but use the palette's error token
ElevatedButton.styleFrom(
  backgroundColor: AppTheme.error.withValues(alpha: 0.08),
  foregroundColor: AppTheme.error,
)
```

### 13.2 — Icon colors in ListTiles

```dart
// CURRENT — default (inherits textPrimary / grey)
// NEW  [COLOR ONLY] — give them the dark green text color
Icon(LucideIcons.user,        color: AppTheme.onPrimary)
Icon(LucideIcons.smartphone,  color: AppTheme.onPrimary)
Icon(LucideIcons.bell,        color: AppTheme.onPrimary)
```

---

## 14. Shared Navigation Elements (`router.dart` AppBar)

### 14.1 — AppBar bell icon

```dart
// CURRENT — inherits foregroundColor from AppBarTheme (was textPrimary)
// NEW  [COLOR ONLY] — theme update handles this automatically
// If explicitly set, use:
IconButton(icon: Icon(LucideIcons.bell, color: AppTheme.text))
```

---

## 15. Implementation Order

Follow this order to avoid re-touching files multiple times:

```
Step 1 → lib/theme.dart          (foundation — do this first)
Step 2 → lib/router.dart         (drawer + bottom nav)
Step 3 → lib/screens/dashboard_screen.dart
Step 4 → lib/screens/irrigation_screen.dart
Step 5 → lib/screens/weather_screen.dart
Step 6 → lib/screens/pump_control_screen.dart
Step 7 → lib/screens/crop_profiles_screen.dart
Step 8 → lib/screens/water_usage_screen.dart
Step 9 → lib/screens/fertigation_screen.dart
Step 10→ lib/screens/alerts_screen.dart
Step 11→ lib/screens/settings_screen.dart
```

After Step 1, run the app and check which screens auto-fix from the theme.
Steps 3–11 are only for **hardcoded** colors that the theme can't reach.

---

## 16. Things to Fix Alongside (from existing warnings)

These are pre-existing issues in the codebase. Fix them in the same pass:

| File | Issue | Fix |
|---|---|---|
| `irrigation_screen.dart` | `.withOpacity()` deprecated | Replace with `.withValues(alpha: ...)` |
| `water_usage_screen.dart` | `.withOpacity()` deprecated | Replace with `.withValues(alpha: ...)` |
| `router.dart` lines 80–84 | `if` without `{}` braces | Wrap all `if` bodies in curly braces |
| `supabase_config.dart` | Unused import | Remove the unused `supabase_flutter` import |

---

## 17. Color Usage Quick Reference

Use this cheat sheet when coding any new widget:

| Situation | Token to use |
|---|---|
| Primary action button | `primary` + `onPrimary` text |
| Subtle badge / chip | `secondary` bg + `onSecondary` text |
| Warning / temperature / nutrients | `accent` (`#F59E0B`) |
| Water / rain / humidity | `Color(0xFF22D3EE)` cyan |
| All body text | `text` (`#1A2E1F`) |
| Muted/secondary text | `textMuted` (`#4A6741`) |
| Card background | `surface` (`#FFFFFF`) |
| Screen background | `background` (`#F8FFF8`) |
| Error / fault / pump OFF | `error` (`#DC2626`) |
| Deep dark green accents | `onPrimary` (`#03341F`) |
