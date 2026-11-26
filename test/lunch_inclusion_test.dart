import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_log/app.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> fuel(String id, DateTime date, double price) => {
      'id': id,
      'date': date.toIso8601String(),
      'updatedAt': date.toIso8601String(),
      'price': price,
      'volume': 10.0,
      'odometer': id == 'current' ? 1000.0 : 800.0,
    };

Map<String, dynamic> lunch(DateTime date, double price) => {
      'restaurant': 'Cafe',
      'date': date.toIso8601String(),
      'price': price,
    };

Future<void> start(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: HomePage()));
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Future<void> navigate(WidgetTester tester, String page) async {
  await tester.tap(find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == '$page page',
  ));
  await tester.pumpAndSettle();
}

Future<void> reachControl(WidgetTester tester, String page) async {
  final scroll = find
      .descendant(
        of: find.byKey(ValueKey('$page-scroll')),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(
    find.byKey(ValueKey('include-lunch-$page')),
    250,
    scrollable: scroll,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shared inclusion persists and totals include lunch-only months',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final previous = DateTime(now.year, now.month - 1, 15);
    final lunchOnly = DateTime(now.year - 2, 1, 15);
    SharedPreferences.setMockInitialValues({
      'fuel_entries_v1': jsonEncode([
        fuel('current', now, 5),
        fuel('previous', previous, 2),
      ]),
      'lunch_entries_v1': jsonEncode([
        lunch(now, 10),
        lunch(previous, 25),
        lunch(lunchOnly, 20),
      ]),
    });
    await start(tester);
    expect(find.text('This month\n\$50.00'), findsOneWidget);
    await navigate(tester, 'Totals');
    expect(find.text('Lunch spent'), findsNothing);
    await reachControl(tester, 'totals');
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('include-lunch-totals')),
      matching: find.text('On'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('This month\n\$60.00'), findsOneWidget);
    expect(find.text('Fuel spent'), findsWidgets);
    expect(find.text('Lunch spent'), findsWidgets);
    expect(find.text('Combined spent'), findsWidgets);
    expect(find.text('\$125.00'), findsOneWidget);
    expect(find.text('\$60.00'), findsWidgets);
    expect(find.text(DateFormat.yMMMM().format(lunchOnly)), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('fuel_include_lunch_v1'), isTrue);

    await navigate(tester, 'Charts');
    await reachControl(tester, 'charts');
    expect(
      tester
          .widget<SegmentedButton<bool>>(find.descendant(
            of: find.byKey(const ValueKey('include-lunch-charts')),
            matching: find.byType(SegmentedButton<bool>),
          ))
          .selected,
      {true},
    );
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('include-lunch-charts')),
      matching: find.text('Off'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('This month\n\$50.00'), findsOneWidget);
    await navigate(tester, 'Totals');
    expect(find.text('Combined spent'), findsNothing);
    await reachControl(tester, 'totals');
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('include-lunch-totals')),
      matching: find.text('On'),
    ));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await start(tester);
    await navigate(tester, 'Totals');
    expect(find.text('Combined spent'), findsWidgets);
    await reachControl(tester, 'totals');
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('include-lunch-totals')),
      matching: find.text('Off'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Combined spent'), findsNothing);
    expect(prefs.getBool('fuel_include_lunch_v1'), isFalse);
  });

  testWidgets('charts use three budget and custom slices and two month totals',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final previous = DateTime(now.year, now.month - 1, 15);
    SharedPreferences.setMockInitialValues({
      'fuel_include_lunch_v1': true,
      'fuel_monthly_budget_${now.year}_${now.month}': 100.0,
      'fuel_entries_v1': jsonEncode([
        fuel('current', now, 5),
        fuel('previous', previous, 2),
      ]),
      'lunch_entries_v1': jsonEncode([lunch(now, 10), lunch(previous, 25)]),
    });
    await start(tester);
    await navigate(tester, 'Charts');
    expect(find.text('50% / 40% / 10%'), findsOneWidget);
    expect(find.text('60% of \$100.00'), findsOneWidget);
    expect(find.text('57% / 43%'), findsOneWidget);
    expect(find.text('63% / 25% / 12%'), findsOneWidget);
    expect(find.text('Current month travel and lunch'), findsOneWidget);
    expect(find.text('Previous month lunch'), findsOneWidget);
    expect(find.text('Selected amounts can overlap.'), findsOneWidget);
    final budgetPie = find.byWidgetPredicate((widget) =>
        widget is Semantics &&
        widget.properties.label ==
            'Fuel, remaining budget and lunch: 50 percent and 40 percent and 10 percent');
    final painter = tester
        .widget<CustomPaint>(
          find.descendant(of: budgetPie, matching: find.byType(CustomPaint)),
        )
        .painter!;
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(100, 100));
    final picture = recorder.endRecording();
    final pixels = await tester.runAsync(() async {
      final image = await picture.toImage(100, 100);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return bytes;
    });
    picture.dispose();
    final colors = Theme.of(tester.element(budgetPie)).colorScheme;
    int pixel(int x, int y) => pixels!.getUint32((y * 100 + x) * 4);
    int rgba(Color color) => (color.toARGB32() << 8 & 0xFFFFFFFF) | 0xFF;
    expect(pixel(90, 50), rgba(colors.primary));
    expect(pixel(10, 50), rgba(colors.surfaceContainerHighest));
    expect(pixel(38, 12), rgba(Colors.deepOrange.shade700));
    await tester.tap(find.byKey(const ValueKey('custom-chart-First amount')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remaining monthly budget').last);
    await tester.pumpAndSettle();
    expect(find.text('57% / 29% / 14%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('over-budget chart uses actual fuel and lunch shares',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'fuel_include_lunch_v1': true,
      'fuel_monthly_budget_${now.year}_${now.month}': 25.0,
      'fuel_entries_v1': jsonEncode([fuel('current', now, 5)]),
      'lunch_entries_v1': jsonEncode([lunch(now, 10)]),
    });
    await start(tester);
    await navigate(tester, 'Charts');
    final budgetCard = find
        .ancestor(
          of: find.text('${DateFormat.yMMMM().format(now)} spending'),
          matching: find.byType(Card),
        )
        .first;
    expect(
        find.descendant(
          of: budgetCard,
          matching: find.text('83% / 0% / 17%'),
        ),
        findsOneWidget);
    expect(find.text('Over budget by \$35.00'), findsOneWidget);
    expect(find.text('240% of \$25.00'), findsOneWidget);
  });

  testWidgets('lunch-only charts and controls fit a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'fuel_include_lunch_v1': true,
      'lunch_entries_v1': jsonEncode([lunch(DateTime.now(), 10)]),
    });
    await start(tester);
    await navigate(tester, 'Charts');
    expect(find.text('Set a monthly budget to view progress.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Custom Chart'),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('charts-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('0% / 0% / 100%'), findsOneWidget);
    await reachControl(tester, 'charts');
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('include-lunch-charts')),
      matching: find.text('Off'),
    ));
    await tester.pumpAndSettle();
    await reachControl(tester, 'charts');
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('include-lunch-charts')),
      matching: find.text('On'),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('lunch-only totals work and new lunch updates them immediately',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'fuel_include_lunch_v1': true});
    await start(tester);
    await navigate(tester, 'Lunch');
    await tester.tap(find.text('Add lunch'));
    await tester.pumpAndSettle();
    final restaurant = find.byKey(const ValueKey('lunch-restaurant-input'));
    await tester.tap(restaurant);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other restaurant'));
    await tester.enterText(restaurant, 'Cafe');
    await tester.enterText(
        find.byKey(const ValueKey('lunch-price-input')), '12');
    await tester.tap(find.text('Save lunch'));
    await tester.pumpAndSettle();
    expect(find.text('This month\n\$12.00'), findsOneWidget);
    await navigate(tester, 'Totals');
    expect(find.text('No fill-ups yet'), findsNothing);
    expect(find.text('Lunch spent'), findsWidgets);
    expect(find.text('\$12.00'), findsWidgets);
    expect(find.text('0.0 gal'), findsWidgets);
    await navigate(tester, 'Lunch');
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - now.weekday + 1);
    await tester.tap(find.text('Week of ${DateFormat.yMMMd().format(monday)}'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(DateFormat.yMMMd().format(now)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete lunch entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('This month\n\$0.00'), findsOneWidget);
    await navigate(tester, 'Totals');
    expect(find.text('No fill-ups yet'), findsOneWidget);
    expect(find.text('Lunch spent'), findsNothing);
  });

  testWidgets('monthly weekly totals split a week at the month boundary',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final january = DateTime(2024, 1, 31);
    final february = DateTime(2024, 2, 1);
    SharedPreferences.setMockInitialValues({
      'fuel_include_lunch_v1': true,
      'fuel_entries_v1': jsonEncode([fuel('current', january, 1)]),
      'lunch_entries_v1': jsonEncode([lunch(january, 5), lunch(february, 7)]),
    });
    await start(tester);
    await navigate(tester, 'Totals');
    expect(find.textContaining('Fuel \$0.00 · Lunch \$7.00 · Combined \$7.00'),
        findsOneWidget);
    await tester.tap(find.text('January 2024'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Fuel \$10.00 · Lunch \$5.00 · Combined \$15.00'),
        findsOneWidget);
  });

  testWidgets('unreadable lunch data is reported without blocking fuel',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'fuel_include_lunch_v1': true,
      'lunch_entries_v1': 'invalid json',
    });
    await start(tester);
    expect(find.text('This month\nUnavailable'), findsOneWidget);
    await navigate(tester, 'Totals');
    expect(find.textContaining('Could not load lunch data:'), findsOneWidget);
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('include-lunch-totals')),
      matching: find.text('Off'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('This month\n\$0.00'), findsOneWidget);
    expect(find.text('No fill-ups yet'), findsOneWidget);
  });
}
