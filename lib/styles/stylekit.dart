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

/// Available color palettes for the application's light and dark themes.
enum ThemePalette { classic, forest, purpleRaindrops, sage, rose }

List<ThemePalette> _palettesFor(bool isDark) => isDark
    ? const [
        ThemePalette.classic,
        ThemePalette.forest,
        ThemePalette.purpleRaindrops
      ]
    : const [ThemePalette.classic, ThemePalette.sage, ThemePalette.rose];

String _paletteName(ThemePalette palette) => switch (palette) {
      ThemePalette.classic => 'Classic',
      ThemePalette.forest => 'Forest',
      ThemePalette.purpleRaindrops => 'Purple Raindrops',
      ThemePalette.sage => 'Sage',
      ThemePalette.rose => 'Rose',
    };

class _PaletteColors {
  final Color background;
  final Color surface;
  final Color container;
  final Color accent;
  final Color foreground;
  final Color onAccent;
  final Color appBar;

  const _PaletteColors({
    required this.background,
    required this.surface,
    required this.container,
    required this.accent,
    required this.foreground,
    required this.onAccent,
    required this.appBar,
  });
}

// Based on palettes featured on coolors.co/palettes/trending.
const _paletteColors = <ThemePalette, _PaletteColors>{
  ThemePalette.forest: _PaletteColors(
    background: Color(0xFF132A13),
    surface: Color(0xFF31572C),
    container: Color(0xFF4F772D),
    accent: Color(0xFFECF39E),
    foreground: Colors.white,
    onAccent: Color(0xFF132A13),
    appBar: Color(0xFF31572C),
  ),
  ThemePalette.purpleRaindrops: _PaletteColors(
    background: Color(0xFF14052D),
    surface: Color(0xFF260D50),
    container: Color(0xFF480CA8),
    accent: Color(0xFF4CC9F0),
    foreground: Color(0xFFF5EFFF),
    onAccent: Color(0xFF14052D),
    appBar: Color(0xFF260D50),
  ),
  ThemePalette.sage: _PaletteColors(
    background: Color(0xFFFEFAE0),
    surface: Color(0xFFE9EDC9),
    container: Color(0xFFCCD5AE),
    accent: Color(0xFF283618),
    foreground: Color(0xFF283618),
    onAccent: Colors.white,
    appBar: Color(0xFFCCD5AE),
  ),
  ThemePalette.rose: _PaletteColors(
    background: Color(0xFFF7E1D7),
    surface: Color(0xFFDEDBD2),
    container: Color(0xFFB0C4B1),
    accent: Color(0xFF4A5759),
    foreground: Color(0xFF283334),
    onAccent: Colors.white,
    appBar: Color(0xFFEDAFB8),
  ),
};

ColorScheme _buildPaletteScheme(_PaletteColors palette, bool isDark) {
  final brightness = isDark ? Brightness.dark : Brightness.light;
  return ColorScheme.fromSeed(seedColor: palette.accent, brightness: brightness)
      .copyWith(
    primary: palette.accent,
    onPrimary: palette.onAccent,
    primaryContainer: palette.container,
    onPrimaryContainer: palette.foreground,
    secondary: palette.accent,
    onSecondary: palette.onAccent,
    secondaryContainer: palette.container,
    onSecondaryContainer: palette.foreground,
    surface: palette.surface,
    onSurface: palette.foreground,
    onSurfaceVariant: palette.foreground,
    outline: palette.accent,
    outlineVariant: palette.container,
    surfaceDim: palette.background,
    surfaceBright: palette.surface,
    surfaceContainerLowest: palette.background,
    surfaceContainerLow: palette.surface,
    surfaceContainer: palette.surface,
    surfaceContainerHigh: palette.container,
    surfaceContainerHighest: palette.container,
    surfaceTint: Colors.transparent,
    inverseSurface: palette.foreground,
    onInverseSurface: palette.background,
    inversePrimary: palette.container,
  );
}

/// Builds the application's Material 3 theme and shared component styles.
ThemeData buildTheme({
  bool isDark = true,
  ThemePalette palette = ThemePalette.classic,
}) {
  if (!_palettesFor(isDark).contains(palette)) {
    throw ArgumentError(
        'Palette ${palette.name} is not available in this mode.');
  }
  final customPalette = _paletteColors[palette];
  final scheme = customPalette != null
      ? _buildPaletteScheme(customPalette, isDark)
      : isDark
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
    scaffoldBackgroundColor:
        customPalette?.background ?? (isDark ? kNavy900 : kLightBackground),
    appBarTheme: AppBarTheme(
      backgroundColor:
          customPalette?.appBar ?? (isDark ? kNavy800 : kLightContainer),
      foregroundColor: customPalette == null
          ? (isDark ? kYellow : kLightText)
          : (isDark ? scheme.primary : scheme.onSurface),
      surfaceTintColor: Colors.transparent,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: customPalette == null && isDark ? kGold : scheme.primary,
      foregroundColor:
          customPalette == null && isDark ? kNavy900 : scheme.onPrimary,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(
        color: customPalette == null
            ? (isDark ? kNavy900 : Colors.white)
            : scheme.onInverseSurface,
      ),
      actionTextColor:
          customPalette == null ? scheme.primary : scheme.onInverseSurface,
    ),
  );
}

