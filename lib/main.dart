import 'package:flutter/material.dart';

import 'app.dart';
import 'nearby_sync_page.dart';

export 'app.dart';
export 'nearby_sync_page.dart';

/// Starts the full Fuel Log application with Nearby Sync enabled.
void main() {
  runApp(
    FuelLogApp(
      nearbySyncPageBuilder: (snapshot, onSnapshotReceived) => NearbySyncPage(
        snapshot: snapshot,
        onSnapshotReceived: onSnapshotReceived,
      ),
    ),
  );
}
