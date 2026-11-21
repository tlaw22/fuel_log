import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

ThemeData buildTheme() {
  const scheme = ColorScheme(
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
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kNavy900,
    appBarTheme: const AppBarTheme(
      backgroundColor: kNavy800,
      foregroundColor: kYellow,
      surfaceTintColor: Colors.transparent,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kGold,
      foregroundColor: kNavy900,
    ),
    dividerTheme: const DividerThemeData(color: kBlue),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kNavy800,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: kBlue,
      contentTextStyle: TextStyle(color: Colors.white),
      actionTextColor: kGold,
    ),
  );
}

void main() => runApp(const FuelLogApp());

class FuelLogApp extends StatelessWidget {
  const FuelLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fuel Log',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomePage(),
    );
  }
}

// ======================= Model =======================

class FuelEntry {
  final String id;
  final DateTime date;
  final double price; // price per unit of fuel
  final double volume; // units of fuel purchased
  final double odometer;

  FuelEntry({
    required this.id,
    required this.date,
    required this.price,
    required this.volume,
    required this.odometer,
  });

  double get total => price * volume;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'price': price,
        'volume': volume,
        'odometer': odometer,
      };

  factory FuelEntry.fromJson(Map<String, dynamic> j) => FuelEntry(
        id: j['id'] as String,
        date: DateTime.parse(j['date'] as String),
        price: (j['price'] as num).toDouble(),
        volume: (j['volume'] as num).toDouble(),
        odometer: (j['odometer'] as num).toDouble(),
      );
}

/// Aggregated numbers for a set of entries.
class Stats {
  double spent = 0;
  double volume = 0;
  double distance = 0;
  double _effVolume = 0; // volume only from fill-ups that have a distance
  int fills = 0;

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

  double? get efficiency =>
      (_effVolume > 0 && distance > 0) ? distance / _effVolume : null;
}

class WeekGroup {
  final DateTime weekStart;
  final List<FuelEntry> entries;
  WeekGroup(this.weekStart, this.entries);
}

class MonthGroup {
  final DateTime month;
  final List<FuelEntry> entries;
  final List<WeekGroup> weeks;
  MonthGroup(this.month, this.entries, this.weeks);
}

// ======================= Formatting =======================

final _money = NumberFormat.currency(symbol: kCurrency, decimalDigits: 2);
final _num1 = NumberFormat('#,##0.0');
final _num3 = NumberFormat('#,##0.000');
final _dateFmt = DateFormat.yMMMd();
final _monthFmt = DateFormat.yMMMM();
final _shortDate = DateFormat.MMMd();

String fmtEfficiency(double? v) =>
    v == null ? '—' : '${v.toStringAsFixed(1)} $kDistanceUnit/$kVolumeUnit';

// ======================= Home =======================

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _prefsKey = 'fuel_entries_v1';
  List<FuelEntry> _entries = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      final list = (jsonDecode(raw) as List)
          .map((e) => FuelEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      _entries = list;
    }
    setState(() => _loaded = true);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefsKey, jsonEncode(_entries.map((e) => e.toJson()).toList()));
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

  Future<void> _openForm([FuelEntry? existing]) async {
    final result = await showModalBottomSheet<FuelEntry>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EntryForm(
        existing: existing,
        lastOdometer: _chronological.isEmpty ? null : _chronological.last.odometer,
      ),
    );
    if (result == null) return;
    setState(() {
      if (existing != null) {
        _entries[_entries.indexWhere((e) => e.id == existing.id)] = result;
      } else {
        _entries.add(result);
      }
    });
    await _save();
  }

  Future<void> _delete(FuelEntry entry) async {
    final index = _entries.indexWhere((e) => e.id == entry.id);
    setState(() => _entries.removeAt(index));
    await _save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Entry deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            setState(() => _entries.insert(index, entry));
            await _save();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lawless Fuel Log'),
          bottom: const TabBar(
            indicatorColor: kGold,
            labelColor: kGold,
            unselectedLabelColor: Color(0xFF8FA6C4),
            tabs: [
              Tab(icon: Icon(Icons.list_alt), text: 'Log'),
              Tab(icon: Icon(Icons.bar_chart), text: 'Totals'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openForm(),
          icon: const Icon(Icons.add),
          label: const Text('Fill-up'),
        ),
        body: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildLog(),
                  _buildSummary(),
                ],
              ),
      ),
    );
  }

  // ---------------- CSV export ----------------

  String _csvField(String v) =>
      (v.contains(',') || v.contains('"') || v.contains('\n'))
          ? '"${v.replaceAll('"', '""')}"'
          : v;

  String _plain(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  Future<void> _exportCsv(BuildContext buttonContext) async {
    final messenger = ScaffoldMessenger.of(context);
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin =
        box != null ? box.localToGlobal(Offset.zero) & box.size : null;

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

      final dir = await getTemporaryDirectory();
      final file =
          File('${dir.path}/fuel_log_${df.format(DateTime.now())}.csv');
      await file.writeAsString(csv);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Fuel log',
        sharePositionOrigin: origin,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not export CSV: $e')),
      );
    }
  }

  // ---------------- Log tab ----------------

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
          child: ListTile(
            onTap: () => _openForm(e),
            title: Text('${_dateFmt.format(e.date)}  ·  ${_money.format(e.total)}'),
            subtitle: Text(
              '${_num1.format(e.odometer)} $kDistanceUnit odometer\n'
              '${_num3.format(e.volume)} $kVolumeUnit @ ${_money.format(e.price)}/$kVolumeUnit'
              '${dist != null ? '\n${_num1.format(dist)} $kDistanceUnit since last  ·  ${fmtEfficiency(eff)}' : ''}',
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.edit_outlined, size: 18),
          ),
        );
      },
    );
  }

  // ---------------- Totals tab ----------------

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
        Builder(
          builder: (ctx) => FilledButton.icon(
            onPressed: () => _exportCsv(ctx),
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('Export CSV'),
          ),
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

// ======================= Widgets =======================

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_gas_station,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text('No fill-ups yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text('Tap “Fill-up” to log your first one.'),
          ],
        ),
      ),
    );
  }
}

