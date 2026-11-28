/// Lunch and restaurant expense page.
/// Records lunch purchases and provides restaurant totals, charts, budgets, and recurring entries.
part of '../app.dart';

const _lunchEntriesKey = 'lunch_entries_v1';
const _lunchBudgetKey = 'lunch_daily_budget_v1';
const _lunchChartSelectionKey = 'lunch_chart_selection_v1';
const _restaurantCsvKey = 'lunch_restaurants_csv_v1';
const _restaurantFileKey = 'lunch_restaurants_file_v1';
const _restaurantFileName = 'lunch_restaurants.csv';
const _lunchChartDefaults = ['today', 'remaining'];
const _lunchMetricLabels = {
  'today': 'Lunch today',
  'week': 'Lunch this week',
  'month': 'Lunch this month',
  'all': 'All-time lunch spending',
  'budget': 'Daily lunch budget',
  'remaining': 'Remaining daily budget',
};
Future<void>? _pendingLunchChartSave;
Future<void>? _pendingLunchEntriesSave;
Future<void>? _pendingRestaurantSave;

class _LunchEntry {
  const _LunchEntry({
    required this.restaurant,
    required this.date,
    required this.price,
  });

  final String restaurant;
  final DateTime date;
  final double price;

  Map<String, Object> toJson() => {
        'restaurant': restaurant,
        'date': date.toIso8601String(),
        'price': price,
      };

  factory _LunchEntry.fromJson(Map<String, dynamic> json) {
    final restaurant = json['restaurant'] as String;
    final price = (json['price'] as num).toDouble();
    if (restaurant.trim().isEmpty || !price.isFinite || price < 0) {
      throw const FormatException('Invalid lunch entry');
    }
    return _LunchEntry(
      restaurant: restaurant,
      date: DateTime.parse(json['date'] as String),
      price: price,
    );
  }
}

