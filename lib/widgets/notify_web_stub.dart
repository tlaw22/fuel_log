Future<bool> requestPermission() =>
    Future.error(UnsupportedError('Browser notifications are unavailable.'));

Future<void> show(Map<String, Object?> data) =>
    Future.error(UnsupportedError('Browser notifications are unavailable.'));

Future<void> cancel() =>
    Future.error(UnsupportedError('Browser notifications are unavailable.'));
