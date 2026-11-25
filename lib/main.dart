import 'package:flutter/material.dart';

import 'app.dart';
import 'pages/btshare.dart';

export 'app.dart';
export 'pages/btshare.dart';

/// Starts the full Fuel Log application with Bluetooth sharing enabled.
void main() {
  runApp(
    FuelLogApp(
      bluetoothSharePageBuilder: (snapshot, onSnapshotReceived) => BtSharePage(
        snapshot: snapshot,
        onSnapshotReceived: onSnapshotReceived,
      ),
    ),
  );
}
