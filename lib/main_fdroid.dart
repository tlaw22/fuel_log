// Application entry point for the F-Droid build.
// Starts FuelLog with Bluetooth sharing disabled to avoid unavailable dependencies.
import 'package:flutter/material.dart';

import 'app.dart';
import 'pages/btshare.dart';

/// Starts the F-Droid build with Bluetooth sharing controls disabled.
void main() {
  runApp(
    FuelLogApp(
      bluetoothShareEnabled: false,
      bluetoothSharePageBuilder: (snapshot, onSnapshotReceived) => BtSharePage(
        snapshot: snapshot,
        onSnapshotReceived: onSnapshotReceived,
        enabled: false,
      ),
    ),
  );
}