class _StatsWrap extends StatelessWidget {
  final Stats stats;
  const _StatsWrap({required this.stats});

  @override
  Widget build(BuildContext context) {
    final items = <(String, String)>[
      ('Spent', _money.format(stats.spent)),
      ('Fuel', '${_num1.format(stats.volume)} $kVolumeUnit'),
      ('Distance', '${_num1.format(stats.distance)} $kDistanceUnit'),
      ('Efficiency', fmtEfficiency(stats.efficiency)),
    ];
    return Wrap(
      spacing: 24,
      runSpacing: 8,
      children: [
        for (final (label, value) in items)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              Text(value,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
      ],
    );
  }
}

class _WeekRow extends StatelessWidget {
  final WeekGroup week;
  final Stats stats;
  const _WeekRow({required this.week, required this.stats});

  @override
  Widget build(BuildContext context) {
    final end = week.weekStart.add(const Duration(days: 6));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
                '${_shortDate.format(week.weekStart)} – ${_shortDate.format(end)}',
                style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            child: Text(
              '${_money.format(stats.spent)}  ·  ${_num1.format(stats.volume)} $kVolumeUnit\n'
              '${_num1.format(stats.distance)} $kDistanceUnit  ·  ${fmtEfficiency(stats.efficiency)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

// ======================= Entry form =======================

class EntryForm extends StatefulWidget {
  final FuelEntry? existing;
  final double? lastOdometer;
  const EntryForm({super.key, this.existing, this.lastOdometer});

  @override
  State<EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends State<EntryForm> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _date;
  late final TextEditingController _price;
  late final TextEditingController _volume;
  late final TextEditingController _odo;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = e?.date ?? DateTime.now();
    _price = TextEditingController(text: e != null ? '${e.price}' : '');
    _volume = TextEditingController(text: e != null ? '${e.volume}' : '');
    _odo = TextEditingController(text: e != null ? '${e.odometer}' : '');
  }

  @override
  void dispose() {
    _price.dispose();
    _volume.dispose();
    _odo.dispose();
    super.dispose();
  }

  double? _parse(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  String? _positive(String? s) {
    final v = _parse(s ?? '');
    if (v == null) return 'Enter a number';
    if (v <= 0) return 'Must be greater than 0';
    return null;
  }

  double? get _previewTotal {
    final p = _parse(_price.text);
    final v = _parse(_volume.text);
    return (p != null && v != null) ? p * v : null;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      FuelEntry(
        id: widget.existing?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        date: DateTime(_date.year, _date.month, _date.day),
        price: _parse(_price.text)!,
        volume: _parse(_volume.text)!,
        odometer: _parse(_odo.text)!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final decimal = const TextInputType.numberWithOptions(decimal: true);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.existing == null ? 'New fill-up' : 'Edit fill-up',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(_dateFmt.format(_date)),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _price,
                keyboardType: decimal,
                decoration: InputDecoration(
                  labelText: 'Fuel price per $kVolumeUnit',
                  prefixText: '$kCurrency ',
                  border: const OutlineInputBorder(),
                ),
                validator: _positive,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _volume,
                keyboardType: decimal,
                decoration: InputDecoration(
                  labelText: 'Amount purchased',
                  suffixText: kVolumeUnit,
                  border: const OutlineInputBorder(),
                ),
                validator: _positive,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _odo,
                keyboardType: decimal,
                decoration: InputDecoration(
                  labelText: 'Odometer reading',
                  suffixText: kDistanceUnit,
                  helperText: widget.lastOdometer != null
                      ? 'Latest logged: ${_num1.format(widget.lastOdometer)}'
                      : null,
                  border: const OutlineInputBorder(),
                ),
                validator: _positive,
              ),
              const SizedBox(height: 12),
              if (_previewTotal != null)
                Text('Total: ${_money.format(_previewTotal)}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              FilledButton(onPressed: _submit, child: const Text('Save')),
            ],
          ),
        ),
      ),
    );
  }
}
