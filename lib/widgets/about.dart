/// About dialog and project information.
/// Displays bundled README content and provides project and donation links.
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
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
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
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const _DonatePage(),
                        ),
                      ),
                      icon: const Icon(Icons.attach_money),
                      label: const Text('Donate'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _fuelLogProjectUrl,
                  textAlign: TextAlign.center,
                  style: DefaultTextStyle.of(context)
                      .style
                      .apply(fontSizeFactor: 0.5),
                ),
                const SizedBox(height: 8),
                const _DownloadPlatforms(),
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
                final readme = snapshot.data!;
                final firstLineEnd = readme.indexOf('\n');
                final headerEnd =
                    firstLineEnd == -1 ? readme.length : firstLineEnd;
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: readme.substring(0, headerEnd),
                          style: const TextStyle(fontFamily: 'Pacifico'),
                        ),
                        TextSpan(text: readme.substring(headerEnd)),
                      ],
                    ),
                    style: const TextStyle(fontSize: 10, fontFamily: 'Oswald'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DonatePage extends StatelessWidget {
  const _DonatePage();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Donate')),
        body: const Center(child: Text('Donation page coming soon.')),
      );
}
