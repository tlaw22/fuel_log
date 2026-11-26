part of '../app.dart';

/// Shows all-time and current-month spending against an editable monthly budget.
class ChartsPage extends StatefulWidget {
  final List<FuelEntry> entries;
  final Map<String, double> distances;
  final bool _includeLunch;
  final List<_LunchEntry> _lunchEntries;
  final String? _lunchLoadError;
  final VoidCallback? _onRetryLunch;
  final ValueChanged<bool>? _onIncludeLunchChanged;

  /// Creates the charts page for the supplied fuel entries.
  const ChartsPage({
    super.key,
    required this.entries,
    required this.distances,
  })  : _includeLunch = false,
        _lunchEntries = const [],
        _lunchLoadError = null,
        _onRetryLunch = null,
        _onIncludeLunchChanged = null;

  const ChartsPage._withLunch({
    super.key,
    required this.entries,
    required this.distances,
    required bool includeLunch,
    required List<_LunchEntry> lunchEntries,
    required String? lunchLoadError,
    required VoidCallback onRetryLunch,
    required ValueChanged<bool> onIncludeLunchChanged,
  })  : _includeLunch = includeLunch,
        _lunchEntries = lunchEntries,
        _lunchLoadError = lunchLoadError,
        _onRetryLunch = onRetryLunch,
        _onIncludeLunchChanged = onIncludeLunchChanged;

  /// Creates state for loading and editing this month's spending budget.
  @override
  State<ChartsPage> createState() => _ChartsPageState();
}

