part of 'main.dart';

// ======================= Home =======================

/// Displays the fuel log, totals, CSV export, and nearby sync entry points.
class HomePage extends StatefulWidget {
  /// Creates the home page.
  const HomePage({super.key});

  /// Creates the state and connects it to the HomePage widget.
  @override
  State<HomePage> createState() => _HomePageState();
}

/// State that loads, edits, calculates, persists, and synchronizes fuel entries.
class _HomePageState extends State<HomePage> {
  static const _prefsKey = 'fuel_entries_v1';
  static const _deletedPrefsKey = 'fuel_entries_deleted_v1';
  static const _pageNames = ['Log', 'Totals', 'Graphs', 'Stations'];
  static const _pageIcons = [
    Icons.list_alt,
    Icons.bar_chart,
    Icons.pie_chart_outline,
    Icons.local_gas_station,
  ];
  final CarouselSliderController _carouselController =
      CarouselSliderController();
  List<FuelEntry> _entries = [];
  Map<String, DateTime> _deletions = {};
  bool _loaded = false;
  int _currentPage = 0;

  /// Loads persisted entries after the first frame of the home page.
  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Loads active entries and deleted-entry tombstones from shared preferences.
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      final list = (jsonDecode(raw) as List)
          .map((e) => FuelEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      _entries = list;
    }
    final rawDeletions = prefs.getString(_deletedPrefsKey);
    if (rawDeletions != null) {
      _deletions = (jsonDecode(rawDeletions) as Map<String, dynamic>).map(
        (id, value) => MapEntry(id, DateTime.parse(value as String)),
      );
    }
    setState(() => _loaded = true);
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

  /// Builds the swipeable Log, Totals, Graphs, and Stations carousel.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          'FuelLog',
          style: TextStyle(fontFamily: 'BBH Bogle', fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'Open Android Auto outputs',
            icon: const Icon(Icons.directions_car_outlined),
            onPressed: _loaded
                ? () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AndroidAutoScreen(
                          entries: List.of(_entries),
                          distances: Map.of(_distances),
                        ),
                      ),
                    )
                : null,
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
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Fill-up'),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
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
                                                  ? kGold
                                                  : const Color(0xFF8FA6C4),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              _pageNames[index],
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(
                                                    color: index == _currentPage
                                                        ? kGold
                                                        : const Color(
                                                            0xFF8FA6C4,
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
                          final page = switch (index) {
                            0 => _buildLog(),
                            1 => _buildSummary(),
                            2 => GraphicsPage(
                                entries: _entries,
                                distances: _distances,
                              ),
                            _ => FuelStationsPage(
                                entries: _entries,
                                distances: _distances,
                              ),
                          };
                          return SizedBox(
                            width: constraints.maxWidth,
                            child: page,
                          );
                        },
                        options: CarouselOptions(
                          height: constraints.maxHeight,
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

  /// Escapes a CSV field that contains commas, quotes, or line breaks.
  String _csvField(String v) =>
      (v.contains(',') || v.contains('"') || v.contains('\n'))
          ? '"${v.replaceAll('"', '""')}"'
          : v;

  /// Formats a decimal value without unnecessary trailing zeros.
  String _plain(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// Exports the chronological fuel log as a CSV file.
  Future<void> _exportCsv() async {
    final messenger = ScaffoldMessenger.of(context);

    try {
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
      for (final e in _chronological) {
        final dist = distances[e.id];
        rows.add([
          df.format(e.date),
          _plain(e.odometer),
          e.price.toStringAsFixed(3),
          e.volume.toStringAsFixed(3),
          e.total.toStringAsFixed(2),
          dist != null ? _plain(dist) : '',
          dist != null ? (dist / e.volume).toStringAsFixed(2) : '',
        ]);
      }
      final csv = rows.map((r) => r.map(_csvField).join(',')).join('\r\n');
      final name = 'fuel_log_${df.format(DateTime.now())}.csv';
      final bytes = Uint8List.fromList(utf8.encode(csv));
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
            messenger.showSnackBar(SnackBar(content: Text(message)));
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
        SnackBar(content: Text('CSV saved to $savedLocation')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not export CSV: $e')),
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
              color: kYellow,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: kNavy800,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Material(
                color: kNavy800,
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
    if (_entries.isEmpty) return const _EmptyState();
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
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _exportCsv,
          icon: const Icon(Icons.file_download_outlined),
          label: const Text('Export CSV'),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < months.length; i++)
          Card(
            color: kNavy800,
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
