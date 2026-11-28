// Application shell and core data model for FuelLog.
// Defines startup configuration, themes, units, fuel and sync models, and shared formatting.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:animated_background/animated_background.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart' hide XFile;
import 'package:url_launcher/url_launcher.dart';
import 'widgets/folder_picker_stub.dart'
    if (dart.library.js_interop) 'widgets/folder_picker_web.dart'
    as folder_picker;
import 'widgets/notify_web_stub.dart'
    if (dart.library.js_interop) 'widgets/notify_web.dart'
    as browser_notifications;

part 'pages/home_page.dart';
part 'pages/settings_page.dart';
part 'pages/lunch_page.dart';
part 'pages/charts_page.dart';
part 'custom_chart.dart';
part 'widgets/shared_widgets.dart';
part 'widgets/app_background.dart';
part 'widgets/page_shimmer.dart';
part 'widgets/entry_form.dart';
part 'widgets/lunch_entry_form.dart';
part 'widgets/mute_sound_control.dart';
part 'widgets/notify.dart';
part 'widgets/lunch_notification.dart';
part 'pages/pump_photos.dart';
part 'widgets/about.dart';
part 'widgets/download_platforms.dart';
part 'pages/reports.dart';
part 'styles/stylekit.dart';

const MethodChannel fuelLogNativeChannel =
    MethodChannel('io.github.tlaw22.fuellog/native');
const MethodChannel _androidNativeChannel = fuelLogNativeChannel;
const String _monthlyBudgetPrefsKeyPrefix = 'fuel_monthly_budget_';
const String _photoFolderPrefsKey = 'photo_folder';
const String _launchCountPrefsKey = 'app_launch_count';
const Duration kAppSnackBarDuration = Duration(seconds: 10);

String _monthlyValueKey(String name, DateTime month) =>
    'fuel_${name}_${month.year}_${month.month}';

double _travelExpense(double fuel, double insurance, double carPayment) =>
    fuel + insurance + carPayment;

typedef BluetoothSharePageBuilder = Widget Function(
  SyncSnapshot Function() snapshot,
  Future<int> Function(SyncSnapshot snapshot) onSnapshotReceived,
);

// ---- Change these to switch units (e.g. 'L' and 'km', and '€') ----
const String kVolumeUnit = 'gal';
const String kDistanceUnit = 'mi';
const String kCurrency = '\$';
// --------------------------------------------------------------------

/// Root widget that configures the app's title, theme, and home page.
class FuelLogApp extends StatefulWidget {
  final BluetoothSharePageBuilder? bluetoothSharePageBuilder;
  final bool bluetoothShareEnabled;

  /// Creates the root application widget.
  const FuelLogApp({
    super.key,
    this.bluetoothSharePageBuilder,
    this.bluetoothShareEnabled = true,
  });

  @override
  State<FuelLogApp> createState() => _FuelLogAppState();
}

class _FuelLogAppState extends State<FuelLogApp> with _ThemeSettings {
  int? _launchCount;

  @override
  void initState() {
    super.initState();
    _loadThemePreferences();
    _recordLaunch();
  }

  Future<void> _recordLaunch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = (prefs.getInt(_launchCountPrefsKey) ?? 0) + 1;
      await prefs.setInt(_launchCountPrefsKey, count);
      if (mounted) setState(() => _launchCount = count);
    } catch (_) {}
  }

  /// Builds the root Material application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FuelLog',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      theme: buildTheme(isDark: _isDarkTheme, palette: _currentPalette),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: _fontSizePercent == 100
                ? media.textScaler
                : _AppTextScaler(media.textScaler, _fontSizePercent / 100),
          ),
          child: _AppBackground(
            bubblesEnabled: _bubblesEnabled,
            child: child!,
          ),
        );
      },
      home: HomePage(
        isDarkTheme: _isDarkTheme,
        onToggleTheme: _toggleTheme,
        settingsPageBuilder: (context) => _SettingsPage(
          isDarkTheme: () => _isDarkTheme,
          selectedPalette: () => _currentPalette,
          fontSizePercent: () => _fontSizePercent,
          bubblesEnabled: () => _bubblesEnabled,
          launchCount: () => _launchCount,
          onToggleTheme: _toggleTheme,
          onSelectPalette: _selectPalette,
          onSetFontSize: _setFontSize,
          onSetBubblesEnabled: _setBubblesEnabled,
        ),
        themePaletteMenu: _ThemePaletteMenu(
          isDark: _isDarkTheme,
          selected: _currentPalette,
          onSelected: _selectPalette,
        ),
        bluetoothSharePageBuilder: widget.bluetoothSharePageBuilder,
        bluetoothShareEnabled: widget.bluetoothShareEnabled,
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

  /// Converts active entries and deletions into Bluetooth-share records.
  List<Map<String, dynamic>> toRecords() => [
        for (final entry in entries) {'kind': 'entry', 'entry': entry.toJson()},
        for (final deletion in deletions.entries)
          {
            'kind': 'delete',
            'id': deletion.key,
            'deletedAt': deletion.value.toIso8601String(),
          },
      ];

  /// Reconstructs a snapshot from Bluetooth-share records.
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
            final aTieBreaker =
                '${a.date.microsecondsSinceEpoch}|${a.odometer}|${a.price}|${a.volume}';
            final bTieBreaker =
                '${b.date.microsecondsSinceEpoch}|${b.odometer}|${b.price}|${b.volume}';
            return aTieBreaker.compareTo(bTieBreaker) >= 0 ? a : b;
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
