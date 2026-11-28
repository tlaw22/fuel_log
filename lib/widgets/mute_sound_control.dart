/// Fill-up sound mute control.
/// Displays and persists the setting used by save confirmation sounds.
part of '../app.dart';

class _MuteSoundControl extends StatelessWidget {
  final bool muted;
  final ValueChanged<bool> onChanged;

  const _MuteSoundControl({
    required this.muted,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('MUTE', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(width: 8),
        Semantics(
          label: 'Mute save sound',
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('On')),
              ButtonSegment(value: false, label: Text('Off')),
            ],
            selected: {muted},
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onSelectionChanged: (selection) => onChanged(selection.single),
          ),
        ),
      ],
    );
  }
}