DateTime _lunchDay(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime _lunchWeek(DateTime date) =>
    DateTime(date.year, date.month, date.day - date.weekday + 1);

double _lunchTotal(Iterable<_LunchEntry> entries) =>
    entries.fold(0, (total, entry) => total + entry.price);

List<_LunchEntry> _readLunchEntries(SharedPreferences prefs) {
  final raw = prefs.getString(_lunchEntriesKey);
  return raw == null
      ? <_LunchEntry>[]
      : (jsonDecode(raw) as List)
          .map((item) => _LunchEntry.fromJson(item as Map<String, dynamic>))
          .toList();
}

String? _validateLunchAmount(String? value) {
  final amount = double.tryParse(value?.trim() ?? '');
  if (amount == null || !amount.isFinite || amount < 0) {
    return 'Enter a valid non-negative amount';
  }
  return null;
}

List<String> _parseRestaurantCsv(String csv) {
  final rows = _decodeCsv(csv);
  if (rows.isEmpty ||
      rows.first.length != 1 ||
      rows.first.first.replaceFirst('\uFEFF', '').trim() != 'Chain') {
    throw const FormatException(
        'Expected a restaurant CSV with a Chain header.');
  }
  final names = <String>[];
  final seen = <String>{};
  for (var index = 1; index < rows.length; index++) {
    final row = rows[index];
    if (row.length != 1) {
      throw FormatException('Invalid restaurant CSV row ${index + 1}.');
    }
    final name = row.first.trim();
    if (name.isNotEmpty && seen.add(name.toLowerCase())) names.add(name);
  }
  return names;
}

String _restaurantCsv(List<String> names) =>
    ['Chain', ...names.map(_csvField)].join('\r\n');

Future<File> _restaurantFile() async {
  final directory = await getApplicationDocumentsDirectory();
  return File('${directory.path}${Platform.pathSeparator}FuelLog'
      '${Platform.pathSeparator}$_restaurantFileName');
}

Future<List<String>> _readRestaurants(SharedPreferences prefs) async {
  final String csv;
  if (kIsWeb && prefs.containsKey(_restaurantCsvKey)) {
    csv = prefs.getString(_restaurantCsvKey)!;
  } else if (!kIsWeb && (prefs.getBool(_restaurantFileKey) ?? false)) {
    csv = await (await _restaurantFile()).readAsString();
  } else {
    csv = await rootBundle.loadString(
      'lib/assets/fast_food_chains.csv',
      cache: false,
    );
  }
  return _parseRestaurantCsv(csv);
}

Future<void> _writeRestaurants(List<String> restaurants,
    {bool replaceExistingFile = false}) {
  final previous = _pendingRestaurantSave;
  final save = () async {
    if (previous != null) await previous;
    final csv = _restaurantCsv(restaurants);
    final prefs = await SharedPreferences.getInstance();
    if (kIsWeb) {
      if (!await prefs.setString(_restaurantCsvKey, csv)) {
        throw StateError('Could not save the restaurant list.');
      }
    } else {
      final file = await _restaurantFile();
      final temporary = File('${file.path}.tmp');
      await file.parent.create(recursive: true);
      if (!replaceExistingFile &&
          !(prefs.getBool(_restaurantFileKey) ?? false) &&
          await file.exists()) {
        throw StateError('Restaurant file already exists at ${file.path}. '
            'Import it before saving a new restaurant.');
      }
      try {
        await temporary.writeAsString(csv, flush: true);
        await temporary.rename(file.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
      if (!await prefs.setBool(_restaurantFileKey, true)) {
        throw StateError('Could not save the restaurant file setting.');
      }
    }
  }();
  final pending =
      save.then<void>((_) {}, onError: (Object _, StackTrace __) {});
  _pendingRestaurantSave = pending;
  unawaited(pending.whenComplete(() {
    if (identical(_pendingRestaurantSave, pending)) {
      _pendingRestaurantSave = null;
    }
  }));
  return save;
}

List<_LunchEntry> _parseLunchCsv(String csv) {
  final rows = _decodeCsv(csv);
  if (rows.isEmpty ||
      rows.first.length != 3 ||
      rows.first[0].replaceFirst('\uFEFF', '').trim() != 'Date' ||
      rows.first[1].trim() != 'Restaurant' ||
      rows.first[2].trim() != 'Price') {
    throw const FormatException('This is not a FuelLog lunch CSV file.');
  }
  final entries = <_LunchEntry>[];
  for (var index = 1; index < rows.length; index++) {
    final row = rows[index];
    if (row.length == 1 && row.first.trim().isEmpty) continue;
    if (row.length != 3) {
      throw FormatException(
          'Invalid lunch CSV row ${index + 1}: wrong number of columns.');
    }
    try {
      final restaurant = row[1].trim();
      final price = double.parse(row[2].trim());
      if (restaurant.isEmpty || !price.isFinite || price < 0) {
        throw const FormatException(
            'Restaurant and non-negative price are required.');
      }
      entries.add(_LunchEntry(
        restaurant: restaurant,
        date: DateTime.parse(row[0].trim()),
        price: price,
      ));
    } on FormatException catch (error) {
      throw FormatException(
          'Invalid lunch CSV row ${index + 1}: ${error.message}');
    }
  }
  return entries;
}

String _lunchCsv(List<_LunchEntry> entries) => [
      'Date,Restaurant,Price',
      for (final entry in entries)
        [
          entry.date.toIso8601String(),
          entry.restaurant,
          entry.price.toString(),
        ].map(_csvField).join(','),
    ].join('\r\n');

/// Records lunch purchases separately from the fuel log.
class LunchPage extends StatefulWidget {
  const LunchPage({super.key}) : _onEntriesChanged = null;

  const LunchPage._withUpdates({
    super.key,
    required ValueChanged<List<_LunchEntry>> onEntriesChanged,
  }) : _onEntriesChanged = onEntriesChanged;

  final ValueChanged<List<_LunchEntry>>? _onEntriesChanged;

  @override
  State<LunchPage> createState() => _LunchPageState();
}

class _LunchPageState extends State<LunchPage> {
  final _infoTooltipKey = GlobalKey<TooltipState>();
  List<String> _restaurants = [];
  List<_LunchEntry> _entries = [];
  double? _budget;
  List<String> _chartSelection = _lunchChartDefaults;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _pendingLunchChartSave;
      await _pendingLunchEntriesSave;
      await _pendingRestaurantSave;
      final prefs = await SharedPreferences.getInstance();
      final restaurants = await _readRestaurants(prefs);
      final entries = _readLunchEntries(prefs);
      final budget = prefs.getDouble(_lunchBudgetKey);
      if (budget != null && (!budget.isFinite || budget < 0)) {
        throw const FormatException('Invalid lunch budget');
      }
      final selection =
          prefs.getStringList(_lunchChartSelectionKey) ?? _lunchChartDefaults;
      if (selection.length != 2 ||
          selection.any((key) =>
              !_lunchMetricLabels.containsKey(key) &&
              !(key.startsWith('restaurant:') && key.length > 11))) {
        throw const FormatException('Invalid lunch chart selection');
      }
      if (!mounted) return;
      setState(() {
        _restaurants = restaurants;
        _entries = entries;
        _budget = budget;
        _chartSelection = selection;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _showError(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content: Text(message),
      duration: kAppSnackBarDuration,
    ));
  }

  Future<void> _saveEntries(List<_LunchEntry> entries,
      {String? restaurantToAdd}) async {
    setState(() => _saving = true);
    final onEntriesChanged = widget._onEntriesChanged;
    final previous = _pendingLunchEntriesSave;
    final save = () async {
      if (previous != null) await previous;
      final prefs = await SharedPreferences.getInstance();
      if (restaurantToAdd != null &&
          !_restaurants.any(
              (name) => name.toLowerCase() == restaurantToAdd.toLowerCase())) {
        final restaurants = await _readRestaurants(prefs);
        if (!restaurants.any(
            (name) => name.toLowerCase() == restaurantToAdd.toLowerCase())) {
          restaurants.add(restaurantToAdd);
          await _writeRestaurants(restaurants);
        }
        if (mounted) setState(() => _restaurants = restaurants);
      }
      if (!await prefs.setString(_lunchEntriesKey,
          jsonEncode(entries.map((e) => e.toJson()).toList()))) {
        throw StateError('Storage did not confirm the save');
      }
    }();
    final pending =
        save.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _pendingLunchEntriesSave = pending;
    unawaited(pending.whenComplete(() {
      if (identical(_pendingLunchEntriesSave, pending)) {
        _pendingLunchEntriesSave = null;
      }
    }));
    try {
      await save;
      onEntriesChanged?.call(entries);
      if (!mounted) return;
      setState(() => _entries = entries);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openEntry() async {
    if (_loading || _error != null || _saving) {
      _showError('Lunch data is not ready.');
      return;
    }
    Future<Object?>? browserPermission;
    final saved = await showModalBottomSheet<_LunchEntry>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _LunchEntryForm(
        restaurants: _restaurants,
        onSave: (entry) => _saveEntries([..._entries, entry],
            restaurantToAdd: entry.restaurant),
        onValidatedSavePressed: () {
          if (kIsWeb) {
            browserPermission = FuelLogNotifications.requestBrowserPermission();
          }
        },
      ),
    );
    if (saved == null || !mounted) return;
    final entries = List<_LunchEntry>.of(_entries);
    final budget = _budget;
    try {
      if (browserPermission != null) {
        final error = await browserPermission;
        if (error != null) throw error;
      }
      await _LunchNotification.show(saved, entries, budget);
      if (mounted) _showError('Lunch saved.');
    } catch (error) {
      if (mounted) {
        FuelLogNotifications.reportFailure(context, error, lunch: true);
      }
    }
  }

  Future<void> _deleteEntry(_LunchEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete lunch entry?'),
        content: Text('${entry.restaurant} · ${_money.format(entry.price)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _saving) return;
    try {
      await _saveEntries(_entries.where((item) => item != entry).toList());
    } catch (error) {
      if (mounted) _showError('Could not delete lunch entry: $error');
    }
  }

  Future<bool> _confirmCsvReplacement(String description) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Replace current data?'),
            content: Text(description),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Replace'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _importCsv({required bool restaurants}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'CSV files', extensions: ['csv']),
        ],
      );
      if (file == null) return;
      final source = await file.readAsString();
      if (!mounted) return;
      if (restaurants) {
        final imported = _parseRestaurantCsv(source);
        final confirmed = await _confirmCsvReplacement(
          'Replace the restaurant list with ${imported.length} '
          'restaurant${imported.length == 1 ? '' : 's'} from ${file.name}? '
          'The saved restaurant list will be overwritten.',
        );
        if (!confirmed || !mounted) return;
        await _writeRestaurants(imported, replaceExistingFile: true);
        if (!mounted) return;
        setState(() => _restaurants = imported);
        if (_error != null) {
          await _load();
          if (!mounted || _error != null) return;
        }
        _showError('Loaded ${imported.length} restaurants from ${file.name}.');
      } else {
        final imported = _parseLunchCsv(source);
        final confirmed = await _confirmCsvReplacement(
          'Replace all lunch entries with ${imported.length} '
          'entr${imported.length == 1 ? 'y' : 'ies'} from ${file.name}? '
          'Fuel entries will not be changed.',
        );
        if (!confirmed || !mounted) return;
        await _saveEntries(imported);
        if (!mounted) return;
        _showError(
            'Loaded ${imported.length} lunch entries from ${file.name}.');
      }
    } catch (error) {
      if (mounted) _showError('Could not import CSV: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _exportCsv({required bool restaurants}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final name = restaurants
          ? _restaurantFileName
          : 'lunch_log_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv';
      final csv =
          restaurants ? _restaurantCsv(_restaurants) : _lunchCsv(_entries);
      final saved =
          await _saveCsvFile(name, Uint8List.fromList(utf8.encode(csv)));
      if (saved != null && mounted) _showError('CSV saved to $saved');
    } catch (error) {
      if (mounted) _showError('Could not export CSV: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setBudget() async {
    var budgetText = _budget?.toStringAsFixed(2) ?? '';
    final formKey = GlobalKey<FormState>();
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Daily lunch budget'),
        content: Form(
          key: formKey,
          child: TextFormField(
            key: const ValueKey('lunch-budget-input'),
            initialValue: budgetText,
            onChanged: (value) => budgetText = value,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Planned per day'),
            validator: _validateLunchAmount,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, double.parse(budgetText.trim()));
              }
            },
            child: const Text('Save budget'),
          ),
        ],
      ),
    );
    if (value == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setDouble(_lunchBudgetKey, value)) {
        throw StateError('Storage did not confirm the save');
      }
      if (mounted) setState(() => _budget = value);
    } catch (error) {
      if (mounted) _showError('Could not save lunch budget: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _changeChartSelection(int index, String value) {
    final selection = [..._chartSelection]..[index] = value;
    setState(() => _chartSelection = selection);
    final previous = _pendingLunchChartSave;
    final save = () async {
      if (previous != null) await previous;
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setStringList(_lunchChartSelectionKey, selection)) {
        throw StateError('Storage did not confirm the save');
      }
    }();
    final pending =
        save.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _pendingLunchChartSave = pending;
    unawaited(pending.whenComplete(() {
      if (identical(_pendingLunchChartSave, pending)) {
        _pendingLunchChartSave = null;
      }
    }));
    unawaited(save.catchError((Object error, StackTrace stackTrace) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'FuelLog lunch chart',
      ));
      if (mounted) _showError('Could not save lunch chart selection: $error');
    }));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Could not load lunch data: $_error'),
            TextButton(onPressed: _load, child: const Text('Retry')),
            TextButton(
              onPressed: _saving ? null : () => _importCsv(restaurants: true),
              child: const Text('Import restaurants CSV'),
            ),
          ],
        ),
      );
    }
    final now = DateTime.now();
    final today = _lunchDay(now);
    final week = _lunchWeek(now);
    final nextWeek = DateTime(week.year, week.month, week.day + 7);
    final restaurantNames = <String, String>{};
    final restaurantTotals = <String, double>{};
    var todayTotal = 0.0;
    var weekTotal = 0.0;
    var monthTotal = 0.0;
    for (final entry in _entries) {
      final day = _lunchDay(entry.date);
      if (day == today) todayTotal += entry.price;
      if (!day.isBefore(week) && day.isBefore(nextWeek)) {
        weekTotal += entry.price;
      }
      if (entry.date.year == now.year && entry.date.month == now.month) {
        monthTotal += entry.price;
      }
      final key = 'restaurant:${entry.restaurant.trim().toLowerCase()}';
      restaurantNames.putIfAbsent(key, () => entry.restaurant);
      restaurantTotals.update(key, (total) => total + entry.price,
          ifAbsent: () => entry.price);
    }
    final restaurantKeys = restaurantNames.keys.toList()
      ..sort((a, b) => restaurantNames[a]!
          .toLowerCase()
          .compareTo(restaurantNames[b]!.toLowerCase()));
    final labels = <String, String>{
      ..._lunchMetricLabels,
      for (final key in restaurantKeys)
        key: 'Restaurant: ${restaurantNames[key]} (all time)',
      for (final key in _chartSelection)
        if (key.startsWith('restaurant:') && !restaurantNames.containsKey(key))
          key: 'Restaurant: ${key.substring(11)} (all time)',
    };
    final amounts = <String, double?>{
      'today': todayTotal,
      'week': weekTotal,
      'month': monthTotal,
      'all': _lunchTotal(_entries),
      'budget': _budget,
      'remaining': _budget == null ? null : math.max(0, _budget! - todayTotal),
      for (final key
          in labels.keys.where((key) => key.startsWith('restaurant:')))
        key: restaurantTotals[key] ?? 0,
    };
    final days = <DateTime, List<_LunchEntry>>{};
    for (final entry in _entries) {
      days.putIfAbsent(_lunchDay(entry.date), () => []).add(entry);
    }
    final sortedDays = days.keys.toList()..sort((a, b) => b.compareTo(a));
    final months = <DateTime, Map<DateTime, List<DateTime>>>{};
    for (final day in sortedDays) {
      final month = DateTime(day.year, day.month);
      months
          .putIfAbsent(month, () => {})
          .putIfAbsent(_lunchWeek(day), () => [])
          .add(day);
    }

    return ListView(
      key: const ValueKey('lunch-scroll'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
      children: [
        Row(
          children: [
            Text('Lunch', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(width: 8),
            Tooltip(
              key: _infoTooltipKey,
              message: "The lunch calculator is included because you can't "
                  'always pack your lunch while traveling.',
              triggerMode: TooltipTriggerMode.manual,
              child: IconButton.outlined(
                style: IconButton.styleFrom(
                  minimumSize: const Size(24, 24),
                  fixedSize: const Size(24, 24),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () =>
                    _infoTooltipKey.currentState?.ensureTooltipVisible(),
                icon: const Icon(Icons.help_outline, size: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _saving ? null : _setBudget,
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: const Text('Lunch budget'),
          ),
        ),
        Text(_budget == null
            ? 'No daily budget set'
            : 'Daily budget: ${_money.format(_budget)}'
                ' · ${todayTotal > _budget! ? 'Over' : 'Remaining'}: '
                '${_money.format((todayTotal - _budget!).abs())}'),
        const SizedBox(height: 12),
        _LunchBudgetChart(spent: todayTotal, budget: _budget),
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                for (final (label, amount) in [
                  ('Today', todayTotal),
                  ('This week', weekTotal),
                  ('This month', monthTotal),
                ])
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: Theme.of(context).textTheme.bodySmall),
                      Text(_money.format(amount),
                          style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
              ],
            ),
          ),
        ),
        Text('Lunch history', style: Theme.of(context).textTheme.titleMedium),
        if (sortedDays.isEmpty) const Text('No lunch entries yet.'),
        for (final month in months.keys)
          Card(
            child: ExpansionTile(
              initiallyExpanded: month == months.keys.first,
              title: Text(_monthFmt.format(month)),
              subtitle: Text(
                  'Monthly total: ${_money.format(_lunchTotal(months[month]!.values.expand((weekDays) => weekDays).expand((day) => days[day]!)))}'),
              children: [
                for (final weekStart in months[month]!.keys)
                  ExpansionTile(
                    title: Text('Week of ${_dateFmt.format(weekStart)}'),
                    subtitle: Text(
                        'Week total: ${_money.format(_lunchTotal(_entries.where((entry) => _lunchWeek(entry.date) == weekStart)))}'
                        ' · Days in this month'),
                    children: [
                      for (final day in months[month]![weekStart]!)
                        ExpansionTile(
                          title: Text(_dateFmt.format(day)),
                          subtitle: Text(
                              'Daily total: ${_money.format(_lunchTotal(days[day]!))}'),
                          children: [
                            for (final entry in days[day]!)
                              ListTile(
                                title: Text(entry.restaurant),
                                subtitle: Text(
                                    TimeOfDay.fromDateTime(entry.date)
                                        .format(context)),
                                trailing: Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(_money.format(entry.price)),
                                    IconButton(
                                      tooltip: 'Delete lunch entry',
                                      onPressed: _saving
                                          ? null
                                          : () => _deleteEntry(entry),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        _LunchCustomChart(
          labels: labels,
          amounts: amounts,
          selection: _chartSelection,
          onChanged: _changeChartSelection,
        ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _saving ? null : () => _importCsv(restaurants: false),
              icon: const Icon(Icons.upload_file),
              label: const Text('Import lunch CSV'),
            ),
            OutlinedButton.icon(
              onPressed: _saving ? null : () => _exportCsv(restaurants: false),
              icon: const Icon(Icons.download),
              label: const Text('Export lunch CSV'),
            ),
            OutlinedButton(
              onPressed: _saving ? null : () => _importCsv(restaurants: true),
              child: const Text('Import restaurants CSV'),
            ),
            OutlinedButton(
              onPressed: _saving ? null : () => _exportCsv(restaurants: true),
              child: const Text('Export restaurants CSV'),
            ),
          ],
        ),
      ],
    );
  }
}

class _LunchBudgetChart extends StatelessWidget {
  const _LunchBudgetChart({required this.spent, required this.budget});

  final double spent;
  final double? budget;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final goal = budget;
    final remaining = goal == null ? null : math.max(0.0, goal - spent);
    final progress = goal == null || (goal == 0 && spent == 0)
        ? null
        : goal == 0
            ? 1.0
            : (spent / goal).clamp(0.0, 1.0).toDouble();
    return _CollapsibleChart(
      title: 'Today’s lunch budget',
      child: _ChartSummary(
        progress: progress,
        semanticsLabel: 'Lunch spent and remaining daily budget',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BudgetLegendRow(
                color: colors.primary, label: 'Spent', amount: spent),
            _BudgetLegendRow(
              color: colors.surfaceContainerHighest,
              label: 'Remaining',
              amount: remaining,
            ),
            Text(goal == null
                ? 'Set a daily budget to view progress.'
                : 'Daily budget: ${_money.format(goal)}'),
            if (goal != null && spent > goal)
              Text('Over budget by ${_money.format(spent - goal)}',
                  style: TextStyle(color: colors.error)),
            if (goal != null && goal > 0)
              Text('${(spent / goal * 100).round()}% of daily budget'),
          ],
        ),
      ),
    );
  }
}

class _LunchCustomChart extends StatelessWidget {
  const _LunchCustomChart({
    required this.labels,
    required this.amounts,
    required this.selection,
    required this.onChanged,
  });

  final Map<String, String> labels;
  final Map<String, double?> amounts;
  final List<String> selection;
  final void Function(int index, String value) onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final first = amounts[selection[0]];
    final second = amounts[selection[1]];
    final total = (first ?? 0) + (second ?? 0);
    final progress =
        first == null || second == null || total == 0 ? null : first / total;

    Widget selector(int index, String label) {
      final accent = colors.brightness == Brightness.dark
          ? colors.primary
          : colors.onSurface;
      return InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: colors.surfaceContainerHighest,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: accent, width: 1.5),
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: ValueKey('lunch-chart-$index'),
            value: selection[index],
            isExpanded: true,
            menuWidth: math.min(MediaQuery.sizeOf(context).width - 32, 360),
            items: [
              for (final entry in labels.entries)
                DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) {
              if (value != null) onChanged(index, value);
            },
          ),
        ),
      );
    }

    return _CollapsibleChart(
      title: 'Custom Lunch Chart',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('select two values to compare',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: selector(0, 'First amount')),
                    const SizedBox(width: 8),
                    Expanded(child: selector(1, 'Second amount')),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _ChartSummary(
            progress: progress,
            semanticsLabel:
                '${labels[selection[0]]} and ${labels[selection[1]]}',
            child: Column(
              children: [
                _BudgetLegendRow(
                    color: colors.primary,
                    label: labels[selection[0]]!,
                    amount: first),
                _BudgetLegendRow(
                    color: colors.surfaceContainerHighest,
                    label: labels[selection[1]]!,
                    amount: second),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
