part of 'main.dart';

/// Tracks chunks received for one nearby snapshot transfer.
class _IncomingTransfer {
  final int total;
  final Map<int, List<dynamic>> chunks = {};

  /// Creates transfer state for the expected number of snapshot chunks.
  _IncomingTransfer(this.total);
}

/// Screen and callbacks for exchanging fuel data with a nearby Android phone.
class NearbySyncPage extends StatefulWidget {
  final SyncSnapshot Function() snapshot;
  final Future<int> Function(SyncSnapshot snapshot) onSnapshotReceived;

  /// Creates a nearby sync page with snapshot and merge callbacks.
  const NearbySyncPage({
    super.key,
    required this.snapshot,
    required this.onSnapshotReceived,
  });

  /// Creates the nearby sync page state.
  @override
  State<NearbySyncPage> createState() => _NearbySyncPageState();
}

/// State that manages nearby discovery, connection, permissions, and transfer protocol.
class _NearbySyncPageState extends State<NearbySyncPage> {
  static const _protocol = 'fuel-log-sync-v1';
  static const _maxMessageBytes = 24000;
  static const _maxChunkRecords = 40;

  late final Nearby _nearby;
  final Map<String, String> _devices = {};
  String? _connectedDeviceId;
  String? _connectedDeviceName;
  String? _authenticationToken;
  final Map<String, _IncomingTransfer> _incomingTransfers = {};
  bool _starting = true;
  bool _serviceInitialized = false;
  bool _connectionEstablished = false;
  bool _localReady = false;
  bool _remoteReady = false;
  bool _snapshotSent = false;
  bool _processingTransfer = false;
  bool _complete = false;
  String? _error;

