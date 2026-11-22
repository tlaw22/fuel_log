import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_log/main.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

FuelEntry _entry({
  required String id,
  required DateTime updatedAt,
  required double price,
  DateTime? date,
  double odometer = 100,
}) =>
    FuelEntry(
      id: id,
      date: date ?? DateTime(2026, 1, 1),
      price: price,
      volume: 10,
      odometer: odometer,
      updatedAt: updatedAt,
    );

void main() {
  test('BBH Bogle is the global text font', () {
    final theme = buildTheme();
    final lightTheme = buildTheme(isDark: false);

    expect(theme.textTheme.bodyMedium?.fontFamily, 'BBH Bogle');
    expect(theme.textTheme.titleLarge?.fontFamily, 'BBH Bogle');
    expect(theme.brightness, Brightness.dark);
    expect(lightTheme.brightness, Brightness.light);
    expect(lightTheme.scaffoldBackgroundColor, const Color(0xFFEDEDE9));
    expect(lightTheme.colorScheme.surface, const Color(0xFFF5EBE0));
    expect(lightTheme.colorScheme.primaryContainer, const Color(0xFFD6CCC2));
    expect(lightTheme.colorScheme.surfaceContainerHighest,
        const Color(0xFFE3D5CA));
    expect(lightTheme.colorScheme.primary, const Color(0xFFD5BDAF));
  });

  test('parses exported CSV entries and quoted fields', () {
    final entries = parseFuelCsv(
      'Date,Odometer (mi),Price per gal,Amount (gal),Total cost,'
      'Distance since last (mi),Efficiency (mi/gal)\r\n'
      '2026-01-02,1200,3.125,10.5,"\$32.81",,\r\n',
    );

    expect(entries, hasLength(1));
    expect(entries.single.date, DateTime(2026, 1, 2));
    expect(entries.single.odometer, 1200);
    expect(entries.single.price, 3.125);
    expect(entries.single.volume, 10.5);
    expect(entries.single.id, isNotEmpty);
  });

  test('rejects malformed or invalid CSV rows', () {
    expect(
      () => parseFuelCsv('not a FuelLog file'),
      throwsFormatException,
    );
    expect(
      () => parseFuelCsv(
        'Date,Odometer (mi),Price per gal,Amount (gal)\n'
        '2026-01-02,0,3.125,10.5',
      ),
      throwsFormatException,
    );
  });

  testWidgets('AppBar theme control switches between dark and light',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const FuelLogApp());
    await tester.pumpAndSettle();

    expect(find.byType(HomePage), findsOneWidget);
    expect(find.text('Log'), findsOneWidget);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!.brightness,
      Brightness.dark,
    );
    await tester.tap(find.byTooltip('Switch to light theme'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!.brightness,
      Brightness.light,
    );
    expect(find.byTooltip('Switch to dark theme'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('fuel_theme_is_dark_v1'), isFalse);

    await tester.pumpWidget(
      const FuelLogApp(key: ValueKey('second-launch')),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!.brightness,
      Brightness.light,
    );
    expect(find.byTooltip('Switch to dark theme'), findsOneWidget);
  });

  testWidgets('startup shows local-data progress and privacy notice',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: HomePage()));

    expect(find.text('Loading Local Data'), findsOneWidget);
    expect(
      find.text('This app does not sell/share/collect any data.'),
      findsOneWidget,
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('% loaded'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Loading Local Data'), findsNothing);
  });

  testWidgets('new fill-up form shows a pump camera action', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: EntryForm())),
    );

    expect(find.byTooltip('Take pump photo'), findsOneWidget);
    final pumpIcon =
        tester.widget<Icon>(find.byIcon(Icons.photo_camera_outlined));
    expect(pumpIcon.size, 40);
  });

  testWidgets('AppBar menu includes CSV and backup actions', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    final menuFinder = find.byTooltip('App menu');
    final menuButtonFinder = find.byWidgetPredicate(
      (widget) => widget is PopupMenuButton && widget.tooltip == 'App menu',
    );
    final menuButton =
        tester.widget<PopupMenuButton<dynamic>>(menuButtonFinder);
    final colorScheme = Theme.of(tester.element(menuFinder)).colorScheme;
    expect(
      menuButton.style?.side?.resolve({})?.color,
      colorScheme.secondary,
    );

    await tester.tap(menuFinder);
    await tester.pumpAndSettle();

    expect(find.text('Load CSV'), findsOneWidget);
    expect(find.text('Save CSV'), findsOneWidget);
    expect(find.text('Share CSV backup'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Wipe Data'), findsOneWidget);
  });

  testWidgets('Wipe Data confirms, warns, and clears saved app data',
      (tester) async {
    final now = DateTime.now();
    final previousMonth = DateTime(now.year, now.month - 1);
    final entry = _entry(
      id: 'to-wipe',
      updatedAt: now,
      price: 5,
      date: now,
    );
    SharedPreferences.setMockInitialValues({
      'fuel_entries_v1': jsonEncode([entry.toJson()]),
      'fuel_entries_deleted_v1': jsonEncode({
        'deleted-entry': now.toIso8601String(),
      }),
      'fuel_monthly_budget_${now.year}_${now.month}': 250.0,
      'fuel_monthly_budget_${previousMonth.year}_${previousMonth.month}': 200.0,
      'fuel_income_${now.year}_${now.month}': 5000.0,
      'fuel_insurance_${now.year}_${now.month}': 150.0,
      'fuel_car_payment_${now.year}_${now.month}': 300.0,
      'fuel_theme_is_dark_v1': false,
    });

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    expect(find.byType(Dismissible), findsOneWidget);

    await tester.tap(find.byTooltip('App menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wipe Data'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Fill-ups can only be restored from a backup CSV'),
      findsOneWidget,
    );
    expect(find.textContaining('pump photos are not included in CSV'),
        findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('fuel_entries_v1'), isNotNull);

    await tester.tap(find.byTooltip('App menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wipe Data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wipe data'));
    await tester.pumpAndSettle();

    prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('fuel_entries_v1'), isNull);
    expect(prefs.getString('fuel_entries_deleted_v1'), isNull);
    expect(prefs.getDouble('fuel_monthly_budget_${now.year}_${now.month}'),
        isNull);
    expect(
        prefs.getDouble(
            'fuel_monthly_budget_${previousMonth.year}_${previousMonth.month}'),
        isNull);
    expect(prefs.getDouble('fuel_income_${now.year}_${now.month}'), isNull);
    expect(prefs.getDouble('fuel_insurance_${now.year}_${now.month}'), isNull);
    expect(
        prefs.getDouble('fuel_car_payment_${now.year}_${now.month}'), isNull);
    expect(prefs.getBool('fuel_theme_is_dark_v1'), isFalse);
    expect(find.text('App data wiped.'), findsOneWidget);
  });

  testWidgets('About menu displays the bundled README', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('App menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();

    expect(find.text('About Fuel Log'), findsOneWidget);
    expect(find.textContaining('A Flutter app for tracking fuel fill-ups'),
        findsOneWidget);
  });

  test('loads legacy entries without an edit timestamp', () {
    final date = DateTime(2026, 1, 1);
    final entry = FuelEntry.fromJson({
      'id': 'legacy',
      'date': date.toIso8601String(),
      'price': 2,
      'volume': 10,
      'odometer': 100,
    });

    expect(entry.updatedAt, date);
  });

  test('merges unique entries and keeps the most recently edited version', () {
    final oldEdit = DateTime(2026, 1, 1);
    final newEdit = DateTime(2026, 1, 2);
    final merged = mergeSnapshots(
      SyncSnapshot(
        entries: [
          _entry(id: 'shared', updatedAt: oldEdit, price: 2),
          _entry(id: 'local', updatedAt: oldEdit, price: 3),
        ],
        deletions: const {},
      ),
      SyncSnapshot(
        entries: [
          _entry(id: 'shared', updatedAt: newEdit, price: 5),
          _entry(id: 'remote', updatedAt: oldEdit, price: 4),
        ],
        deletions: const {},
      ),
    );

    expect(merged.entries.map((entry) => entry.id).toSet(),
        {'shared', 'local', 'remote'});
    expect(
      merged.entries.singleWhere((entry) => entry.id == 'shared').price,
      5,
    );
  });

  test('propagates deletions unless a newer edit recreated the entry', () {
    final edit = DateTime(2026, 1, 1);
    final deletion = DateTime(2026, 1, 2);
    final merged = mergeSnapshots(
      SyncSnapshot(
        entries: [_entry(id: 'removed', updatedAt: edit, price: 2)],
        deletions: const {},
      ),
      SyncSnapshot(entries: const [], deletions: {'removed': deletion}),
    );
    expect(merged.entries, isEmpty);
    expect(merged.deletions['removed'], deletion);

    final recreated = mergeSnapshots(
      SyncSnapshot(entries: const [], deletions: {'removed': deletion}),
      SyncSnapshot(
        entries: [
          _entry(
              id: 'removed',
              updatedAt: deletion.add(const Duration(seconds: 1)),
              price: 6)
        ],
        deletions: const {},
      ),
    );
    expect(recreated.entries.single.price, 6);
    expect(recreated.deletions, isEmpty);
  });

  test('same-time edits converge regardless of merge direction', () {
    final updatedAt = DateTime(2026, 1, 1);
    final first = SyncSnapshot(
      entries: [_entry(id: 'same', updatedAt: updatedAt, price: 2)],
      deletions: const {},
    );
    final second = SyncSnapshot(
      entries: [_entry(id: 'same', updatedAt: updatedAt, price: 5)],
      deletions: const {},
    );

    expect(
      mergeSnapshots(first, second).entries.single.toJson(),
      mergeSnapshots(second, first).entries.single.toJson(),
    );
  });

  testWidgets('graphs carry forward the previous month budget', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final previousMonth = DateTime(now.year, now.month - 1);
    final previousBudgetKey =
        'fuel_monthly_budget_${previousMonth.year}_${previousMonth.month}';
    SharedPreferences.setMockInitialValues({previousBudgetKey: 250.0});

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GraphicsPage(
            distances: const {'current-month': 150},
            entries: [
              _entry(
                id: 'current-month',
                updatedAt: now,
                price: 5,
                date: now,
                odometer: 250,
              ),
              _entry(
                id: 'previous-month',
                updatedAt: now,
                price: 2,
                date: DateTime(now.year, now.month - 1),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Log my budget data'));
    await tester.pumpAndSettle();
    final budgetField = find.byKey(const ValueKey('monthly-budget-input'));
    expect(tester.widget<TextField>(budgetField).controller!.text, '250.00');
    expect(find.text('20% of \$250.00'), findsOneWidget);
    expect(find.text('28% of \$250.00'), findsNothing);
    expect(find.text('Miles driven'), findsOneWidget);
    expect(find.text('150.0 mi'), findsOneWidget);
    expect(find.text('Fuel efficiency'), findsOneWidget);
    expect(find.text('15.0 mi/gal'), findsOneWidget);
  });

  testWidgets('home graphs page shows monthly miles and fuel efficiency',
      (tester) async {
    final now = DateTime.now();
    final previousMonth = DateTime(now.year, now.month - 1, 15);
    final currentMonthEntry = _entry(
      id: 'current-month',
      updatedAt: now,
      price: 5,
      date: now,
      odometer: 1300,
    );
    final previousMonthEntry = _entry(
      id: 'previous-month',
      updatedAt: previousMonth,
      price: 2,
      date: previousMonth,
      odometer: 1000,
    );
    SharedPreferences.setMockInitialValues({
      'fuel_entries_v1':
          jsonEncode([previousMonthEntry.toJson(), currentMonthEntry.toJson()]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();

    expect(find.text('Miles driven'), findsOneWidget);
    expect(find.text('300.0 mi'), findsOneWidget);
    expect(find.text('30.0 mi/gal'), findsOneWidget);
  });

  testWidgets('saving a budget stores it for the current month',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GraphicsPage(
            distances: const {},
            entries: [
              _entry(
                id: 'current-month',
                updatedAt: now,
                price: 5,
                date: now,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Log my budget data'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('monthly-budget-input')),
      '100',
    );
    await tester.tap(find.text('Save monthly data'));
    await tester.pumpAndSettle();

    expect(find.text('Monthly budget data'), findsNothing);
    expect(
      find.text('Your data have been saved to the local disk.'),
      findsOneWidget,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getDouble('fuel_monthly_budget_${now.year}_${now.month}'),
      100,
    );
    expect(find.text('50% of \$100.00'), findsOneWidget);
    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).duration,
      const Duration(seconds: 10),
    );
  });

  testWidgets('monthly travel inputs save and comparison chart collapses',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();
    final previousMonth = DateTime(now.year, now.month - 1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GraphicsPage(
            distances: const {},
            entries: [
              _entry(
                id: 'current-month',
                updatedAt: now,
                price: 4,
                date: now,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('gross-monthly-income-input')), findsNothing);
    await tester.tap(find.text('Log my budget data'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gross-monthly-income-input')),
        findsOneWidget);
    expect(find.text('Save monthly data'), findsOneWidget);
    expect(find.text('Save budget'), findsNothing);
    expect(find.text('Save monthly details'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('gross-monthly-income-input')),
      '5000',
    );
    await tester.enterText(
      find.byKey(const ValueKey('monthly-insurance-input')),
      '150',
    );
    await tester.enterText(
      find.byKey(const ValueKey('monthly-car-payment-input')),
      '300',
    );
    await tester.tap(find.text('Save monthly data'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('gross-monthly-income-input')),
      findsNothing,
    );
    expect(
      find.text('Your data have been saved to the local disk.'),
      findsOneWidget,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getDouble('fuel_income_${now.year}_${now.month}'),
      5000,
    );
    expect(
      prefs.getDouble('fuel_insurance_${now.year}_${now.month}'),
      150,
    );
    expect(
      prefs.getDouble('fuel_car_payment_${now.year}_${now.month}'),
      300,
    );
    expect(find.text('Previous month travel expenses'), findsOneWidget);
    expect(find.text('Previous month insurance'), findsOneWidget);
    expect(find.text('\$0.00'), findsWidgets);

    final chartTitle =
        '${DateFormat.yMMMM().format(now)} vs ${DateFormat.yMMMM().format(previousMonth)}';
    await tester.tap(find.text(chartTitle));
    await tester.pumpAndSettle();
    expect(find.text('Current month travel expenses'), findsNothing);
    await tester.tap(find.text(chartTitle));
    await tester.pumpAndSettle();
    expect(find.text('Current month travel expenses'), findsOneWidget);
  });

  testWidgets('nearby sync requires a sender or receiver selection',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NearbySyncPage(
          snapshot: () => const SyncSnapshot(entries: [], deletions: {}),
          onSnapshotReceived: (_) async => 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Select a role before connecting or syncing.'),
      findsOneWidget,
    );
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Sender'))
            .selected,
        isFalse);
    await tester.tap(find.text('Receiver'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Receiver'))
          .selected,
      isTrue,
    );
    expect(
      find.text('This phone will receive and merge the Sender’s log.'),
      findsOneWidget,
    );
  });

  testWidgets('carousel swipes and controls navigate between app sections',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(home: HomePage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Log'), findsOneWidget);
    expect(find.byIcon(Icons.list_alt), findsOneWidget);
    expect(find.byIcon(Icons.bar_chart), findsOneWidget);
    expect(find.byIcon(Icons.pie_chart_outline), findsOneWidget);
    expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
    await tester.tap(find.text('Totals'));
    await tester.pumpAndSettle();
    expect(find.text('Totals'), findsOneWidget);
    expect(find.text('Export CSV'), findsOneWidget);
    expect(find.text('Load CSV'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('fuel-log-carousel')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Graphs'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous page'));
    await tester.pumpAndSettle();
    expect(find.text('Totals'), findsOneWidget);

    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Graphs'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous page'));
    await tester.pumpAndSettle();
    expect(find.text('Totals'), findsOneWidget);

    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Graphs'), findsOneWidget);

    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(
      find.text('Pump photo gallery is available on Android.'),
      findsOneWidget,
    );
  });

  testWidgets('log entries have a rounded yellow outline', (tester) async {
    final entry = _entry(
      id: 'outlined',
      updatedAt: DateTime(2026, 1, 1),
      price: 4,
    );
    SharedPreferences.setMockInitialValues({
      'fuel_entries_v1': jsonEncode([entry.toJson()]),
    });

    await tester.pumpWidget(
      MaterialApp(theme: buildTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();

    final outline = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration! as BoxDecoration).color == kYellow &&
          (widget.decoration! as BoxDecoration).borderRadius ==
              BorderRadius.circular(15),
    );
    final innerContainer = find.descendant(
      of: outline,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).color == kNavy800 &&
            (widget.decoration! as BoxDecoration).borderRadius ==
                BorderRadius.circular(13),
      ),
    );
    expect(outline, findsOneWidget);
    expect(innerContainer, findsOneWidget);
    expect(find.descendant(of: outline, matching: find.byType(ListTile)),
        findsOneWidget);
  });
}