/// Loads the monthly budget and builds spending charts from the current entries.
class _ChartsPageState extends State<ChartsPage>
    with AutomaticKeepAliveClientMixin<ChartsPage> {
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
  SharedPreferences? _customChartPrefs;
  _CustomChartSelection? _customSelection;
  String? _customChartError;

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

  /// Loads a saved budget for this month, falling back to the previous month.
  Future<void> _loadMonthlyValues() async {
    try {
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
        _carPayment =
            prefs.getDouble(_monthlyValueKey('car_payment', now)) ?? 0;
        _previousInsurancePayment =
            prefs.getDouble(_monthlyValueKey('insurance', previousMonth)) ?? 0;
        _previousCarPayment =
            prefs.getDouble(_monthlyValueKey('car_payment', previousMonth)) ??
                0;
        _incomeController.text =
            _grossIncome == 0 ? '' : _grossIncome.toStringAsFixed(2);
        _insuranceController.text =
            _insurancePayment == 0 ? '' : _insurancePayment.toStringAsFixed(2);
        _carPaymentController.text =
            _carPayment == 0 ? '' : _carPayment.toStringAsFixed(2);
      });
      final customSelection = await _CustomChartSelection.load(prefs);
      if (!mounted) return;
      setState(() {
        _customChartPrefs = prefs;
        _customSelection = customSelection;
        _customChartError = null;
      });
    } catch (error, stackTrace) {
      _reportCustomChartError('load', error, stackTrace);
      if (mounted) setState(() => _customChartError = error.toString());
    }
  }

  void _reportCustomChartError(String action, Object error, StackTrace stack) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'FuelLog custom chart',
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Could not $action custom chart settings: $error'),
      duration: kAppSnackBarDuration,
    ));
  }

  void _changeCustomSelection(_CustomChartSelection selection) {
    setState(() => _customSelection = selection);
    unawaited(_saveCustomSelection(selection));
  }

  Future<void> _saveCustomSelection(_CustomChartSelection selection) async {
    try {
      await selection.save();
    } catch (error, stackTrace) {
      _reportCustomChartError('save', error, stackTrace);
    }
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
    final control = _LunchInclusionControl(
      key: const ValueKey('include-lunch-charts'),
      included: widget._includeLunch,
      onChanged: widget._onIncludeLunchChanged,
    );
    if (widget._includeLunch && widget._lunchLoadError != null) {
      return ListView(
        key: const ValueKey('charts-scroll'),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          _PageReveal(
            index: 0,
            child: _LunchDataError(
              error: widget._lunchLoadError!,
              onRetry: widget._onRetryLunch,
            ),
          ),
          const SizedBox(height: 16),
          _PageReveal(index: 1, child: control),
        ],
      );
    }
    final now = DateTime.now();
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
    final currentTravelExpense =
        _travelExpense(monthStats.spent, insurance, carPayment);
    final previousTravelExpense = _travelExpense(previousMonthStats.spent,
        _previousInsurancePayment, _previousCarPayment);
    final currentLunch = _lunchTotal(widget._lunchEntries.where((entry) =>
        entry.date.year == now.year && entry.date.month == now.month));
    final previousLunch = _lunchTotal(widget._lunchEntries.where((entry) =>
        entry.date.year == previousMonth.year &&
        entry.date.month == previousMonth.month));

    return ListView(
      key: const ValueKey('charts-scroll'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        _PageReveal(
          key: const ValueKey('reveal-charts-budget'),
          index: 0,
          child: FilledButton.icon(
            key: const ValueKey('open-budget-data-sheet'),
            onPressed: _showBudgetDataSheet,
            icon: const Icon(Icons.edit_note),
            label: const Text('Log my budget data'),
          ),
        ),
        const SizedBox(height: 12),
        _PageReveal(
          key: const ValueKey('reveal-charts-spending'),
          index: 1,
          child: _BudgetPieChart(
            title: '${_monthFmt.format(now)} spending',
            spent: monthStats.spent,
            lunchSpent: widget._includeLunch ? currentLunch : null,
            budget: chartBudget,
            distance: monthStats.distance,
            efficiency: monthStats.efficiency,
          ),
        ),
        const SizedBox(height: 12),
        _PageReveal(
          key: const ValueKey('reveal-charts-comparison'),
          index: 2,
          child: _MonthlyTravelComparisonChart(
          title:
              '${_monthFmt.format(now)} vs ${_monthFmt.format(previousMonth)}',
          currentTotal: currentTravelExpense + (widget._includeLunch ? currentLunch : 0),
          previousTotal: previousTravelExpense + (widget._includeLunch ? previousLunch : 0),
          currentLunch: widget._includeLunch ? currentLunch : null,
          previousLunch: widget._includeLunch ? previousLunch : null,
          grossIncome: income,
          fuel: monthStats.spent,
          insurance: insurance,
          carPayment: carPayment,
          previousFuel: previousMonthStats.spent,
          previousInsurance: _previousInsurancePayment,
          previousCarPayment: _previousCarPayment,
          distance: monthStats.distance,
          ),
        ),
        const SizedBox(height: 12),
        _PageReveal(
          key: const ValueKey('reveal-charts-custom'),
          index: 3,
          child: _customChartError != null
              ? _CollapsibleChart(
            title: 'Custom Chart',
            child: Text('Could not load custom chart: $_customChartError'),
          )
              : _customChartPrefs == null || _customSelection == null
                  ? const _CollapsibleChart(
            title: 'Custom Chart',
            child: Center(child: CircularProgressIndicator()),
          )
                  : _CustomComparisonChart(
            selection: _customSelection!,
            values: _CustomChartValues(widget.entries, _customChartPrefs!, now,
                lunchSpent: widget._includeLunch ? currentLunch : 0),
            onChanged: _changeCustomSelection,
            lunchSpent: widget._includeLunch ? currentLunch : null,
          ),
        ),
        const SizedBox(height: 16),
        _PageReveal(
          key: const ValueKey('reveal-charts-control'),
          index: 4,
          child: control,
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
  final double? lunchSpent;

  /// Creates a chart for the supplied spending total and budget.
  const _BudgetPieChart({
    required this.title,
    required this.spent,
    required this.budget,
    this.distance,
    this.efficiency,
    this.lunchSpent,
  });

  /// Builds the pie chart, legend, and budget progress details.
  @override
  Widget build(BuildContext context) {
    final goal = budget;
    final colors = Theme.of(context).colorScheme;
    final totalSpent = spent + (lunchSpent ?? 0);
    final remaining = goal == null || totalSpent >= goal ? 0.0 : goal - totalSpent;
    final denominator = goal == null ? 1.0 : math.max(goal, totalSpent);
    final progress = goal == null ? 0.0 : spent / denominator;
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
          else
            _ChartSummary(
              progress: progress,
              thirdProgress: lunchSpent == null ? null : lunchSpent! / denominator,
              semanticsLabel: lunchSpent == null
                  ? 'Spent and remaining budget'
                  : 'Fuel, remaining budget and lunch',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BudgetLegendRow(
                    color: colors.primary,
                    label: lunchSpent == null ? 'Spent' : 'Fuel spent',
                    amount: spent,
                  ),
                  _BudgetLegendRow(
                    color: colors.surfaceContainerHighest,
                    label: 'Remaining',
                    amount: remaining,
                  ),
                  if (lunchSpent != null)
                    _BudgetLegendRow(
                      color: _lunchPieColor(colors),
                      label: 'Lunch this month',
                      amount: lunchSpent,
                    ),
                  if (totalSpent > goal)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Over budget by ${_money.format(totalSpent - goal)}',
                        style: TextStyle(color: colors.error),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    '${(totalSpent / goal * 100).round()}% of ${_money.format(goal)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          if (distance != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Miles driven',
                          style: Theme.of(context).textTheme.bodySmall),
                      Text('${_num1.format(distance)} $kDistanceUnit',
                          style: Theme.of(context).textTheme.titleSmall),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Fuel efficiency',
                          style: Theme.of(context).textTheme.bodySmall),
                      Text(fmtEfficiency(efficiency),
                          style: Theme.of(context).textTheme.titleSmall),
                    ],
                  ),
                ),
              ],
            ),
          ],
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
  final double distance;
  final double? currentLunch;
  final double? previousLunch;

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
    required this.distance,
    this.currentLunch,
    this.previousLunch,
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
          _ChartSummary(
            progress: total == 0 ? null : currentShare,
            semanticsLabel: currentLunch == null
                ? 'Current and previous month travel expenses'
                : 'Current and previous month travel and lunch expenses',
            child: Column(
              children: [
                _BudgetLegendRow(
                  color: colors.primary,
                  label: currentLunch == null ? 'Current month travel expenses' : 'Current month travel and lunch',
                  amount: currentTotal,
                ),
                _BudgetLegendRow(
                  color: colors.surfaceContainerHighest,
                  label: currentLunch == null ? 'Previous month travel expenses' : 'Previous month travel and lunch',
                  amount: previousTotal,
                ),
              ],
            ),
          ),
          const Divider(height: 20),
          Text(
            'Total distance traveled this month: '
            '${_num1.format(distance)} $kDistanceUnit',
          ),
          const SizedBox(height: 8),
          _BudgetLegendRow(
            color: colors.primary,
            label: 'Fuel this month',
            amount: fuel,
          ),
          if (currentLunch != null)
            _BudgetLegendRow(
              color: _lunchPieColor(colors),
              label: 'Lunch this month',
              amount: currentLunch,
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
          if (previousLunch != null)
            _BudgetLegendRow(
              color: _lunchPieColor(colors),
              label: 'Previous month lunch',
              amount: previousLunch,
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
            label: currentLunch == null ? 'Income after travel expenses' : 'Income after travel and lunch',
            amount: grossIncome - currentTotal,
          ),
        ],
      ),
    );
  }
}

