/// Custom chart metric definitions and calculations.
/// Loads chart selections and derives the values shown in charts and notifications.
part of 'app.dart';

enum _CustomChartMetric {
  currentTravel('Current month travel expenses'),
  previousTravel('Previous month travel expenses'),
  allTimeFuel('All-time fuel spending'),
  currentFuel('Fuel this month'),
  previousFuel('Previous month fuel'),
  currentInsurance('Insurance payment'),
  previousInsurance('Previous month insurance'),
  currentCarPayment('Car payment'),
  previousCarPayment('Previous month car payment'),
  income('Gross monthly income'),
  incomeAfterTravel('Income after travel expenses'),
  budget('Monthly spending budget'),
  budgetRemaining('Remaining monthly budget');

  const _CustomChartMetric(this.label);

  final String label;
}

class _CustomChartSelection {
  static const preferenceKey = 'fuel_custom_chart_selection_v1';
  static const defaults = _CustomChartSelection(
    _CustomChartMetric.currentTravel,
    _CustomChartMetric.previousTravel,
  );
  static Future<void>? _pendingSave;

  final _CustomChartMetric first;
  final _CustomChartMetric second;

  const _CustomChartSelection(this.first, this.second);

  static Future<_CustomChartSelection> load(SharedPreferences prefs) async {
    final pending = _pendingSave;
    if (pending != null) await pending;
    final saved = prefs.getStringList(preferenceKey);
    if (saved == null) return defaults;
    if (saved.length != 2) {
      throw const FormatException('Invalid custom chart selection.');
    }
    _CustomChartMetric parse(String name) =>
        _CustomChartMetric.values.firstWhere((metric) => metric.name == name,
            orElse: () =>
                throw FormatException('Unknown custom chart metric: $name'));
    return _CustomChartSelection(parse(saved[0]), parse(saved[1]));
  }

  Future<void> save() {
    final previous = _pendingSave;
    final result = () async {
      if (previous != null) await previous;
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs
          .setStringList(preferenceKey, [first.name, second.name])) {
        throw StateError('The custom chart selection was not saved.');
      }
    }();
    final pending =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _pendingSave = pending;
    pending.whenComplete(() {
      if (identical(_pendingSave, pending)) _pendingSave = null;
    });
    return result;
  }
}

class _CustomChartValues {
  final Map<_CustomChartMetric, double?> amounts;

  _CustomChartValues(
      List<FuelEntry> entries, SharedPreferences prefs, DateTime now,
      {double lunchSpent = 0})
      : amounts = _calculate(entries, prefs, now, lunchSpent);

  static Map<_CustomChartMetric, double?> _calculate(
    List<FuelEntry> entries,
    SharedPreferences prefs,
    DateTime now,
    double lunchSpent,
  ) {
    final previous = DateTime(now.year, now.month - 1);
    var fuel = 0.0;
    var previousFuel = 0.0;
    var allTimeFuel = 0.0;
    for (final entry in entries) {
      final amount = entry.total;
      allTimeFuel += amount;
      if (entry.date.year == now.year && entry.date.month == now.month) {
        fuel += amount;
      } else if (entry.date.year == previous.year &&
          entry.date.month == previous.month) {
        previousFuel += amount;
      }
    }
    double monthly(String key, DateTime month) =>
        prefs.getDouble(_monthlyValueKey(key, month)) ?? 0;
    final insurance = monthly('insurance', now);
    final previousInsurance = monthly('insurance', previous);
    final carPayment = monthly('car_payment', now);
    final previousCarPayment = monthly('car_payment', previous);
    final income = monthly('income', now);
    final currentTravel = _travelExpense(fuel, insurance, carPayment);
    final budget = prefs.getDouble(_monthlyValueKey('monthly_budget', now)) ??
        prefs.getDouble(_monthlyValueKey('monthly_budget', previous));
    return {
      _CustomChartMetric.currentTravel: currentTravel,
      _CustomChartMetric.previousTravel:
          _travelExpense(previousFuel, previousInsurance, previousCarPayment),
      _CustomChartMetric.allTimeFuel: allTimeFuel,
      _CustomChartMetric.currentFuel: fuel,
      _CustomChartMetric.previousFuel: previousFuel,
      _CustomChartMetric.currentInsurance: insurance,
      _CustomChartMetric.previousInsurance: previousInsurance,
      _CustomChartMetric.currentCarPayment: carPayment,
      _CustomChartMetric.previousCarPayment: previousCarPayment,
      _CustomChartMetric.income: income,
      _CustomChartMetric.incomeAfterTravel: income - currentTravel,
      _CustomChartMetric.budget: budget,
      _CustomChartMetric.budgetRemaining: budget == null
          ? null
          : math.max(0, budget - fuel - lunchSpent).toDouble(),
    };
  }
}
