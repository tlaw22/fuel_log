import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:carousel_slider/carousel_slider.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart' hide XFile;

part 'home_page.dart';
part 'graphs_page.dart';
part 'nearby_sync_page.dart';
part 'shared_widgets.dart';
part 'entry_form.dart';
part 'pump_photos.dart';

const MethodChannel _androidNativeChannel =
    MethodChannel('com.example.fuel_log/native');
const String _monthlyBudgetPrefsKeyPrefix = 'fuel_monthly_budget_';

// ---- Change these to switch units (e.g. 'L' and 'km', and '€') ----
const String kVolumeUnit = 'gal';
const String kDistanceUnit = 'mi';
const String kCurrency = '\$';
// --------------------------------------------------------------------

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

/// Starts the Fuel Log application.
void main() => runApp(const FuelLogApp());

/// Root widget that configures the app's title, theme, and home page.
class FuelLogApp extends StatefulWidget {
  /// Creates the root application widget.
  const FuelLogApp({super.key});

  @override
  State<FuelLogApp> createState() => _FuelLogAppState();
}

class _FuelLogAppState extends State<FuelLogApp> {
  static const _themePreferenceKey = 'fuel_theme_is_dark_v1';
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  bool _isDarkTheme = true;
  bool _themeWasChanged = false;
  Future<void> _themeSaveQueue = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTheme = prefs.getBool(_themePreferenceKey);
      if (!mounted || _themeWasChanged || savedTheme == null) return;
      setState(() => _isDarkTheme = savedTheme);
    } catch (error, stackTrace) {
      _reportThemePreferenceError('load', error, stackTrace);
    }
  }

  void _toggleTheme() {
    _themeWasChanged = true;
    final selectedTheme = !_isDarkTheme;
    setState(() => _isDarkTheme = selectedTheme);
    _themeSaveQueue = _themeSaveQueue.then(
      (_) => _saveThemePreference(selectedTheme),
    );
  }

  Future<void> _saveThemePreference(bool isDarkTheme) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setBool(_themePreferenceKey, isDarkTheme)) {
        throw StateError('The theme preference was not saved.');
      }
    } catch (error, stackTrace) {
      _reportThemePreferenceError('save', error, stackTrace);
    }
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
      SnackBar(content: Text('Could not $action theme preference: $error')),
    );
  }

  /// Builds the root Material application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FuelLog',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      theme: buildTheme(isDark: _isDarkTheme),
      home: HomePage(
        isDarkTheme: _isDarkTheme,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}

// ======================= Model =======================

/// Represents one recorded fuel fill-up and its associated odometer reading.
class FuelEntry {
  final String id;
  final DateTime date;
  final double price; // price per unit of fuel
  final double volume; // units of fuel purchased
  final double odometer;
  final DateTime updatedAt;

  /// Creates a fuel entry from its identifying, purchase, and odometer values.
  FuelEntry({
    required this.id,
    required this.date,
    required this.price,
    required this.volume,
    required this.odometer,
    required this.updatedAt,
  });

  /// Calculates the total cost of this fill-up.
  double get total => price * volume;

  /// Converts this entry into a JSON-serializable map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'price': price,
        'volume': volume,
        'odometer': odometer,
        'updatedAt': updatedAt.toIso8601String(),
      };

  /// Creates a fuel entry by decoding a JSON object.
  factory FuelEntry.fromJson(Map<String, dynamic> j) {
    final date = DateTime.parse(j['date'] as String);
    return FuelEntry(
      id: j['id'] as String,
      date: date,
      price: (j['price'] as num).toDouble(),
      volume: (j['volume'] as num).toDouble(),
      odometer: (j['odometer'] as num).toDouble(),
      updatedAt:
          DateTime.parse((j['updatedAt'] as String?) ?? date.toIso8601String()),
    );
  }
}

/// Contains the complete set of active entries and tombstones to be synchronized.
class SyncSnapshot {
  final List<FuelEntry> entries;
  final Map<String, DateTime> deletions;

  /// Creates a snapshot of active entries and deletion timestamps.
  const SyncSnapshot({required this.entries, required this.deletions});

  /// Converts active entries and deletions into records suitable for nearby sync.
  List<Map<String, dynamic>> toRecords() => [
        for (final entry in entries) {'kind': 'entry', 'entry': entry.toJson()},
        for (final deletion in deletions.entries)
          {
            'kind': 'delete',
            'id': deletion.key,
            'deletedAt': deletion.value.toIso8601String(),
          },
      ];

