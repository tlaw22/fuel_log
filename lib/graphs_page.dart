part of 'main.dart';

/// Shows all-time and current-month spending against an editable monthly budget.
class GraphicsPage extends StatefulWidget {
  final List<FuelEntry> entries;
  final Map<String, double> distances;

  /// Creates the graphs page for the supplied fuel entries.
  const GraphicsPage({
    super.key,
    required this.entries,
    required this.distances,
  });

  /// Creates state for loading and editing this month's spending budget.
  @override
  State<GraphicsPage> createState() => _GraphicsPageState();
}

/// Loads the monthly budget and builds spending charts from the current entries.
class _GraphicsPageState extends State<GraphicsPage>
    with AutomaticKeepAliveClientMixin<GraphicsPage> {
  final _budgetController = TextEditingController();
  double? _budget;

  /// Keeps the budget editor alive while navigating between carousel pages.
  @override
  bool get wantKeepAlive => true;

  /// Loads this month's saved budget or carries forward the previous month's.
  @override
  void initState() {
    super.initState();
    unawaited(_loadBudget());
  }

  /// Releases the budget text controller.
  @override
  void dispose() {
    _budgetController.dispose();
    super.dispose();
  }

  /// Builds the preference key for the specified calendar month.
  String _budgetKey(DateTime month) =>
      '$_monthlyBudgetPrefsKeyPrefix${month.year}_${month.month}';

  /// Loads a saved budget for this month, falling back to the previous month.
  Future<void> _loadBudget() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final currentMonthBudget = prefs.getDouble(_budgetKey(now));
    final previousMonthBudget =
        prefs.getDouble(_budgetKey(DateTime(now.year, now.month - 1)));
    final budget = currentMonthBudget ?? previousMonthBudget;
    if (!mounted) return;
    setState(() {
      _budget = budget;
      _budgetController.text = budget?.toStringAsFixed(2) ?? '';
    });
  }

  /// Parses the editable budget amount entered by the user.
  double? _parseBudget() =>
      double.tryParse(_budgetController.text.trim().replaceAll(',', '.'));

  /// Saves the entered budget for the current month.
  Future<void> _saveBudget() async {
    final budget = _parseBudget();
    if (budget == null || budget <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a budget greater than zero.')),
      );
      return;
    }

    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_budgetKey(now), budget);
    if (!mounted) return;
    setState(() => _budget = budget);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Monthly budget saved')),
    );
  }

  /// Builds the budget input and all-time and monthly spending charts.
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final now = DateTime.now();
    final allTimeSpent =
        widget.entries.fold<double>(0, (total, entry) => total + entry.total);
    final monthEntries = widget.entries
        .where((entry) =>
            entry.date.year == now.year && entry.date.month == now.month)
        .toList();
    final monthStats = Stats.from(monthEntries, widget.distances);
    final budget = _budget;
    final inputBudget = _parseBudget();
    final chartBudget =
        inputBudget != null && inputBudget > 0 ? inputBudget : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        TextField(
          controller: _budgetController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          decoration: InputDecoration(
            labelText: 'Monthly spending budget',
            prefixText: '$kCurrency ',
            border: const OutlineInputBorder(),
            helperText: budget == null
                ? 'Enter a budget to compare spending.'
                : 'The previous month’s budget is carried forward.',
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _saveBudget(),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _saveBudget,
            child: const Text('Save budget'),
          ),
        ),
        const SizedBox(height: 8),
        _BudgetPieChart(
          title: '${_monthFmt.format(now)} spending',
          spent: monthStats.spent,
          budget: chartBudget,
          distance: monthStats.distance,
          efficiency: monthStats.efficiency,
        ),
        const SizedBox(height: 12),
        _BudgetPieChart(
          title: 'All-time spending',
          spent: allTimeSpent,
          budget: chartBudget,
        ),
      ],
    );
  }
}

/// Displays spent and remaining amounts as a budget-progress pie chart.
class _BudgetPieChart extends StatelessWidget {
  final String title;
  final double spent;
  final double? budget;
  final double? distance;
  final double? efficiency;

  /// Creates a chart for the supplied spending total and budget.
  const _BudgetPieChart({
    required this.title,
    required this.spent,
    required this.budget,
    this.distance,
    this.efficiency,
  });

  /// Builds the pie chart, legend, and budget progress details.
  @override
  Widget build(BuildContext context) {
    final goal = budget;
    final colors = Theme.of(context).colorScheme;
    final remaining = goal == null || spent >= goal ? 0.0 : goal - spent;
    final progress =
        goal == null ? 0.0 : (spent / goal).clamp(0.0, 1.0).toDouble();
    return Card(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (goal == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Set a monthly budget to view progress.'),
                ),
              )
            else ...[
              Center(
                child: Semantics(
                  label: '${(progress * 100).round()} percent of budget used',
                  child: CustomPaint(
                    size: const Size.square(180),
                    painter: _BudgetPiePainter(
                      progress,
                      spentColor: colors.primary,
                      remainingColor: colors.surfaceContainerHighest,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (goal != null || distance != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (goal != null)
                    Expanded(
                      flex: distance == null ? 1 : 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _BudgetLegendRow(
                            color: colors.primary,
                            label: 'Spent',
                            amount: spent,
                          ),
                          _BudgetLegendRow(
                            color: colors.surfaceContainerHighest,
                            label: 'Remaining',
                            amount: remaining,
                          ),
                          if (spent > goal)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Over budget by ${_money.format(spent - goal)}',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          const SizedBox(height: 4),
                          Text(
                            '${(spent / goal * 100).round()}% of ${_money.format(goal)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  if (distance != null) ...[
                    if (goal != null) const SizedBox(width: 16),
                    Expanded(
                      flex: goal == null ? 1 : 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Miles driven',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            '${_num1.format(distance)} $kDistanceUnit',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Fuel efficiency',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            fmtEfficiency(efficiency),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Shows a color swatch and the corresponding budget amount.
class _BudgetLegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final double amount;

  /// Creates a legend row for a budget segment.
  const _BudgetLegendRow({
    required this.color,
    required this.label,
    required this.amount,
  });

  /// Builds the segment swatch, label, and formatted amount.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text(_money.format(amount)),
        ],
      ),
    );
  }
}

/// Paints a pie using the current theme's primary and elevated-surface colors.
class _BudgetPiePainter extends CustomPainter {
  final double progress;
  final Color spentColor;
  final Color remainingColor;

  /// Creates a pie painter for the given fraction of the budget spent.
  const _BudgetPiePainter(
    this.progress, {
    required this.spentColor,
    required this.remainingColor,
  });

  /// Draws the spent and remaining portions of the budget.
  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawCircle(
      bounds.center,
      size.shortestSide / 2,
      Paint()..color = remainingColor,
    );
    if (progress <= 0) return;
    canvas.drawArc(
      bounds,
      -math.pi / 2,
      math.pi * 2 * progress,
      true,
      Paint()..color = spentColor,
    );
  }

  /// Repaints only when the spending fraction changes.
  @override
  bool shouldRepaint(_BudgetPiePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.spentColor != spentColor ||
      oldDelegate.remainingColor != remainingColor;
}
