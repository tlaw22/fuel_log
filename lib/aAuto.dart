part of 'main.dart';

/// Presents read-only totals and graph outputs in an Android Auto-style layout.
class AndroidAutoScreen extends StatefulWidget {
  final List<FuelEntry> entries;
  final Map<String, double> distances;

  /// Creates the output screen from the current fuel log snapshot.
  const AndroidAutoScreen({
    super.key,
    required this.entries,
    required this.distances,
  });

  @override
  State<AndroidAutoScreen> createState() => _AndroidAutoScreenState();
}

class _AndroidAutoScreenState extends State<AndroidAutoScreen> {
  double? _budget;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBudget());
  }

  String _budgetKey(DateTime month) =>
      '$_monthlyBudgetPrefsKeyPrefix${month.year}_${month.month}';

  Future<void> _loadBudget() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final budget = prefs.getDouble(_budgetKey(now)) ??
        prefs.getDouble(_budgetKey(DateTime(now.year, now.month - 1)));
    if (!mounted) return;
    setState(() => _budget = budget);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthEntries = widget.entries
        .where((entry) =>
            entry.date.year == now.year && entry.date.month == now.month)
        .toList();
    final monthStats = Stats.from(monthEntries, widget.distances);
    final allTimeStats = Stats.from(widget.entries, widget.distances);

    return Scaffold(
      appBar: AppBar(title: const Text('FuelLog Auto Outputs')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _AutoOutputPanel(
            title: 'Totals',
            children: [
              Text(
                _monthFmt.format(now),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              _StatsWrap(stats: monthStats),
              const Divider(height: 24),
              Text(
                'All time',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              _StatsWrap(stats: allTimeStats),
            ],
          ),
          const SizedBox(height: 12),
          _AutoOutputPanel(
            title: 'Graphs',
            children: [
              _BudgetPieChart(
                title: '${_monthFmt.format(now)} spending',
                spent: monthStats.spent,
                budget: _budget,
                distance: monthStats.distance,
                efficiency: monthStats.efficiency,
              ),
              const SizedBox(height: 8),
              _BudgetPieChart(
                title: 'All-time spending',
                spent: allTimeStats.spent,
                budget: _budget,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Wraps an output section in the app's rounded yellow outline.
class _AutoOutputPanel extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _AutoOutputPanel({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: kYellow,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Material(
        color: kNavy800,
        borderRadius: BorderRadius.circular(13),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
