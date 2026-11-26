import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:animated_background/animated_background.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_log/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('bubbles animate behind the app and do not intercept controls',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    RandomParticleBehaviour.random = math.Random(42);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const FuelLogApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    final background = find.byKey(const ValueKey('app-bubbles'));
    expect(background, findsOneWidget);
    final layer = tester.renderObject<RenderRepaintBoundary>(background);
    Future<Uint8List> pixels() async {
      final result = await tester.runAsync(() async {
        final image = await layer.toImage();
        try {
          return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
              .buffer.asUint8List();
        } finally {
          image.dispose();
        }
      });
      return result!;
    }

    final first = await pixels();
    await tester.pump(const Duration(seconds: 1));
    final second = await pixels();
    expect(listEquals(first, second), isFalse);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Animated bubbles'), findsOneWidget);
    await tester.tap(find.text('Animated bubbles'));
    await tester.pumpAndSettle();
    expect(background, findsNothing);
    await tester.tap(find.text('Animated bubbles'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(background, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bubble setting is saved and reduced motion pauses animation',
      (tester) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const FuelLogApp());
    await tester.pumpAndSettle();
    final background = find.byKey(const ValueKey('app-bubbles'));
    expect(background, findsOneWidget);
    final tickerMode = find.ancestor(
      of: background,
      matching: find.byType(TickerMode),
    ).first;
    expect(tester.widget<TickerMode>(tickerMode).enabled, isFalse);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    final setting = find.widgetWithText(SwitchListTile, 'Animated bubbles');
    expect(tester.widget<SwitchListTile>(setting).value, isTrue);
    await tester.tap(find.text('Animated bubbles'));
    await tester.pumpAndSettle();
    expect(background, findsNothing);
    expect((await SharedPreferences.getInstance())
        .getBool('fuel_bubbles_enabled_v1'), isFalse);

    await tester.pumpWidget(const FuelLogApp(key: ValueKey('bubble-relaunch')));
    await tester.pumpAndSettle();
    expect(background, findsNothing);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(setting).value, isFalse);
    await tester.tap(find.text('Animated bubbles'));
    await tester.pumpAndSettle();
    expect(background, findsOneWidget);
    expect((await SharedPreferences.getInstance())
        .getBool('fuel_bubbles_enabled_v1'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bubble color follows the selected light and dark palettes',
      (tester) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const FuelLogApp());
    await tester.pumpAndSettle();

    void expectBubbleColor() {
      final animated = tester.widget<AnimatedBackground>(
          find.byType(AnimatedBackground));
      final color = (animated.behaviour as RandomParticleBehaviour).options.baseColor;
      final context = tester.element(find.byType(AnimatedBackground));
      final theme = Theme.of(context);
      final expected = theme.brightness == Brightness.dark
          ? theme.colorScheme.primary
          : theme.colorScheme.onSurface;
      expect(color, expected);
      final a = color.computeLuminance();
      final b = theme.scaffoldBackgroundColor.computeLuminance();
      final contrast = a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
      expect(contrast, greaterThanOrEqualTo(3));
    }

    Future<void> select(String name) async {
      await tester.tap(find.byTooltip('Choose color palette'));
      await tester.pumpAndSettle();
      await tester.tap(find.ancestor(
        of: find.text(name),
        matching: find.byType(CheckedPopupMenuItem<ThemePalette>),
      ));
      await tester.pumpAndSettle();
      expectBubbleColor();
    }

    expectBubbleColor();
    await select('Forest');
    await select('Purple Raindrops');
    await tester.tap(find.byTooltip('Switch to light theme'));
    await tester.pumpAndSettle();
    expectBubbleColor();
    await select('Sage');
    await select('Rose');
    expect(tester.takeException(), isNull);
  });
}
