// The Botanical Atelier Theme
// Design System: "The Living Editorial"
import 'package:flutter/material.dart';

class AppTheme {
  // ─────────────────────────────────────────────────────────────────────────────
  // BOTANICAL ATELIER COLOR PALETTE
  // ─────────────────────────────────────────────────────────────────────────────

  // Primary: Deep chlorophyll greens
  static const Color primary = Color(0xFF16351C);       // Deep forest green
  static const Color primaryContainer = Color(0xFF2D4C31); // Lighter green
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer = Color(0xFFD4E8D0);

  // Secondary: Earthy accents
  static const Color secondary = Color(0xFF4A5D23);    // Olive
  static const Color secondaryContainer = Color(0xFF6B8240);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color onSecondaryContainer = Color(0xFFE8F0D8);

  // ─────────────────────────────────────────────────────────────────────────────
  // BACKWARDS COMPATIBILITY (legacy names for existing screens)
  // ─────────────────────────────────────────────────────────────────────────────
  // These map old names to new botanical palette
  static const Color teal = primary;         // Was #40916C → now #16351C
  static const Color deepLeaf = primaryContainer; // Was #2D6A4F → now #2D4C31
  static const Color pine = primaryContainer;
  static const Color night = onSurface;    // Was #081C15 → now #1B1C1A
  static const Color freshLeaf = secondary;      // Was #52B788 → now #4A5D23
  static const Color softMint = Color(0xFF95D5B2);
  static const Color paleMint = surfaceContainerLow;
  static const Color mist = surfaceContainerLow;
  static const Color lightLeaf = Color(0xFF74C69D);
  static const Color accentRed = error;

  // Tertiary: Warm botanical
  static const Color tertiary = Color(0xFF3D6B54);      // Sage
  static const Color tertiaryContainer = Color(0xFF5A9178);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color onTertiaryContainer = Color(0xFFD0E8DC);

