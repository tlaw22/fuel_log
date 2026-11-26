part of '../app.dart';

class _DownloadPlatforms extends StatelessWidget {
  const _DownloadPlatforms();

  Future<void> _openReleases(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final opened = await launchUrl(
        Uri.parse('https://github.com/tlaw22/fuel_log/releases'),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('The link could not be opened.');
    } catch (error) {
      if (!messenger.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not open the releases page: $error'),
          duration: kAppSnackBarDuration,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (label, icon) in [
          ('Windows', FontAwesomeIcons.windows),
          ('Firefox', FontAwesomeIcons.firefox),
          ('Android', FontAwesomeIcons.android),
        ]) ...[
          Tooltip(
            message: label,
            child: CircleAvatar(
              radius: 15,
              child: FaIcon(icon, size: 16),
            ),
          ),
          const SizedBox(width: 4),
        ],
        const SizedBox(width: 4),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _openReleases(context),
            icon: const Icon(Icons.download),
            label: const Text(
              'Download Other Platroms',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}