class _CustomComparisonChart extends StatelessWidget {
  final _CustomChartSelection selection;
  final _CustomChartValues values;
  final ValueChanged<_CustomChartSelection> onChanged;
  final double? lunchSpent;

  const _CustomComparisonChart({
    required this.selection,
    required this.values,
    required this.onChanged,
    this.lunchSpent,
  });

  @override
  Widget build(BuildContext context) {
    final first = values.amounts[selection.first];
    final second = values.amounts[selection.second];
    final negative =
        (first != null && first < 0) || (second != null && second < 0);
    final total = (first ?? 0) + (second ?? 0) + (lunchSpent ?? 0);
    final progress = negative || first == null || second == null || total == 0
        ? null
        : first / total;
    final colors = Theme.of(context).colorScheme;

    Widget selector(String label, _CustomChartMetric selected,
        ValueChanged<_CustomChartMetric> onSelected) {
      final accent = colors.brightness == Brightness.dark
          ? colors.primary
          : colors.onSurface;
      return InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: colors.onSurface),
          filled: true,
          fillColor: colors.surfaceContainerHighest,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: accent, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: accent, width: 2),
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<_CustomChartMetric>(
            key: ValueKey('custom-chart-$label'),
            value: selected,
            isExpanded: true,
            iconEnabledColor: accent,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: colors.onSurface),
            menuWidth: math.min(MediaQuery.sizeOf(context).width - 32, 360),
            items: [
              for (final metric in _CustomChartMetric.values)
                DropdownMenuItem(
                  value: metric,
                  child: Text(metric.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) {
              if (value != null) onSelected(value);
            },
          ),
        ),
      );
    }

    return _CollapsibleChart(
      title: 'Custom Chart',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'select two values to compare',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: selector('First amount', selection.first, (value) {
                          onChanged(
                              _CustomChartSelection(value, selection.second));
                        }),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child:
                            selector('Second amount', selection.second, (value) {
                          onChanged(
                              _CustomChartSelection(selection.first, value));
                        }),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _ChartSummary(
            progress: progress,
            thirdProgress: progress == null || lunchSpent == null ? null : lunchSpent! / total,
            emptyLabel: negative ? 'Negative amount' : 'No data',
            semanticsLabel:
                '${selection.first.label} and ${selection.second.label}'
                '${lunchSpent == null ? '' : ' and lunch this month'}',
            child: Column(
              children: [
                _BudgetLegendRow(
                  color: colors.primary,
                  label: selection.first.label,
                  amount: first,
                ),
                _BudgetLegendRow(
                  color: colors.surfaceContainerHighest,
                  label: selection.second.label,
                  amount: second,
                ),
                if (lunchSpent != null)
                  _BudgetLegendRow(
                    color: _lunchPieColor(colors),
                    label: 'Lunch this month',
                    amount: lunchSpent,
                  ),
                if (lunchSpent != null)
                  Text('Selected amounts can overlap.',
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartSummary extends StatelessWidget {
  final double? progress;
  final double? thirdProgress;
  final String semanticsLabel;
  final String emptyLabel;
  final Widget child;

  const _ChartSummary({
    required this.progress,
    this.thirdProgress,
    required this.semanticsLabel,
    required this.child,
    this.emptyLabel = 'No data',
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final firstPercent = ((progress ?? 0) * 100).round();
    final secondPercent = ((1 - (progress ?? 0) - (thirdProgress ?? 0)) * 100)
        .round()
        .clamp(0, 100 - firstPercent);
    final thirdPercent = 100 - firstPercent - secondPercent;
    final percentageText = progress == null
        ? emptyLabel
        : thirdProgress == null
            ? '$firstPercent% / $secondPercent%'
            : '$firstPercent% / $secondPercent% / $thirdPercent%';

    return LayoutBuilder(
      builder: (context, constraints) {
        final chartSize = math.min(120.0, constraints.maxWidth * 0.36);
        return Row(
          children: [
            Expanded(child: child),
            const SizedBox(width: 12),
            Semantics(
              label: progress == null
                  ? '$semanticsLabel: $emptyLabel'
                  : '$semanticsLabel: $firstPercent percent and '
                      '$secondPercent percent'
                      '${thirdProgress == null ? '' : ' and $thirdPercent percent'}',
              child: ExcludeSemantics(
                child: SizedBox.square(
                  dimension: chartSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: Size.square(chartSize),
                        painter: _BudgetPiePainter(
                          progress ?? 0,
                          spentColor: colors.primary,
                          remainingColor: colors.surfaceContainerHighest,
                          thirdProgress: thirdProgress ?? 0,
                          thirdColor: _lunchPieColor(colors),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 3,
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                percentageText,
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
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
  final double? amount;

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
          Text(amount == null ? 'Not set' : _money.format(amount)),
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
  final double thirdProgress;
  final Color? thirdColor;

  /// Creates a pie painter for the given fraction of the budget spent.
  const _BudgetPiePainter(
    this.progress, {
    required this.spentColor,
    required this.remainingColor,
    this.thirdProgress = 0,
    this.thirdColor,
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
    if (progress > 0) {
      canvas.drawArc(
        bounds,
        -math.pi / 2,
        math.pi * 2 * progress,
        true,
        Paint()..color = spentColor,
      );
    }
    if (thirdProgress > 0) {
      canvas.drawArc(
        bounds,
        -math.pi / 2 + math.pi * 2 * (1 - thirdProgress),
        math.pi * 2 * thirdProgress,
        true,
        Paint()..color = thirdColor!,
      );
    }
  }

  /// Repaints only when the spending fraction changes.
  @override
  bool shouldRepaint(_BudgetPiePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.spentColor != spentColor ||
      oldDelegate.remainingColor != remainingColor ||
      oldDelegate.thirdProgress != thirdProgress ||
      oldDelegate.thirdColor != thirdColor;
}

Color _lunchPieColor(ColorScheme colors) =>
    colors.brightness == Brightness.dark ? Colors.deepOrange.shade300 : Colors.deepOrange.shade700;
