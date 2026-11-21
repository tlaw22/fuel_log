part of 'main.dart';

// ======================= Widgets =======================

/// Displays a friendly placeholder when no fuel entries exist.
class _EmptyState extends StatelessWidget {
  /// Creates the empty log placeholder.
  const _EmptyState();

  /// Builds the empty-state icon and prompt.
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

/// Displays aggregate statistics in a responsive wrapping layout.
class _StatsWrap extends StatelessWidget {
  final Stats stats;

  /// Creates a statistics wrap from the supplied aggregate values.
  const _StatsWrap({required this.stats});

  /// Builds the labels and values for the supplied aggregate statistics.
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

/// Displays a weekly date range and its associated aggregate statistics.
class _WeekRow extends StatelessWidget {
  final WeekGroup week;
  final Stats stats;

  /// Creates a row for the supplied week and statistics.
  const _WeekRow({required this.week, required this.stats});

  /// Builds the weekly summary row.
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
