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

/// Finds nearby fuel stations and shows the phone's saved totals.
class FuelStationsPage extends StatefulWidget {
  final List<FuelEntry> entries;
  final Map<String, double> distances;

  /// Creates the station finder for the supplied fuel log snapshot.
  const FuelStationsPage({
    super.key,
    required this.entries,
    required this.distances,
  });

  @override
  State<FuelStationsPage> createState() => _FuelStationsPageState();
}

class _FuelStationsPageState extends State<FuelStationsPage> {
  List<NearbyFuelStation> _stations = [];
  bool _loading = false;
  bool _backgroundPermissionMissing = false;
  bool _backgroundPermissionNeedsSettings = false;
  String? _error;

  Future<void> _findStations() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var foregroundPermission = await Permission.locationWhenInUse.status;
      if (!foregroundPermission.isGranted) {
        foregroundPermission = await Permission.locationWhenInUse.request();
      }
      if (!mounted) return;
      if (!foregroundPermission.isGranted) {
        setState(() {
          _error = 'Allow location access to find nearby fuel stations.';
        });
        return;
      }

      var backgroundPermission = await Permission.locationAlways.status;
      if (!backgroundPermission.isGranted) {
        backgroundPermission = await Permission.locationAlways.request();
      }
      if (!mounted) return;
      setState(() {
        _backgroundPermissionMissing = !backgroundPermission.isGranted;
        _backgroundPermissionNeedsSettings =
            backgroundPermission.isPermanentlyDenied ||
                backgroundPermission.isRestricted;
      });

      final response = await _androidNativeChannel
          .invokeListMethod<Object?>('findNearbyFuelStations');
      if (!mounted) return;
      final stations = (response ?? const <Object?>[]).map((value) {
        if (value is! Map<Object?, Object?>) {
          throw const FormatException('Station result was not an object.');
        }
        return NearbyFuelStation.fromMap(value);
      }).toList();
      setState(() {
        _stations = stations;
        _error = null;
      });
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message ?? 'Could not load nearby fuel stations.';
        });
      }
    } on MissingPluginException {
      if (mounted) {
        setState(() {
          _error = 'Nearby station search is available on Android devices.';
        });
      }
    } on FormatException catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Could not read station results: ${error.message}';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _AutoOutputPanel(
          title: 'Totals from this phone',
          children: [
            Text(_monthFmt.format(now)),
            const SizedBox(height: 8),
            _StatsWrap(stats: monthStats),
            const Divider(height: 24),
            const Text('All time'),
            const SizedBox(height: 8),
            _StatsWrap(stats: allTimeStats),
          ],
        ),
        const SizedBox(height: 12),
        _AutoOutputPanel(
          title: 'Nearby fuel stations',
          children: [
            const Text(
              'Your location is sent to OpenStreetMap only when you search. '
              'Allow location access all the time to search from Android Auto.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _findStations,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.local_gas_station),
              label: Text(_loading ? 'Searching...' : 'Find nearby stations'),
            ),
            if (_backgroundPermissionMissing) ...[
              const SizedBox(height: 8),
              const Text(
                'Phone search still works, but Android Auto needs background '
                'location permission while the car screen is active.',
              ),
              if (_backgroundPermissionNeedsSettings)
                const TextButton(
                  onPressed: openAppSettings,
                  child: Text('Open location settings'),
                ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!),
            ],
            if (_stations.isNotEmpty) ...[
              const Divider(height: 24),
              for (final station in _stations)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.local_gas_station, color: kGold),
                  title: Text(station.name),
                  subtitle: Text(
                    [
                      '${(station.distanceMeters / 1609.344).toStringAsFixed(1)} mi',
                      if (station.brand.isNotEmpty) station.brand,
                      if (station.address.isNotEmpty) station.address,
                    ].join(' · '),
                  ),
                ),
            ] else if (!_loading && _error == null) ...[
              const SizedBox(height: 12),
              const Text('Tap Find nearby stations to search within 10 km.'),
            ],
            const SizedBox(height: 8),
            const Text(
              'Station data © OpenStreetMap contributors.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

class NearbyFuelStation {
  final String id;
  final String name;
  final String brand;
  final String address;
  final double latitude;
  final double longitude;
  final double distanceMeters;

  const NearbyFuelStation({
    required this.id,
    required this.name,
    required this.brand,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
  });

  factory NearbyFuelStation.fromMap(Map<Object?, Object?> map) {
    return NearbyFuelStation(
      id: _requiredString(map, 'id'),
      name: _requiredString(map, 'name'),
      brand: map['brand'] as String? ?? '',
      address: map['address'] as String? ?? '',
      latitude: _requiredNumber(map, 'latitude'),
      longitude: _requiredNumber(map, 'longitude'),
      distanceMeters: _requiredNumber(map, 'distanceMeters'),
    );
  }

  static String _requiredString(Map<Object?, Object?> map, String key) {
    final value = map[key];
    if (value is String) return value;
    throw FormatException('Missing station field "$key".');
  }

  static double _requiredNumber(Map<Object?, Object?> map, String key) {
    final value = map[key];
    if (value is num) return value.toDouble();
    throw FormatException('Missing numeric station field "$key".');
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
