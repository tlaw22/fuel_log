/// Shared loading, empty-state, statistics, and reveal widgets.
/// Provides reusable presentation components used across FuelLog pages.
part of '../app.dart';

// ======================= Widgets =======================

/// Shows a spinner or a recoverable local-data loading error.
class _StartupLoadingScreen extends StatelessWidget {
  final String? error;
  final VoidCallback onRetry;

  const _StartupLoadingScreen({
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: SafeArea(
        child: Center(
          child: error == null
              ? const CircularProgressIndicator(
                  key: ValueKey('startup-spinner'),
                  color: kBlue,
                  semanticsLabel: 'Loading local data',
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Could not load local data: $error',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.black87),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: onRetry,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Displays a friendly placeholder when no fuel entries exist.
class _EmptyState extends StatelessWidget {
  /// Creates the empty log placeholder.
  const _EmptyState();

  /// Builds the empty-state icon and prompt.
  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
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
      ),
    );
  }
}

/// Displays aggregate statistics in a responsive wrapping layout.
class _StatsWrap extends StatelessWidget {
  final Stats stats;
  final double? lunchSpent;

  /// Creates a statistics wrap from the supplied aggregate values.
  const _StatsWrap({required this.stats, this.lunchSpent});

  /// Builds the labels and values for the supplied aggregate statistics.
  @override
  Widget build(BuildContext context) {
    final items = <(String, String)>[
      if (lunchSpent == null)
        ('Spent', _money.format(stats.spent))
      else ...[
        ('Fuel spent', _money.format(stats.spent)),
        ('Lunch spent', _money.format(lunchSpent)),
        ('Combined spent', _money.format(stats.spent + lunchSpent!)),
      ],
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
  final double? lunchSpent;

  /// Creates a row for the supplied week and statistics.
  const _WeekRow({required this.week, required this.stats, this.lunchSpent});

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
              '${lunchSpent == null ? _money.format(stats.spent) : 'Fuel ${_money.format(stats.spent)} · Lunch ${_money.format(lunchSpent)} · Combined ${_money.format(stats.spent + lunchSpent!)}'}'
              '  ·  ${_num1.format(stats.volume)} $kVolumeUnit\n'
              '${_num1.format(stats.distance)} $kDistanceUnit  ·  ${fmtEfficiency(stats.efficiency)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _LunchInclusionControl extends StatelessWidget {
  const _LunchInclusionControl({
    super.key,
    required this.included,
    required this.onChanged,
  });

  final bool included;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Include lunch', style: Theme.of(context).textTheme.labelLarge),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Off')),
              ButtonSegment(value: true, label: Text('On')),
            ],
            selected: {included},
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onSelectionChanged: onChanged == null
                ? null
                : (values) => onChanged!(values.single),
          ),
        ],
      );
}

class _LunchDataError extends StatelessWidget {
  const _LunchDataError({required this.error, required this.onRetry});

  final String error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Could not load lunch data: $error'),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      );
}