  /// Reconstructs a snapshot from a list of nearby sync records.
  factory SyncSnapshot.fromRecords(List<dynamic> records) {
    final entries = <String, FuelEntry>{};
    final deletions = <String, DateTime>{};
    for (final value in records) {
      if (value is! Map) throw const FormatException('Invalid sync record');
      final record = Map<String, dynamic>.from(value);
      switch (record['kind']) {
        case 'entry':
          final rawEntry = record['entry'];
          if (rawEntry is! Map) {
            throw const FormatException('Invalid fuel entry in sync data');
          }
          final entry = FuelEntry.fromJson(Map<String, dynamic>.from(rawEntry));
          if (entries.containsKey(entry.id) ||
              deletions.containsKey(entry.id)) {
            throw const FormatException('Duplicate record in sync data');
          }
          entries[entry.id] = entry;
          break;
        case 'delete':
          final id = record['id'];
          final deletedAt = record['deletedAt'];
          if (id is! String || deletedAt is! String) {
            throw const FormatException('Invalid deletion in sync data');
          }
          if (entries.containsKey(id) || deletions.containsKey(id)) {
            throw const FormatException('Duplicate record in sync data');
          }
          deletions[id] = DateTime.parse(deletedAt);
          break;
        default:
          throw const FormatException('Unknown sync record');
      }
    }
    return SyncSnapshot(entries: entries.values.toList(), deletions: deletions);
  }
}

/// Merges local and remote snapshots using each entry or deletion's latest update time.
SyncSnapshot mergeSnapshots(SyncSnapshot local, SyncSnapshot remote) {
  final localEntries = {for (final entry in local.entries) entry.id: entry};
  final remoteEntries = {for (final entry in remote.entries) entry.id: entry};
  final ids = <String>{
    ...localEntries.keys,
    ...remoteEntries.keys,
    ...local.deletions.keys,
    ...remote.deletions.keys,
  };
  final entries = <FuelEntry>[];
  final deletions = <String, DateTime>{};

  for (final id in ids) {
    final entryCandidates = [
      if (localEntries[id] case final entry?) entry,
      if (remoteEntries[id] case final entry?) entry,
    ];
    final deletionCandidates = [
      if (local.deletions[id] case final deletedAt?) deletedAt,
      if (remote.deletions[id] case final deletedAt?) deletedAt,
    ];
    final newestEntry = entryCandidates.isEmpty
        ? null
        : entryCandidates.reduce((a, b) {
            if (a.updatedAt != b.updatedAt) {
              return a.updatedAt.isAfter(b.updatedAt) ? a : b;
            }
            return jsonEncode(a.toJson()).compareTo(jsonEncode(b.toJson())) >= 0
                ? a
                : b;
          });
    final newestDeletion = deletionCandidates.isEmpty
        ? null
        : deletionCandidates.reduce((a, b) => a.isAfter(b) ? a : b);

    if (newestDeletion != null &&
        (newestEntry == null ||
            !newestEntry.updatedAt.isAfter(newestDeletion))) {
      deletions[id] = newestDeletion;
    } else if (newestEntry != null) {
      entries.add(newestEntry);
    }
  }
  return SyncSnapshot(entries: entries, deletions: deletions);
}

/// Aggregated numbers for a set of entries.
class Stats {
  double spent = 0;
  double volume = 0;
  double distance = 0;
  double _effVolume = 0; // volume only from fill-ups that have a distance
  int fills = 0;

  /// Builds aggregate totals and per-fill efficiency data from the supplied entries.
  Stats.from(Iterable<FuelEntry> entries, Map<String, double> distances) {
    for (final e in entries) {
      fills++;
      spent += e.total;
      volume += e.volume;
      final d = distances[e.id];
      if (d != null) {
        distance += d;
        _effVolume += e.volume;
      }
    }
  }

  /// Returns fuel efficiency when both distance and applicable fill-up volume exist.
  double? get efficiency =>
      (_effVolume > 0 && distance > 0) ? distance / _effVolume : null;
}

/// Groups fuel entries that fall within the same Monday-based week.
class WeekGroup {
  final DateTime weekStart;
  final List<FuelEntry> entries;

  /// Creates a group of entries beginning at the supplied week start.
  WeekGroup(this.weekStart, this.entries);
}

/// Groups fuel entries and weekly subgroups that fall within the same month.
class MonthGroup {
  final DateTime month;
  final List<FuelEntry> entries;
  final List<WeekGroup> weeks;

  /// Creates a month group containing its entries and Monday-based weeks.
  MonthGroup(this.month, this.entries, this.weeks);
}

// ======================= Formatting =======================

final _money = NumberFormat.currency(symbol: kCurrency, decimalDigits: 2);
final _num1 = NumberFormat('#,##0.0');
final _num3 = NumberFormat('#,##0.000');
final _dateFmt = DateFormat.yMMMd();
final _monthFmt = DateFormat.yMMMM();
final _shortDate = DateFormat.MMMd();

/// Formats a distance-per-volume efficiency value, or shows an em dash when unavailable.
String fmtEfficiency(double? v) =>
    v == null ? '—' : '${v.toStringAsFixed(1)} $kDistanceUnit/$kVolumeUnit';
