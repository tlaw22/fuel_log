import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app.dart' show SyncSnapshot, fuelLogNativeChannel;

class PairedBluetoothDevice {
  final String name;
  final String address;

  const PairedBluetoothDevice({required this.name, required this.address});
}

class BtSharePage extends StatefulWidget {
  final SyncSnapshot Function() snapshot;
  final Future<int> Function(SyncSnapshot snapshot) onSnapshotReceived;
  final bool enabled;

  const BtSharePage({
    super.key,
    required this.snapshot,
    required this.onSnapshotReceived,
    this.enabled = true,
  });

  @override
  State<BtSharePage> createState() => _BtSharePageState();
}

class _BtSharePageState extends State<BtSharePage> {
  final List<PairedBluetoothDevice> _devices = [];
  String? _selectedAddress;
  bool _loading = true;
  String? _error;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  PairedBluetoothDevice? get _selectedDevice {
    for (final device in _devices) {
      if (device.address == _selectedAddress) return device;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    if (!widget.enabled || !_isAndroid) {
      _loading = false;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_refreshPairedDevices());
      });
    }
  }

  Future<void> _refreshPairedDevices() async {
    if (!widget.enabled || !_isAndroid) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sdkInt =
          await fuelLogNativeChannel.invokeMethod<int>('androidSdkInt');
      if (sdkInt == null) {
        throw StateError('Could not determine the Android version.');
      }
      if (sdkInt >= 31) {
        final permission = await Permission.bluetoothConnect.request();
        if (!permission.isGranted) {
          throw StateError(
              'Bluetooth permission is required to list paired phones.');
        }
      }

      final rawDevices = await fuelLogNativeChannel
              .invokeListMethod<dynamic>('listPairedBluetoothDevices') ??
          const [];
      final devices = rawDevices.map((raw) {
        if (raw is! Map) {
          throw const FormatException('Invalid paired phone details.');
        }
        final details = Map<String, dynamic>.from(raw);
        final name = details['name'];
        final address = details['address'];
        if (name is! String || address is! String) {
          throw const FormatException('Invalid paired phone details.');
        }
        return PairedBluetoothDevice(name: name, address: address);
      }).toList()
        ..sort((first, second) =>
            first.name.toLowerCase().compareTo(second.name.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _devices
          ..clear()
          ..addAll(devices);
        if (!_devices.any((device) => device.address == _selectedAddress)) {
          _selectedAddress = null;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openBluetoothSettings() async {
    try {
      await fuelLogNativeChannel.invokeMethod<void>('openBluetoothSettings');
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not open Bluetooth settings: $error');
      }
    }
  }

  Future<void> _showPairingGuide() => showDialog<void>(
        context: context,
        builder: (_) => const _PairingGuideDialog(),
      );

  Future<void> _beginSharing() async {
    final device = _selectedDevice;
    if (device == null || !widget.enabled) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BluetoothFileSharingPage(
          device: device,
          snapshot: widget.snapshot,
          onSnapshotReceived: widget.onSnapshotReceived,
        ),
      ),
    );
  }

  Widget _buildPlatformMessage() {
    final message = !widget.enabled
        ? 'Bluetooth sharing is not available in this app version.'
        : 'Bluetooth sharing is available in the Android app.';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedDevice = _selectedDevice;
    final androidAvailable = widget.enabled && _isAndroid;
    return Scaffold(
      appBar: AppBar(title: const Text('Bluetooth Share')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Pair both phones in Android Bluetooth settings, then select the '
            'other phone below. FuelLog only transfers your log after you '
            'choose a role and begin sharing.',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _showPairingGuide,
            icon: const Icon(Icons.slideshow_outlined),
            label: const Text('How to pair two phones'),
          ),
          const SizedBox(height: 16),
          if (!androidAvailable)
            _buildPlatformMessage()
          else if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else ...[
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Paired phones',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh paired phones',
                  onPressed: _refreshPairedDevices,
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  tooltip: 'Open Bluetooth settings',
                  onPressed: _openBluetoothSettings,
                  icon: const Icon(Icons.settings_bluetooth),
                ),
              ],
            ),
            if (_devices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No paired phones found. Pair both phones in Android '
                  'Bluetooth settings, then refresh this list.',
                ),
              )
            else
              RadioGroup<String>(
                groupValue: _selectedAddress,
                onChanged: (address) =>
                    setState(() => _selectedAddress = address),
                child: Column(
                  children: [
                    for (final device in _devices)
                      RadioListTile<String>(
                        value: device.address,
                        title: Text(device.name),
                        subtitle: Text(device.address),
                        secondary: const Icon(Icons.phone_android),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (androidAvailable && selectedDevice != null) ...[
                FilledButton.icon(
                  onPressed: null,
                  style: FilledButton.styleFrom(
                    disabledBackgroundColor: Colors.red,
                    disabledForegroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.bluetooth_connected),
                  label: Text('Phones are paired: ${selectedDevice.name}'),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton.icon(
                onPressed:
                    androidAvailable && !_loading && selectedDevice != null
                        ? _beginSharing
                        : null,
                icon: const Icon(Icons.bluetooth),
                label: const Text('Begin Bluetooth File Sharing'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PairingGuideDialog extends StatefulWidget {
  const _PairingGuideDialog();

  @override
  State<_PairingGuideDialog> createState() => _PairingGuideDialogState();
}

class _PairingGuideDialogState extends State<_PairingGuideDialog> {
  static const _steps = [
    (
      title: 'Pair the phones',
      description:
          'On both Android phones, open Settings > Bluetooth. Turn Bluetooth '
              'on and pair each phone with the other.',
      icon: Icons.bluetooth_searching,
    ),
    (
      title: 'Choose the paired phone',
      description:
          'Return to FuelLog. Select the other phone from Paired phones on '
              'both devices. The red indicator confirms the selected pairing.',
      icon: Icons.phone_android,
    ),
    (
      title: 'Receive, then send',
      description:
          'Open Bluetooth File Sharing on both phones. Choose Receiver on '
              'one and tap Wait for sender first. On the other phone choose '
              'Sender and tap Connect and send log.',
      icon: Icons.swap_horiz,
    ),
  ];

  final PageController _controller = PageController();
  int _currentStep = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _moveTo(int step) {
    setState(() => _currentStep = step);
    _controller.animateToPage(
      step,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 440,
        height: 390,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Pairing guide',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close pairing guide',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _steps.length,
                  onPageChanged: (step) => setState(() => _currentStep = step),
                  itemBuilder: (context, index) {
                    final step = _steps[index];
                    return LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(step.icon, size: 56),
                                const SizedBox(height: 16),
                                Text(
                                  step.title,
                                  textAlign: TextAlign.center,
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  step.description,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _steps.length,
                  (index) => Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: index == _currentStep
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _currentStep == 0
                        ? null
                        : () => _moveTo(_currentStep - 1),
                    child: const Text('Back'),
                  ),
                  Text('${_currentStep + 1} of ${_steps.length}'),
                  if (_currentStep == _steps.length - 1)
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Done'),
                    )
                  else
                    FilledButton(
                      onPressed: () => _moveTo(_currentStep + 1),
                      child: const Text('Next'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _BluetoothShareRole { sender, receiver }

class BluetoothFileSharingPage extends StatefulWidget {
  static const _protocol = 'fuel-log-bluetooth-v1';
  static const _maxPayloadBytes = 32 * 1024 * 1024;

  final PairedBluetoothDevice device;
  final SyncSnapshot Function() snapshot;
  final Future<int> Function(SyncSnapshot snapshot) onSnapshotReceived;

  const BluetoothFileSharingPage({
    super.key,
    required this.device,
    required this.snapshot,
    required this.onSnapshotReceived,
  });

  @override
  State<BluetoothFileSharingPage> createState() =>
      _BluetoothFileSharingPageState();
}

class _BluetoothFileSharingPageState extends State<BluetoothFileSharingPage> {
  _BluetoothShareRole? _role;
  bool _busy = false;
  bool _complete = false;
  String? _status;
  String? _error;

  Future<void> _startTransfer() async {
    final role = _role;
    if (role == null || _busy || _complete) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = role == _BluetoothShareRole.receiver
          ? 'Waiting for ${widget.device.name} to connect…'
          : 'Connecting to ${widget.device.name}…';
    });
    try {
      if (role == _BluetoothShareRole.receiver) {
        await fuelLogNativeChannel.invokeMethod<void>(
          'startBluetoothServer',
          {'address': widget.device.address},
        );
        if (!mounted) return;
        setState(() => _status = 'Connected. Receiving the fuel log…');
        final bytes = await fuelLogNativeChannel
            .invokeMethod<Uint8List>('receiveBluetoothData');
        if (bytes == null) {
          throw const FormatException('The sender did not send a log file.');
        }
        final message = _decodeMessage(bytes);
        if (message['type'] != 'snapshot' || message['records'] is! List) {
          throw const FormatException('The received log file is invalid.');
        }
        final mergedCount = await widget.onSnapshotReceived(
          SyncSnapshot.fromRecords(message['records'] as List<dynamic>),
        );
        await _sendMessage({
          'type': 'complete',
          'entryCount': mergedCount,
        });
        if (mounted) {
          setState(() {
            _complete = true;
            _status = 'Log received and merged ($mergedCount entries).';
          });
        }
      } else {
        final bytes = Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'protocol': BluetoothFileSharingPage._protocol,
              'type': 'snapshot',
              'records': widget.snapshot().toRecords(),
            }),
          ),
        );
        if (bytes.length > BluetoothFileSharingPage._maxPayloadBytes) {
          throw StateError('The log is too large to send over Bluetooth.');
        }
        await fuelLogNativeChannel.invokeMethod<void>(
          'connectBluetoothDevice',
          {'address': widget.device.address},
        );
        if (!mounted) return;
        setState(() => _status = 'Connected. Sending the fuel log…');
        await _sendBytes(bytes);
        if (!mounted) return;
        setState(() => _status = 'Waiting for the receiver to confirm…');
        final acknowledgment = await fuelLogNativeChannel
            .invokeMethod<Uint8List>('receiveBluetoothData');
        if (acknowledgment == null) {
          throw const FormatException(
              'The receiver did not confirm the transfer.');
        }
        final message = _decodeMessage(acknowledgment);
        final count = message['entryCount'];
        if (message['type'] != 'complete' || count is! int || count < 0) {
          throw const FormatException(
              'The receiver returned an invalid confirmation.');
        }
        if (mounted) {
          setState(() {
            _complete = true;
            _status = 'Log sent successfully ($count entries on the receiver).';
          });
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Bluetooth sharing failed: $error');
    } finally {
      await _closeBluetoothTransfer();
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> _decodeMessage(Uint8List bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic> ||
        decoded['protocol'] != BluetoothFileSharingPage._protocol) {
      throw const FormatException('The other phone sent an incompatible file.');
    }
    return decoded;
  }

  Future<void> _sendMessage(Map<String, dynamic> message) =>
      _sendBytes(Uint8List.fromList(utf8.encode(jsonEncode({
        'protocol': BluetoothFileSharingPage._protocol,
        ...message,
      }))));

  Future<void> _sendBytes(Uint8List bytes) async {
    await fuelLogNativeChannel.invokeMethod<void>(
      'sendBluetoothData',
      {'bytes': bytes},
    );
  }

  Future<void> _closeBluetoothTransfer() async {
    try {
      await fuelLogNativeChannel.invokeMethod<void>('closeBluetoothTransfer');
    } catch (error) {
      debugPrint('Could not close the Bluetooth transfer: $error');
    }
  }

  @override
  void dispose() {
    unawaited(_closeBluetoothTransfer());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bluetooth File Sharing')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.bluetooth_connected),
            title: Text(widget.device.name),
            subtitle: const Text('Paired phone'),
          ),
          const Text(
            'Choose one phone as Sender and the other as Receiver. The '
            'Receiver should start waiting before the Sender connects.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            children: [
              ChoiceChip(
                avatar: const Icon(Icons.upload_outlined),
                label: const Text('Sender'),
                selected: _role == _BluetoothShareRole.sender,
                onSelected: _busy || _complete
                    ? null
                    : (selected) {
                        if (selected) {
                          setState(() => _role = _BluetoothShareRole.sender);
                        }
                      },
              ),
              ChoiceChip(
                avatar: const Icon(Icons.download_outlined),
                label: const Text('Receiver'),
                selected: _role == _BluetoothShareRole.receiver,
                onSelected: _busy || _complete
                    ? null
                    : (selected) {
                        if (selected) {
                          setState(() => _role = _BluetoothShareRole.receiver);
                        }
                      },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            switch (_role) {
              _BluetoothShareRole.sender =>
                'This phone will send its log to ${widget.device.name}.',
              _BluetoothShareRole.receiver =>
                'This phone will receive and merge the sender’s log.',
              null => 'Choose a role to begin.',
            },
          ),
          if (_status != null) ...[
            const SizedBox(height: 20),
            if (_busy) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(_status!),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed:
                _role == null || _busy || _complete ? null : _startTransfer,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _role == _BluetoothShareRole.receiver
                        ? Icons.download
                        : Icons.bluetooth_searching,
                  ),
            label: Text(
              _busy
                  ? 'Bluetooth sharing in progress…'
                  : _role == _BluetoothShareRole.receiver
                      ? 'Wait for sender'
                      : _role == _BluetoothShareRole.sender
                          ? 'Connect and send log'
                          : 'Choose Sender or Receiver',
            ),
          ),
        ),
      ),
    );
  }
}