  // Error
  static const Color error = Color(0xFFBA1A1A);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFFFFDAD6);
  static const Color onErrorContainer = Color(0xFF410002);

  // Surface hierarchy (The "No-Line" Rule - no borders, only color shifts)
  static const Color surface = Color(0xFFFBF9F5);         // Base - warm paper white
  static const Color surfaceBright = Color(0xFFF8F5F0);    // Slightly brighter
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF); // Cards - max pop
  static const Color surfaceContainerLow = Color(0xFFF5F3F0);     // Sections
  static const Color surfaceContainer = Color(0xFFEFEEEA);         // Elevated
  static const Color surfaceContainerHigh = Color(0xFFE9E8E3);      // High elevation
  static const Color surfaceContainerHighest = Color(0xFFE3E2DD);

  // On-surface (warm charcoal instead of pure black)
  static const Color onSurface = Color(0xFF1B1C1A);
  static const Color onSurfaceVariant = Color(0xFF464743);
  static const Color outline = Color(0xFF767671);
  static const Color outlineVariant = Color(0xFFC6C5C0); // Ghost border (15%)

  // Background
  static const Color background = Color(0xFFFBF9F5);
  static const Color onBackground = Color(0xFF1B1C1A);

  // Inverse
  static const Color inverseSurface = Color(0xFF30302E);
  static const Color inverseOnSurface = Color(0xFFF1F0EB);
  static const Color inversePrimary = Color(0xFF8CD189);

  // Scrim
  static const Color scrim = Color(0xFF000000);

  // ─────────────────────────────────────────────────────────────────────────────
  // SHADOWS (Ambient - minimal, tinted)
  // ─────────────────────────────────────────────────────────────────────────────
  static List<BoxShadow> ambientShadow(Color color) => [
    BoxShadow(
      color: color.withValues(alpha: 0.06),
      blurRadius: 30,
      offset: const Offset(0, 8),
    ),
  ];

  // ─────────────────────────────────────────────────────────────────────────────
  // LIGHT THEME
  // ─────────────────────────────────────────────────────────────────────────────
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primaryContainer,
      onPrimaryContainer: onPrimaryContainer,
      secondary: secondary,
      onSecondary: onSecondary,
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: onSecondaryContainer,
      tertiary: tertiary,
      onTertiary: onTertiary,
      tertiaryContainer: tertiaryContainer,
      onTertiaryContainer: onTertiaryContainer,
      error: error,
      onError: onError,
      errorContainer: errorContainer,
      onErrorContainer: onErrorContainer,
      surface: surface,
      onSurface: onSurface,
      onSurfaceVariant: onSurfaceVariant,
      outline: outline,
      outlineVariant: outlineVariant,
      scrim: scrim,
      inverseSurface: inverseSurface,
      onInverseSurface: inverseOnSurface,
      inversePrimary: inversePrimary,
      surfaceContainerLowest: surfaceContainerLowest,
      surfaceContainerLow: surfaceContainerLow,
      surfaceContainer: surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh,
      surfaceContainerHighest: surfaceContainerHighest,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,

      // Typography: Manrope (all text)
      fontFamily: 'Manrope',
      textTheme: _buildTextTheme(Brightness.light),

      // App Bar - No-line, use surface color
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: onSurface,
          letterSpacing: -0.5,
        ),
        iconTheme: const IconThemeData(color: onSurface),
      ),

      // Bottom Navigation - Surface container with glassmorphism feel
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        elevation: 0,
        indicatorColor: primaryContainer,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: onPrimaryContainer,
            );
          }
          return TextStyle(
            fontFamily: 'Manrope',
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: onPrimaryContainer);
          }
          return IconThemeData(color: onSurfaceVariant);
        }),
      ),

      // Cards - Surface container lowest for max "pop", no borders
      cardTheme: CardThemeData(
        color: surfaceContainerLowest,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: const EdgeInsets.only(bottom: 12),
      ),

      // Buttons - Exaggerated roundedness (pill shape = xl radius)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(48), // Pill shape
          ),
          textStyle: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryContainer,
          foregroundColor: onPrimaryContainer,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(48),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: outlineVariant),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(48),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),

      // Floating Action Button
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryContainer,
        foregroundColor: onPrimaryContainer,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),

      // Input Fields - Surface container high, no border, ghost border on focus
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16), // DEFAULT (1rem)
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primary, width: 1.5), // Ghost border
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: error),
        ),
        hintStyle: TextStyle(color: onSurfaceVariant.withValues(alpha: 0.6)),
        labelStyle: const TextStyle(color: onSurfaceVariant),
      ),

      // Chips - Secondary fixed dim
      chipTheme: ChipThemeData(
        backgroundColor: surfaceContainerLow,
        selectedColor: secondaryContainer,
        labelStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        side: BorderSide.none,
      ),

      // Dividers - GONE! Use spacing instead. If needed, use ghost border.
      dividerTheme: DividerThemeData(
        color: outlineVariant.withValues(alpha: 0.4),
        thickness: 1,
        space: 1,
      ),

      // Dialog - Surface container
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceContainerLow,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: onSurface,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 14,
          color: onSurfaceVariant,
        ),
      ),

      // Bottom Sheet
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceContainerLow,
        modalBackgroundColor: surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),

      // List Tiles - No dividers, use spacing
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        tileColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),

      // Switch
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary;
          return onSurfaceVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primary.withValues(alpha: 0.3);
          }
          return outlineVariant;
        }),
      ),

      // Checkbox
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(onPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        side: BorderSide(color: outlineVariant, width: 1.5),
      ),

      // Radio
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary;
          return onSurfaceVariant;
        }),
      ),

      // Progress Indicator
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: surfaceContainerHigh,
      ),

      // Slider
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        inactiveTrackColor: surfaceContainerHigh,
        thumbColor: primary,
        overlayColor: primary.withValues(alpha: 0.12),
      ),

      // Icon Theme
      iconTheme: const IconThemeData(
        color: onSurfaceVariant,
        size: 24,
      ),

      // Extensions
    ).copyWith(
      extensions: const <ThemeExtension<dynamic>>[
        AppColors.light,
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // DARK THEME - THE MIDNIGHT GREENHOUSE
  // ─────────────────────────────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    // Midnight Greenhouse palette
    const darkSurface = Color(0xFF121412);           // Level 0 - Base canvas
    const darkSurfaceContainerLow = Color(0xFF1a1c1a); // Level 1 - Sections
    const darkSurfaceContainer = Color(0xFF1e201e);    // Level 2 - Cards
    const darkSurfaceContainerHigh = Color(0xFF282a28);
    const darkSurfaceContainerHighest = Color(0xFF333533); // Level 3 - Pop-overs
    const darkSurfaceContainerLowest = Color(0xFF0d0f0d);  // Input fields

    const darkPrimary = Color(0xFFb5cdb3);           // Leaf in moonlight
    const darkOnPrimary = Color(0xFF213522);
    const darkPrimaryContainer = Color(0xFF2d4530);
    const darkOnPrimaryContainer = Color(0xFFd4e8d0);

    const darkSecondary = Color(0xFF9fbca3);
    const darkOnSecondary = Color(0xFF1e3522);
    const darkSecondaryContainer = Color(0xFF334d38);  // Chips
    const darkOnSecondaryContainer = Color(0xFF9fbca3);

    const darkTertiary = Color(0xFFeac34a);           // Gold highlight
    const darkOnTertiary = Color(0xFF3d3000);
    const darkTertiaryContainer = Color(0xFF584500);
    const darkOnTertiaryContainer = Color(0xFFffe08a);

    const darkOnSurface = Color(0xFFe2e3df);         // Body text - WCAG AA
    const darkOnSurfaceVariant = Color(0xFFc3c8bf);  // Labels
    const darkOutline = Color(0xFF434842);           // Ghost border
    const darkOutlineVariant = Color(0xFF434842);    // 15% opacity for ghost borders

    const darkError = Color(0xFFffb4ab);
    const darkOnError = Color(0xFF690005);
    const darkErrorContainer = Color(0xFF93000a);
    const darkOnErrorContainer = Color(0xFFffdad6);

    final colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: darkPrimary,
      onPrimary: darkOnPrimary,
      primaryContainer: darkPrimaryContainer,
      onPrimaryContainer: darkOnPrimaryContainer,
      secondary: darkSecondary,
      onSecondary: darkOnSecondary,
      secondaryContainer: darkSecondaryContainer,
      onSecondaryContainer: darkOnSecondaryContainer,
      tertiary: darkTertiary,
      onTertiary: darkOnTertiary,
      tertiaryContainer: darkTertiaryContainer,
      onTertiaryContainer: darkOnTertiaryContainer,
      error: darkError,
      onError: darkOnError,
      errorContainer: darkErrorContainer,
      onErrorContainer: darkOnErrorContainer,
      surface: darkSurface,
      onSurface: darkOnSurface,
      onSurfaceVariant: darkOnSurfaceVariant,
      outline: darkOutline,
      outlineVariant: darkOutlineVariant.withValues(alpha: 0.15),
      scrim: const Color(0xFF000000),
      inverseSurface: darkOnSurface,
      onInverseSurface: const Color(0xFF2f312e),
      inversePrimary: darkPrimaryContainer,
      surfaceContainerLowest: darkSurfaceContainerLowest,
      surfaceContainerLow: darkSurfaceContainerLow,
      surfaceContainer: darkSurfaceContainer,
      surfaceContainerHigh: darkSurfaceContainerHigh,
      surfaceContainerHighest: darkSurfaceContainerHighest,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: darkSurface,

      fontFamily: 'Manrope',
      textTheme: _buildTextTheme(Brightness.dark),

      // App Bar - No-line, use surface color
      appBarTheme: AppBarTheme(
        backgroundColor: darkSurface,
        foregroundColor: darkOnSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: darkOnSurface,
          letterSpacing: -0.5,
        ),
        iconTheme: const IconThemeData(color: darkOnSurface),
      ),

      // Bottom Navigation - Frosted glass effect (70% opacity with blur)
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkSurface.withValues(alpha: 0.7),
        elevation: 0,
        indicatorColor: darkPrimaryContainer,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: darkOnPrimaryContainer,
            );
          }
          return TextStyle(
            fontFamily: 'Manrope',
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: darkOnSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: darkOnPrimaryContainer);
          }
          return IconThemeData(color: darkOnSurfaceVariant);
        }),
      ),

      // Cards - Surface container for natural lift, no borders
      cardTheme: CardThemeData(
        color: darkSurfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(32), // rounded-xl (3rem)
        ),
        margin: const EdgeInsets.only(bottom: 12),
      ),

      // Primary Button - Full rounded (pill), leaf in moonlight
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: darkPrimary,
          foregroundColor: darkOnPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999), // full pill
          ),
          textStyle: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Secondary Button - Transparent with ghost border
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: darkPrimaryContainer,
          foregroundColor: darkOnPrimaryContainer,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999), // full pill
          ),
          textStyle: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Tertiary Button - Gold highlight with glow on hover
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkTertiary,
          side: BorderSide(color: darkOutlineVariant.withValues(alpha: 0.15)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999), // full pill
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: darkPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),

      // Floating Action Button
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: darkPrimaryContainer,
        foregroundColor: darkOnPrimaryContainer,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),

      // Input Fields - Surface container lowest, no border
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: darkPrimary.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        hintStyle: TextStyle(color: darkOnSurfaceVariant.withValues(alpha: 0.6)),
        labelStyle: const TextStyle(color: darkOnSurfaceVariant),
      ),

      // Chips - Secondary container, full rounded (pebble-like)
      chipTheme: ChipThemeData(
        backgroundColor: darkSecondaryContainer,
        selectedColor: darkTertiaryContainer,
        labelStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: darkOnSecondaryContainer,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9999), // full - pebble
        ),
        side: BorderSide.none,
      ),

      // Dividers - GONE! Use spacing instead. If needed, use ghost border.
      dividerTheme: DividerThemeData(
        color: darkOutlineVariant.withValues(alpha: 0.15),
        thickness: 1,
        space: 1,
      ),

      // Dialog - Surface container
      dialogTheme: DialogThemeData(
        backgroundColor: darkSurfaceContainerHigh,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: darkOnSurface,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 14,
          color: darkOnSurfaceVariant,
        ),
      ),

      // Bottom Sheet
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: darkSurfaceContainerHigh,
        modalBackgroundColor: darkSurfaceContainerHigh,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),

      // List Tiles - No dividers, use spacing
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        tileColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),

      // Switch
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return darkPrimary;
          return darkOnSurfaceVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return darkPrimary.withValues(alpha: 0.3);
          }
          return darkOutlineVariant.withValues(alpha: 0.15);
        }),
      ),

      // Checkbox
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return darkPrimary;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(darkOnPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        side: BorderSide(color: darkOutlineVariant.withValues(alpha: 0.15), width: 1.5),
      ),

      // Radio
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return darkPrimary;
          return darkOnSurfaceVariant;
        }),
      ),

      // Progress Indicator
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: darkPrimary,
        linearTrackColor: darkSurfaceContainerHigh,
      ),

      // Slider
      sliderTheme: SliderThemeData(
        activeTrackColor: darkPrimary,
        inactiveTrackColor: darkSurfaceContainerHigh,
        thumbColor: darkPrimary,
        overlayColor: darkPrimary.withValues(alpha: 0.12),
      ),

      // Icon Theme
      iconTheme: const IconThemeData(
        color: darkOnSurfaceVariant,
        size: 24,
      ),

    ).copyWith(
      extensions: const <ThemeExtension<dynamic>>[
        AppColors.dark,
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // TEXT THEME BUILDER
  // ─────────────────────────────────────────────────────────────────────────────
  static TextTheme _buildTextTheme(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final onSurface = isLight ? const Color(0xFF1B1C1A) : const Color(0xFFE3E2DD);
    final onSurfaceVariant = isLight ? const Color(0xFF464743) : const Color(0xFFc3c8bf);

    return TextTheme(
      // Display - Manrope (hero moments)
      displayLarge: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 57,
        fontWeight: FontWeight.bold,
        letterSpacing: -1.5,
        color: onSurface,
      ),
      displayMedium: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 45,
        fontWeight: FontWeight.bold,
        letterSpacing: -0.5,
        color: onSurface,
      ),
      displaySmall: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 36,
        fontWeight: FontWeight.bold,
        letterSpacing: 0,
        color: onSurface,
      ),

      // Headline - Manrope (editorial authority)
      headlineLarge: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 32,
        fontWeight: FontWeight.bold,
        letterSpacing: 0,
        color: onSurface,
      ),
      headlineMedium: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 28,
        fontWeight: FontWeight.bold,
        letterSpacing: 0,
        color: onSurface,
      ),
      headlineSmall: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 24,
        fontWeight: FontWeight.bold,
        letterSpacing: 0,
        color: onSurface,
      ),

      // Title - Manrope
      titleLarge: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: onSurface,
      ),
      titleMedium: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
        color: onSurface,
      ),
      titleSmall: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: onSurface,
      ),

      // Body - Inter (utility/readability)
      bodyLarge: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 16,
        fontWeight: FontWeight.normal,
        letterSpacing: 0.5,
        color: onSurface,
      ),
      bodyMedium: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 14,
        fontWeight: FontWeight.normal,
        letterSpacing: 0.25,
        color: onSurface,
      ),
      bodySmall: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 12,
        fontWeight: FontWeight.normal,
        letterSpacing: 0.4,
        color: onSurfaceVariant,
      ),

      // Label - Inter
      labelLarge: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: onSurface,
      ),
      labelMedium: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: onSurfaceVariant,
      ),
      labelSmall: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: onSurfaceVariant,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // APP COLORS EXTENSION
  // ─────────────────────────────────────────────────────────────────────────────
  static const Color successGreen = Color(0xFF2D6A4F);
  static const Color infoBlue = Color(0xFF3D6B54);
}

