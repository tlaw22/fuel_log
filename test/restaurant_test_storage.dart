import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Directory useRestaurantTestDirectory() {
  final directory =
      Directory.systemTemp.createTempSync('fuel_log_restaurants_');
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    if (call.method != 'getApplicationDocumentsDirectory') {
      throw PlatformException(code: 'unexpected_method', message: call.method);
    }
    return directory.path;
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  return directory;
}

Future<void> waitForRestaurantIo(WidgetTester tester, bool Function() completed,
    {Future<void> Function()? start}) async {
  await tester.runAsync(() async {
    if (start != null) await start();
    for (var attempt = 0; attempt < 200 && !completed(); attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 20));
    }
  });
  final errors = tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data)
      .where((text) => text != null && text.contains('Could not'));
  expect(completed(), isTrue,
      reason: 'Timed out waiting for restaurant IO. Errors: $errors');
  await tester.pumpAndSettle();
}
