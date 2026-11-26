part of '../app.dart';

class _SettingsPage extends StatefulWidget {
  final bool Function() isDarkTheme;
  final ThemePalette Function() selectedPalette;
  final int Function() fontSizePercent;
  final bool Function() bubblesEnabled;
  final VoidCallback onToggleTheme;
  final ValueChanged<ThemePalette> onSelectPalette;
  final ValueChanged<int> onSetFontSize;
  final ValueChanged<bool> onSetBubblesEnabled;

  const _SettingsPage({
    required this.isDarkTheme,
    required this.selectedPalette,
    required this.fontSizePercent,
    required this.bubblesEnabled,
    required this.onToggleTheme,
    required this.onSelectPalette,
    required this.onSetFontSize,
    required this.onSetBubblesEnabled,
  });

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
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
                        onPressed: fontSize == 60
                            ? null
                            : () => setState(
                                () => widget.onSetFontSize(fontSize - 20)),
                        icon: const Icon(Icons.remove),
                      ),
                      Text('$fontSize%'),
                      IconButton(
                        tooltip: 'Increase font size',
                        onPressed: fontSize == 120
                            ? null
                            : () => setState(
                                () => widget.onSetFontSize(fontSize + 20)),
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
        ],
      ),
    );
  }
}
