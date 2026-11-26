import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
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

Future<void> _pumpStartupToCompletion(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

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

  testWidgets('snackbar text is readable in dark and light themes',
      (tester) async {
    for (final isDark in [true, false]) {
      final theme = buildTheme(isDark: isDark);
      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(MaterialApp(
        key: ValueKey(isDark),
        theme: theme,
        scaffoldMessengerKey: messengerKey,
        home: const Scaffold(),
      ));
      messengerKey.currentState!.showSnackBar(
        const SnackBar(content: Text('Snack message')),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final color =
          DefaultTextStyle.of(tester.element(find.text('Snack message')))
              .style
              .color!;
      final background = theme.snackBarTheme.backgroundColor!;
      final foregroundLuminance = color.computeLuminance();
      final backgroundLuminance = background.computeLuminance();
      final contrast = foregroundLuminance > backgroundLuminance
          ? (foregroundLuminance + 0.05) / (backgroundLuminance + 0.05)
          : (backgroundLuminance + 0.05) / (foregroundLuminance + 0.05);
      expect(contrast, greaterThanOrEqualTo(4.5));
      if (!isDark) expect(color, Colors.white);
    }
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
    await _pumpStartupToCompletion(tester);

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
    await _pumpStartupToCompletion(tester);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!.brightness,
      Brightness.light,
    );
    expect(find.byTooltip('Switch to dark theme'), findsOneWidget);
  });

  test('new palettes have readable text and controls', () {
    double contrast(Color first, Color second) {
      final a = first.computeLuminance();
      final b = second.computeLuminance();
      return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
    }

    for (final (isDark, palette) in [
      (true, ThemePalette.forest),
      (true, ThemePalette.purpleRaindrops),
      (false, ThemePalette.sage),
      (false, ThemePalette.rose),
    ]) {
      final theme = buildTheme(isDark: isDark, palette: palette);
      final scheme = theme.colorScheme;
      final pairs = [
        (scheme.onSurface, scheme.surface),
        (scheme.onSurface, scheme.surfaceContainerHighest),
        (scheme.onPrimary, scheme.primary),
        (scheme.onPrimaryContainer, scheme.primaryContainer),
        (theme.appBarTheme.foregroundColor!, theme.appBarTheme.backgroundColor!),
        (theme.snackBarTheme.contentTextStyle!.color!,
            theme.snackBarTheme.backgroundColor!),
      ];
      for (final (foreground, background) in pairs) {
        expect(contrast(foreground, background), greaterThanOrEqualTo(4.5),
            reason: '${palette.name}: $foreground on $background');
      }
      final selectorAccent = isDark ? scheme.primary : scheme.onSurface;
      expect(contrast(selectorAccent, scheme.surfaceContainerHighest),
          greaterThanOrEqualTo(3), reason: palette.name);
    }
  });

  testWidgets('palette menu remembers separate light and dark selections',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const FuelLogApp());
    await _pumpStartupToCompletion(tester);

    Future<void> openMenu() async {
      await tester.tap(find.byTooltip('Choose color palette'));
      await tester.pumpAndSettle();
    }

    Future<void> selectPalette(String name) async {
      await tester.tap(find.ancestor(
        of: find.text(name),
        matching: find.byType(CheckedPopupMenuItem<ThemePalette>),
      ));
      await tester.pumpAndSettle();
    }

    ThemeData currentTheme() =>
        tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;

    await openMenu();
    expect(find.text('Classic'), findsOneWidget);
    expect(find.text('Forest'), findsOneWidget);
    expect(find.text('Purple Raindrops'), findsOneWidget);
    expect(find.text('Sage'), findsNothing);
    await selectPalette('Forest');
    expect(currentTheme().scaffoldBackgroundColor,
        buildTheme(palette: ThemePalette.forest).scaffoldBackgroundColor);
    await openMenu();
    await selectPalette('Purple Raindrops');
    expect(currentTheme().scaffoldBackgroundColor,
        buildTheme(palette: ThemePalette.purpleRaindrops).scaffoldBackgroundColor);

    await tester.tap(find.byTooltip('Switch to light theme'));
    await tester.pumpAndSettle();
    expect(currentTheme().brightness, Brightness.light);
    await openMenu();
    expect(find.text('Classic'), findsOneWidget);
    expect(find.text('Sage'), findsOneWidget);
    expect(find.text('Rose'), findsOneWidget);
    expect(find.text('Purple Raindrops'), findsNothing);
    await selectPalette('Sage');
    expect(currentTheme().scaffoldBackgroundColor,
        buildTheme(isDark: false, palette: ThemePalette.sage).scaffoldBackgroundColor);
    await openMenu();
    await selectPalette('Rose');

    await tester.tap(find.byTooltip('Switch to dark theme'));
    await tester.pumpAndSettle();
    expect(currentTheme().scaffoldBackgroundColor,
        buildTheme(palette: ThemePalette.purpleRaindrops).scaffoldBackgroundColor);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('fuel_dark_palette_v1'), 'purpleRaindrops');
    expect(prefs.getString('fuel_light_palette_v1'), 'rose');
    await tester.pumpWidget(const FuelLogApp(key: ValueKey('palette-relaunch')));
    await _pumpStartupToCompletion(tester);
    expect(currentTheme().scaffoldBackgroundColor,
        buildTheme(palette: ThemePalette.purpleRaindrops).scaffoldBackgroundColor);
    await tester.tap(find.byTooltip('Switch to light theme'));
    await tester.pumpAndSettle();
    expect(currentTheme().scaffoldBackgroundColor,
        buildTheme(isDark: false, palette: ThemePalette.rose).scaffoldBackgroundColor);
    await openMenu();
    final rose = tester.widget<CheckedPopupMenuItem<ThemePalette>>(
      find.ancestor(
        of: find.text('Rose'),
        matching: find.byType(CheckedPopupMenuItem<ThemePalette>),
      ),
    );
    expect(rose.checked, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid palette is reported without losing other theme settings',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'fuel_theme_is_dark_v1': false,
      'fuel_dark_palette_v1': 'forest',
      'fuel_light_palette_v1': 'invalid',
    });
    final errors = <FlutterErrorDetails>[];
    final oldHandler = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = oldHandler);
    await tester.pumpWidget(const FuelLogApp());
    await _pumpStartupToCompletion(tester);

    var theme = tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;
    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor,
        buildTheme(isDark: false).scaffoldBackgroundColor);
    expect(errors, hasLength(1));
    expect(errors.single.exception, isA<FormatException>());
    await tester.tap(find.byTooltip('Switch to dark theme'));
    await tester.pumpAndSettle();
    theme = tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;
    expect(theme.scaffoldBackgroundColor,
        buildTheme(palette: ThemePalette.forest).scaffoldBackgroundColor);
  });

  testWidgets('startup shows local-data progress and privacy notice',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: HomePage()));

    expect(find.text('Loading Local Data'), findsOneWidget);
    expect(
      find.text(
        'This app does not sell/share/collect any data.',
      ),
      findsOneWidget,
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('% loaded'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Loading Local Data'), findsOneWidget);
    await _pumpStartupToCompletion(tester);
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
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('new fill-up form hides pump camera action on Windows',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: EntryForm())),
    );

    expect(find.byTooltip('Take pump photo'), findsNothing);
    expect(find.byIcon(Icons.photo_camera_outlined), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('new fill-up Save plays sound and retains form validation',
      (tester) async {
    var soundCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EntryForm(onNewSavePressed: () => soundCount++),
      ),
    ));

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(soundCount, 1);
    expect(find.text('Enter a number'), findsNWidgets(3));
    expect(find.byType(EntryForm), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Fuel price per gal'), '5');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount purchased'), '10');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Odometer reading'), '100');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(soundCount, 2);
  });

  testWidgets('notification permission is requested only after valid input',
      (tester) async {
    var requests = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EntryForm(onValidatedSavePressed: (_) => requests++),
      ),
    ));
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(requests, 0);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Fuel price per gal'), '5');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount purchased'), '10');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Odometer reading'), '100');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(requests, 1);
  });

  testWidgets('mute selector controls the new fill-up save sound',
      (tester) async {
    var soundCount = 0;
    final muteChanges = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EntryForm(
          onNewSavePressed: () => soundCount++,
          onSoundMutedChanged: muteChanges.add,
        ),
      ),
    ));

    expect(find.text('MUTE'), findsOneWidget);
    expect(find.byIcon(Icons.local_gas_station), findsOneWidget);
    await tester.tap(find.text('On'));
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(soundCount, 0);
    expect(find.text('Enter a number'), findsNWidgets(3));

    await tester.ensureVisible(find.text('Off'));
    await tester.tap(find.text('Off'));
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(soundCount, 1);
    expect(muteChanges, [true, false]);
  });

  testWidgets('mute control sits to the left of Save on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: EntryForm())),
    );
    await tester.ensureVisible(find.text('Save'));
    await tester.pump();

    final mute = tester.getRect(find.byType(SegmentedButton<bool>));
    final save = tester.getRect(find.widgetWithText(FilledButton, 'Save'));
    expect(mute.right, lessThan(save.left));
    expect(mute.center.dy, closeTo(save.center.dy, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('mute selection persists across form openings and app reloads',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    Future<void> openForm() async {
      await tester.tap(find.text('Fill-up'));
      await tester.pumpAndSettle();
    }

    Future<void> reloadApp(String key) async {
      await tester.pumpWidget(MaterialApp(
        key: ValueKey(key),
        home: const HomePage(),
      ));
      await _pumpStartupToCompletion(tester);
      await openForm();
    }

    await reloadApp('first');
    expect(
        tester
            .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
            .selected,
        {false});
    await tester.ensureVisible(find.text('On'));
    await tester.tap(find.text('On'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('fuel_save_sound_muted_v1'), isTrue);

    Navigator.of(tester.element(find.byType(EntryForm))).pop();
    await tester.pumpAndSettle();
    await openForm();
    expect(
        tester
            .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
            .selected,
        {true});

    await reloadApp('second');
    expect(
        tester
            .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
            .selected,
        {true});
    await tester.ensureVisible(find.text('Off'));
    await tester.tap(find.text('Off'));
    await tester.pumpAndSettle();
    expect(prefs.getBool('fuel_save_sound_muted_v1'), isFalse);
    await reloadApp('third');
    expect(
        tester
            .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
            .selected,
        {false});
  });

  testWidgets('muted new fill-up still saves without starting audio',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'fuel_save_sound_muted_v1': true,
    });
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const audioChannel = MethodChannel('xyz.luan/audioplayers');
    const globalAudioChannel = MethodChannel('xyz.luan/audioplayers.global');
    Future<dynamic> recordAudioCall(MethodCall call) async {
      calls.add(call);
      return null;
    }

    messenger.setMockMethodCallHandler(audioChannel, recordAudioCall);
    messenger.setMockMethodCallHandler(globalAudioChannel, recordAudioCall);
    addTearDown(() {
      messenger.setMockMethodCallHandler(audioChannel, null);
      messenger.setMockMethodCallHandler(globalAudioChannel, null);
    });
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await _pumpStartupToCompletion(tester);
    await tester.tap(find.text('Fill-up'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Fuel price per gal'), '5');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount purchased'), '10');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Odometer reading'), '100');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(
        jsonDecode(prefs.getString('fuel_entries_v1')!) as List, hasLength(1));
    expect(calls, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('editing a fill-up does not play the new-fill-up sound',
      (tester) async {
    var soundCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EntryForm(
          existing: _entry(
            id: 'existing',
            updatedAt: DateTime(2026, 1, 1),
            price: 2,
          ),
          onNewSavePressed: () => soundCount++,
        ),
      ),
    ));
    expect(find.text('MUTE'), findsNothing);
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(soundCount, 0);
  });

  testWidgets('coin-drop sound is bundled', (tester) async {
    final sound = await rootBundle.load('lib/assets/sounds/coin-drop.wav');
    expect(sound.lengthInBytes, greaterThan(0));
  });

  testWidgets('saving a fill-up posts the default custom chart on Android',
      (tester) async {
    final now = DateTime.now();
    final previous = DateTime(now.year, now.month - 1, 15);
    SharedPreferences.setMockInitialValues({
      'fuel_entries_v1': jsonEncode([
        _entry(id: 'previous', updatedAt: previous, price: 2, date: previous)
            .toJson(),
      ]),
      'fuel_insurance_${now.year}_${now.month}': 30.0,
      'fuel_car_payment_${now.year}_${now.month}': 20.0,
      'fuel_insurance_${previous.year}_${previous.month}': 5.0,
      'fuel_car_payment_${previous.year}_${previous.month}': 10.0,
    });
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(fuelLogNativeChannel, (call) async {
      calls.add(call);
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString('fuel_entries_v1')!) as List,
          hasLength(2));
      return true;
    });
    addTearDown(
        () => messenger.setMockMethodCallHandler(fuelLogNativeChannel, null));

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await _pumpStartupToCompletion(tester);
    await tester.tap(find.text('Fill-up'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Fuel price per gal'), '5');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount purchased'), '10');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Odometer reading'), '100');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(calls, hasLength(1));
    expect(calls.single.method, 'showTravelNotification');
    final args = calls.single.arguments as Map<dynamic, dynamic>;
    expect(args['title'], 'Fueled up: 10 gal - \$50.00');
    expect(args['firstLabel'], 'Current month travel expenses');
    expect(args['secondLabel'], 'Previous month travel expenses');
    expect(args['firstTotal'], 100.0);
    expect(args['secondTotal'], 35.0);
    expect(args['firstAmount'], '\$100.00');
    expect(args['secondAmount'], '\$35.00');
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('notification uses saved custom choices and negative amounts',
      (tester) async {
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'fuel_save_sound_muted_v1': true,
      'fuel_custom_chart_selection_v1': ['incomeAfterTravel', 'budget'],
      'fuel_income_${now.year}_${now.month}': 20.0,
      'fuel_monthly_budget_${now.year}_${now.month}': 100.0,
    });
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(fuelLogNativeChannel, (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(
        () => messenger.setMockMethodCallHandler(fuelLogNativeChannel, null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await _pumpStartupToCompletion(tester);
    await tester.tap(find.text('Fill-up'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Fuel price per gal'), '5');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount purchased'), '10');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Odometer reading'), '100');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final args = calls.single.arguments as Map<dynamic, dynamic>;
    expect(args['firstLabel'], 'Income after travel expenses');
    expect(args['secondLabel'], 'Monthly spending budget');
    expect(args['firstTotal'], -30.0);
    expect(args['secondTotal'], 100.0);
    expect(args['firstAmount'], '-\$30.00');
    expect(args['secondAmount'], '\$100.00');
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('denied notification leaves the saved fill-up and reports it',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        fuelLogNativeChannel, (call) async => false);
    addTearDown(
        () => messenger.setMockMethodCallHandler(fuelLogNativeChannel, null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await _pumpStartupToCompletion(tester);
    await tester.tap(find.text('Fill-up'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Fuel price per gal'), '5');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount purchased'), '10');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Odometer reading'), '100');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Fill-up saved, but notification failed:'),
        findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(
        jsonDecode(prefs.getString('fuel_entries_v1')!) as List, hasLength(1));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('notification cancellation calls Android and propagates errors',
      (tester) async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(fuelLogNativeChannel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
        () => messenger.setMockMethodCallHandler(fuelLogNativeChannel, null));

    await FuelLogNotifications.cancel();
    expect(calls.single.method, 'cancelTravelNotification');
    messenger.setMockMethodCallHandler(fuelLogNativeChannel, (call) async {
      throw PlatformException(code: 'cancel_failed');
    });
    await expectLater(FuelLogNotifications.cancel(),
        throwsA(isA<PlatformException>()));
  });

  testWidgets('Windows notification uses saved fill-up and chart selection',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'fuel_save_sound_muted_v1': true,
      'fuel_custom_chart_selection_v1': ['currentFuel', 'allTimeFuel'],
    });
    const channel = MethodChannel('io.github.tlaw22.fuellog/windows_notification');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await _pumpStartupToCompletion(tester);
    await tester.tap(find.text('Fill-up'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Fuel price per gal'), '5');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount purchased'), '10,123450');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Odometer reading'), '100');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(calls.single.method, 'show');
    final args = calls.single.arguments as Map<dynamic, dynamic>;
    expect(args['title'], 'Fueled up: 10,123450 gal - \$50.62');
    expect(args['fillUp'], contains('10.1 gal, \$50.62'));
    expect(args['firstLabel'], 'Fuel this month');
    expect(args['secondLabel'], 'All-time fuel spending');
    expect(args['firstAmount'], '\$50.62');
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString('fuel_entries_v1')!) as List, hasLength(1));
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('Windows notification failure does not prevent saving',
      (tester) async {
    SharedPreferences.setMockInitialValues({'fuel_save_sound_muted_v1': true});
    const channel = MethodChannel('io.github.tlaw22.fuellog/windows_notification');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
          code: 'notification_failed',
          message: 'Notifications are disabled in Windows notification settings.');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await _pumpStartupToCompletion(tester);
    await tester.tap(find.text('Fill-up'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Fuel price per gal'), '5');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount purchased'), '10');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Odometer reading'), '100');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Fill-up saved, but notification failed:'),
        findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString('fuel_entries_v1')!) as List, hasLength(1));
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('AppBar menu includes Bluetooth share, reports, CSV, and backups',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          bluetoothSharePageBuilder: (snapshot, onSnapshotReceived) =>
              const Text('Bluetooth File Sharing'),
        ),
      ),
    );
    await _pumpStartupToCompletion(tester);

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

    expect(find.text('Bluetooth Share'), findsOneWidget);
    expect(find.byIcon(Icons.bluetooth), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Bluetooth Share')).dy,
      lessThan(tester.getTopLeft(find.text('Reports')).dy),
    );
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Load CSV'), findsOneWidget);
    expect(find.text('Save CSV'), findsOneWidget);
    expect(find.text('Share CSV backup'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Wipe Data'), findsOneWidget);
  });

  testWidgets('Windows CSV actions open import and save pickers',
      (tester) async {
    const fileSelectorChannel =
        MethodChannel('plugins.flutter.io/file_selector');
    final calls = <MethodCall>[];
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    binaryMessenger.setMockMethodCallHandler(
      fileSelectorChannel,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(() {
      binaryMessenger.setMockMethodCallHandler(fileSelectorChannel, null);
    });

    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await _pumpStartupToCompletion(tester);

    Future<void> selectMenuItem(String label) async {
      await tester.tap(find.byTooltip('App menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    await selectMenuItem('Load CSV');
    await selectMenuItem('Save CSV');
    await selectMenuItem('Share CSV backup');

    expect(
      calls.map((call) => call.method),
      ['openFile', 'getSavePath', 'getSavePath'],
    );
    final saveCalls = calls.where((call) => call.method == 'getSavePath');
    for (final call in saveCalls) {
      final arguments = call.arguments as Map<dynamic, dynamic>;
      expect(arguments['suggestedName'], endsWith('.csv'));
      expect(arguments['acceptedTypeGroups'], isNotEmpty);
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

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
      'fuel_reports_v1': jsonEncode([
        {'fileName': 'fuel_log_report_old.txt', 'contents': 'Old report'},
      ]),
      'fuel_theme_is_dark_v1': false,
      'fuel_dark_palette_v1': 'forest',
      'fuel_light_palette_v1': 'rose',
    });

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await _pumpStartupToCompletion(tester);
    expect(find.byType(Dismissible), findsOneWidget);

    await tester.tap(find.byTooltip('App menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wipe Data'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Fill-ups can only be restored from a backup CSV'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'generated reports, and pump photos are not included in CSV',
      ),
      findsOneWidget,
    );

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
    expect(prefs.getString('fuel_reports_v1'), isNull);
    expect(prefs.getBool('fuel_theme_is_dark_v1'), isFalse);
    expect(prefs.getString('fuel_dark_palette_v1'), 'forest');
    expect(prefs.getString('fuel_light_palette_v1'), 'rose');
    expect(find.text('App data wiped.'), findsOneWidget);
  });

  testWidgets('Windows wipe continues if notification removal fails',
      (tester) async {
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'fuel_entries_v1':
          jsonEncode([_entry(id: 'entry', updatedAt: now, price: 5).toJson()]),
    });
    const channel = MethodChannel('io.github.tlaw22.fuellog/windows_notification');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'cancel');
      throw PlatformException(code: 'notification_failed');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await _pumpStartupToCompletion(tester);
    await tester.tap(find.byTooltip('App menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wipe Data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wipe data'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('fuel_entries_v1'), isNull);
    expect(
        find.textContaining('App data wiped, but notification could not be removed:'),
        findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('About menu displays the bundled README', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await _pumpStartupToCompletion(tester);

    await tester.tap(find.byTooltip('App menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();

    expect(find.text('About Fuel Log'), findsOneWidget);
    expect(find.text('View project on GitHub'), findsOneWidget);
    expect(find.text('https://github.com/tlaw22/fuel_log'), findsOneWidget);
    final projectUrl = find.text('https://github.com/tlaw22/fuel_log');
    final selectableUrl =
        find.ancestor(of: projectUrl, matching: find.byType(SelectableText));
    final urlText = tester.widget<SelectableText>(selectableUrl);
    final defaultSize =
        DefaultTextStyle.of(tester.element(selectableUrl)).style.fontSize;
    expect(urlText.style?.fontSize, defaultSize! / 2);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is FaIcon &&
            widget.icon?.codePoint == FontAwesomeIcons.github.codePoint,
      ),
      findsOneWidget,
    );
    final readme =
        find.textContaining('A Flutter app for tracking fuel fill-ups');
    expect(readme, findsOneWidget);
    final selectableReadme =
        find.ancestor(of: readme, matching: find.byType(SelectableText));
    final readmeText = tester.widget<SelectableText>(selectableReadme);
    expect(readmeText.style?.fontSize, 10);
    expect(readmeText.style?.fontFamily, 'Oswald');
    final spans = readmeText.textSpan!.children!;
    final heading = spans.first as TextSpan;
    final body = spans.last as TextSpan;
    expect(heading.text!.trimRight(), '# Fuel Log');
    expect(heading.style?.fontFamily, 'Pacifico');
    expect(body.text!.replaceAll('\r\n', '\n'),
        startsWith('\n\nA Flutter app for tracking fuel fill-ups'));
    expect(body.style?.fontFamily, isNull);
    expect('${heading.text}${body.text}', await rootBundle.loadString('README.md'));
  });

  testWidgets('About page download button opens the releases page',
      (tester) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodCall? launch;
    messenger.setMockMethodCallHandler(channel, (call) async {
      launch = call;
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AboutSheet())),
    );
    await tester.pump();

    final button = find.text('Download Other Platroms');
    expect(button, findsOneWidget);
    for (final name in ['Windows', 'Firefox', 'Android']) {
      final avatar = find.byTooltip(name);
      expect(avatar, findsOneWidget);
      expect(
          tester.getTopLeft(avatar).dx, lessThan(tester.getTopLeft(button).dx));
    }
    for (final icon in [
      FontAwesomeIcons.windows,
      FontAwesomeIcons.firefox,
      FontAwesomeIcons.android,
    ]) {
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is FaIcon && widget.icon?.codePoint == icon.codePoint,
        ),
        findsOneWidget,
      );
    }
    await tester.tap(button);
    await tester.pump();
    expect(launch?.method, 'launch');
    expect(
        launch?.arguments['url'], 'https://github.com/tlaw22/fuel_log/releases');
    expect(launch?.arguments['useWebView'], false);
    expect(tester.takeException(), isNull);
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

  testWidgets('charts carry forward the previous month budget', (tester) async {
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
          body: ChartsPage(
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

  testWidgets('chart summaries show their pie percentages beside the figures',
      (tester) async {
    tester.view.physicalSize = const Size(320, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final previousMonth = DateTime(now.year, now.month - 1, 15);
    SharedPreferences.setMockInitialValues({
      'fuel_monthly_budget_${now.year}_${now.month}': 250.0,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChartsPage(
            distances: const {},
            entries: [
              _entry(id: 'current', updatedAt: now, price: 5, date: now),
              _entry(
                id: 'previous',
                updatedAt: now,
                price: 2,
                date: previousMonth,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('20% / 80%'), findsOneWidget);
    expect(find.text('28% / 72%'), findsNothing);
    expect(find.text('71% / 29%'), findsNWidgets(2));
    expect(tester.getTopLeft(find.text('Spent').first).dx,
        lessThan(tester.getTopLeft(find.text('20% / 80%')).dx));
    expect(
        tester.getTopLeft(find.text('Current month travel expenses').first).dx,
        lessThan(tester.getTopLeft(find.text('71% / 29%').first).dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('chart pies handle overspending and empty comparisons',
      (tester) async {
    tester.view.physicalSize = const Size(320, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'fuel_monthly_budget_${now.year}_${now.month}': 25.0,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChartsPage(
            distances: const {},
            entries: [
              _entry(id: 'old', updatedAt: now, price: 5, date: DateTime(2020)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('0% / 100%'), findsOneWidget);
    expect(find.text('100% / 0%'), findsNothing);
    expect(find.text('Over budget by \$25.00'), findsNothing);
    expect(find.text('No data'), findsNWidgets(2));
    expect(find.text('Total distance traveled this month: 0.0 mi'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('middle chart totals only the current month distance',
      (tester) async {
    tester.view.physicalSize = const Size(320, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChartsPage(
          entries: [
            _entry(id: 'first', updatedAt: now, price: 2, date: now),
            _entry(id: 'second', updatedAt: now, price: 3, date: now),
            _entry(
              id: 'previous',
              updatedAt: now,
              price: 1,
              date: DateTime(now.year, now.month - 1, 15),
            ),
          ],
          distances: const {'first': 125.5, 'second': 40, 'previous': 900},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final title = find.text(
        '${DateFormat.yMMMM().format(now)} vs ${DateFormat.yMMMM().format(DateTime(now.year, now.month - 1))}');
    final chart = find.ancestor(of: title, matching: find.byType(Card));
    expect(
      find.descendant(
        of: chart,
        matching: find.text('Total distance traveled this month: 165.5 mi'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom chart selectors share a card and fit side by side',
      (tester) async {
    tester.view.physicalSize = const Size(320, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ChartsPage(entries: [], distances: {})),
    ));
    await tester.pumpAndSettle();

    final first = find.byKey(const ValueKey('custom-chart-First amount'));
    final second = find.byKey(const ValueKey('custom-chart-Second amount'));
    final card = find.ancestor(of: first, matching: find.byType(Card)).first;
    expect(find.descendant(of: card, matching: second), findsOneWidget);
    expect(
      find.descendant(
        of: card,
        matching: find.text('select two values to compare'),
      ),
      findsOneWidget,
    );
    expect(tester.getTopLeft(first).dy, tester.getTopLeft(second).dy);
    expect(tester.getTopLeft(first).dx, lessThan(tester.getTopLeft(second).dx));
    await tester.tap(first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fuel this month').last);
    await tester.pumpAndSettle();
    await tester.tap(second);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Previous month fuel').last);
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('fuel_custom_chart_selection_v1'),
        ['currentFuel', 'previousFuel']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom chart selectors stand out in both themes',
      (tester) async {
    tester.view.physicalSize = const Size(320, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    double contrast(Color first, Color second) {
      final a = first.computeLuminance();
      final b = second.computeLuminance();
      return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
    }

    for (final isDark in [true, false]) {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(MaterialApp(
        key: ValueKey(isDark),
        theme: buildTheme(isDark: isDark),
        home: const Scaffold(body: ChartsPage(entries: [], distances: {})),
      ));
      await tester.pumpAndSettle();
      for (final label in ['First amount', 'Second amount']) {
        final selector = find.byKey(ValueKey('custom-chart-$label'));
        final decorator = tester.widget<InputDecorator>(
          find.ancestor(of: selector, matching: find.byType(InputDecorator)).first,
        );
        final decoration = decorator.decoration;
        final fill = decoration.fillColor!;
        final border = decoration.enabledBorder! as OutlineInputBorder;
        final dropdown = tester.widget<DropdownButton<dynamic>>(selector);
        expect(decoration.filled, isTrue);
        expect(contrast(border.borderSide.color, fill), greaterThanOrEqualTo(3));
        expect(contrast(dropdown.style!.color!, fill), greaterThanOrEqualTo(4.5));
        expect(contrast(dropdown.iconEnabledColor!, fill), greaterThanOrEqualTo(3));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('custom chart selections update labels, percentages and persist',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'fuel_insurance_${now.year}_${now.month}': 30.0,
    });
    final entry = _entry(id: 'current', updatedAt: now, price: 5, date: now);
    Future<void> loadChart(String key) async {
      await tester.pumpWidget(MaterialApp(
        key: ValueKey(key),
        home: Scaffold(
          body: ChartsPage(entries: [entry], distances: const {}),
        ),
      ));
      await tester.pumpAndSettle();
    }

    await loadChart('first');
    final customTitle = find.text('Custom Chart');
    final monthTitle = find.text(
        '${DateFormat.yMMMM().format(now)} vs ${DateFormat.yMMMM().format(DateTime(now.year, now.month - 1))}');
    expect(tester.getTopLeft(customTitle).dy,
        greaterThan(tester.getTopLeft(monthTitle).dy));
    expect(find.text('All-time spending'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('custom-chart-First amount')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fuel this month').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('custom-chart-Second amount')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insurance payment').last);
    await tester.pumpAndSettle();
    expect(find.text('63% / 37%'), findsOneWidget);
    final card = find.ancestor(of: customTitle, matching: find.byType(Card));
    expect(find.descendant(of: card, matching: find.text('Fuel this month')),
        findsNWidgets(2));
    expect(find.descendant(of: card, matching: find.text('Insurance payment')),
        findsNWidgets(2));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('fuel_custom_chart_selection_v1'),
        ['currentFuel', 'currentInsurance']);

    await loadChart('second');
    expect(find.text('63% / 37%'), findsOneWidget);
    expect(
        find.descendant(
            of: find.ancestor(
                of: find.text('Custom Chart'), matching: find.byType(Card)),
            matching: find.text('Fuel this month')),
        findsNWidgets(2));
  });

  testWidgets('custom chart reports a negative amount instead of a percentage',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'fuel_custom_chart_selection_v1': ['incomeAfterTravel', 'currentFuel'],
      'fuel_income_${now.year}_${now.month}': 20.0,
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChartsPage(
          entries: [_entry(id: 'current', updatedAt: now, price: 5, date: now)],
          distances: const {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Negative amount'), findsOneWidget);
    expect(find.text('-\$30.00'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom chart distinguishes an unset budget from zero',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'fuel_custom_chart_selection_v1': ['budget', 'currentFuel'],
    });
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ChartsPage(entries: [], distances: {})),
    ));
    await tester.pumpAndSettle();
    final card = find.ancestor(
        of: find.text('Custom Chart'), matching: find.byType(Card));
    expect(find.descendant(of: card, matching: find.text('Not set')),
        findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('No data')),
        findsOneWidget);
  });

  testWidgets('home charts page shows monthly miles and fuel efficiency',
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
    await _pumpStartupToCompletion(tester);
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
          body: ChartsPage(
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
          body: ChartsPage(
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
    final chartTitle =
        '${DateFormat.yMMMM().format(now)} vs ${DateFormat.yMMMM().format(previousMonth)}';
    final card = find.ancestor(
        of: find.text(chartTitle), matching: find.byType(Card));
    Finder inTravelChart(String text) =>
        find.descendant(of: card, matching: find.text(text));
    expect(inTravelChart('Previous month travel expenses'), findsOneWidget);
    expect(inTravelChart('Previous month insurance'), findsOneWidget);
    expect(find.text('\$0.00'), findsWidgets);

    await tester.tap(find.text(chartTitle));
    await tester.pumpAndSettle();
    expect(inTravelChart('Current month travel expenses'), findsNothing);
    await tester.tap(find.text(chartTitle));
    await tester.pumpAndSettle();
    expect(inTravelChart('Current month travel expenses'), findsOneWidget);
  });

  testWidgets('Bluetooth sharing entry point is optional per build variant',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await _pumpStartupToCompletion(tester);
    expect(find.text('Bluetooth Share'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          bluetoothSharePageBuilder: (snapshot, onSnapshotReceived) =>
              const Text('Bluetooth File Sharing'),
        ),
      ),
    );
    await _pumpStartupToCompletion(tester);
    expect(find.text('Bluetooth Share'), findsNothing);
    await tester.tap(find.byTooltip('App menu'));
    await tester.pumpAndSettle();
    expect(find.text('Bluetooth Share'), findsOneWidget);
    expect(find.byIcon(Icons.bluetooth), findsOneWidget);
  });

  testWidgets('F-Droid build disables the Bluetooth sharing menu action',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      FuelLogApp(
        bluetoothShareEnabled: false,
        bluetoothSharePageBuilder: (snapshot, onSnapshotReceived) =>
            const Text('Bluetooth File Sharing'),
      ),
    );
    await _pumpStartupToCompletion(tester);
    await tester.tap(find.byTooltip('App menu'));
    await tester.pumpAndSettle();

    expect(
      find.ancestor(
        of: find.text('Bluetooth Share'),
        matching: find.byWidgetPredicate(
          (widget) => widget is PopupMenuItem && !widget.enabled,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('pairing guide opens as a slideshow and sharing is disabled',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BtSharePage(
          enabled: false,
          snapshot: () => const SyncSnapshot(entries: [], deletions: {}),
          onSnapshotReceived: (_) async => 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final beginButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Begin Bluetooth File Sharing'),
    );
    expect(beginButton.onPressed, isNull);

    await tester.tap(find.text('How to pair two phones'));
    await tester.pumpAndSettle();
    expect(find.text('Pair the phones'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Choose the paired phone'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Receive, then send'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Pairing guide'), findsNothing);
  });

  testWidgets('paired phone selection enables Bluetooth sharing',
      (tester) async {
    const channel = MethodChannel('io.github.tlaw22.fuellog/native');
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    binaryMessenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'androidSdkInt':
          return 30;
        case 'listPairedBluetoothDevices':
          return [
            {'name': 'FuelLog test phone', 'address': '00:11:22:33:44:55'},
          ];
        default:
          return null;
      }
    });
    addTearDown(() {
      binaryMessenger.setMockMethodCallHandler(channel, null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: BtSharePage(
          snapshot: () => const SyncSnapshot(entries: [], deletions: {}),
          onSnapshotReceived: (_) async => 0,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('FuelLog test phone'));
    await tester.pumpAndSettle();

    final pairedIndicator = tester.widget<FilledButton>(
      find.widgetWithText(
        FilledButton,
        'Phones are paired: FuelLog test phone',
      ),
    );
    final beginButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Begin Bluetooth File Sharing'),
    );
    expect(pairedIndicator.onPressed, isNull);
    expect(beginButton.onPressed, isNotNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('Reports button opens the reports list', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await _pumpStartupToCompletion(tester);

    await tester.tap(find.byTooltip('Reports'));
    await tester.pumpAndSettle();

    expect(find.text('Generate Report'), findsOneWidget);
    expect(
      find.text('No reports yet. Select Generate Report to create one.'),
      findsOneWidget,
    );
  });

  testWidgets('generates, lists, and opens a text report', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final entry = _entry(
      id: 'report-entry',
      updatedAt: DateTime(2026, 1, 2),
      date: DateTime(2026, 1, 2),
      price: 4,
      odometer: 120,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReportsPage(entries: [entry], distances: const {}),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Generate Report'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('fuel_reports_v1')!) as List;
    expect(saved, hasLength(1));
    expect(saved.single['contents'], contains('Fuel Log Report'));
    expect(saved.single['contents'], contains('Fill-ups: 1'));
    expect(saved.single['contents'], isNot(contains('Total spending logged:')));
    expect(
      saved.single['contents'],
      contains('Monthly summary (up to 2 most recent months):'),
    );
    expect(find.textContaining('fuel_log_report_'), findsOneWidget);

    await tester.tap(find.textContaining('fuel_log_report_'));
    await tester.pumpAndSettle();
    final report = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(report.data, contains('Fill-ups: 1'));
    expect(report.data, contains('Odometer: 120.0 mi'));
    expect(report.data, contains('January 2026 | Fill-ups: 1'));
    expect(report.data, isNot(contains('Total spending logged:')));
    expect(find.text('Download Report'), findsOneWidget);
    expect(find.text('Share Report'), findsOneWidget);
  });

  testWidgets(
      'reports include monthly summaries for only the latest two months',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final entries = [
      _entry(
        id: 'january-entry',
        date: DateTime(2026, 1, 15),
        updatedAt: DateTime(2026, 1, 15),
        price: 3,
      ),
      _entry(
        id: 'february-entry',
        date: DateTime(2026, 2, 15),
        updatedAt: DateTime(2026, 2, 15),
        price: 3,
      ),
      _entry(
        id: 'march-entry',
        date: DateTime(2026, 3, 15),
        updatedAt: DateTime(2026, 3, 15),
        price: 3,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(home: ReportsPage(entries: entries, distances: const {})),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Generate Report'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('fuel_reports_v1')!) as List;
    final contents = saved.single['contents'] as String;
    final monthlySummary =
        contents.split('Fill-up details (oldest to newest):').first;
    expect(monthlySummary, contains('March 2026 | Fill-ups: 1'));
    expect(monthlySummary, contains('February 2026 | Fill-ups: 1'));
    expect(monthlySummary, isNot(contains('January 2026 |')));
    expect(contents, contains('Jan 15, 2026'));
  });

  testWidgets('Bluetooth file sharing requires a sender or receiver role',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BluetoothFileSharingPage(
          device: const PairedBluetoothDevice(
            name: 'Paired phone',
            address: '00:11:22:33:44:55',
          ),
          snapshot: () => const SyncSnapshot(entries: [], deletions: {}),
          onSnapshotReceived: (_) async => 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Choose a role to begin.'),
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
      find.text('Wait for sender'),
      findsOneWidget,
    );
  });

  testWidgets('carousel swipes and controls navigate between app sections',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(home: HomePage()),
    );
    await _pumpStartupToCompletion(tester);

    expect(find.text('Log'), findsOneWidget);
    expect(find.byIcon(Icons.list_alt), findsOneWidget);
    expect(find.byIcon(Icons.bar_chart), findsOneWidget);
    expect(find.byIcon(Icons.pie_chart_outline), findsOneWidget);
    expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
    final chartsNavigation = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == 'Charts page',
    );
    expect(chartsNavigation, findsOneWidget);
    expect(
      find.descendant(
          of: chartsNavigation, matching: find.byIcon(Icons.pie_chart_outline)),
      findsOneWidget,
    );
    expect(find.text('Graphs'), findsNothing);
    await tester.tap(find.text('Charts'));
    await tester.pumpAndSettle();
    expect(find.text('Log my budget data'), findsOneWidget);
    await tester.tap(find.text('Totals'));
    await tester.pumpAndSettle();
    expect(find.text('Totals'), findsOneWidget);
    expect(find.text('Export CSV'), findsNothing);
    expect(find.text('Load CSV'), findsNothing);

    await tester.drag(
      find.byKey(const ValueKey('fuel-log-carousel')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Charts'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous page'));
    await tester.pumpAndSettle();
    expect(find.text('Totals'), findsOneWidget);

    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Charts'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous page'));
    await tester.pumpAndSettle();
    expect(find.text('Totals'), findsOneWidget);

    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Charts'), findsOneWidget);
  });

  testWidgets('Linux Photos page offers access to the Pictures folder',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PumpPhotosPage()),
    );
    await tester.pump();

    expect(find.text('Pictures'), findsOneWidget);
    expect(find.text('Open Pictures Folder'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('Windows Photos page shows the Android-only feature button',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PumpPhotosPage()),
    );

    final featureButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Android Only Feature'),
    );
    expect(featureButton.onPressed, isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('Android Photos page keeps the saved pump photo gallery',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PumpPhotosPage()),
    );

    expect(find.text('Pump Photos'), findsOneWidget);
    expect(find.byTooltip('Refresh photos'), findsOneWidget);
    expect(find.text('Android Only Feature'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('Photos page offers downloads and reports launch failures',
      (tester) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodCall? launch;
    messenger.setMockMethodCallHandler(channel, (call) async {
      launch = call;
      return false;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.binding.setSurfaceSize(const Size(400, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PumpPhotosPage())),
    );
    await tester.pump();

    expect(find.byTooltip('Windows'), findsOneWidget);
    expect(find.byTooltip('Firefox'), findsOneWidget);
    expect(find.byTooltip('Android'), findsOneWidget);
    await tester.tap(find.text('Download Other Platroms'));
    await tester.pump();
    expect(
        launch?.arguments['url'], 'https://github.com/tlaw22/fuel_log/releases');
    expect(
        find.textContaining('Could not open the releases page:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({
    TargetPlatform.android,
    TargetPlatform.windows,
    TargetPlatform.linux,
  }));

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
    await _pumpStartupToCompletion(tester);

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

  testWidgets('loaded duplicate odometers are marked and update on deletion',
      (tester) async {
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'fuel_entries_v1': jsonEncode([
        _entry(id: 'a', updatedAt: now, price: 2, odometer: 100).toJson(),
        _entry(id: 'b', updatedAt: now, price: 3, odometer: 100).toJson(),
        _entry(id: 'c', updatedAt: now, price: 4, odometer: 100.04).toJson(),
      ]),
    });
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await _pumpStartupToCompletion(tester);

    Finder badgeFor(String id) => find.descendant(
          of: find.byKey(ValueKey(id)),
          matching: find.text('DUPLICATE'),
        );
    expect(badgeFor('a'), findsOneWidget);
    expect(badgeFor('b'), findsOneWidget);
    expect(badgeFor('c'), findsNothing);
    await tester.drag(find.byKey(const ValueKey('a')), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('DUPLICATE'), findsNothing);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('DUPLICATE'), findsNWidgets(2));
  });

  testWidgets('new and edited fill-ups update duplicate labels',
      (tester) async {
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'fuel_entries_v1': jsonEncode([
        _entry(id: 'existing', updatedAt: now, price: 2, odometer: 100)
            .toJson(),
      ]),
    });
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await _pumpStartupToCompletion(tester);
    await tester.tap(find.text('Fill-up'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Fuel price per gal'), '5');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount purchased'), '10');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Odometer reading'), '100');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('DUPLICATE'), findsNWidgets(2));

    final tile = find
        .ancestor(
          of: find.textContaining('\$50.00'),
          matching: find.byType(ListTile),
        )
        .first;
    await tester.tap(find.descendant(
      of: tile,
      matching: find.byIcon(Icons.edit_outlined),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Edit fill-up'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).last, '200');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('DUPLICATE'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('CSV replacement and Bluetooth merge update duplicate labels',
      (tester) async {
    final directory = await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('fuel_log_test_');
      final csv = File('${directory.path}${Platform.pathSeparator}entries.csv');
      await csv.writeAsString(
        'Date,Odometer (mi),Price per gal,Amount (gal)\n'
        '2026-01-01,100,2,10\n'
        '2026-01-02,100,3,10\n',
      );
      return directory;
    });
    expect(directory, isNotNull);
    final tempDirectory = directory!;
    addTearDown(() => tempDirectory.delete(recursive: true));
    final csv =
        File('${tempDirectory.path}${Platform.pathSeparator}entries.csv');
    const channel = MethodChannel('plugins.flutter.io/file_selector');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => [csv.path]);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    SharedPreferences.setMockInitialValues({});
    late Future<int> Function(SyncSnapshot) receive;
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: HomePage(
          bluetoothSharePageBuilder: (snapshot, onSnapshotReceived) {
            receive = onSnapshotReceived;
            return const Scaffold(body: Text('Bluetooth test'));
          },
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('App menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load CSV'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 100 && find.text('Replace').evaluate().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
      expect(find.text('Replace'), findsOneWidget);
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      expect(find.text('DUPLICATE'), findsNWidgets(2));

      await tester.tap(find.byTooltip('App menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bluetooth Share'));
      await tester.pumpAndSettle();
      final now = DateTime.now();
      await receive(SyncSnapshot(entries: [
        _entry(id: 'synced', updatedAt: now, price: 4, odometer: 100),
        _entry(id: 'unique', updatedAt: now, price: 5, odometer: 200),
      ], deletions: const {}));
      Navigator.of(tester.element(find.text('Bluetooth test'))).pop();
      await tester.pumpAndSettle();
      expect(find.text('DUPLICATE'), findsNWidgets(3));
      expect(find.byKey(const ValueKey('unique')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('unique')),
          matching: find.text('DUPLICATE'),
        ),
        findsNothing,
      );
    });
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
