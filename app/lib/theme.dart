// Fresh Greens Theme
// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

class AppTheme {
  // Palette constants
  static const Color mist = Color(0xFFD8F3DC);
  static const Color paleMint = Color(0xFFB7E4C7);
  static const Color softMint = Color(0xFF95D5B2);
  static const Color lightLeaf = Color(0xFF74C69D);
  static const Color freshLeaf = Color(0xFF52B788);
  static const Color teal = Color(0xFF40916C);
  static const Color deepLeaf = Color(0xFF2D6A4F);
  static const Color pine = Color(0xFF1B4332);
  static const Color night = Color(0xFF081C15);
  static const Color accentRed = Color(0xFF9B2226);

  static ThemeData get theme {
    final colorScheme = const ColorScheme.light(
      primary: teal,
      onPrimary: Colors.white,
      secondary: freshLeaf,
      onSecondary: night,
      surface: mist,          // swapped: cards/charts now use former screen bg
      onSurface: night,
      background: paleMint,   // swapped: screen bg now paleMint
      onBackground: night,
      error: accentRed,
      onError: Colors.white,
      outline: softMint,
      surfaceTint: Colors.transparent,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: 'Poppins',
      primaryColor: teal,
      scaffoldBackgroundColor: paleMint,
      colorScheme: colorScheme,
      iconTheme: const IconThemeData(color: pine, size: 24),

      appBarTheme: const AppBarTheme(
        backgroundColor: paleMint,
        foregroundColor: night,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: night),
        actionsIconTheme: IconThemeData(color: night),
        titleTextStyle: TextStyle(
          color: night,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          fontFamily: 'Poppins',
        ),
      ),

      drawerTheme: const DrawerThemeData(
        backgroundColor: mist,
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: mist,
        surfaceTintColor: Colors.transparent,
        indicatorColor: deepLeaf,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: Colors.white);
          }
          return const IconThemeData(color: pine);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            );
          }
          return const TextStyle(
            color: night,
            fontWeight: FontWeight.bold,
          );
        }),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: paleMint,
        selectedItemColor: Colors.white,
        unselectedItemColor: night,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: paleMint,
        elevation: 0,
        indicatorColor: deepLeaf,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: Colors.white);
          }
          return const IconThemeData(color: night);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            );
          }
          return const TextStyle(
            color: night,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          );
        }),
      ),

      cardTheme: CardThemeData(
        color: mist,
        shadowColor: deepLeaf.withValues(alpha: 0.2),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: softMint, width: 0.5),
        ),
        margin: const EdgeInsets.only(bottom: 16),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: teal,
          foregroundColor: Colors.white,
          disabledBackgroundColor: softMint.withValues(alpha: 0.4),
          disabledForegroundColor: night.withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 0,
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: freshLeaf,
          foregroundColor: night,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 0,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: deepLeaf,
          side: const BorderSide(color: deepLeaf, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: teal,
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: teal,
        foregroundColor: Colors.white,
        elevation: 4,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: mist.withValues(alpha: 0.85), // swapped with screen bg
        hintStyle: TextStyle(color: deepLeaf.withValues(alpha: 0.6)),
        labelStyle: const TextStyle(color: deepLeaf),
        prefixIconColor: deepLeaf,
        suffixIconColor: deepLeaf,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: softMint),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: softMint),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: teal, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: accentRed),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: accentRed, width: 2),
        ),
        errorStyle: const TextStyle(color: accentRed),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: teal,
        inactiveTrackColor: softMint.withValues(alpha: 0.5),
        thumbColor: deepLeaf,
        overlayColor: deepLeaf.withValues(alpha: 0.15),
        valueIndicatorColor: deepLeaf,
        valueIndicatorTextStyle: const TextStyle(color: Colors.white),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return teal;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(Colors.white),
        side: const BorderSide(color: deepLeaf, width: 1.5),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return teal;
          return deepLeaf;
        }),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return teal;
          return deepLeaf.withValues(alpha: 0.6);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return teal.withValues(alpha: 0.35);
          }
          return deepLeaf.withValues(alpha: 0.2);
        }),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: teal,
        circularTrackColor: softMint.withValues(alpha: 0.3),
        linearTrackColor: softMint.withValues(alpha: 0.3),
        linearMinHeight: 4,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: mist,
        selectedColor: teal,
        labelStyle: const TextStyle(color: night),
        secondaryLabelStyle: const TextStyle(color: night),
        side: const BorderSide(color: deepLeaf),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      dividerTheme: DividerThemeData(
        color: deepLeaf.withValues(alpha: 0.25),
        thickness: 1,
        space: 1,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: paleMint,
        titleTextStyle: const TextStyle(
          color: night,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        contentTextStyle:
            const TextStyle(color: deepLeaf, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: mist,
        modalBackgroundColor: mist,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),

      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        iconColor: deepLeaf,
        textColor: night,
        subtitleTextStyle: TextStyle(color: deepLeaf.withValues(alpha: 0.7)),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: deepLeaf,
          hoverColor: teal.withValues(alpha: 0.1),
        ),
      ),

      textTheme: const TextTheme(
        displayLarge: TextStyle(color: night, fontWeight: FontWeight.bold, fontSize: 57),
        displayMedium: TextStyle(color: night, fontWeight: FontWeight.bold, fontSize: 45),
        displaySmall: TextStyle(color: night, fontWeight: FontWeight.bold, fontSize: 36),

        headlineLarge: TextStyle(color: night, fontWeight: FontWeight.bold, fontSize: 32),
        headlineMedium: TextStyle(color: night, fontWeight: FontWeight.bold, fontSize: 24),
        headlineSmall: TextStyle(color: pine, fontWeight: FontWeight.bold, fontSize: 20),

        titleLarge: TextStyle(color: night, fontWeight: FontWeight.bold, fontSize: 18),
        titleMedium: TextStyle(color: night, fontWeight: FontWeight.bold, fontSize: 16),
        titleSmall: TextStyle(color: pine, fontWeight: FontWeight.bold, fontSize: 14),

        bodyLarge: TextStyle(color: night, fontSize: 16),
        bodyMedium: TextStyle(color: pine, fontSize: 14),
        bodySmall: TextStyle(color: Color(0xB01B4332), fontSize: 12),

        labelLarge: TextStyle(color: night, fontWeight: FontWeight.bold, fontSize: 14),
        labelMedium: TextStyle(color: pine, fontSize: 12),
        labelSmall: TextStyle(color: Color(0xB01B4332), fontSize: 11),
      ),
    ).copyWith(
      // keep ThemeExtension for compatibility
      extensions: const <ThemeExtension<dynamic>>[
        AppColors.light,
      ],
    );
  }

  // Backwards compatibility getters
  static ThemeData get lightTheme => theme;
  static ThemeData get darkTheme => theme;
}

@immutable
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
    successGreen: AppTheme.teal,
    infoBlue: AppTheme.freshLeaf,
    infoBlueDark: AppTheme.deepLeaf,
    infoBlueBackground: AppTheme.paleMint,
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
      infoBlueBackground: Color.lerp(infoBlueBackground, other.infoBlueBackground, t) ??
          infoBlueBackground,
    );
  }
}