  /// Starts nearby synchronization after the first frame.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_start());
    });
  }

  /// Requests permissions and starts nearby advertising and discovery.
  Future<void> _start() async {
    try {
      if (!Platform.isAndroid) {
        throw UnsupportedError(
            'Nearby sync is currently available on Android only.');
      }

      final sdkInt =
          await _androidNativeChannel.invokeMethod<int>('androidSdkInt');
      if (sdkInt == null) {
        throw StateError('Could not determine the Android version.');
      }

      if (sdkInt <= 32) {
        final location = await Permission.locationWhenInUse.request();
        if (!location.isGranted) {
          throw StateError('Location permission is required for nearby sync.');
        }
      }

      final bluetoothPermissions = sdkInt >= 31
          ? <Permission>[
              Permission.bluetoothScan,
              Permission.bluetoothConnect,
              Permission.bluetoothAdvertise,
            ]
          : <Permission>[Permission.bluetooth];
      final bluetoothResults = await bluetoothPermissions.request();
      if (bluetoothResults.values.any((status) => !status.isGranted)) {
        throw StateError(
          'Bluetooth permissions are required for nearby sync.',
        );
      }

      if (sdkInt >= 33) {
        final nearbyWifi = await Permission.nearbyWifiDevices.request();
        if (!nearbyWifi.isGranted) {
          throw StateError(
            'Nearby devices permission is required for nearby sync.',
          );
        }
      }

      if (!await Permission.location.serviceStatus.isEnabled) {
        throw StateError('Turn on Location/GPS to discover nearby phones.');
      }

      _nearby = Nearby();
      _serviceInitialized = true;
      final advertisingStarted = await _nearby.startAdvertising(
        'FuelLog',
        Strategy.P2P_POINT_TO_POINT,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
      if (!advertisingStarted) {
        throw StateError('Nearby advertising could not start.');
      }
      final discoveryStarted = await _nearby.startDiscovery(
        'FuelLog',
        Strategy.P2P_POINT_TO_POINT,
        onEndpointFound: _onEndpointFound,
        onEndpointLost: _onEndpointLost,
      );
      if (!discoveryStarted) {
        throw StateError('Nearby phone discovery could not start.');
      }
      if (mounted) setState(() => _starting = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _starting = false;
          _error = 'Could not start nearby sync: $e';
        });
      }
    }
  }

  /// Records a discovered nearby device.
  void _onEndpointFound(String deviceId, String name, String serviceId) {
    if (!mounted) return;
    setState(() => _devices[deviceId] = name);
  }

  /// Removes a nearby device that is no longer discoverable.
  void _onEndpointLost(String? deviceId) {
    if (!mounted || deviceId == null) return;
    setState(() => _devices.remove(deviceId));
  }

  /// Accepts connection details and prepares the sync handshake.
  void _onConnectionInitiated(String deviceId, ConnectionInfo info) {
    if (!mounted) return;
    setState(() {
      _connectedDeviceId = deviceId;
      _connectedDeviceName = info.endpointName;
      _authenticationToken = info.authenticationToken;
      _connectionEstablished = false;
      _localReady = false;
      _remoteReady = false;
      _snapshotSent = false;
      _complete = false;
      _incomingTransfers.clear();
    });
    unawaited(_acceptConnection(deviceId));
  }

  /// Accepts a requested nearby connection and begins byte payload handling.
  Future<void> _acceptConnection(String deviceId) async {
    try {
      final accepted = await _nearby.acceptConnection(
        deviceId,
        onPayLoadRecieved: _onPayloadReceived,
      );
      if (!accepted) _showError('The nearby connection was not accepted.');
    } catch (e) {
      _showError('Could not accept the nearby connection: $e');
    }
  }

  /// Updates connection status after the nearby library reports success or failure.
  void _onConnectionResult(String deviceId, Status status) {
    if (!mounted) return;
    if (status == Status.CONNECTED) {
      setState(() {
        _connectedDeviceId = deviceId;
        _connectionEstablished = true;
        _error = null;
      });
      unawaited(_nearby.stopDiscovery());
    } else {
      setState(() {
        _connectedDeviceId = null;
        _connectedDeviceName = null;
        _authenticationToken = null;
        _connectionEstablished = false;
      });
      _showError('Nearby connection failed: $status');
    }
  }

  /// Clears connection state and resumes discovery when a phone disconnects.
  void _onDisconnected(String deviceId) {
    if (!mounted || _connectedDeviceId != deviceId) return;
    setState(() {
      _connectedDeviceId = null;
      _connectedDeviceName = null;
      _authenticationToken = null;
      _connectionEstablished = false;
      _localReady = false;
      _remoteReady = false;
      _snapshotSent = false;
      _complete = false;
      _incomingTransfers.clear();
    });
    unawaited(_resumeDiscovery());
  }

  /// Restarts nearby discovery after an active connection ends.
  Future<void> _resumeDiscovery() async {
    try {
      final started = await _nearby.startDiscovery(
        'FuelLog',
        Strategy.P2P_POINT_TO_POINT,
        onEndpointFound: _onEndpointFound,
        onEndpointLost: _onEndpointLost,
      );
      if (!started) _showError('Nearby phone discovery could not restart.');
    } catch (e) {
      _showError('Could not restart nearby discovery: $e');
    }
  }

  /// Requests a nearby connection to a selected device.
  Future<void> _connect(String deviceId, String deviceName) async {
    try {
      final requested = await _nearby.requestConnection(
        'FuelLog',
        deviceId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
      if (!requested) {
        _showError('Could not request a connection to $deviceName.');
      }
    } catch (e) {
      _showError('Could not connect to $deviceName: $e');
    }
  }

  /// Disconnects from the currently connected phone.
  Future<void> _disconnect() async {
    final id = _connectedDeviceId;
    if (id == null) return;
    try {
      await _nearby.disconnectFromEndpoint(id);
    } catch (e) {
      _showError('Could not disconnect: $e');
    }
  }

  /// Confirms that this phone is ready to exchange snapshots.
  Future<void> _confirmSync() async {
    final id = _connectedDeviceId;
    if (id == null || _localReady) return;
    setState(() {
      _localReady = true;
      _error = null;
    });
    try {
      await _send(id, {'type': 'ready'});
      if (_remoteReady) await _sendSnapshot(id);
    } catch (e) {
      if (mounted) setState(() => _localReady = false);
      _showError('Could not start sync: $e');
    }
  }

  /// Validates and dispatches an incoming nearby byte payload.
  void _onPayloadReceived(String deviceId, Payload payload) {
    if (payload.type != PayloadType.BYTES || payload.bytes == null) {
      _showError('Received an unsupported nearby payload.');
      return;
    }
    try {
      unawaited(_handleReceived(deviceId, utf8.decode(payload.bytes!)));
    } catch (e) {
      _showError('Could not read nearby sync data: $e');
    }
  }

  /// Decodes and handles protocol, readiness, and snapshot messages.
  Future<void> _handleReceived(String deviceId, String encoded) async {
    try {
      if (deviceId != _connectedDeviceId) {
        throw const FormatException('Message is not from the connected phone');
      }
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) throw const FormatException('Invalid sync message');
      final message = Map<String, dynamic>.from(decoded);
      if (message['protocol'] != _protocol) {
        throw const FormatException(
            'The other phone uses an incompatible sync version');
      }
      switch (message['type']) {
        case 'ready':
          setState(() => _remoteReady = true);
          final id = _connectedDeviceId;
          if (id != null && _localReady) await _sendSnapshot(id);
          await _processCompletedTransfers();
          break;
        case 'snapshot':
          _receiveChunk(message);
          await _processCompletedTransfers();
          break;
        default:
          throw const FormatException('Unknown nearby sync message');
      }
    } catch (e) {
      _showError('Could not sync nearby: $e');
    }
  }

  /// Validates and stores one chunk of an incoming snapshot transfer.
  void _receiveChunk(Map<String, dynamic> message) {
    if (!_localReady || !_remoteReady) {
      throw const FormatException('Sync was not confirmed on both phones');
    }
    final transferId = message['transferId'];
    final index = message['index'];
    final total = message['total'];
    final records = message['records'];
    if (transferId is! String ||
        index is! int ||
        total is! int ||
        records is! List ||
        total < 1 ||
        total > 1000 ||
        index < 0 ||
        index >= total) {
      throw const FormatException('Invalid sync data chunk');
    }
    final transfer = _incomingTransfers.putIfAbsent(
      transferId,
      () => _IncomingTransfer(total),
    );
    if (transfer.total != total) {
      throw const FormatException('Inconsistent sync data chunks');
    }
    final previous = transfer.chunks[index];
    if (previous != null && jsonEncode(previous) != jsonEncode(records)) {
      throw const FormatException('Conflicting sync data chunks');
    }
    transfer.chunks[index] = List<dynamic>.from(records);
  }

  /// Assembles completed chunks and merges the received snapshot.
  Future<void> _processCompletedTransfers() async {
    if (!_localReady || !_remoteReady || _complete || _processingTransfer) {
      return;
    }
    for (final transfer in _incomingTransfers.values) {
      if (transfer.chunks.length != transfer.total) continue;
      final records = <dynamic>[
        for (var index = 0; index < transfer.total; index++)
          ...?transfer.chunks[index],
      ];
      _processingTransfer = true;
      try {
        final mergedCount = await widget.onSnapshotReceived(
          SyncSnapshot.fromRecords(records),
        );
        if (!mounted) return;
        setState(() {
          _complete = true;
          _error = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Sync complete — $mergedCount entries on this phone'),
              duration: kAppSnackBarDuration),
        );
      } finally {
        _processingTransfer = false;
      }
      return;
    }
  }

  /// Sends this phone's snapshot as size-limited protocol chunks.
  Future<void> _sendSnapshot(String deviceId) async {
    if (_snapshotSent || !_localReady || !_remoteReady) return;
    _snapshotSent = true;
    final records = widget.snapshot().toRecords();
    final chunks = <List<Map<String, dynamic>>>[];
    for (var i = 0; i < records.length; i += _maxChunkRecords) {
      chunks.add(
        records.sublist(
          i,
          i + _maxChunkRecords > records.length
              ? records.length
              : i + _maxChunkRecords,
        ),
      );
    }
    if (chunks.isEmpty) chunks.add([]);
    final transferId = DateTime.now().microsecondsSinceEpoch.toString();
    for (var index = 0; index < chunks.length; index++) {
      final message = {
        'type': 'snapshot',
        'transferId': transferId,
        'index': index,
        'total': chunks.length,
        'records': chunks[index],
      };
      final encoded = jsonEncode({'protocol': _protocol, ...message});
      if (utf8.encode(encoded).length > _maxMessageBytes) {
        _snapshotSent = false;
        throw StateError(
            'A sync data chunk exceeded the nearby transfer limit.');
      }
      await _nearby.sendBytesPayload(
          deviceId, Uint8List.fromList(utf8.encode(encoded)));
    }
  }

  /// Serializes and sends one nearby protocol message.
  Future<void> _send(String deviceId, Map<String, dynamic> message) async {
    final encoded = jsonEncode({'protocol': _protocol, ...message});
    if (utf8.encode(encoded).length > _maxMessageBytes) {
      throw StateError('Nearby message exceeded the transfer limit.');
    }
    await _nearby.sendBytesPayload(
        deviceId, Uint8List.fromList(utf8.encode(encoded)));
  }

  /// Displays a nearby sync error on screen and in a snackbar.
  void _showError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: kAppSnackBarDuration,
      ),
    );
  }

  /// Stops discovery, advertising, and all nearby endpoints when leaving the page.
  Future<void> _cleanupNearby() async {
    if (!_serviceInitialized) return;
    try {
      await Future.wait([
        _nearby.stopDiscovery(),
        _nearby.stopAdvertising(),
        _nearby.stopAllEndpoints(),
      ]);
    } catch (e) {
      debugPrint('Could not stop nearby sync cleanly: $e');
    }
  }

  /// Cleans up nearby services when the sync page is removed.
  @override
  void dispose() {
    unawaited(_cleanupNearby());
    super.dispose();
  }

  /// Builds the nearby device list, connection controls, and sync status.
  @override
  Widget build(BuildContext context) {
    final connected = _connectedDeviceId != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Sync with nerby Android')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Both phones must be Android and open to this screen to sync data between the two phones. If the connection fails or you cannot click the CONNECT button, lock the phones screen for 1 minute and try again.',
          ),
          const SizedBox(height: 16),
          if (_starting) const Center(child: CircularProgressIndicator()),
          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
          ],
          if (!_starting && !connected && _error == null)
            const Text('Looking for nearby FuelLog phones…'),
          if (connected) ...[
            ListTile(
              leading: const Icon(Icons.phone_android),
              title: Text(_connectedDeviceName ?? 'Connected phone'),
              subtitle: Text(
                !_connectionEstablished
                    ? 'Connecting…'
                    : _complete
                        ? 'Sync complete'
                        : _remoteReady
                            ? 'The other phone is ready'
                            : 'Security code: ${_authenticationToken ?? '—'}',
              ),
              trailing: IconButton(
                tooltip: 'Disconnect',
                onPressed: _disconnect,
                icon: const Icon(Icons.link_off),
              ),
            ),
            const SizedBox(height: 8),
            if (_connectionEstablished && !_complete)
              FilledButton.icon(
                onPressed: _localReady ? null : _confirmSync,
                icon: const Icon(Icons.sync),
                label: Text(
                    _localReady ? 'Waiting for the other phone…' : 'Sync log'),
              )
            else
              const Text('Disconnect and reconnect to start another sync.'),
          ],
          if (!connected)
            for (final device in _devices.entries)
              ListTile(
                leading: const Icon(Icons.phone_android),
                title: Text(device.value),
                subtitle: const Text('Nearby'),
                trailing: TextButton(
                  onPressed: () => _connect(device.key, device.value),
                  child: const Text('Connect'),
                ),
              ),
        ],
      ),
    );
  }
}