class _ThemePaletteMenu extends StatelessWidget {
  final bool isDark;
  final ThemePalette selected;
  final ValueChanged<ThemePalette> onSelected;

  const _ThemePaletteMenu({
    required this.isDark,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ThemePalette>(
      tooltip: 'Choose color palette',
      icon: const Icon(Icons.palette_outlined),
      initialValue: selected,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final palette in _palettesFor(isDark))
          CheckedPopupMenuItem<ThemePalette>(
            value: palette,
            checked: palette == selected,
            child: Text(_paletteName(palette)),
          ),
      ],
    );
  }
}

mixin _ThemeSettings on State<FuelLogApp> {
  static const _themePreferenceKey = 'fuel_theme_is_dark_v1';
  static const _darkPaletteKey = 'fuel_dark_palette_v1';
  static const _lightPaletteKey = 'fuel_light_palette_v1';

  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  bool _isDarkTheme = true;
  ThemePalette _darkPalette = ThemePalette.classic;
  ThemePalette _lightPalette = ThemePalette.classic;
  bool _themeWasChanged = false;
  bool _darkPaletteWasChanged = false;
  bool _lightPaletteWasChanged = false;
  Future<void> _themeSaveQueue = Future<void>.value();

  ThemePalette get _currentPalette =>
      _isDarkTheme ? _darkPalette : _lightPalette;

  ThemePalette _readPalette(SharedPreferences prefs, bool isDark) {
    try {
      final stored =
          prefs.getString(isDark ? _darkPaletteKey : _lightPaletteKey);
      if (stored == null) return ThemePalette.classic;
      for (final palette in _palettesFor(isDark)) {
        if (palette.name == stored) return palette;
      }
      throw FormatException('Unknown saved color palette: $stored');
    } catch (error, stackTrace) {
      _reportThemePreferenceError('load', error, stackTrace);
      return ThemePalette.classic;
    }
  }

  Future<void> _loadThemePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTheme = prefs.getBool(_themePreferenceKey);
      final darkPalette = _readPalette(prefs, true);
      final lightPalette = _readPalette(prefs, false);
      if (!mounted) return;
      setState(() {
        if (!_themeWasChanged && savedTheme != null) _isDarkTheme = savedTheme;
        if (!_darkPaletteWasChanged) _darkPalette = darkPalette;
        if (!_lightPaletteWasChanged) _lightPalette = lightPalette;
      });
    } catch (error, stackTrace) {
      _reportThemePreferenceError('load', error, stackTrace);
    }
  }

  void _toggleTheme() {
    _themeWasChanged = true;
    final selectedTheme = !_isDarkTheme;
    setState(() => _isDarkTheme = selectedTheme);
    _saveThemeSetting(
        (prefs) => prefs.setBool(_themePreferenceKey, selectedTheme));
  }

  void _selectPalette(ThemePalette palette) {
    final isDark = _isDarkTheme;
    if (!_palettesFor(isDark).contains(palette)) {
      throw ArgumentError(
          'Palette ${palette.name} is not available in this mode.');
    }
    setState(() {
      if (isDark) {
        _darkPaletteWasChanged = true;
        _darkPalette = palette;
      } else {
        _lightPaletteWasChanged = true;
        _lightPalette = palette;
      }
    });
    _saveThemeSetting(
      (prefs) => prefs.setString(
          isDark ? _darkPaletteKey : _lightPaletteKey, palette.name),
    );
  }

  void _saveThemeSetting(Future<bool> Function(SharedPreferences) write) {
    _themeSaveQueue = _themeSaveQueue.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!await write(prefs)) {
          throw StateError('The theme preference was not saved.');
        }
      } catch (error, stackTrace) {
        _reportThemePreferenceError('save', error, stackTrace);
      }
    });
  }

  void _reportThemePreferenceError(
    String action,
    Object error,
    StackTrace stackTrace,
  ) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'FuelLog theme preference',
      ),
    );
    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text('Could not $action theme preference: $error'),
        duration: kAppSnackBarDuration,
      ),
    );
  }
}
