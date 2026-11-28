/// Main FuelLog page and local-data coordinator.
/// Handles the carousel, fuel entry persistence, import/export, backup, and app actions.
part of '../app.dart';

// ======================= Home =======================

/// Parses the app's exported CSV format into fuel entries.
List<FuelEntry> parseFuelCsv(String source) {
  final rows = _decodeCsv(source);
  if (rows.isEmpty) throw const FormatException('The CSV file is empty.');

  final header = rows.first;
  header[0] = header[0].replaceFirst('\uFEFF', '').trim();
  if (header.length < 4 ||
      header[0] != 'Date' ||
      !header[1].trim().startsWith('Odometer (') ||
      !header[2].trim().startsWith('Price per ') ||
      !header[3].trim().startsWith('Amount (')) {
    throw const FormatException('This is not a FuelLog CSV file.');
  }

  final importedAt = DateTime.now();
  final entries = <FuelEntry>[];
  for (var index = 1; index < rows.length; index++) {
    final row = rows[index];
    if (row.length == 1 && row.first.trim().isEmpty) continue;
    if (row.length != header.length) {
      throw FormatException(
          'Invalid CSV row ${index + 1}: wrong number of columns.');
    }

    try {
      final date = DateTime.parse(row[0].trim());
      final odometer = double.parse(row[1].trim());
      final price = double.parse(row[2].trim());
      final volume = double.parse(row[3].trim());
      if (!odometer.isFinite ||
          !price.isFinite ||
          !volume.isFinite ||
          odometer <= 0 ||
          price <= 0 ||
          volume <= 0) {
        throw const FormatException(
            'Values must be finite and greater than zero.');
      }
      entries.add(
        FuelEntry(
          id: '${importedAt.microsecondsSinceEpoch}_$index',
          date: date,
          price: price,
          volume: volume,
          odometer: odometer,
          updatedAt: importedAt,
        ),
      );
    } on FormatException catch (error) {
      throw FormatException('Invalid CSV row ${index + 1}: ${error.message}');
    }
  }
  return entries;
}

List<List<String>> _decodeCsv(String source) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var afterQuote = false;

  for (var index = 0; index < source.length; index++) {
    final character = source[index];
    if (inQuotes) {
      if (character == '"') {
        if (index + 1 < source.length && source[index + 1] == '"') {
          field.write('"');
          index++;
        } else {
          inQuotes = false;
          afterQuote = true;
        }
      } else {
        field.write(character);
      }
      continue;
    }

    if (character == ',') {
      row.add(field.toString());
      field.clear();
      afterQuote = false;
    } else if (character == '\r' || character == '\n') {
      row.add(field.toString());
      rows.add(row);
      row = <String>[];
      field.clear();
      afterQuote = false;
      if (character == '\r' &&
          index + 1 < source.length &&
          source[index + 1] == '\n') {
        index++;
      }
    } else if (character == '"') {
      if (field.length != 0 || afterQuote) {
        throw const FormatException('Invalid quote in CSV file.');
      }
      inQuotes = true;
    } else {
      if (afterQuote) {
        throw const FormatException(
            'Unexpected character after quoted CSV field.');
      }
      field.write(character);
    }
  }

  if (inQuotes) throw const FormatException('Unclosed quote in CSV file.');
  if (row.isNotEmpty || field.length != 0 || afterQuote) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}

String _csvField(String value) =>
    (value.contains(',') ||
            value.contains('"') ||
            value.contains('\n') ||
            value.contains('\r'))
        ? '"${value.replaceAll('"', '""')}"'
        : value;

Future<String?> _saveCsvFile(String name, Uint8List bytes) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    final sdkInt =
        await _androidNativeChannel.invokeMethod<int>('androidSdkInt');
    if (sdkInt == null) {
      throw StateError('Could not determine the Android version.');
    }
    if (sdkInt < 29) {
      var permission = await Permission.storage.status;
      if (!permission.isGranted) {
        permission = await Permission.storage.request();
      }
      if (!permission.isGranted) {
        throw StateError(permission.isPermanentlyDenied
            ? 'Storage permission is disabled. Enable it in app settings to export CSV.'
            : 'Storage permission is required to export CSV.');
      }
    }
    return await _androidNativeChannel.invokeMethod<String>('saveCsv', {
          'name': name,
          'bytes': bytes,
        }) ??
        (throw StateError('Android did not return the saved file path.'));
  }
  final location = await getSaveLocation(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'CSV files', extensions: ['csv']),
    ],
    suggestedName: name,
  );
  if (location == null) return null;
  await XFile.fromData(bytes, mimeType: 'text/csv', name: name)
      .saveTo(location.path);
  return kIsWeb ? name : location.path;
}

/// Displays the fuel log, totals, CSV export, and Bluetooth sharing entry point.
class HomePage extends StatefulWidget {
  final bool isDarkTheme;
  final VoidCallback? onToggleTheme;
  final Widget? themePaletteMenu;
  final WidgetBuilder? settingsPageBuilder;
  final BluetoothSharePageBuilder? bluetoothSharePageBuilder;
  final bool bluetoothShareEnabled;

