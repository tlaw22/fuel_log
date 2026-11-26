import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_log/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool _revealed(WidgetTester tester, String key) {
  final visibility = find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(Visibility),
  );
  return tester.widget<Visibility>(visibility.first).visible;
}

Future<void> _start(WidgetTester tester,
    {bool reducedMotion = false, ThemeData? theme}) async {
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: MediaQuery(
      data: MediaQueryData.fromView(tester.view)
          .copyWith(disableAnimations: reducedMotion),
      child: const HomePage(),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

Future<void> _open(WidgetTester tester, String page) async {
  await tester.tap(find.text(page).first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

void main() {
  testWidgets('log reveals entries half a second apart and restarts on revisit',
      (tester) async {
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'fuel_entries_v1': jsonEncode([
        FuelEntry(
          id: 'older',
          date: now.subtract(const Duration(days: 1)),
          price: 2,
          volume: 10,
          odometer: 100,
          updatedAt: now,
        ).toJson(),
        FuelEntry(
          id: 'newer',
          date: now,
          price: 3,
          volume: 10,
          odometer: 200,
          updatedAt: now,
        ).toJson(),
      ]),
    });
    await _start(tester);
    expect(_revealed(tester, 'reveal-newer'), isFalse);
    expect(_revealed(tester, 'reveal-older'), isFalse);
    final shimmer = find.descendant(
      of: find.byKey(const ValueKey('reveal-newer')),
      matching: find.byKey(const ValueKey('page-shimmer')),
    );
    final initialColor =
        (tester.widget<DecoratedBox>(shimmer).decoration as BoxDecoration)
            .color;
    expect(initialColor!.a, closeTo(0.55, 0.01));
    await tester.pump(const Duration(milliseconds: 250));
    final nextColor =
        (tester.widget<DecoratedBox>(shimmer).decoration as BoxDecoration)
            .color;
    expect(nextColor, isNot(initialColor));
    await tester.pump(const Duration(milliseconds: 249));
    expect(_revealed(tester, 'reveal-newer'), isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    expect(_revealed(tester, 'reveal-newer'), isTrue);
    expect(_revealed(tester, 'reveal-older'), isFalse);
    await tester.pump(const Duration(milliseconds: 500));
    expect(_revealed(tester, 'reveal-older'), isTrue);

    await _open(tester, 'Totals');
    await _open(tester, 'Log');
    expect(_revealed(tester, 'reveal-newer'), isFalse);
    await tester.pump(const Duration(milliseconds: 500));
    expect(_revealed(tester, 'reveal-newer'), isTrue);
    expect(_revealed(tester, 'reveal-older'), isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty totals and charts reveal their sections in order',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 2000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _start(tester);
    expect(_revealed(tester, 'reveal-log-empty'), isFalse);
    await _open(tester, 'Totals');
    expect(_revealed(tester, 'reveal-totals-empty'), isFalse);
    expect(_revealed(tester, 'reveal-totals-control'), isFalse);
    await tester.pump(const Duration(milliseconds: 500));
    expect(_revealed(tester, 'reveal-totals-empty'), isTrue);
    expect(_revealed(tester, 'reveal-totals-control'), isFalse);
    await tester.pump(const Duration(milliseconds: 500));
    expect(_revealed(tester, 'reveal-totals-control'), isTrue);

    await _open(tester, 'Charts');
    const stages = [
      'reveal-charts-budget',
      'reveal-charts-spending',
      'reveal-charts-comparison',
      'reveal-charts-custom',
      'reveal-charts-control',
    ];
    for (final stage in stages) {
      expect(find.byKey(ValueKey(stage)), findsOneWidget, reason: stage);
      expect(_revealed(tester, stage), isFalse);
    }
    for (var i = 0; i < stages.length; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      for (var j = 0; j < stages.length; j++) {
        expect(_revealed(tester, stages[j]), j <= i);
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('populated totals reveal each month before the control',
      (tester) async {
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'fuel_entries_v1': jsonEncode([
        for (var i = 0; i < 2; i++)
          FuelEntry(
            id: 'entry-$i',
            date: DateTime(now.year, now.month - i, 1),
            price: 2,
            volume: 10,
            odometer: 100 + 100.0 * i,
            updatedAt: now,
          ).toJson(),
      ]),
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _start(tester);
    await _open(tester, 'Totals');
    const stages = [
      'reveal-totals-all',
      'reveal-totals-month-0',
      'reveal-totals-month-1',
      'reveal-totals-control',
    ];
    for (var i = 0; i < stages.length; i++) {
      expect(_revealed(tester, stages[i]), isFalse);
      await tester.pump(const Duration(milliseconds: 500));
      expect(_revealed(tester, stages[i]), isTrue);
    }
  });

  testWidgets('Photos preserves real loading and error states under shimmer',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final sdk = Completer<int?>();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(fuelLogNativeChannel, (call) async {
      if (call.method == 'androidSdkInt') return sdk.future;
      return null;
    });
    addTearDown(
        () => messenger.setMockMethodCallHandler(fuelLogNativeChannel, null));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _start(tester);
    await _open(tester, 'Photos');
    expect(_revealed(tester, 'reveal-photos-header'), isFalse);
    expect(_revealed(tester, 'reveal-photos-gallery'), isFalse);
    expect(_revealed(tester, 'reveal-photos-download'), isFalse);
    await tester.pump(const Duration(milliseconds: 500));
    expect(_revealed(tester, 'reveal-photos-header'), isTrue);
    expect(_revealed(tester, 'reveal-photos-gallery'), isFalse);
    await tester.pump(const Duration(milliseconds: 500));
    expect(_revealed(tester, 'reveal-photos-gallery'), isTrue);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    sdk.completeError(PlatformException(code: 'gallery-error'));
    await tester.pump();
    expect(find.textContaining('Could not load pump photos:'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    expect(_revealed(tester, 'reveal-photos-download'), isTrue);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('reduced motion shows content without delaying it',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _start(tester, reducedMotion: true);
    expect(_revealed(tester, 'reveal-log-empty'), isTrue);
    await _open(tester, 'Totals');
    expect(_revealed(tester, 'reveal-totals-empty'), isTrue);
    expect(_revealed(tester, 'reveal-totals-control'), isTrue);
  });

  testWidgets('shimmer visibly animates in every app palette', (tester) async {
    for (final (isDark, palette) in [
      (true, ThemePalette.classic),
      (true, ThemePalette.forest),
      (true, ThemePalette.purpleRaindrops),
      (false, ThemePalette.classic),
      (false, ThemePalette.sage),
      (false, ThemePalette.rose),
    ]) {
      SharedPreferences.setMockInitialValues({});
      await _start(tester, theme: buildTheme(isDark: isDark, palette: palette));
      final shimmer = find.descendant(
        of: find.byKey(const ValueKey('reveal-log-empty')),
        matching: find.byKey(const ValueKey('page-shimmer')),
      );
      final initial =
          (tester.widget<DecoratedBox>(shimmer).decoration as BoxDecoration)
              .color;
      await tester.pump(const Duration(milliseconds: 250));
      final animated =
          (tester.widget<DecoratedBox>(shimmer).decoration as BoxDecoration)
              .color;
      expect(animated, isNot(initial), reason: palette.name);
      await tester.pumpWidget(const SizedBox());
    }
  });
}
