part of '../app.dart';

const _lunchEntriesKey = 'lunch_entries_v1';
const _lunchBudgetKey = 'lunch_daily_budget_v1';
const _lunchChartSelectionKey = 'lunch_chart_selection_v1';
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
      final csv = await rootBundle.loadString(
        'lib/assets/fast_food_chains.csv',
        cache: false,
      );
      final lines = const LineSplitter().convert(csv);
      if (lines.isEmpty || lines.first.trim() != 'Chain') {
        throw const FormatException('Invalid restaurant list');
      }
      final restaurants = lines.skip(1).map((line) => line.trim())
          .where((line) => line.isNotEmpty).toList();
      await _pendingLunchChartSave;
      await _pendingLunchEntriesSave;
      final prefs = await SharedPreferences.getInstance();
      final entries = _readLunchEntries(prefs);
      final budget = prefs.getDouble(_lunchBudgetKey);
      if (budget != null && (!budget.isFinite || budget < 0)) {
        throw const FormatException('Invalid lunch budget');
      }
      final selection = prefs.getStringList(_lunchChartSelectionKey) ??
          _lunchChartDefaults;
      if (selection.length != 2 ||
          selection.any((key) => !_lunchMetricLabels.containsKey(key) &&
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      duration: kAppSnackBarDuration,
    ));
  }

  Future<void> _saveEntries(List<_LunchEntry> entries) async {
    setState(() => _saving = true);
    final onEntriesChanged = widget._onEntriesChanged;
    final previous = _pendingLunchEntriesSave;
    final save = () async {
      if (previous != null) await previous;
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(
          _lunchEntriesKey, jsonEncode(entries.map((e) => e.toJson()).toList()))) {
        throw StateError('Storage did not confirm the save');
      }
    }();
    final pending = save.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _pendingLunchEntriesSave = pending;
    unawaited(pending.whenComplete(() {
      if (identical(_pendingLunchEntriesSave, pending)) _pendingLunchEntriesSave = null;
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
        onSave: (entry) => _saveEntries([..._entries, entry]),
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
      if (mounted) _showError('Lunch saved, but notification failed: $error');
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
    final pending = save.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _pendingLunchChartSave = pending;
    unawaited(pending.whenComplete(() {
      if (identical(_pendingLunchChartSave, pending)) _pendingLunchChartSave = null;
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
          ],
        ),
      );
    }
    final now = DateTime.now();
    final today = _lunchDay(now);
    final week = _lunchWeek(now);
    final nextWeek = DateTime(week.year, week.month, week.day + 7);
    final todayTotal = _lunchTotal(_entries.where((e) => _lunchDay(e.date) == today));
    final weekTotal = _lunchTotal(_entries.where(
        (e) => !_lunchDay(e.date).isBefore(week) && _lunchDay(e.date).isBefore(nextWeek)));
    final monthTotal = _lunchTotal(_entries.where(
        (e) => e.date.year == now.year && e.date.month == now.month));
    final restaurantNames = <String, String>{};
    final restaurantTotals = <String, double>{};
    for (final entry in _entries) {
      final key = 'restaurant:${entry.restaurant.trim().toLowerCase()}';
      restaurantNames.putIfAbsent(key, () => entry.restaurant);
      restaurantTotals.update(key, (total) => total + entry.price,
          ifAbsent: () => entry.price);
    }
    final restaurantKeys = restaurantNames.keys.toList()
      ..sort((a, b) => restaurantNames[a]!.toLowerCase()
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
      for (final key in labels.keys.where((key) => key.startsWith('restaurant:')))
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
      months.putIfAbsent(month, () => {})
          .putIfAbsent(_lunchWeek(day), () => [])
          .add(day);
    }

    return ListView(
      key: const ValueKey('lunch-scroll'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
      children: [
        Text('Lunch', style: Theme.of(context).textTheme.headlineSmall),
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
                      Text(_money.format(amount), style: Theme.of(context).textTheme.titleMedium),
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
              subtitle: Text('Monthly total: ${_money.format(_lunchTotal(
                months[month]!.values.expand((weekDays) => weekDays)
                    .expand((day) => days[day]!)))}'),
              children: [
                for (final weekStart in months[month]!.keys)
                  ExpansionTile(
                    title: Text('Week of ${_dateFmt.format(weekStart)}'),
                    subtitle: Text('Week total: ${_money.format(_lunchTotal(
                      _entries.where((entry) => _lunchWeek(entry.date) == weekStart)))}'
                      ' · Days in this month'),
                    children: [
                      for (final day in months[month]![weekStart]!)
                        ExpansionTile(
                          title: Text(_dateFmt.format(day)),
                          subtitle: Text('Daily total: ${_money.format(_lunchTotal(days[day]!))}'),
                          children: [
                            for (final entry in days[day]!)
                              ListTile(
                                title: Text(entry.restaurant),
                                subtitle: Text(TimeOfDay.fromDateTime(entry.date).format(context)),
                                trailing: Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(_money.format(entry.price)),
                                    IconButton(
                                      tooltip: 'Delete lunch entry',
                                      onPressed: _saving ? null : () => _deleteEntry(entry),
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
            _BudgetLegendRow(color: colors.primary, label: 'Spent', amount: spent),
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
    final progress = first == null || second == null || total == 0
        ? null
        : first / total;

    Widget selector(int index, String label) {
      final accent = colors.brightness == Brightness.dark
          ? colors.primary
          : colors.onSurface;
      return InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: colors.surfaceContainerHighest,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            semanticsLabel: '${labels[selection[0]]} and ${labels[selection[1]]}',
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
