part of '../app.dart';

const String _fuelLogProjectUrl = 'https://github.com/tlaw22/fuel_log';

/// Displays the bundled README in a scrollable About bottom sheet.
class AboutSheet extends StatefulWidget {
  /// Creates the About bottom sheet.
  const AboutSheet({super.key});

  @override
  State<AboutSheet> createState() => _AboutSheetState();
}

class _AboutSheetState extends State<AboutSheet> {
  late final Future<String> _readme;

  @override
  void initState() {
    super.initState();
    _readme = rootBundle.loadString('README.md');
  }

  Future<void> _openProjectPage() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final opened = await launchUrl(
        Uri.parse(_fuelLogProjectUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('The link could not be opened.');
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not open the GitHub project page: $error'),
          duration: kAppSnackBarDuration,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'About Fuel Log',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close about',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton(
                  onPressed: _openProjectPage,
                  child: const Row(
                    children: [
                      Expanded(
                        child: Text(
                          'View project on GitHub',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      SizedBox(width: 12),
                      FaIcon(FontAwesomeIcons.github, size: 36),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const SelectableText(
                  _fuelLogProjectUrl,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'GitHub icon by Font Awesome (CC BY 4.0).',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<String>(
              future: _readme,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child:
                          Text('Unable to load README.md: ${snapshot.error}'),
                    ),
                  );
                }
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(snapshot.data!),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
