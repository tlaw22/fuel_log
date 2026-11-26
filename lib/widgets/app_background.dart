part of '../app.dart';

class _AppBackground extends StatelessWidget {
  final bool bubblesEnabled;
  final Widget child;

  const _AppBackground({required this.bubblesEnabled, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bubbleColor =
        colors.brightness == Brightness.dark ? colors.primary : colors.onSurface;
    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (bubblesEnabled)
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: TickerMode(
                    enabled: !MediaQuery.disableAnimationsOf(context),
                    child: RepaintBoundary(
                      key: const ValueKey('app-bubbles'),
                      child: _AppBubbles(color: bubbleColor),
                    ),
                  ),
                ),
              ),
            ),
          Theme(
            data: theme.copyWith(scaffoldBackgroundColor: Colors.transparent),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _AppBubbles extends StatefulWidget {
  final Color color;

  const _AppBubbles({required this.color});

  @override
  State<_AppBubbles> createState() => _AppBubblesState();
}

class _AppBubblesState extends State<_AppBubbles> with TickerProviderStateMixin {
  @override
  Widget build(BuildContext context) => AnimatedBackground(
        vsync: this,
        behaviour: RandomParticleBehaviour(
          options: ParticleOptions(
            baseColor: widget.color,
            particleCount: 18,
            spawnMinRadius: 8,
            spawnMaxRadius: 22,
            spawnMinSpeed: 4,
            spawnMaxSpeed: 12,
            spawnOpacity: 0.3,
            minOpacity: 0.25,
            maxOpacity: 0.45,
          ),
          paint: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        ),
        child: const SizedBox.expand(),
      );
}
