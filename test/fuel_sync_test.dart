import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_log/main.dart';
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

    expect(find.byType(TextField), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '250.00');
    expect(find.text('20% of \$250.00'), findsOneWidget);
    expect(find.text('28% of \$250.00'), findsOneWidget);
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

  testWidgets('Android Auto outputs open as a read-only Totals and Graphs page',
      (tester) async {
    final now = DateTime.now();
    final previousMonth = DateTime(now.year, now.month - 1, 15);
    final entries = [
      _entry(
        id: 'previous-month',
        updatedAt: previousMonth,
        price: 2,
        date: previousMonth,
        odometer: 1000,
      ),
      _entry(
        id: 'current-month',
        updatedAt: now,
        price: 5,
        date: now,
        odometer: 1300,
      ),
    ];
    SharedPreferences.setMockInitialValues({
      'fuel_entries_v1':
          jsonEncode(entries.map((entry) => entry.toJson()).toList()),
      'fuel_monthly_budget_${now.year}_${now.month}': 250.0,
    });

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open Android Auto outputs'));
    await tester.pumpAndSettle();

    expect(find.text('Totals'), findsOneWidget);
    expect(find.text('Graphs'), findsOneWidget);
    expect(find.text('300.0 mi'), findsNWidgets(3));
    expect(find.text('30.0 mi/gal'), findsNWidgets(3));
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('saving a budget stores it for the current month',
      (tester) async {
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

    await tester.enterText(find.byType(TextField), '100');
    await tester.tap(find.text('Save budget'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getDouble('fuel_monthly_budget_${now.year}_${now.month}'),
      100,
    );
    expect(find.text('50% of \$100.00'), findsNWidgets(2));
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
    await tester.drag(
      find.byKey(const ValueKey('fuel-log-carousel')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Totals'), findsOneWidget);

    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Graphs'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous page'));
    await tester.pumpAndSettle();
    expect(find.text('Totals'), findsOneWidget);
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

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
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