  /// Creates the home page.
  const HomePage({
    super.key,
    this.isDarkTheme = true,
    this.onToggleTheme,
    this.themePaletteMenu,
    this.settingsPageBuilder,
    this.bluetoothSharePageBuilder,
    this.bluetoothShareEnabled = true,
  });

  /// Creates the state and connects it to the HomePage widget.
  @override
  State<HomePage> createState() => _HomePageState();
}

enum _HomeMenuAction {
  bluetoothShare,
  loadCsv,
  saveCsv,
  shareCsv,
  about,
  wipeData,
  reports,
}

class _HomeMenuEntry extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HomeMenuEntry({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
}

/// State that loads, edits, calculates, persists, and synchronizes fuel entries.
class _HomePageState extends State<HomePage> {
  static const _prefsKey = 'fuel_entries_v1';
  static const _deletedPrefsKey = 'fuel_entries_deleted_v1';
  static const _soundMutedPrefsKey = 'fuel_save_sound_muted_v1';
  static const _includeLunchPrefsKey = 'fuel_include_lunch_v1';
  static Future<void>? _pendingIncludeLunchSave;
  static const _monthlyDataPrefixes = [
    _monthlyBudgetPrefsKeyPrefix,
    'fuel_income_',
    'fuel_insurance_',
    'fuel_car_payment_',
  ];
  static const _pageNames = ['Log', 'Totals', 'Charts', 'Photos', 'Lunch'];
  static const _pageIcons = [
    Icons.list_alt,
    Icons.bar_chart,
    Icons.pie_chart_outline,
    Icons.photo_library_outlined,
    Icons.lunch_dining,
  ];
  final CarouselSliderController _carouselController =
      CarouselSliderController();
  List<FuelEntry> _entries = [];
  List<_LunchEntry> _lunchEntries = [];
  String? _lunchLoadError;
  bool _includeLunch = false;
  Map<String, DateTime> _deletions = {};
  bool _loaded = false;
  String? _loadError;
  int _currentPage = 0;
  int _dataGeneration = 0;
  GlobalKey<_LunchPageState> _lunchKey = GlobalKey<_LunchPageState>();
  GlobalKey<_ChartsPageState> _chartsKey = GlobalKey<_ChartsPageState>();

  /// Closes settings, shows the page at [page], then runs [action] on it.
  Future<void> _openFromSettings(
    int page,
    Future<void>? Function() action,
  ) async {
    Navigator.of(context).pop();
    await _carouselController.animateToPage(page);
    for (var attempt = 0; attempt < 20; attempt++) {
      if (!mounted) return;
      final pending = action();
      if (pending != null) {
        await pending;
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _SettingsActions(
          onLogBudgetData: () => _openFromSettings(
              2, () => _chartsKey.currentState?._showBudgetDataSheet()),
          onLunchBudget: () =>
              _openFromSettings(4, () => _lunchKey.currentState?._setBudget()),
          child: widget.settingsPageBuilder!(context),
        ),
      ),
    );
  }

  AudioPlayer? _saveSoundPlayer;
  bool _soundMuted = false;
  Future<void> _soundMuteSaveQueue = Future<void>.value();
  Timer? _monthChangeTimer;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _isWindowsOrWeb =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.windows;

  /// Loads persisted entries when the home page initializes.
  @override
  void initState() {
    super.initState();
    _load();
    _scheduleMonthChange();
  }

  @override
  void dispose() {
    _monthChangeTimer?.cancel();
    final player = _saveSoundPlayer;
    if (player != null) unawaited(_disposeSaveSound(player));
    super.dispose();
  }

  void _scheduleMonthChange() {
    final now = DateTime.now();
    final nextMonth = DateTime(now.year, now.month + 1);
    _monthChangeTimer = Timer(nextMonth.difference(now), () {
      if (!mounted) return;
      setState(() {});
      _scheduleMonthChange();
    });
  }

  Future<void> _disposeSaveSound(AudioPlayer player) async {
    try {
      await player.dispose();
    } catch (error, stackTrace) {
      _reportSaveSoundError(error, stackTrace);
    }
  }

  void _reportSaveSoundError(Object error, StackTrace stackTrace) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'FuelLog save sound',
    ));
  }

  Future<void> _playSaveSound() async {
    try {
      final player = _saveSoundPlayer ??= AudioPlayer()
        ..audioCache = AudioCache(prefix: 'lib/assets/sounds/');
      await player.play(AssetSource('coin-drop.wav'));
    } catch (error, stackTrace) {
      _reportSaveSoundError(error, stackTrace);
    }
  }

  void _setSoundMuted(bool muted) {
    _soundMuted = muted;
    _soundMuteSaveQueue = _soundMuteSaveQueue.then(
      (_) => _saveSoundMutedPreference(muted),
    );
  }

  Future<void> _saveSoundMutedPreference(bool muted) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setBool(_soundMutedPrefsKey, muted)) {
        throw StateError('The mute preference was not saved.');
      }
    } catch (error, stackTrace) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'FuelLog mute preference',
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save mute preference: $error'),
          duration: kAppSnackBarDuration,
        ),
      );
    }
  }

  /// Loads active entries and deleted-entry tombstones from shared preferences.
  Future<void> _load() async {
    try {
      await _pendingIncludeLunchSave;
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      _soundMuted = prefs.getBool(_soundMutedPrefsKey) ?? false;
      _includeLunch = prefs.getBool(_includeLunchPrefsKey) ?? false;
      await _pendingLunchEntriesSave;
      if (!mounted) return;
      try {
        _lunchEntries = _readLunchEntries(prefs);
        _lunchLoadError = null;
      } catch (error) {
        _lunchLoadError = error.toString();
      }
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final list = (jsonDecode(raw) as List)
            .map((e) => FuelEntry.fromJson(e as Map<String, dynamic>))
            .toList();
        _entries = list;
      }
      if (!mounted) return;
      final rawDeletions = prefs.getString(_deletedPrefsKey);
      if (rawDeletions != null) {
        _deletions = (jsonDecode(rawDeletions) as Map<String, dynamic>).map(
          (id, value) => MapEntry(id, DateTime.parse(value as String)),
        );
      }
      if (!mounted) return;
      setState(() => _loaded = true);
    } catch (error, stackTrace) {
      if (!mounted) return;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'FuelLog local data loading',
        ),
      );
      setState(() => _loadError = error.toString());
    }
  }

  void _retryLoad() {
    setState(() {
      _loadError = null;
    });
    unawaited(_load());
  }

  Future<void> _retryLunchLoad() async {
    final generation = _dataGeneration;
    try {
      await _pendingLunchEntriesSave;
      final prefs = await SharedPreferences.getInstance();
      final entries = _readLunchEntries(prefs);
      if (!mounted || generation != _dataGeneration) return;
      setState(() {
        _lunchEntries = entries;
        _lunchLoadError = null;
      });
    } catch (error) {
      if (mounted && generation == _dataGeneration) {
        setState(() => _lunchLoadError = error.toString());
      }
    }
  }

  void _setIncludeLunch(bool value) {
    setState(() => _includeLunch = value);
    final previous = _pendingIncludeLunchSave;
    final save = () async {
      if (previous != null) await previous;
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setBool(_includeLunchPrefsKey, value)) {
        throw StateError('Storage did not confirm the save');
      }
    }();
    final pending =
        save.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _pendingIncludeLunchSave = pending;
    unawaited(pending.whenComplete(() {
      if (identical(_pendingIncludeLunchSave, pending)) {
        _pendingIncludeLunchSave = null;
      }
    }));
    unawaited(save.catchError((Object error, StackTrace stackTrace) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'FuelLog lunch inclusion',
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not save lunch inclusion setting: $error'),
          duration: kAppSnackBarDuration,
        ));
      }
    }));
  }

  /// Persists active entries and deleted-entry tombstones to shared preferences.
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final entriesSaved = await prefs.setString(
        _prefsKey, jsonEncode(_entries.map((e) => e.toJson()).toList()));
    final deletionsSaved = await prefs.setString(
      _deletedPrefsKey,
      jsonEncode(
          _deletions.map((id, date) => MapEntry(id, date.toIso8601String()))),
    );
    if (!entriesSaved || !deletionsSaved) {
      throw StateError('The fill-up data could not be saved.');
    }
  }

  /// Entries oldest -> newest (by date, then odometer).
  List<FuelEntry> get _chronological {
    final list = [..._entries];
    list.sort((a, b) {
      final c = a.date.compareTo(b.date);
      return c != 0 ? c : a.odometer.compareTo(b.odometer);
    });
    return list;
  }

  /// Distance driven since the previous fill-up, keyed by entry id.
  Map<String, double> get _distances {
    final map = <String, double>{};
    final sorted = _chronological;
    for (var i = 1; i < sorted.length; i++) {
      final d = sorted[i].odometer - sorted[i - 1].odometer;
      if (d > 0) map[sorted[i].id] = d;
    }
    return map;
  }

  /// Groups chronological entries into reverse-date months and Monday-based weeks.
  List<MonthGroup> get _monthGroups {
    final byMonth = <DateTime, List<FuelEntry>>{};
    for (final e in _chronological) {
      final key = DateTime(e.date.year, e.date.month);
      byMonth.putIfAbsent(key, () => []).add(e);
    }
    final months = byMonth.keys.toList()..sort((a, b) => b.compareTo(a));
    return months.map((m) {
      final entries = byMonth[m]!;
      final byWeek = <DateTime, List<FuelEntry>>{};
      for (final e in entries) {
        // Weeks start on Monday.
        final start = DateTime(
            e.date.year, e.date.month, e.date.day - (e.date.weekday - 1));
        byWeek.putIfAbsent(start, () => []).add(e);
      }
      final weekKeys = byWeek.keys.toList()..sort((a, b) => b.compareTo(a));
      return MonthGroup(
        m,
        entries,
        weekKeys.map((k) => WeekGroup(k, byWeek[k]!)).toList(),
      );
    }).toList();
  }

  /// Opens the add/edit form and persists a new or changed fuel entry.
  Future<void> _openForm([FuelEntry? existing]) async {
    Future<Object?>? browserPermission;
    String? enteredAmount;
    final result = await showModalBottomSheet<FuelEntry>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => EntryForm(
        existing: existing,
        onNewSavePressed: () => unawaited(_playSaveSound()),
        initialSoundMuted: _soundMuted,
        onSoundMutedChanged: _setSoundMuted,
        onValidatedSavePressed: (amount) {
          enteredAmount = amount;
          if (kIsWeb) {
            browserPermission = FuelLogNotifications.requestBrowserPermission();
          }
        },
        lastOdometer:
            _chronological.isEmpty ? null : _chronological.last.odometer,
        onDelete: existing == null
            ? null
            : () async {
                Navigator.of(sheetContext).pop();
                await _delete(existing);
              },
      ),
    );
    if (result == null) return;
    setState(() {
      if (existing != null) {
        _entries[_entries.indexWhere((e) => e.id == existing.id)] = result;
        _deletions.remove(result.id);
      } else {
        _entries.add(result);
      }
    });
    try {
      await _save();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save fill-up: $error'),
          duration: kAppSnackBarDuration,
        ),
      );
      return;
    }
    if (_isAndroid || _isWindowsOrWeb) {
      try {
        if (browserPermission != null) {
          final permissionError = await browserPermission;
          if (permissionError != null) throw permissionError;
        }
        final amount = enteredAmount;
        if (amount == null) {
          throw StateError('The saved fill-up amount was not provided.');
        }
        await FuelLogNotifications.showCustomChart(_entries, result, amount);
      } catch (error) {
        if (!mounted) return;
        FuelLogNotifications.reportFailure(context, error);
      }
    }
  }

  /// Opens the About sheet with the bundled README content.
  Future<void> _showAbout() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const AboutSheet(),
    );
  }

  /// Confirms and permanently removes saved app data and pump photos.
  Future<void> _confirmWipeData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Wipe all data?'),
        content: const Text(
          'This permanently deletes all fill-ups, monthly budget data, '
          'generated reports, and saved pump photos. Fill-ups can only be '
          'restored from a backup CSV. Monthly budget data, generated reports, '
          'and pump photos are not included in CSV backups and cannot be '
          'restored. Lunch entries and the restaurant list can be restored '
          'from their separate CSV backups; the lunch budget and chart '
          'selections cannot.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Wipe data'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      if (!kIsWeb && Platform.isAndroid) {
        final sdkInt =
            await _androidNativeChannel.invokeMethod<int>('androidSdkInt');
        if (sdkInt == null) {
          throw StateError('Could not determine the Android version.');
        }
        if (sdkInt < 29) {
          var permission = await Permission.storage.status;
          if (!permission.isGranted) {
            permission = await Permission.storage.request();
          }
          if (!mounted) return;
          if (!permission.isGranted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Storage permission is required to wipe data.'),
                duration: kAppSnackBarDuration,
              ),
            );
            return;
          }
        }
        final deletedPhotoCount = await _androidNativeChannel
            .invokeMethod<int>('deleteAllPumpPhotos');
        if (deletedPhotoCount == null) {
          throw StateError('Android did not confirm pump photo deletion.');
        }
        final deletedReportCount = await _androidNativeChannel
            .invokeMethod<int>('deleteAllTextReports');
        if (deletedReportCount == null) {
          throw StateError('Android did not confirm report deletion.');
        }
        await FuelLogNotifications.cancel();
        await _LunchNotification.cancel();
      }

      Object? notificationError;
      if (_isWindowsOrWeb) {
        try {
          await FuelLogNotifications.cancel();
        } catch (error) {
          notificationError = error;
        }
        try {
          await _LunchNotification.cancel();
        } catch (error) {
          notificationError ??= error;
        }
      }
      await _pendingLunchChartSave;
      await _pendingLunchEntriesSave;
      await _pendingRestaurantSave;
      final prefs = await SharedPreferences.getInstance();
      if (!kIsWeb && (prefs.getBool(_restaurantFileKey) ?? false)) {
        final file = await _restaurantFile();
        if (await file.exists()) await file.delete();
      }
      final keysToRemove = prefs.getKeys().where((key) {
        return key == _prefsKey ||
            key == _deletedPrefsKey ||
            key == _savedReportsPreferencesKey ||
            key == _lunchEntriesKey ||
            key == _lunchBudgetKey ||
            key == _lunchChartSelectionKey ||
            key == _restaurantCsvKey ||
            key == _restaurantFileKey ||
            _monthlyDataPrefixes.any(key.startsWith);
      }).toList();
      for (final key in keysToRemove) {
        if (!await prefs.remove(key)) {
          throw StateError('Could not remove saved data: $key');
        }
      }
      if (!mounted) return;
      setState(() {
        _entries = [];
        _lunchEntries = [];
        _lunchLoadError = null;
        _deletions = {};
        _dataGeneration++;
        _lunchKey = GlobalKey<_LunchPageState>();
        _chartsKey = GlobalKey<_ChartsPageState>();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(notificationError == null
              ? 'App data wiped.'
              : 'App data wiped, but notification could not be removed: '
                  '$notificationError'),
          duration: kAppSnackBarDuration,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not wipe all app data: $error'),
          duration: kAppSnackBarDuration,
        ),
      );
    }
  }

  /// Deletes an entry, records its tombstone, and offers an undo action.
  Future<void> _delete(FuelEntry entry) async {
    final index = _entries.indexWhere((e) => e.id == entry.id);
    setState(() {
      _entries.removeAt(index);
      _deletions[entry.id] = DateTime.now();
    });
    await _save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Entry deleted'),
        duration: kAppSnackBarDuration,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            setState(() {
              _entries.insert(index, entry);
              _deletions.remove(entry.id);
            });
            await _save();
          },
        ),
      ),
    );
  }

  /// Builds the swipeable app sections.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedPageColor = colorScheme.brightness == Brightness.dark
        ? colorScheme.primary
        : colorScheme.onSurface;
    final now = DateTime.now();
    bool isCurrentMonth(DateTime date) =>
        date.year == now.year && date.month == now.month;
    final monthFuel = _entries
        .where((entry) => isCurrentMonth(entry.date))
        .fold<double>(0, (total, entry) => total + entry.total);
    final monthLunch = _includeLunch
        ? _lunchTotal(
            _lunchEntries.where((entry) => isCurrentMonth(entry.date)))
        : 0.0;
    final monthSpent = _includeLunch && _lunchLoadError != null
        ? 'Unavailable'
        : _money.format(monthFuel + monthLunch);
    final appBarColor =
        theme.appBarTheme.backgroundColor ?? colorScheme.surface;
    final monthTextColor =
        ThemeData.estimateBrightnessForColor(appBarColor) == Brightness.dark
            ? Colors.white
            : Colors.black;
    final narrowAppBar = MediaQuery.sizeOf(context).width < 480;
    final appBarTitle = Text(
      MediaQuery.sizeOf(context).width < 400 &&
              widget.settingsPageBuilder != null
          ? 'FuelLog'
          : 'Fuel Fill-ups Log',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    );
    return Scaffold(
      backgroundColor: _loaded ? null : Colors.white,
      appBar: _loaded
          ? AppBar(
              centerTitle: true,
              leadingWidth: 120,
              leading: Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: PopupMenuButton<_HomeMenuAction>(
                      tooltip: 'App menu',
                      icon: const Icon(Icons.menu),
                      style: IconButton.styleFrom(
                        side: BorderSide(color: colorScheme.secondary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onSelected: (action) {
                        switch (action) {
                          case _HomeMenuAction.bluetoothShare:
                            _openBluetoothShare();
                            break;
                          case _HomeMenuAction.loadCsv:
                            unawaited(_importCsv());
                            break;
                          case _HomeMenuAction.saveCsv:
                            unawaited(_exportCsv());
                            break;
                          case _HomeMenuAction.shareCsv:
                            unawaited(_shareCsvBackup());
                            break;
                          case _HomeMenuAction.about:
                            unawaited(_showAbout());
                            break;
                          case _HomeMenuAction.wipeData:
                            unawaited(_confirmWipeData());
                            break;
                          case _HomeMenuAction.reports:
                            _openReports();
                            break;
                        }
                      },
                      itemBuilder: (context) =>
                          <PopupMenuItem<_HomeMenuAction>>[
                        if (!kIsWeb && widget.bluetoothSharePageBuilder != null)
                          PopupMenuItem(
                            enabled: widget.bluetoothShareEnabled,
                            value: _HomeMenuAction.bluetoothShare,
                            child: const _HomeMenuEntry(
                              icon: Icons.bluetooth,
                              label: 'Bluetooth Share',
                            ),
                          ),
                        const PopupMenuItem(
                          value: _HomeMenuAction.reports,
                          child: _HomeMenuEntry(
                            icon: Icons.picture_as_pdf_outlined,
                            label: 'Reports',
                          ),
                        ),
                        const PopupMenuItem(
                          value: _HomeMenuAction.loadCsv,
                          child: _HomeMenuEntry(
                            icon: Icons.file_upload_outlined,
                            label: 'Load CSV',
                          ),
                        ),
                        const PopupMenuItem(
                          value: _HomeMenuAction.saveCsv,
                          child: _HomeMenuEntry(
                            icon: Icons.file_download_outlined,
                            label: 'Save CSV',
                          ),
                        ),
                        const PopupMenuItem(
                          value: _HomeMenuAction.shareCsv,
                          child: _HomeMenuEntry(
                            icon: Icons.cloud_upload_outlined,
                            label: 'Share CSV backup',
                          ),
                        ),
                        const PopupMenuItem(
                          value: _HomeMenuAction.about,
                          child: _HomeMenuEntry(
                            icon: Icons.info_outline,
                            label: 'About',
                          ),
                        ),
                        const PopupMenuItem(
                          value: _HomeMenuAction.wipeData,
                          child: _HomeMenuEntry(
                            icon: Icons.delete_forever_outlined,
                            label: 'Wipe Data',
                          ),
                        ),
                      ]
                              .map(
                                  (item) => _OutlinedPopupMenuEntry(item: item))
                              .toList(),
                    ),
                  ),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'This month\n$monthSpent',
                        key: const ValueKey('app-bar-month-spent'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: monthTextColor,
                          fontFamily: 'Oswald',
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              title: narrowAppBar ? null : appBarTitle,
              bottom: narrowAppBar
                  ? PreferredSize(
                      preferredSize: Size.fromHeight(
                        MediaQuery.textScalerOf(context).scale(18) + 10,
                      ),
                      child: Center(child: appBarTitle),
                    )
                  : null,
              actions: [
                if (widget.settingsPageBuilder != null)
                  IconButton(
                    tooltip: 'Settings',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: _openSettings,
                  ),
                IconButton(
                  tooltip: widget.isDarkTheme
                      ? 'Switch to light theme'
                      : 'Switch to dark theme',
                  icon: Icon(
                    widget.isDarkTheme ? Icons.light_mode : Icons.dark_mode,
                  ),
                  onPressed: widget.onToggleTheme,
                ),
                if (widget.themePaletteMenu != null) widget.themePaletteMenu!,
                IconButton(
                  tooltip: 'Reports',
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  onPressed: () => _openReports(),
                ),
              ],
            )
          : null,
      floatingActionButton: _loaded
          ? Padding(
              padding: const EdgeInsets.only(bottom: 50),
              child: FloatingActionButton.extended(
                onPressed: _currentPage == 4
                    ? () {
                        final lunch = _lunchKey.currentState;
                        if (lunch != null) {
                          lunch._openEntry();
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Lunch is still loading.')),
                          );
                        }
                      }
                    : () => _openForm(),
                icon: const Icon(Icons.add),
                label: Text(_currentPage == 4 ? 'Add lunch' : 'Fill-up'),
              ))
          : null,
      body: !_loaded
          ? _StartupLoadingScreen(
              error: _loadError,
              onRetry: _retryLoad,
            )
          : Column(
              children: [
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Previous page',
                          onPressed: _currentPage > 0
                              ? () => _carouselController.previousPage()
                              : null,
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              for (var index = 0;
                                  index < _pageNames.length;
                                  index++)
                                Expanded(
                                  child: Semantics(
                                    button: true,
                                    selected: index == _currentPage,
                                    label: '${_pageNames[index]} page',
                                    child: InkWell(
                                      onTap: () => unawaited(
                                        _carouselController.animateToPage(
                                          index,
                                        ),
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                          horizontal: 2,
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              _pageIcons[index],
                                              color: index == _currentPage
                                                  ? selectedPageColor
                                                  : colorScheme
                                                      .onSurfaceVariant,
                                            ),
                                            const SizedBox(height: 2),
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(
                                                _pageNames[index],
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color: index ==
                                                              _currentPage
                                                          ? selectedPageColor
                                                          : colorScheme
                                                              .onSurfaceVariant,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Next page',
                          onPressed: _currentPage < _pageNames.length - 1
                              ? () => _carouselController.nextPage()
                              : null,
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return CarouselSlider.builder(
                        key: const ValueKey('fuel-log-carousel'),
                        carouselController: _carouselController,
                        itemCount: _pageNames.length,
                        itemBuilder: (context, index, pageIndex) {
                          final generation = _dataGeneration;
                          final page = switch (index) {
                            0 => _buildLog(),
                            1 => _buildSummary(),
                            2 => ChartsPage._withLunch(
                                key: _chartsKey,
                                entries: _entries,
                                distances: _distances,
                                includeLunch: _includeLunch,
                                lunchEntries: _lunchEntries,
                                lunchLoadError: _lunchLoadError,
                                onRetryLunch: _retryLunchLoad,
                                onIncludeLunchChanged: _setIncludeLunch,
                              ),
                            3 => PumpPhotosPage(
                                key: ValueKey('photos-$_dataGeneration'),
                                isActive: index == _currentPage,
                              ),
                            _ => LunchPage._withUpdates(
                                key: _lunchKey,
                                onEntriesChanged: (entries) {
                                  if (!mounted ||
                                      generation != _dataGeneration) {
                                    return;
                                  }
                                  setState(() {
                                    _lunchEntries = entries;
                                    _lunchLoadError = null;
                                  });
                                },
                              ),
                          };
                          return SizedBox(
                            width: constraints.maxWidth,
                            child: index == 4
                                ? page
                                : _StaggeredPage(
                                    key: ValueKey(
                                        'reveal-$index-$_dataGeneration'),
                                    active: index == _currentPage,
                                    count: switch (index) {
                                      0 => math.max(1, _entries.length),
                                      1 => _summaryRevealCount,
                                      2 =>
                                        _includeLunch && _lunchLoadError != null
                                            ? 2
                                            : 5,
                                      _ => 3,
                                    },
                                    child: page,
                                  ),
                          );
                        },
                        options: CarouselOptions(
                          height: constraints.maxHeight,
                          initialPage: 0,
                          viewportFraction: 1,
                          enableInfiniteScroll: false,
                          onPageChanged: (index, _) {
                            setState(() => _currentPage = index);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  /// Merges a received snapshot, saves the result, and reports the final entry count.
  Future<int> _mergeReceivedSnapshot(SyncSnapshot remote) async {
    final merged = mergeSnapshots(
      SyncSnapshot(entries: _entries, deletions: _deletions),
      remote,
    );
    setState(() {
      _entries = merged.entries;
      _deletions = merged.deletions;
    });
    await _save();
    return _entries.length;
  }

  // ---------------- CSV export ----------------

  void _openBluetoothShare() {
    final pageBuilder = widget.bluetoothSharePageBuilder;
    if (pageBuilder == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => pageBuilder(
          () => SyncSnapshot(
            entries: List.of(_entries),
            deletions: Map.of(_deletions),
          ),
          _mergeReceivedSnapshot,
        ),
      ),
    );
  }

  void _openReports() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportsPage(
          entries: List.of(_entries),
          distances: Map.of(_distances),
        ),
      ),
    );
  }

  /// Opens a CSV file and replaces all active entries after confirmation.
  Future<void> _importCsv() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'CSV files', extensions: ['csv']),
        ],
      );
      if (file == null) return;

      final entries = parseFuelCsv(await file.readAsString());
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Replace current data?'),
          content: Text(
            'This will replace all current fill-ups with ${entries.length} '
            'fill-up${entries.length == 1 ? '' : 's'} from ${file.name}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      setState(() {
        _entries = entries;
        _deletions = {};
      });
      await _save();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Loaded ${entries.length} fill-ups from ${file.name}'),
          duration: kAppSnackBarDuration,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load CSV: $error'),
          duration: kAppSnackBarDuration,
        ),
      );
    }
  }

  /// Formats a decimal value without unnecessary trailing zeros.
  String _plain(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  ({String name, Uint8List bytes}) _createCsvExport() {
    final distances = _distances;
    final df = DateFormat('yyyy-MM-dd');
    final rows = <List<String>>[
      [
        'Date',
        'Odometer ($kDistanceUnit)',
        'Price per $kVolumeUnit',
        'Amount ($kVolumeUnit)',
        'Total cost',
        'Distance since last ($kDistanceUnit)',
        'Efficiency ($kDistanceUnit/$kVolumeUnit)',
      ],
    ];
    for (final entry in _chronological) {
      final distance = distances[entry.id];
      rows.add([
        df.format(entry.date),
        _plain(entry.odometer),
        entry.price.toStringAsFixed(3),
        entry.volume.toStringAsFixed(3),
        entry.total.toStringAsFixed(2),
        distance != null ? _plain(distance) : '',
        distance != null ? (distance / entry.volume).toStringAsFixed(2) : '',
      ]);
    }
    final csv = rows.map((row) => row.map(_csvField).join(',')).join('\r\n');
    final name = 'fuel_log_${df.format(DateTime.now())}.csv';
    return (name: name, bytes: Uint8List.fromList(utf8.encode(csv)));
  }

  /// Exports the chronological fuel log as a CSV file.
  Future<void> _exportCsv() async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      final export = _createCsvExport();
      final savedLocation = await _saveCsvFile(export.name, export.bytes);
      if (savedLocation == null) return;

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('CSV saved to $savedLocation'),
          duration: kAppSnackBarDuration,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not export CSV: $e'),
          duration: kAppSnackBarDuration,
        ),
      );
    }
  }

  Future<void> _shareCsvBackup() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_isWindowsOrWeb) {
      await _exportCsv();
      return;
    }
    if (!_isAndroid) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('CSV backup sharing is available on Android.'),
          duration: kAppSnackBarDuration,
        ),
      );
      return;
    }

    try {
      final export = _createCsvExport();
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              export.bytes,
              mimeType: 'text/csv',
              name: export.name,
            ),
          ],
          fileNameOverrides: [export.name],
          subject: 'FuelLog CSV backup',
          text: 'Choose Google Drive to save a backup of your FuelLog data.',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not share CSV backup: $error'),
          duration: kAppSnackBarDuration,
        ),
      );
    }
  }

  // ---------------- Log tab ----------------

  /// Builds the newest-first fill-up list for the Log tab.
  Widget _buildLog() {
    if (_entries.isEmpty) {
      return const _PageReveal(
        key: ValueKey('reveal-log-empty'),
        index: 0,
        child: _EmptyState(),
      );
    }
    final distances = _distances;
    final list = _chronological.reversed.toList();
    final odometerCounts = <double, int>{};
    for (final entry in _entries) {
      odometerCounts.update(entry.odometer, (count) => count + 1,
          ifAbsent: () => 1);
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final e = list[i];
        final dist = distances[e.id];
        final eff = dist != null ? dist / e.volume : null;
        return _PageReveal(
          key: ValueKey('reveal-${e.id}'),
          index: i,
          child: Dismissible(
            key: ValueKey(e.id),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Theme.of(context).colorScheme.errorContainer,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24),
              child: Icon(Icons.delete,
                  color: Theme.of(context).colorScheme.onErrorContainer),
            ),
            onDismissed: (_) => _delete(e),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Theme.of(context).colorScheme.secondary
                    : Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(13),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    onTap: () => _openForm(e),
                    title: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${_dateFmt.format(e.date)}  ·  ${_money.format(e.total)}',
                        ),
                        if (odometerCounts[e.odometer]! > 1)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.shade700,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'DUPLICATE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Text(
                      '${_num1.format(e.odometer)} $kDistanceUnit odometer\n'
                      '${_num3.format(e.volume)} $kVolumeUnit @ ${_money.format(e.price)}/$kVolumeUnit'
                      '${dist != null ? '\n${_num1.format(dist)} $kDistanceUnit since last  ·  ${fmtEfficiency(eff)}' : ''}',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.edit_outlined, size: 18),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------- Totals tab ----------------

  int get _summaryRevealCount {
    if (_includeLunch && _lunchLoadError != null) return 2;
    if (_entries.isEmpty && (!_includeLunch || _lunchEntries.isEmpty)) return 2;
    final months = {
      for (final month in _monthGroups) month.month,
      if (_includeLunch)
        for (final entry in _lunchEntries)
          DateTime(entry.date.year, entry.date.month),
    };
    return months.length + 2;
  }

  /// Builds overall, monthly, and weekly fuel statistics.
  Widget _buildSummary() {
    final control = _LunchInclusionControl(
      key: const ValueKey('include-lunch-totals'),
      included: _includeLunch,
      onChanged: _setIncludeLunch,
    );
    if (_includeLunch && _lunchLoadError != null) {
      return ListView(
        key: const ValueKey('totals-scroll'),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          _PageReveal(
            index: 0,
            child: _LunchDataError(
                error: _lunchLoadError!, onRetry: _retryLunchLoad),
          ),
          const SizedBox(height: 16),
          _PageReveal(index: 1, child: control),
        ],
      );
    }
    if (_entries.isEmpty && (!_includeLunch || _lunchEntries.isEmpty)) {
      return ListView(
        key: const ValueKey('totals-scroll'),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          const _PageReveal(
            key: ValueKey('reveal-totals-empty'),
            index: 0,
            child: _EmptyState(),
          ),
          _PageReveal(
            key: const ValueKey('reveal-totals-control'),
            index: 1,
            child: control,
          ),
        ],
      );
    }
    final distances = _distances;
    final months = _monthGroups;
    final overall = Stats.from(_entries, distances);

    if (_includeLunch) {
      final byMonth = {for (final month in months) month.month: month};
      final monthKeys = {
        ...byMonth.keys,
        for (final entry in _lunchEntries)
          DateTime(entry.date.year, entry.date.month),
      }.toList()
        ..sort((a, b) => b.compareTo(a));
      return ListView(
        key: const ValueKey('totals-scroll'),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          _PageReveal(
            key: const ValueKey('reveal-totals-all'),
            index: 0,
            child: Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('All time',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    _StatsWrap(
                        stats: overall, lunchSpent: _lunchTotal(_lunchEntries)),
                  ],
                ),
              ),
            ),
          ),
          for (var i = 0; i < monthKeys.length; i++)
            _PageReveal(
              key: ValueKey('reveal-totals-month-$i'),
              index: i + 1,
              child: _buildCombinedMonth(
                  monthKeys[i], byMonth[monthKeys[i]], distances, i == 0),
            ),
          const SizedBox(height: 16),
          _PageReveal(
            key: const ValueKey('reveal-totals-control'),
            index: monthKeys.length + 1,
            child: control,
          ),
        ],
      );
    }

    return ListView(
      key: const ValueKey('totals-scroll'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        _PageReveal(
          key: const ValueKey('reveal-totals-all'),
          index: 0,
          child: Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('All time',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _StatsWrap(stats: overall),
                ],
              ),
            ),
          ),
        ),
        for (var i = 0; i < months.length; i++)
          _PageReveal(
            key: ValueKey('reveal-totals-month-$i'),
            index: i + 1,
            child: Card(
              color: Theme.of(context).colorScheme.surface,
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                initiallyExpanded: i == 0,
                shape: const Border(),
                collapsedShape: const Border(),
                title: Text(_monthFmt.format(months[i].month),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                    '${_money.format(Stats.from(months[i].entries, distances).spent)}  ·  '
                    '${months[i].entries.length} fill-up${months[i].entries.length == 1 ? '' : 's'}'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Monthly total',
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 6),
                  _StatsWrap(stats: Stats.from(months[i].entries, distances)),
                  const SizedBox(height: 16),
                  Text('By week',
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  for (final w in months[i].weeks)
                    _WeekRow(week: w, stats: Stats.from(w.entries, distances)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        _PageReveal(
          key: const ValueKey('reveal-totals-control'),
          index: months.length + 1,
          child: control,
        ),
      ],
    );
  }

  Widget _buildCombinedMonth(
    DateTime month,
    MonthGroup? fuel,
    Map<String, double> distances,
    bool expanded,
  ) {
    final lunch = _lunchEntries
        .where((entry) =>
            entry.date.year == month.year && entry.date.month == month.month)
        .toList();
    final fuelEntries = fuel?.entries ?? <FuelEntry>[];
    final stats = Stats.from(fuelEntries, distances);
    final lunchTotal = _lunchTotal(lunch);
    final weeks = {
      for (final week in fuel?.weeks ?? <WeekGroup>[]) week.weekStart: week
    };
    final weekKeys = {
      ...weeks.keys,
      for (final entry in lunch) _lunchWeek(entry.date),
    }.toList()
      ..sort((a, b) => b.compareTo(a));
    return Card(
      color: Theme.of(context).colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: expanded,
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(_monthFmt.format(month),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${_money.format(stats.spent + lunchTotal)}  ·  '
            '${fuelEntries.length} fill-up${fuelEntries.length == 1 ? '' : 's'}'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Monthly total', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          _StatsWrap(stats: stats, lunchSpent: lunchTotal),
          const SizedBox(height: 16),
          Text('By week', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          for (final start in weekKeys)
            _WeekRow(
              week: weeks[start] ?? WeekGroup(start, []),
              stats:
                  Stats.from(weeks[start]?.entries ?? <FuelEntry>[], distances),
              lunchSpent: _lunchTotal(
                  lunch.where((entry) => _lunchWeek(entry.date) == start)),
            ),
        ],
      ),
    );
  }
}
