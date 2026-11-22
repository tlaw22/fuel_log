part of 'main.dart';

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
