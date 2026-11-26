import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_log/app.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> openLunch(WidgetTester tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: LunchPage())));
    await tester.pumpAndSettle();
  }

  Future<void> openHomeLunch(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Fill-up'), findsOneWidget);
    await tester.tap(find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.label == 'Lunch page',
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('lunch help button shows the travel explanation', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await openHomeLunch(tester);

    final heading = find.descendant(
      of: find.byKey(const ValueKey('lunch-scroll')),
      matching: find.text('Lunch'),
    );
    final help = find.byIcon(Icons.help_outline);
    expect(help, findsOneWidget);
    expect(tester.getSize(help), const Size(12, 12));
    final button = find.ancestor(of: help, matching: find.byType(IconButton));
    expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    expect(tester.getTopLeft(help).dx,
        greaterThan(tester.getTopRight(heading).dx));
    await tester.tap(help);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text("The lunch calculator is included because you can't always "
          'pack your lunch while traveling.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('restaurant search, custom entry and recurring budget persist',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await openHomeLunch(tester);

    await tester.tap(find.text('Lunch budget'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('lunch-budget-input')), '15');
    await tester.tap(find.text('Save budget'));
    await tester.pumpAndSettle();
    expect(find.text('Daily budget: \$15.00 · Remaining: \$15.00'),
        findsOneWidget);

    final restaurant = find.byKey(const ValueKey('lunch-restaurant-input'));
    expect(restaurant, findsNothing);
    await tester.tap(find.text('Add lunch'));
    await tester.pumpAndSettle();
    await tester.tap(restaurant);
    await tester.enterText(restaurant, 'tAcO');
    await tester.pumpAndSettle();
    expect(find.text('Other restaurant'), findsOneWidget);
    expect(find.text('Taco Bell'), findsOneWidget);
    await tester.tap(find.text('Taco Bell'));
    await tester.enterText(
        find.byKey(const ValueKey('lunch-price-input')), '4.50');
    await tester.tap(find.text('Save lunch'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add lunch'));
    await tester.pumpAndSettle();
    await tester.tap(restaurant);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other restaurant'));
    await tester.enterText(restaurant, 'Local Cafe');
    await tester.enterText(
        find.byKey(const ValueKey('lunch-price-input')), '6');
    await tester.tap(find.text('Save lunch'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Remaining: \$4.50'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    final entries = jsonDecode(prefs.getString('lunch_entries_v1')!) as List;
    expect(entries.map((entry) => entry['restaurant']),
        ['Taco Bell', 'Local Cafe']);
    expect(prefs.getDouble('lunch_daily_budget_v1'), 15);
    await tester.pumpWidget(const SizedBox());
    await openHomeLunch(tester);
    expect(find.textContaining('Remaining: \$4.50'), findsOneWidget);
    expect(find.text('\$10.50'), findsWidgets);
  });

  testWidgets('current totals respect calendar day, week and month boundaries',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - now.weekday + 1);
    final beforeWeek = DateTime(monday.year, monday.month, monday.day - 1);
    final nextWeek = DateTime(monday.year, monday.month, monday.day + 7);
    final lastMonth = DateTime(now.year, now.month - 1, 1);
    final dates = [now, monday, beforeWeek, nextWeek, lastMonth];
    final amounts = [1.0, 2.0, 4.0, 8.0, 16.0];
    SharedPreferences.setMockInitialValues({
      'lunch_entries_v1': jsonEncode([
        for (var i = 0; i < dates.length; i++)
          {
            'restaurant': 'Restaurant $i',
            'date': dates[i].toIso8601String(),
            'price': amounts[i]
          },
      ]),
    });
    await openLunch(tester);
    double sum(bool Function(DateTime) predicate) {
      var total = 0.0;
      for (var i = 0; i < dates.length; i++) {
        if (predicate(dates[i])) total += amounts[i];
      }
      return total;
    }

    final currency = NumberFormat.currency(symbol: r'$', decimalDigits: 2);
    void expectSummary(String label, double value) {
      final column = find
          .ancestor(of: find.text(label), matching: find.byType(Column))
          .first;
      expect(
          find.descendant(
              of: column, matching: find.text(currency.format(value))),
          findsOneWidget);
    }

    expectSummary(
        'Today',
        sum((d) =>
            d.year == now.year && d.month == now.month && d.day == now.day));
    expectSummary(
        'This week', sum((d) => !d.isBefore(monday) && d.isBefore(nextWeek)));
    expectSummary(
        'This month', sum((d) => d.year == now.year && d.month == now.month));
    expect(find.text('Lunch history'), findsOneWidget);
  });

  testWidgets('Lunch is reachable at the end of narrow carousel navigation',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    final lunch = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.label == 'Lunch page',
    );
    expect(lunch, findsOneWidget);
    await tester.tap(lunch);
    await tester.pumpAndSettle();
    expect(find.text('Lunch budget'), findsOneWidget);
    expect(find.text('Add lunch'), findsOneWidget);
    expect(find.text('Fill-up'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the lunch sheet saves the selected date and time',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await openHomeLunch(tester);
    await tester.tap(find.text('Add lunch'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.calendar_today));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.access_time));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to text input mode'));
    await tester.pumpAndSettle();
    final inputs = find.descendant(
      of: find.byType(TimePickerDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(inputs.first, '10');
    await tester.enterText(inputs.last, '37');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final restaurant = find.byKey(const ValueKey('lunch-restaurant-input'));
    await tester.tap(restaurant);
    await tester.enterText(restaurant, 'taco');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Taco Bell'));
    await tester.enterText(
        find.byKey(const ValueKey('lunch-price-input')), '5');
    await tester.tap(find.text('Save lunch'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final entries = jsonDecode(prefs.getString('lunch_entries_v1')!) as List;
    final saved = DateTime.parse(entries.single['date'] as String);
    final now = DateTime.now();
    expect(DateTime(saved.year, saved.month, saved.day),
        DateTime(now.year, now.month, 1));
    expect(saved.hour % 12, 10);
    expect(saved.minute, 37);
  });

  testWidgets('lunch sheet and chart are usable with a narrow keyboard',
      (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(fuelLogNativeChannel, (call) async {
      if (call.method == 'showLunchNotification') return true;
      if (call.method == 'androidSdkInt') return 33;
      if (call.method == 'listPumpPhotos') return [];
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(fuelLogNativeChannel, null));
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    SharedPreferences.setMockInitialValues({});
    await openHomeLunch(tester);
    await tester.tap(find.text('Add lunch'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pumpAndSettle();
    final restaurant = find.byKey(const ValueKey('lunch-restaurant-input'));
    await tester.tap(restaurant);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other restaurant'));
    await tester.enterText(restaurant, 'Cafe');
    final price = find.byKey(const ValueKey('lunch-price-input'));
    await tester.ensureVisible(price);
    await tester.enterText(price, '5');
    await tester.ensureVisible(find.text('Save lunch'));
    await tester.tap(find.text('Save lunch'));
    await tester.pumpAndSettle();
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(find.text('Lunch saved.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Custom Lunch Chart'),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('lunch-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    final selector = find.byKey(const ValueKey('lunch-chart-0'));
    await tester.ensureVisible(selector);
    await tester.pumpAndSettle();
    await tester.tap(selector);
    await tester.pumpAndSettle();
    expect(find.text('Lunch this week'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wiping data while on Lunch resets its budget and chart',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'lunch_daily_budget_v1': 10.0,
      'lunch_chart_selection_v1': ['week', 'budget'],
      'lunch_entries_v1': jsonEncode([
        {
          'restaurant': 'Cafe',
          'date': DateTime.now().toIso8601String(),
          'price': 4
        },
      ]),
    });
    await openHomeLunch(tester);
    await tester.tap(find.byTooltip('App menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wipe Data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wipe data'));
    await tester.pumpAndSettle();
    expect(find.text('No daily budget set'), findsOneWidget);
    expect(find.text('No lunch entries yet.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Custom Lunch Chart'),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('lunch-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
        tester
            .widget<DropdownButton<String>>(
                find.byKey(const ValueKey('lunch-chart-0')))
            .value,
        'today');
  });

  testWidgets('daily chart and custom food comparisons update and persist',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'lunch_daily_budget_v1': 10.0,
      'lunch_entries_v1': jsonEncode([
        {'restaurant': 'Taco Bell', 'date': now.toIso8601String(), 'price': 4},
        {
          'restaurant': 'taco bell',
          'date': DateTime(now.year, now.month - 1, 1).toIso8601String(),
          'price': 2
        },
        {
          'restaurant': 'Local Cafe',
          'date': DateTime(now.year, now.month - 1, 2).toIso8601String(),
          'price': 3
        },
      ]),
    });
    await openLunch(tester);
    expect(find.text('40% of daily budget'), findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics &&
            widget.properties.label ==
                'Lunch spent and remaining daily budget: 40 percent and 60 percent'),
        findsOneWidget);
    await tester.ensureVisible(find.text('Custom Lunch Chart'));
    await tester.pumpAndSettle();
    final first = find.byKey(const ValueKey('lunch-chart-0'));
    final second = find.byKey(const ValueKey('lunch-chart-1'));
    expect(tester.widget<DropdownButton<String>>(first).value, 'today');
    expect(tester.widget<DropdownButton<String>>(second).value, 'remaining');
    await tester.tap(first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restaurant: Taco Bell (all time)').last);
    await tester.pumpAndSettle();
    await tester.tap(second);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restaurant: Local Cafe (all time)').last);
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics &&
            widget.properties.label ==
                'Restaurant: Taco Bell (all time) and Restaurant: Local Cafe (all time): 67 percent and 33 percent'),
        findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('lunch_chart_selection_v1'),
        ['restaurant:taco bell', 'restaurant:local cafe']);
    await tester.pumpWidget(const SizedBox());
    await openLunch(tester);
    await tester.ensureVisible(find.text('Custom Lunch Chart'));
    await tester.pumpAndSettle();
    expect(tester.widget<DropdownButton<String>>(first).value,
        'restaurant:taco bell');
    expect(tester.widget<DropdownButton<String>>(second).value,
        'restaurant:local cafe');
  });

  testWidgets('zero budget and overspending remain meaningful', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'lunch_daily_budget_v1': 0.0,
      'lunch_entries_v1': jsonEncode([
        {
          'restaurant': 'Lunch',
          'date': DateTime.now().toIso8601String(),
          'price': 4
        },
      ]),
    });
    await openLunch(tester);
    expect(find.text('Over budget by \$4.00'), findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics &&
            widget.properties.label ==
                'Lunch spent and remaining daily budget: 100 percent and 0 percent'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history shows complete weeks across months and deletes entries',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'lunch_entries_v1': jsonEncode([
        {
          'restaurant': 'January lunch',
          'date': '2024-01-31T12:00:00',
          'price': 5
        },
        {
          'restaurant': 'February lunch',
          'date': '2024-02-01T12:00:00',
          'price': 7
        },
      ]),
    });
    await openLunch(tester);
    expect(find.text('Monthly total: \$7.00'), findsOneWidget);
    expect(
        find.text('Week total: \$12.00 · Days in this month'), findsOneWidget);
    await tester.tap(find.text('Week of Jan 29, 2024'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Feb 1, 2024'));
    await tester.pumpAndSettle();
    expect(find.text('February lunch'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete lunch entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final entries = jsonDecode(prefs.getString('lunch_entries_v1')!) as List;
    expect(entries, hasLength(1));
    expect(entries.single['restaurant'], 'January lunch');
    expect(find.text('Monthly total: \$5.00'), findsOneWidget);
  });
}
