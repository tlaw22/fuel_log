import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_log/app.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'restaurant_test_storage.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
  });
  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher.clearAccessibilityFeaturesTestValue();
  });

  Future<void> openLunch(WidgetTester tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: LunchPage())));
    await tester.pumpAndSettle();
  }

  Future<void> openHomeLunch(WidgetTester tester,
      {bool waitForFile = false}) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Fill-up'), findsOneWidget);
    final lunch = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.label == 'Lunch page',
    );
    if (waitForFile) {
      await waitForRestaurantIo(
        tester,
        () => find.text('Lunch budget').evaluate().isNotEmpty,
        start: () async {
          await tester.tap(lunch);
          await tester.pump(const Duration(seconds: 1));
        },
      );
    } else {
      await tester.tap(lunch);
      await tester.pumpAndSettle();
    }
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
    expect(tester.getSize(button), const Size(24, 24));
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
    final directory = useRestaurantTestDirectory();
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
    await waitForRestaurantIo(
      tester,
      () => find.text('New lunch').evaluate().isEmpty,
      start: () => tester.tap(find.text('Save lunch')),
    );
    expect(find.textContaining('Remaining: \$4.50'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    final entries = jsonDecode(prefs.getString('lunch_entries_v1')!) as List;
    expect(entries.map((entry) => entry['restaurant']),
        ['Taco Bell', 'Local Cafe']);
    expect(prefs.getDouble('lunch_daily_budget_v1'), 15);
    final file = File('${directory.path}${Platform.pathSeparator}FuelLog'
        '${Platform.pathSeparator}lunch_restaurants.csv');
    expect(file.readAsStringSync(), endsWith('\r\nLocal Cafe'));
    file.writeAsStringSync('\r\n"Edited, Cafe"', mode: FileMode.append);
    await tester.pumpWidget(const SizedBox());
    await openHomeLunch(tester, waitForFile: true);
    expect(find.textContaining('Remaining: \$4.50'), findsOneWidget);
    expect(find.text('\$10.50'), findsWidgets);
    await tester.tap(find.text('Add lunch'));
    await tester.pumpAndSettle();
    await tester.enterText(restaurant, 'cafe');
    await tester.pumpAndSettle();
    expect(find.text('Local Cafe'), findsOneWidget);
    expect(find.text('Edited, Cafe'), findsOneWidget);
    await tester.tap(find.text('Other restaurant'));
    await tester.enterText(restaurant, 'local cafe');
    await tester.enterText(
        find.byKey(const ValueKey('lunch-price-input')), '1');
    await tester.tap(find.text('Save lunch'));
    await tester.pumpAndSettle();
    expect(file.readAsStringSync(), endsWith('\r\nLocal Cafe\r\n"Edited, Cafe"'));
    file.writeAsStringSync('\r\nExternal Cafe', mode: FileMode.append);
    await tester.tap(find.text('Add lunch'));
    await tester.pumpAndSettle();
    await tester.tap(restaurant);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other restaurant'));
    await tester.enterText(restaurant, 'Another Cafe');
    await tester.enterText(
        find.byKey(const ValueKey('lunch-price-input')), '1');
    await waitForRestaurantIo(
      tester,
      () => find.text('New lunch').evaluate().isEmpty,
      start: () => tester.tap(find.text('Save lunch')),
    );
    expect(file.readAsStringSync(),
        endsWith('\r\nExternal Cafe\r\nAnother Cafe'));
  });

  testWidgets('lunch CSV export and replacement are separate from fuel',
      (tester) async {
    final directory = useRestaurantTestDirectory();
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final separator = Platform.pathSeparator;
    final output = File('${directory.path}${separator}lunch_export.csv');
    final input = File('${directory.path}${separator}lunch_import.csv');
    final fuelCsv = File('${directory.path}${separator}fuel.csv');
    input.writeAsStringSync(
      'Date,Restaurant,Price\r\n'
      '2026-03-04T15:22:05.000,"Cafe, ""Sun""",0\r\n',
    );
    fuelCsv.writeAsStringSync(
        'Date,Odometer (mi),Price per gal,Amount (gal)\n2026-01-01,10,2,3');
    File selected = input;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('plugins.flutter.io/file_selector');
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'openFile') return [selected.path];
      if (call.method == 'getSavePath') return output.path;
      throw PlatformException(code: 'unexpected_method', message: call.method);
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    const fuel = '[{"unchanged":true}]';
    SharedPreferences.setMockInitialValues({
      'fuel_entries_v1': fuel,
      'lunch_entries_v1': jsonEncode([
        {
          'restaurant': 'Old, "Place"',
          'date': '2025-12-31T23:59:30.000',
          'price': 12.5,
        },
      ]),
    });
    await openLunch(tester);

    Future<void> tapAction(String label) async {
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
    }

    await waitForRestaurantIo(
      tester,
      () => find.textContaining('CSV saved to').evaluate().isNotEmpty,
      start: () => tapAction('Export lunch CSV'),
    );
    expect(output.readAsStringSync(),
        'Date,Restaurant,Price\r\n2025-12-31T23:59:30.000,"Old, ""Place""",12.5');

    Future<void> openImport() => waitForRestaurantIo(
          tester,
          () => find.text('Replace').evaluate().isNotEmpty,
          start: () => tapAction('Import lunch CSV'),
        );
    await openImport();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect((jsonDecode(prefs.getString('lunch_entries_v1')!) as List).single['restaurant'],
        'Old, "Place"');

    await openImport();
    await waitForRestaurantIo(
      tester,
      () => (jsonDecode(prefs.getString('lunch_entries_v1')!) as List)
          .single['restaurant'] == 'Cafe, "Sun"',
      start: () => tester.tap(find.text('Replace')),
    );
    final imported = (jsonDecode(prefs.getString('lunch_entries_v1')!) as List).single;
    expect(imported['restaurant'], 'Cafe, "Sun"');
    expect(imported['date'], '2026-03-04T15:22:05.000');
    expect(imported['price'], 0);
    expect(prefs.getString('fuel_entries_v1'), fuel);

    selected = fuelCsv;
    await waitForRestaurantIo(
      tester,
      () => find.textContaining('Could not import CSV').evaluate().isNotEmpty,
      start: () => tapAction('Import lunch CSV'),
    );
    expect((jsonDecode(prefs.getString('lunch_entries_v1')!) as List).single['restaurant'],
        'Cafe, "Sun"');
    fuelCsv.writeAsStringSync(
        'Date,Restaurant,Price\r\n2026-03-04T15:22:05.000,Cafe,-1');
    await waitForRestaurantIo(
      tester,
      () => find.textContaining('Invalid lunch CSV row 2').evaluate().isNotEmpty,
      start: () => tapAction('Import lunch CSV'),
    );
    expect((jsonDecode(prefs.getString('lunch_entries_v1')!) as List).single['restaurant'],
        'Cafe, "Sun"');
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('restaurant CSV import and export preserve editable names',
      (tester) async {
    final directory = useRestaurantTestDirectory();
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final separator = Platform.pathSeparator;
    final input = File('${directory.path}${separator}restaurants_in.csv')
      ..writeAsStringSync('Chain\r\n"New, Cafe"\r\nNEW, CAFE\r\n');
    final output = File('${directory.path}${separator}restaurants_out.csv');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('plugins.flutter.io/file_selector');
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'openFile') return [input.path];
      if (call.method == 'getSavePath') return output.path;
      throw PlatformException(code: 'unexpected_method', message: call.method);
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    SharedPreferences.setMockInitialValues({});
    await openLunch(tester);

    Future<void> tapAction(String label) async {
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
    }

    await waitForRestaurantIo(
      tester,
      () => find.textContaining('Could not import CSV').evaluate().isNotEmpty,
      start: () => tapAction('Import restaurants CSV'),
    );
    input.writeAsStringSync('Chain\r\n"New, Cafe"\r\n"NEW, CAFE"\r\n');
    await waitForRestaurantIo(
      tester,
      () => find.text('Replace').evaluate().isNotEmpty,
      start: () => tapAction('Import restaurants CSV'),
    );
    final prefs = await SharedPreferences.getInstance();
    await waitForRestaurantIo(
      tester,
      () => prefs.getBool('lunch_restaurants_file_v1') == true,
      start: () => tester.tap(find.text('Replace')),
    );
    final file = File('${directory.path}${separator}FuelLog'
        '${separator}lunch_restaurants.csv');
    expect(file.readAsStringSync(), 'Chain\r\n"New, Cafe"');
    await waitForRestaurantIo(
      tester,
      () => find.textContaining('CSV saved to').evaluate().isNotEmpty,
      start: () => tapAction('Export restaurants CSV'),
    );
    expect(output.readAsStringSync(), 'Chain\r\n"New, Cafe"');
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('Android lunch CSV export uses the native documents service',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<dynamic, dynamic>? saved;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(fuelLogNativeChannel, (call) async {
      if (call.method == 'androidSdkInt') return 33;
      if (call.method == 'saveCsv') {
        saved = call.arguments as Map<dynamic, dynamic>;
        return 'Documents/lunch.csv';
      }
      throw PlatformException(code: 'unexpected_method', message: call.method);
    });
    addTearDown(
        () => messenger.setMockMethodCallHandler(fuelLogNativeChannel, null));
    SharedPreferences.setMockInitialValues({
      'lunch_entries_v1': jsonEncode([
        {
          'restaurant': 'Cafe',
          'date': '2026-03-04T15:22:05.000',
          'price': 9.5,
        },
      ]),
    });
    await openLunch(tester);
    await tester.ensureVisible(find.text('Export lunch CSV'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export lunch CSV'));
    await tester.pumpAndSettle();
    expect(saved?['name'], startsWith('lunch_log_'));
    expect(utf8.decode(saved!['bytes'] as List<int>),
        'Date,Restaurant,Price\r\n2026-03-04T15:22:05.000,Cafe,9.5');
    expect(find.text('CSV saved to Documents/lunch.csv'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('a damaged restaurant CSV can be repaired by importing a list',
      (tester) async {
    final directory = useRestaurantTestDirectory();
    final separator = Platform.pathSeparator;
    final folder = Directory('${directory.path}${separator}FuelLog')
      ..createSync();
    final file = File('${folder.path}${separator}lunch_restaurants.csv')
      ..writeAsStringSync('invalid header');
    final replacement = File('${directory.path}${separator}replacement.csv')
      ..writeAsStringSync('Chain\r\nRestored Cafe');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('plugins.flutter.io/file_selector');
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'openFile') return [replacement.path];
      throw PlatformException(code: 'unexpected_method', message: call.method);
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    SharedPreferences.setMockInitialValues({
      'lunch_restaurants_file_v1': true,
    });
    await waitForRestaurantIo(
      tester,
      () => find.textContaining('Could not load lunch data:').evaluate().isNotEmpty,
      start: () => tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: LunchPage()))),
    );
    await waitForRestaurantIo(
      tester,
      () => find.text('Replace').evaluate().isNotEmpty,
      start: () => tester.tap(find.text('Import restaurants CSV')),
    );
    await waitForRestaurantIo(
      tester,
      () => find.text('Lunch budget').evaluate().isNotEmpty,
      start: () => tester.tap(find.text('Replace')),
    );
    expect(file.readAsStringSync(), 'Chain\r\nRestored Cafe');
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('wiping data removes the managed restaurant CSV', (tester) async {
    final directory = useRestaurantTestDirectory();
    final folder = Directory('${directory.path}${Platform.pathSeparator}FuelLog')
      ..createSync();
    final file = File('${folder.path}${Platform.pathSeparator}lunch_restaurants.csv')
      ..writeAsStringSync('Chain\r\nCafe');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('io.github.tlaw22.fuellog/windows_notification'),
        (call) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(
        const MethodChannel('io.github.tlaw22.fuellog/windows_notification'),
        null));
    SharedPreferences.setMockInitialValues({
      'lunch_restaurants_file_v1': true,
      'lunch_restaurants_csv_v1': 'Chain\r\nCafe',
    });
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('App menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wipe Data'));
    await tester.pumpAndSettle();
    await waitForRestaurantIo(
      tester,
      () => find.text('App data wiped.').evaluate().isNotEmpty,
      start: () => tester.tap(find.text('Wipe data')),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(file.existsSync(), isFalse);
    expect(prefs.containsKey('lunch_restaurants_file_v1'), isFalse);
    expect(prefs.containsKey('lunch_restaurants_csv_v1'), isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

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

  testWidgets('Lunch remains usable with larger app text', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.binding.platformDispatcher.clearTextScaleFactorTestValue);
    SharedPreferences.setMockInitialValues({'fuel_font_size_percent_v1': 120});
    await tester.pumpWidget(const FuelLogApp());
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.label == 'Lunch page',
    ));
    await tester.pumpAndSettle();
    expect(find.text('Lunch budget'), findsOneWidget);
    expect(find.text('Add lunch'), findsOneWidget);
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
    useRestaurantTestDirectory();
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
    await waitForRestaurantIo(
      tester,
      () => find.text('New lunch').evaluate().isEmpty,
      start: () => tester.tap(find.text('Save lunch')),
    );
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
