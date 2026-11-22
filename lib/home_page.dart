part of 'main.dart';

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

/// Displays the fuel log, totals, CSV export, and nearby sync entry points.
class HomePage extends StatefulWidget {
  final bool isDarkTheme;
  final VoidCallback? onToggleTheme;

  /// Creates the home page.
  const HomePage({
    super.key,
    this.isDarkTheme = true,
    this.onToggleTheme,
  });

  /// Creates the state and connects it to the HomePage widget.
  @override
  State<HomePage> createState() => _HomePageState();
}

enum _HomeMenuAction { loadCsv, saveCsv, shareCsv, about, wipeData }

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
  static const _monthlyDataPrefixes = [
    _monthlyBudgetPrefsKeyPrefix,
    'fuel_income_',
    'fuel_insurance_',
    'fuel_car_payment_',
  ];
  static const _pageNames = ['Log', 'Totals', 'Graphs', 'Photos'];
  static const _pageIcons = [
    Icons.list_alt,
    Icons.bar_chart,
    Icons.pie_chart_outline,
    Icons.photo_library_outlined,
  ];
  final CarouselSliderController _carouselController =
      CarouselSliderController();
  List<FuelEntry> _entries = [];
  Map<String, DateTime> _deletions = {};
  bool _loaded = false;
  double _loadingProgress = 0;
  String? _loadError;
  int _currentPage = 0;
  int _dataGeneration = 0;

  /// Loads persisted entries after the first frame of the home page.
  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Loads active entries and deleted-entry tombstones from shared preferences.
  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() => _loadingProgress = 0.25);

      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final list = (jsonDecode(raw) as List)
            .map((e) => FuelEntry.fromJson(e as Map<String, dynamic>))
            .toList();
        _entries = list;
      }
      if (!mounted) return;
      setState(() => _loadingProgress = 0.7);

      final rawDeletions = prefs.getString(_deletedPrefsKey);
      if (rawDeletions != null) {
        _deletions = (jsonDecode(rawDeletions) as Map<String, dynamic>).map(
          (id, value) => MapEntry(id, DateTime.parse(value as String)),
        );
      }
      if (!mounted) return;
      setState(() {
        _loadingProgress = 1;
        _loaded = true;
      });
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
      _loadingProgress = 0;
    });
    unawaited(_load());
  }

  /// Persists active entries and deleted-entry tombstones to shared preferences.
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefsKey, jsonEncode(_entries.map((e) => e.toJson()).toList()));
    await prefs.setString(
      _deletedPrefsKey,
      jsonEncode(
          _deletions.map((id, date) => MapEntry(id, date.toIso8601String()))),
    );
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
    final result = await showModalBottomSheet<FuelEntry>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => EntryForm(
        existing: existing,
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
    await _save();
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
          'This permanently deletes all fill-ups, monthly budget data, and '
          'saved pump photos. Fill-ups can only be restored from a backup '
          'CSV. Monthly budget data and pump photos are not included in CSV '
          'backups and cannot be restored.',
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
      if (Platform.isAndroid) {
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
      }

      final prefs = await SharedPreferences.getInstance();
      final keysToRemove = prefs.getKeys().where((key) {
        return key == _prefsKey ||
            key == _deletedPrefsKey ||
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
        _deletions = {};
        _dataGeneration++;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('App data wiped.'),
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

  /// Builds the swipeable Log, Totals, and Graphs carousel.
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedPageColor = colorScheme.brightness == Brightness.dark
        ? colorScheme.primary
        : colorScheme.onSurface;
    return Scaffold(
      backgroundColor: _loaded ? null : Colors.white,
      appBar: _loaded
          ? AppBar(
              centerTitle: true,
              leading: PopupMenuButton<_HomeMenuAction>(
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
                  }
                },
                itemBuilder: (context) => [
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
                ],
              ),
              title: const Text(
                'Fuel Fill-ups Log',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              actions: [
                IconButton(
                  tooltip: widget.isDarkTheme
                      ? 'Switch to light theme'
                      : 'Switch to dark theme',
                  icon: Icon(
                    widget.isDarkTheme ? Icons.light_mode : Icons.dark_mode,
                  ),
                  onPressed: widget.onToggleTheme,
                ),
                IconButton(
                  tooltip: 'Sync nearby',
                  icon: const Icon(Icons.sync),
                  onPressed: _loaded
                      ? () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => NearbySyncPage(
                                snapshot: () => SyncSnapshot(
                                  entries: List.of(_entries),
                                  deletions: Map.of(_deletions),
                                ),
                                onSnapshotReceived: _mergeReceivedSnapshot,
                              ),
                            ),
                          )
                      : null,
                ),
              ],
            )
          : null,
      floatingActionButton: _loaded
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add),
              label: const Text('Fill-up'),
            )
          : null,
      body: !_loaded
          ? _StartupLoadingScreen(
              progress: _loadingProgress,
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
                                            Text(
                                              _pageNames[index],
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(
                                                    color: index == _currentPage
                                                        ? selectedPageColor
                                                        : colorScheme
                                                            .onSurfaceVariant,
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
                          final page = switch (index) {
                            0 => _buildLog(),
                            1 => _buildSummary(),
                            2 => GraphicsPage(
                                key: ValueKey('graphs-$_dataGeneration'),
                                entries: _entries,
                                distances: _distances,
                              ),
                            _ => PumpPhotosPage(
                                key: ValueKey('photos-$_dataGeneration'),
                                isActive: index == _currentPage,
                              ),
                          };
                          return SizedBox(
                            width: constraints.maxWidth,
                            child: page,
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

  Widget _buildCsvActions() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _exportCsv,
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('Export CSV'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: _importCsv,
                icon: const Icon(Icons.file_upload_outlined),
                label: const Text('Load CSV'),
              ),
            ),
          ],
        ),
      );

  /// Escapes a CSV field that contains commas, quotes, or line breaks.
  String _csvField(String v) =>
      (v.contains(',') || v.contains('"') || v.contains('\n'))
          ? '"${v.replaceAll('"', '""')}"'
          : v;

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
      final name = export.name;
      final bytes = export.bytes;
      late final String savedLocation;

      if (Platform.isAndroid) {
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
            final message = permission.isPermanentlyDenied
                ? 'Storage permission is disabled. Enable it in app settings to export CSV.'
                : 'Storage permission is required to export CSV.';
            messenger.showSnackBar(
              SnackBar(
                content: Text(message),
                duration: kAppSnackBarDuration,
              ),
            );
            return;
          }
        }

        savedLocation = await _androidNativeChannel
                .invokeMethod<String>('saveCsv', {
              'name': name,
              'bytes': bytes,
            }) ??
            (throw StateError('Android did not return the saved file path.'));
      } else {
        final location = await getSaveLocation(suggestedName: name);
        if (location == null) return;
        await XFile.fromData(
          bytes,
          mimeType: 'text/csv',
          name: name,
        ).saveTo(location.path);
        savedLocation = location.path;
      }

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
    if (!Platform.isAndroid) {
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
    if (_entries.isEmpty) return const _EmptyState();
    final distances = _distances;
    final list = _chronological.reversed.toList();
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final e = list[i];
        final dist = distances[e.id];
        final eff = dist != null ? dist / e.volume : null;
        return Dismissible(
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
                  ? kYellow
                  : kLightPrimary,
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
                  title: Text(
                    '${_dateFmt.format(e.date)}  ·  ${_money.format(e.total)}',
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
        );
      },
    );
  }

  // ---------------- Totals tab ----------------

  /// Builds overall, monthly, and weekly fuel statistics.
  Widget _buildSummary() {
    if (_entries.isEmpty) {
      return Column(
        children: [
          _buildCsvActions(),
          const Expanded(child: _EmptyState()),
        ],
      );
    }
    final distances = _distances;
    final months = _monthGroups;
    final overall = Stats.from(_entries, distances);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        Card(
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
        _buildCsvActions(),
        for (var i = 0; i < months.length; i++)
          Card(
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
                Text('By week', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                for (final w in months[i].weeks)
                  _WeekRow(week: w, stats: Stats.from(w.entries, distances)),
              ],
            ),
          ),
      ],
    );
  }
}
