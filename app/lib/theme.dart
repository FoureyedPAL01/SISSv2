// lib/theme.dart

import 'package:flutter/material.dart';

class AppTheme {

  // The single seed color — M3 generates everything else from this
  // Green chosen to match the irrigation / agriculture theme
  static const Color _seed = Color(0xFF16A34A);

  // ── Light theme ───────────────────────────────────────────────────────────
  static ThemeData get lightTheme {
    // fromSeed generates a full M3 ColorScheme from one color.
    // All surface, container, and tonal colors are derived automatically.
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,              // enforce M3 everywhere
      colorScheme: colorScheme,        // hand the generated scheme to the theme
      fontFamily: 'Quicksand',        // Default font for all text

      // ── AppBar ─────────────────────────────────────────────────────────
      // M3 AppBar uses surface color with no elevation by default
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: Color(0xFF000000),
        elevation: 0,
        scrolledUnderElevation: 1,     // subtle shadow only when scrolled
        centerTitle: false,
      ),

      // ── Cards ──────────────────────────────────────────────────────────
      // M3 has three card variants: elevated, filled, outlined.
      // Default (elevated) uses surfaceContainerLow + slight elevation.
      cardTheme: CardThemeData(
        elevation: 1,
        // M3 uses surfaceContainerLow automatically — no need to hardcode color
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12), // M3 spec: 12dp for cards
        ),
        margin: const EdgeInsets.only(bottom: 12),
      ),

      // ── NavigationBar (M3 bottom nav) ───────────────────────────────────
      // Replaces BottomNavigationBar.
      // M3 NavigationBar uses surfaceContainer background by default.
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: colorScheme.secondaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: Color(0xFF000000));
          }
          return IconThemeData(color: Color(0xFF000000));
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
                color: Color(0xFF000000),
                fontWeight: FontWeight.bold,
                fontSize: 12);
          }
          return TextStyle(color: Color(0xFF000000), fontWeight: FontWeight.bold, fontSize: 12);
        }),
      ),

      // ── NavigationDrawer (M3 side drawer) ───────────────────────────────
      navigationDrawerTheme: NavigationDrawerThemeData(
        indicatorColor: colorScheme.secondaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28), // M3 pill shape
        ),
      ),

      // ── Input fields ────────────────────────────────────────────────────
      // M3 uses filled style by default
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,     // filled fields have no border at rest
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      // ── Buttons ─────────────────────────────────────────────────────────
      // M3 has: FilledButton, FilledButton.tonal, OutlinedButton, TextButton
      // ElevatedButton still works but FilledButton is the M3 primary action.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),  // M3 touch target minimum
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(100), // M3 uses fully rounded
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(100),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(100),
          ),
        ),
      ),

      // ── Chips ───────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),

      // ── Dialogs ─────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28), // M3 dialog corner radius
        ),
        elevation: 3,
      ),

      // ── Bottom sheet ────────────────────────────────────────────────────
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
      ),

      // ── Snackbar ─────────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,   // M3 uses floating snackbars
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),

      // ── Typography ──────────────────────────────────────────────────────
      // M3 type scale: displayLarge → labelSmall (15 styles)
      // Do NOT manually override colors here — let colorScheme handle it
      textTheme: const TextTheme(
        headlineLarge:  TextStyle(fontFamily: 'Bungee', fontWeight: FontWeight.w700, fontSize: 32),
        headlineMedium: TextStyle(fontFamily: 'Bungee', fontWeight: FontWeight.w700, fontSize: 24),
        headlineSmall:  TextStyle(fontFamily: 'Bungee', fontWeight: FontWeight.w600, fontSize: 20),
        titleLarge:     TextStyle(fontFamily: 'Bungee', fontWeight: FontWeight.w600, fontSize: 18),
        titleMedium:    TextStyle(fontFamily: 'Merriweather', fontWeight: FontWeight.w500, fontSize: 16),
        titleSmall:     TextStyle(fontFamily: 'Merriweather', fontWeight: FontWeight.w500, fontSize: 14),
        bodyLarge:      TextStyle(fontFamily: 'Quicksand', fontSize: 16),
        bodyMedium:     TextStyle(fontFamily: 'Quicksand', fontSize: 14),
        bodySmall:      TextStyle(fontFamily: 'Quicksand', fontSize: 12),
        labelLarge:     TextStyle(fontFamily: 'Quicksand', fontWeight: FontWeight.w500, fontSize: 14),
        labelMedium:    TextStyle(fontFamily: 'Quicksand', fontWeight: FontWeight.w500, fontSize: 12),
        labelSmall:     TextStyle(fontFamily: 'Quicksand', fontWeight: FontWeight.w500, fontSize: 11),
      ),
    );
  }

  // ── Dark theme ────────────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: 'Quicksand',

      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
      ),

      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.only(bottom: 12),
      ),

      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: colorScheme.secondaryContainer,
      ),

      navigationDrawerTheme: NavigationDrawerThemeData(
        indicatorColor: colorScheme.secondaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(100),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(100),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(100),
          ),
        ),
      ),

      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),

      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        elevation: 3,
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),

      textTheme: const TextTheme(
        headlineLarge:  TextStyle(fontFamily: 'Bungee', fontWeight: FontWeight.w700, fontSize: 32),
        headlineMedium: TextStyle(fontFamily: 'Bungee', fontWeight: FontWeight.w700, fontSize: 24),
        headlineSmall:  TextStyle(fontFamily: 'Bungee', fontWeight: FontWeight.w600, fontSize: 20),
        titleLarge:     TextStyle(fontFamily: 'Bungee', fontWeight: FontWeight.w600, fontSize: 18),
        titleMedium:    TextStyle(fontFamily: 'Merriweather', fontWeight: FontWeight.w500, fontSize: 16),
        titleSmall:     TextStyle(fontFamily: 'Merriweather', fontWeight: FontWeight.w500, fontSize: 14),
        bodyLarge:      TextStyle(fontFamily: 'Quicksand', fontSize: 16),
        bodyMedium:     TextStyle(fontFamily: 'Quicksand', fontSize: 14),
        bodySmall:      TextStyle(fontFamily: 'Quicksand', fontSize: 12),
        labelLarge:     TextStyle(fontFamily: 'Quicksand', fontWeight: FontWeight.w500, fontSize: 14),
        labelMedium:    TextStyle(fontFamily: 'Quicksand', fontWeight: FontWeight.w500, fontSize: 12),
        labelSmall:     TextStyle(fontFamily: 'Quicksand', fontWeight: FontWeight.w500, fontSize: 11),
      ),
    );
  }

}


