import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_log/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _android = MethodChannel('io.github.tlaw22.fuellog/native');
const _windows =
    MethodChannel('io.github.tlaw22.fuellog/windows_notification');

Future<void> _openLunch(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: HomePage()));
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Lunch'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Add lunch'));
  await tester.pumpAndSettle();
}

Future<void> _fillLunch(WidgetTester tester, String price) async {
  final restaurant = find.byKey(const ValueKey('lunch-restaurant-input'));
  await tester.tap(restaurant);
  await tester.enterText(restaurant, 'taco');
  await tester.pumpAndSettle();
  await tester.tap(find.text('Taco Bell'));
  await tester.enterText(find.byKey(const ValueKey('lunch-price-input')), price);
}

void main() {
  const platforms = TargetPlatformVariant({
    TargetPlatform.android,
    TargetPlatform.windows,
  });

  testWidgets('only a valid lunch save posts the selected day budget chart',
      (tester) async {
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'lunch_daily_budget_v1': 20.0,
      'lunch_entries_v1': jsonEncode([
        {'restaurant': 'Earlier', 'date': now.toIso8601String(), 'price': 4.0},
        {
          'restaurant': 'Yesterday',
          'date': now.subtract(const Duration(days: 1)).toIso8601String(),
          'price': 100.0,
        },
      ]),
    });
    final calls = <MethodCall>[];
    final channel =
        defaultTargetPlatform == TargetPlatform.windows ? _windows : _android;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'androidSdkInt') return 33;
      if (call.method == 'listPumpPhotos') return [];
      calls.add(call);
      return defaultTargetPlatform == TargetPlatform.android ? true : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await _openLunch(tester);
    await tester.tap(find.text('Save lunch'));
    await tester.pump();
    expect(calls, isEmpty);
    await _fillLunch(tester, '5.25');
    await tester.tap(find.text('Save lunch'));
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    expect(calls.single.method, defaultTargetPlatform == TargetPlatform.windows
        ? 'showLunch'
        : 'showLunchNotification');
    final data = calls.single.arguments as Map<dynamic, dynamic>;
    expect(data['kind'], 'lunch');
    expect(data['title'], 'Lunch: \$5.25');
    expect(data['fillUp'], contains('Taco Bell'));
    expect(data['fillUp'], contains('Daily budget: \$20.00'));
    expect(data['firstLabel'], 'Lunch spent');
    expect(data['firstTotal'], 9.25);
    expect(data['secondLabel'], 'Remaining');
    expect(data['secondTotal'], 10.75);
    expect(find.text('Lunch saved.'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString('lunch_entries_v1')!) as List, hasLength(3));
  }, variant: platforms);

  for (final budget in [null, 0.0]) {
    testWidgets('lunch handles ${budget == null ? 'an unset' : 'a zero'} budget',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        if (budget != null) 'lunch_daily_budget_v1': budget,
      });
      final calls = <MethodCall>[];
      final channel =
          defaultTargetPlatform == TargetPlatform.windows ? _windows : _android;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'androidSdkInt') return 33;
        if (call.method == 'listPumpPhotos') return [];
        calls.add(call);
        return defaultTargetPlatform == TargetPlatform.android ? true : null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await _openLunch(tester);
      await _fillLunch(tester, '5');
      await tester.tap(find.text('Save lunch'));
      await tester.pumpAndSettle();
      final data = calls.single.arguments as Map<dynamic, dynamic>;
      expect(data['firstTotal'], 5.0);
      expect(data['secondTotal'], budget == null ? null : 0.0);
      expect(data['secondAmount'], budget == null ? 'Not set' : '\$0.00');
      expect(data['fillUp'], contains(budget == null
          ? 'Daily budget: Not set'
          : 'Over by \$5.00'));
    }, variant: platforms);
  }

  testWidgets('a backdated lunch compares spending on the selected day',
      (tester) async {
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'lunch_daily_budget_v1': 20.0,
      'lunch_entries_v1': jsonEncode([
        {
          'restaurant': 'Same day',
          'date': DateTime(now.year, now.month, 1, 12).toIso8601String(),
          'price': 6.0,
        },
        {
          'restaurant': 'Other day',
          'date': DateTime(now.year, now.month, 2, 12).toIso8601String(),
          'price': 9.0,
        },
      ]),
    });
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_windows, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_windows, null));
    await _openLunch(tester);
    await tester.tap(find.byIcon(Icons.calendar_today));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await _fillLunch(tester, '5');
    await tester.tap(find.text('Save lunch'));
    await tester.pumpAndSettle();
    final data = calls.single.arguments as Map<dynamic, dynamic>;
    expect(data['firstTotal'], 11.0);
    expect(data['secondTotal'], 9.0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('budget changes do not post and wiping cancels both notifications',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_windows, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_windows, null));
    await _openLunch(tester);
    Navigator.of(tester.element(find.text('New lunch'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lunch budget'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('lunch-budget-input')), '15');
    await tester.tap(find.text('Save budget'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await tester.tap(find.byTooltip('App menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wipe Data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wipe data'));
    await tester.pumpAndSettle();
    expect(calls.map((call) => call.method), ['cancel', 'cancelLunch']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('notification failure does not undo a saved lunch',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final channel =
        defaultTargetPlatform == TargetPlatform.windows ? _windows : _android;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'androidSdkInt') return 33;
      if (call.method == 'listPumpPhotos') return [];
      if (defaultTargetPlatform == TargetPlatform.android) return false;
      throw PlatformException(code: 'notification_failed', message: 'Denied');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await _openLunch(tester);
    await _fillLunch(tester, '5');
    await tester.tap(find.text('Save lunch'));
    await tester.pumpAndSettle();
    expect(
        defaultTargetPlatform == TargetPlatform.windows
            ? find.text('Notification update failed')
            : find.textContaining('Lunch saved, but notification failed:'),
        findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString('lunch_entries_v1')!) as List, hasLength(1));
  }, variant: platforms);
}
