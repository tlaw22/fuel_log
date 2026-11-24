part of 'app.dart';

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
  final _incomeController = TextEditingController();
  final _insuranceController = TextEditingController();
  final _carPaymentController = TextEditingController();
  double? _budget;
  double _grossIncome = 0;
  double _insurancePayment = 0;
  double _carPayment = 0;
  double _previousInsurancePayment = 0;
  double _previousCarPayment = 0;

  /// Keeps the budget editor alive while navigating between carousel pages.
  @override
  bool get wantKeepAlive => true;

  /// Loads this month's saved budget or carries forward the previous month's.
  @override
  void initState() {
    super.initState();
    unawaited(_loadMonthlyValues());
  }

  /// Releases the budget text controller.
  @override
  void dispose() {
    _budgetController.dispose();
    _incomeController.dispose();
    _insuranceController.dispose();
    _carPaymentController.dispose();
    super.dispose();
  }

  /// Builds the preference key for the specified calendar month.
  String _budgetKey(DateTime month) =>
      '$_monthlyBudgetPrefsKeyPrefix${month.year}_${month.month}';

  String _monthlyValueKey(String name, DateTime month) =>
      'fuel_${name}_${month.year}_${month.month}';

  /// Loads a saved budget for this month, falling back to the previous month.
  Future<void> _loadMonthlyValues() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final previousMonth = DateTime(now.year, now.month - 1);
    final currentMonthBudget = prefs.getDouble(_budgetKey(now));
    final previousMonthBudget = prefs.getDouble(_budgetKey(previousMonth));
    final budget = currentMonthBudget ?? previousMonthBudget;
    if (!mounted) return;
    setState(() {
      _budget = budget;
      _budgetController.text = budget?.toStringAsFixed(2) ?? '';
      _grossIncome = prefs.getDouble(_monthlyValueKey('income', now)) ?? 0;
      _insurancePayment =
          prefs.getDouble(_monthlyValueKey('insurance', now)) ?? 0;
      _carPayment = prefs.getDouble(_monthlyValueKey('car_payment', now)) ?? 0;
      _previousInsurancePayment =
          prefs.getDouble(_monthlyValueKey('insurance', previousMonth)) ?? 0;
      _previousCarPayment =
          prefs.getDouble(_monthlyValueKey('car_payment', previousMonth)) ?? 0;
      _incomeController.text =
          _grossIncome == 0 ? '' : _grossIncome.toStringAsFixed(2);
      _insuranceController.text =
          _insurancePayment == 0 ? '' : _insurancePayment.toStringAsFixed(2);
      _carPaymentController.text =
          _carPayment == 0 ? '' : _carPayment.toStringAsFixed(2);
    });
  }

  /// Parses the editable budget amount entered by the user.
  double? _parseBudget() =>
      double.tryParse(_budgetController.text.trim().replaceAll(',', '.'));

  double? _parseAmount(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '.'));

  /// Saves the entered budget and monthly values with one action.
  Future<void> _saveMonthlyData() async {
    final budgetEntered = _budgetController.text.trim().isNotEmpty;
    final budget = _parseBudget();
    if (budgetEntered && (budget == null || budget <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a budget greater than zero.'),
          duration: kAppSnackBarDuration,
        ),
      );
      return;
    }

    final monthlyValuesEntered = [
      _incomeController,
      _insuranceController,
      _carPaymentController,
    ].any((controller) => controller.text.trim().isNotEmpty);
    final income = _parseAmount(_incomeController);
    final insurance = _parseAmount(_insuranceController);
    final carPayment = _parseAmount(_carPaymentController);
    if (monthlyValuesEntered &&
        (income == null ||
            insurance == null ||
            carPayment == null ||
            income < 0 ||
            insurance < 0 ||
            carPayment < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter valid non-negative monthly amounts.'),
          duration: kAppSnackBarDuration,
        ),
      );
      return;
    }
    if (!budgetEntered && !monthlyValuesEntered) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a budget or monthly details before saving.'),
          duration: kAppSnackBarDuration,
        ),
      );
      return;
    }

    final now = DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (budgetEntered && !await prefs.setDouble(_budgetKey(now), budget!)) {
        throw StateError('The monthly budget was not saved.');
      }
      if (monthlyValuesEntered) {
        if (!await prefs.setDouble(_monthlyValueKey('income', now), income!) ||
            !await prefs.setDouble(
                _monthlyValueKey('insurance', now), insurance!) ||
            !await prefs.setDouble(
                _monthlyValueKey('car_payment', now), carPayment!)) {
          throw StateError('The monthly income and payments were not saved.');
        }
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save monthly data: $error'),
          duration: kAppSnackBarDuration,
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      if (budgetEntered) _budget = budget;
      if (monthlyValuesEntered) {
        _grossIncome = income!;
        _insurancePayment = insurance!;
        _carPayment = carPayment!;
      }
    });
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text('Your data have been saved to the local disk.'),
          duration: kAppSnackBarDuration,
        ),
      );
  }

  /// Opens the sheet for editing this month's budget and payment details.
  Future<void> _showBudgetDataSheet() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        final mediaQuery = MediaQuery.of(sheetContext);
        return Padding(
          padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: mediaQuery.size.height * 0.85,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Monthly budget data',
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey('monthly-budget-input'),
                    controller: _budgetController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Monthly spending budget',
                      prefixText: '$kCurrency ',
                      border: const OutlineInputBorder(),
                      helperText: _budget == null
                          ? 'Enter a budget to compare spending.'
                          : 'The previous month’s budget is carried forward.',
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _saveMonthlyData(),
                  ),
                  const SizedBox(height: 8),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('gross-monthly-income-input'),
                    controller: _incomeController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Gross monthly income',
                      prefixText: '$kCurrency ',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('monthly-insurance-input'),
                    controller: _insuranceController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Monthly insurance payment',
                      prefixText: '$kCurrency ',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('monthly-car-payment-input'),
                    controller: _carPaymentController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Monthly car payment',
                      prefixText: '$kCurrency ',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _saveMonthlyData,
                      child: const Text('Save monthly data'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Builds monthly financial inputs and the spending comparison charts.
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
    final previousMonth = DateTime(now.year, now.month - 1);
    final previousMonthEntries = widget.entries
        .where((entry) =>
            entry.date.year == previousMonth.year &&
            entry.date.month == previousMonth.month)
        .toList();
    final monthStats = Stats.from(monthEntries, widget.distances);
    final previousMonthStats =
        Stats.from(previousMonthEntries, widget.distances);
    final inputBudget = _parseBudget();
    final chartBudget =
        inputBudget != null && inputBudget > 0 ? inputBudget : null;
    final income = _parseAmount(_incomeController) ?? _grossIncome;
    final insurance = _parseAmount(_insuranceController) ?? _insurancePayment;
    final carPayment = _parseAmount(_carPaymentController) ?? _carPayment;
    final currentTravelExpense = monthStats.spent + insurance + carPayment;
    final previousTravelExpense = previousMonthStats.spent +
        _previousInsurancePayment +
        _previousCarPayment;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        FilledButton.icon(
          key: const ValueKey('open-budget-data-sheet'),
          onPressed: _showBudgetDataSheet,
          icon: const Icon(Icons.edit_note),
          label: const Text('Log my budget data'),
        ),
        const SizedBox(height: 12),
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
          showBudgetPercentage: false,
        ),
        const SizedBox(height: 12),
        _MonthlyTravelComparisonChart(
          title:
              '${_monthFmt.format(now)} vs ${_monthFmt.format(previousMonth)}',
          currentTotal: currentTravelExpense,
          previousTotal: previousTravelExpense,
          grossIncome: income,
          fuel: monthStats.spent,
          insurance: insurance,
          carPayment: carPayment,
          previousFuel: previousMonthStats.spent,
          previousInsurance: _previousInsurancePayment,
          previousCarPayment: _previousCarPayment,
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
  final bool showBudgetPercentage;

  /// Creates a chart for the supplied spending total and budget.
  const _BudgetPieChart({
    required this.title,
    required this.spent,
    required this.budget,
    this.distance,
    this.efficiency,
    this.showBudgetPercentage = true,
  });

  /// Builds the pie chart, legend, and budget progress details.
  @override
  Widget build(BuildContext context) {
    final goal = budget;
    final colors = Theme.of(context).colorScheme;
    final remaining = goal == null || spent >= goal ? 0.0 : goal - spent;
    final progress =
        goal == null ? 0.0 : (spent / goal).clamp(0.0, 1.0).toDouble();
    return _CollapsibleChart(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                label: showBudgetPercentage
                    ? '${(progress * 100).round()} percent of budget used'
                    : 'Spending compared to budget',
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
                        if (showBudgetPercentage) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${(spent / goal * 100).round()}% of ${_money.format(goal)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
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
    );
  }
}

class _MonthlyTravelComparisonChart extends StatelessWidget {
  final String title;
  final double currentTotal;
  final double previousTotal;
  final double grossIncome;
  final double fuel;
  final double insurance;
  final double carPayment;
  final double previousFuel;
  final double previousInsurance;
  final double previousCarPayment;

  const _MonthlyTravelComparisonChart({
    required this.title,
    required this.currentTotal,
    required this.previousTotal,
    required this.grossIncome,
    required this.fuel,
    required this.insurance,
    required this.carPayment,
    required this.previousFuel,
    required this.previousInsurance,
    required this.previousCarPayment,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final total = currentTotal + previousTotal;
    final currentShare =
        total == 0 ? 0.0 : (currentTotal / total).clamp(0.0, 1.0).toDouble();
    return _CollapsibleChart(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Semantics(
              label:
                  'Current month travel expenses compared with the previous month',
              child: CustomPaint(
                size: const Size.square(180),
                painter: _BudgetPiePainter(
                  currentShare,
                  spentColor: colors.primary,
                  remainingColor: colors.surfaceContainerHighest,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _BudgetLegendRow(
            color: colors.primary,
            label: 'Current month travel expenses',
            amount: currentTotal,
          ),
          _BudgetLegendRow(
            color: colors.surfaceContainerHighest,
            label: 'Previous month travel expenses',
            amount: previousTotal,
          ),
          const Divider(height: 20),
          _BudgetLegendRow(
            color: colors.primary,
            label: 'Fuel this month',
            amount: fuel,
          ),
          _BudgetLegendRow(
            color: colors.surfaceContainerHighest,
            label: 'Insurance payment',
            amount: insurance,
          ),
          _BudgetLegendRow(
            color: colors.secondary,
            label: 'Car payment',
            amount: carPayment,
          ),
          _BudgetLegendRow(
            color: colors.primary,
            label: 'Previous month fuel',
            amount: previousFuel,
          ),
          _BudgetLegendRow(
            color: colors.surfaceContainerHighest,
            label: 'Previous month insurance',
            amount: previousInsurance,
          ),
          _BudgetLegendRow(
            color: colors.secondary,
            label: 'Previous month car payment',
            amount: previousCarPayment,
          ),
          _BudgetLegendRow(
            color: colors.primary,
            label: 'Gross monthly income',
            amount: grossIncome,
          ),
          _BudgetLegendRow(
            color: colors.surfaceContainerHighest,
            label: 'Income after travel expenses',
            amount: grossIncome - currentTotal,
          ),
        ],
      ),
    );
  }
}

class _CollapsibleChart extends StatefulWidget {
  final String title;
  final Widget child;

  const _CollapsibleChart({
    required this.title,
    required this.child,
  });

  @override
  State<_CollapsibleChart> createState() => _CollapsibleChartState();
}

class _CollapsibleChartState extends State<_CollapsibleChart> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              button: true,
              expanded: _expanded,
              child: InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 12),
              widget.child,
            ],
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
