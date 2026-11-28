/// Application settings page.
/// Manages theme, palette, text scale, animation, photo folder, and launch preferences.
part of '../app.dart';

class _SettingsActions extends InheritedWidget {
  final VoidCallback onLogBudgetData;
  final VoidCallback onLunchBudget;

  const _SettingsActions({
    required this.onLogBudgetData,
    required this.onLunchBudget,
    required super.child,
  });

  static _SettingsActions? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SettingsActions>();

  @override
  bool updateShouldNotify(_SettingsActions oldWidget) => false;
}

class _SettingsPage extends StatefulWidget {
  final bool Function() isDarkTheme;
  final ThemePalette Function() selectedPalette;
  final int Function() fontSizePercent;
  final bool Function() bubblesEnabled;
  final int? Function() launchCount;
  final VoidCallback onToggleTheme;
  final ValueChanged<ThemePalette> onSelectPalette;
  final ValueChanged<int> onSetFontSize;
  final ValueChanged<bool> onSetBubblesEnabled;

  const _SettingsPage({
    required this.isDarkTheme,
    required this.selectedPalette,
    required this.fontSizePercent,
    required this.bubblesEnabled,
    required this.launchCount,
    required this.onToggleTheme,
    required this.onSelectPalette,
    required this.onSetFontSize,
    required this.onSetBubblesEnabled,
  });

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  String? _photoFolder;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(() => _photoFolder = prefs.getString(_photoFolderPrefsKey));
      }
    });
  }

  Future<void> _choosePhotoFolder() async {
    final directory = await getDirectoryPath(
      initialDirectory: _photoFolder,
      confirmButtonText: 'Select folder',
    );
    if (directory == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_photoFolderPrefsKey, directory);
    if (mounted) setState(() => _photoFolder = directory);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDarkTheme();
    final palette = widget.selectedPalette();
    final fontSize = widget.fontSizePercent();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_SettingsActions.maybeOf(context) case final actions?) ...[
            FilledButton.icon(
              onPressed: actions.onLogBudgetData,
              icon: const Icon(Icons.edit_note),
              label: const Text('Log my budget data'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: actions.onLunchBudget,
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: const Text('Lunch budget'),
            ),
            const SizedBox(height: 16),
          ],
          Text('Appearance', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Dark mode'),
                  value: isDark,
                  onChanged: (_) => setState(widget.onToggleTheme),
                ),
                const Divider(height: 1),
                _ThemePaletteMenu(
                  isDark: isDark,
                  selected: palette,
                  onSelected: (value) =>
                      setState(() => widget.onSelectPalette(value)),
                  child: ListTile(
                    leading: const Icon(Icons.palette_outlined),
                    title: const Text('Color palette'),
                    subtitle: Text(_paletteName(palette, isDark)),
                    trailing: const Icon(Icons.arrow_drop_down),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Font size'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Decrease font size',
                        onPressed: fontSize == _minFontSizePercent
                            ? null
                            : () => setState(() =>
                                widget.onSetFontSize(fontSize - _fontSizeStep)),
                        icon: const Icon(Icons.remove),
                      ),
                      Text('$fontSize%'),
                      IconButton(
                        tooltip: 'Increase font size',
                        onPressed: fontSize == _maxFontSizePercent
                            ? null
                            : () => setState(() =>
                                widget.onSetFontSize(fontSize + _fontSizeStep)),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.bubble_chart_outlined),
                  title: const Text('Animated bubbles'),
                  value: widget.bubblesEnabled(),
                  onChanged: (value) =>
                      setState(() => widget.onSetBubblesEnabled(value)),
                ),
              ],
            ),
          ),
          if (!kIsWeb && Platform.isWindows) ...[
            const SizedBox(height: 16),
            Text('Photos', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('Photo folder'),
                subtitle: Text(_photoFolder ?? 'Not set (jpg, jpeg, png only)'),
                onTap: _choosePhotoFolder,
              ),
            ),
          ],
          if (widget.launchCount() case final count?) ...[
            const SizedBox(height: 24),
            Center(
              child: Text(
                'App launched $count ${count == 1 ? 'time' : 'times'}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