class AppColors extends ThemeExtension<AppColors> {
  final Color successGreen;
  final Color infoBlue;
  final Color infoBlueDark;
  final Color infoBlueBackground;

  const AppColors({
    required this.successGreen,
    required this.infoBlue,
    required this.infoBlueDark,
    required this.infoBlueBackground,
  });

  static const light = AppColors(
    successGreen: AppTheme.successGreen,
    infoBlue: AppTheme.infoBlue,
    infoBlueDark: AppTheme.primaryContainer,
    infoBlueBackground: AppTheme.surfaceContainerLow,
  );

  static const dark = AppColors(
    successGreen: Color(0xFF5a9a76),
    infoBlue: Color(0xFF9fbca3),
    infoBlueDark: Color(0xFF2d4530),
    infoBlueBackground: Color(0xFF1a1c1a),
  );

  @override
  AppColors copyWith({
    Color? successGreen,
    Color? infoBlue,
    Color? infoBlueDark,
    Color? infoBlueBackground,
  }) {
    return AppColors(
      successGreen: successGreen ?? this.successGreen,
      infoBlue: infoBlue ?? this.infoBlue,
      infoBlueDark: infoBlueDark ?? this.infoBlueDark,
      infoBlueBackground: infoBlueBackground ?? this.infoBlueBackground,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      successGreen: Color.lerp(successGreen, other.successGreen, t) ?? successGreen,
      infoBlue: Color.lerp(infoBlue, other.infoBlue, t) ?? infoBlue,
      infoBlueDark: Color.lerp(infoBlueDark, other.infoBlueDark, t) ?? infoBlueDark,
      infoBlueBackground: Color.lerp(infoBlueBackground, other.infoBlueBackground, t) ?? infoBlueBackground,
    );
  }
}
