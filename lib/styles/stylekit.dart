part of '../app.dart';

// ---- Color palette (coolors.co/palette/000814-001d3d-003566-ffc300-ffd60a) ----
const Color kNavy900 = Color(0xFF000814);
const Color kNavy800 = Color(0xFF001D3D);
const Color kBlue = Color(0xFF003566);
const Color kGold = Color(0xFFFFC300);
const Color kYellow = Color(0xFFFFD60A);

const Color kLightBackground = Color(0xFFEDEDE9);
const Color kLightSurface = Color(0xFFF5EBE0);
const Color kLightContainer = Color(0xFFD6CCC2);
const Color kLightElevated = Color(0xFFE3D5CA);
const Color kLightPrimary = Color(0xFFD5BDAF);
const Color kLightText = Color(0xFF3B322D);

/// Builds the application's Material 3 theme and shared component styles.
ThemeData buildTheme({bool isDark = true}) {
  final scheme = isDark
      ? const ColorScheme(
          brightness: Brightness.dark,
          primary: kGold,
          onPrimary: kNavy900,
          primaryContainer: kBlue,
          onPrimaryContainer: kYellow,
          secondary: kYellow,
          onSecondary: kNavy900,
          secondaryContainer: kBlue,
          onSecondaryContainer: kYellow,
          error: Color(0xFFFFB4AB),
          onError: Color(0xFF690005),
          errorContainer: Color(0xFF93000A),
          onErrorContainer: Color(0xFFFFDAD6),
          surface: kNavy800,
          onSurface: Color(0xFFEAF0F8),
          onSurfaceVariant: Color(0xFFA9B8CE),
          outline: Color(0xFF5F7FA6),
          outlineVariant: kBlue,
          surfaceContainerHighest: kBlue,
          surfaceTint: Colors.transparent,
        )
      : ColorScheme.fromSeed(
          seedColor: kLightPrimary,
          brightness: Brightness.light,
        ).copyWith(
          primary: kLightPrimary,
          onPrimary: kLightText,
          primaryContainer: kLightContainer,
          onPrimaryContainer: kLightText,
          secondary: kLightContainer,
          onSecondary: kLightText,
          secondaryContainer: kLightElevated,
          onSecondaryContainer: kLightText,
          surface: kLightSurface,
          onSurface: kLightText,
          onSurfaceVariant: const Color(0xFF5C514A),
          outline: kLightPrimary,
          outlineVariant: kLightContainer,
          surfaceDim: kLightBackground,
          surfaceBright: kLightSurface,
          surfaceContainerLowest: kLightSurface,
          surfaceContainerLow: kLightBackground,
          surfaceContainer: kLightSurface,
          surfaceContainerHigh: kLightElevated,
          surfaceContainerHighest: kLightElevated,
          surfaceTint: Colors.transparent,
          inverseSurface: kLightText,
          onInverseSurface: kLightSurface,
          inversePrimary: kLightElevated,
        );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'BBH Bogle',
    scaffoldBackgroundColor: isDark ? kNavy900 : kLightBackground,
    appBarTheme: AppBarTheme(
      backgroundColor: isDark ? kNavy800 : kLightContainer,
      foregroundColor: isDark ? kYellow : kLightText,
      surfaceTintColor: Colors.transparent,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: isDark ? kGold : scheme.primary,
      foregroundColor: isDark ? kNavy900 : scheme.onPrimary,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: const TextStyle(color: Colors.white),
      actionTextColor: scheme.primary,
    ),
  );
}
