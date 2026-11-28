/// Lunch budget notification service.
/// Calculates current spending and updates the platform notification after a lunch entry.
part of '../app.dart';

class _LunchNotification {
  static const _windowsChannel =
      MethodChannel('io.github.tlaw22.fuellog/windows_notification');

  static Future<void> show(
      _LunchEntry entry, List<_LunchEntry> entries, double? budget) async {
    final day = _lunchDay(entry.date);
    final spent =
        _lunchTotal(entries.where((item) => _lunchDay(item.date) == day));
    final remaining = budget == null ? null : math.max(0.0, budget - spent);
    final data = <String, Object?>{
      'kind': 'lunch',
      'title': 'Lunch: ${_money.format(entry.price)}',
      'fillUp': '${entry.restaurant} · ${_dateFmt.format(entry.date)} · '
          'Daily budget: ${budget == null ? 'Not set' : _money.format(budget)}'
          '${budget != null && spent > budget ? ' · Over by ${_money.format(spent - budget)}' : ''}',
      'firstLabel': 'Lunch spent',
      'firstAmount': _money.format(spent),
      'firstTotal': spent,
      'secondLabel': 'Remaining',
      'secondAmount': remaining == null ? 'Not set' : _money.format(remaining),
      'secondTotal': remaining,
    };
    if (kIsWeb) {
      await browser_notifications.show(data);
    } else if (defaultTargetPlatform == TargetPlatform.windows) {
      await _windowsChannel.invokeMethod<void>('showLunch', data);
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      final posted = await _androidNativeChannel.invokeMethod<bool>(
          'showLunchNotification', data);
      if (posted != true) {
        throw StateError(
            'Notifications are disabled. Enable them in Android settings.');
      }
    } else {
      throw UnsupportedError(
          'Lunch notifications are not supported on this platform.');
    }
  }

  static Future<void> cancel() async {
    if (kIsWeb) {
      await browser_notifications.cancelLunch();
    } else if (defaultTargetPlatform == TargetPlatform.windows) {
      await _windowsChannel.invokeMethod<void>('cancelLunch');
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      await _androidNativeChannel.invokeMethod<void>('cancelLunchNotification');
    }
  }
}
