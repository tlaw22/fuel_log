/// Cross-platform notification service.
/// Builds chart notification payloads and posts or cancels them on Android, Windows, and web.
part of '../app.dart';

/// Posts and cancels custom-chart notifications.
class FuelLogNotifications {
  static const _windowsChannel =
      MethodChannel('io.github.tlaw22.fuellog/windows_notification');

  /// Starts the browser permission request directly from a save action.
  static Future<Object?> requestBrowserPermission() async {
    try {
      if (!await browser_notifications.requestPermission()) {
        throw StateError('Notifications are blocked in browser settings.');
      }
      return null;
    } catch (error) {
      debugPrint('Could not request browser notification permission: $error');
      return error;
    }
  }

  /// Posts a custom-chart notification.
  static Future<void> showCustomChart(List<FuelEntry> entries,
      FuelEntry savedEntry, String enteredAmount) async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final selection = await _CustomChartSelection.load(prefs);
    final values = _CustomChartValues(entries, prefs, now).amounts;
    final first = values[selection.first];
    final second = values[selection.second];
    final data = <String, Object?>{
      'title': 'Fueled up: $enteredAmount $kVolumeUnit - '
          '${_money.format(savedEntry.total)}',
      'firstLabel': selection.first.label,
      'secondLabel': selection.second.label,
      'firstAmount': first == null ? 'Not set' : _money.format(first),
      'secondAmount': second == null ? 'Not set' : _money.format(second),
      'firstTotal': first,
      'secondTotal': second,
      'fillUp': '${_dateFmt.format(savedEntry.date)}: '
          '${_num1.format(savedEntry.volume)} $kVolumeUnit, '
          '${_money.format(savedEntry.total)}',
    };
    if (kIsWeb) {
      await browser_notifications.show(data);
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      await _windowsChannel.invokeMethod<void>('show', data);
      return;
    }
    final posted = await _androidNativeChannel.invokeMethod<bool>(
      'showTravelNotification',
      data,
    );
    if (posted != true) {
      throw StateError(
        'Notifications are disabled. Enable them in Android settings.',
      );
    }
  }

  /// Reports a notification failure after an entry is saved.
  static void reportFailure(BuildContext context, Object error,
      {bool lunch = false}) {
    final concise = kIsWeb || defaultTargetPlatform == TargetPlatform.windows;
    if (concise) debugPrint('Notification update failed: $error');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(concise
            ? 'Notification update failed'
            : '${lunch ? 'Lunch' : 'Fill-up'} saved, but notification failed: $error'),
        duration: kAppSnackBarDuration,
      ),
    );
  }

  /// Removes the custom-chart notification.
  static Future<void> cancel() {
    if (kIsWeb) return browser_notifications.cancel();
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return _windowsChannel.invokeMethod<void>('cancel');
    }
    return _androidNativeChannel.invokeMethod<void>('cancelTravelNotification');
  }
}
