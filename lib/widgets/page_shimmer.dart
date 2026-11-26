part of '../app.dart';

class _StaggeredPage extends StatefulWidget {
  final bool active;
  final int count;
  final Widget child;

  const _StaggeredPage({
    super.key,
    required this.active,
    required this.count,
    required this.child,
  });

  @override
  State<_StaggeredPage> createState() => _StaggeredPageState();
}

class _StaggeredPageState extends State<_StaggeredPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;
  Timer? _timer;
  int _revealed = 0;
  bool _complete = false;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (_reducedMotion != reducedMotion) {
      _reducedMotion = reducedMotion;
      _restart();
    } else if (_timer == null && widget.active && !_complete) {
      _restart();
    }
  }

  @override
  void didUpdateWidget(covariant _StaggeredPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _restart();
    } else if (widget.active && !_complete && _revealed >= widget.count) {
      _finish();
    }
  }

  void _restart() {
    _timer?.cancel();
    _timer = null;
    _shimmer.stop();
    _revealed = 0;
    _complete = _reducedMotion;
    if (!widget.active || _reducedMotion) return;
    _shimmer.repeat(reverse: true);
    _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      setState(() {
        _revealed = timer.tick;
        if (_revealed >= widget.count) _finish();
      });
    });
  }

  void _finish() {
    _timer?.cancel();
    _timer = null;
    _shimmer.stop();
    _complete = true;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _PageRevealScope(
        revealed: _revealed,
        complete: _complete,
        shimmer: _shimmer,
        child: widget.child,
      );
}

class _PageRevealScope extends InheritedWidget {
  final int revealed;
  final bool complete;
  final Animation<double> shimmer;

  const _PageRevealScope({
    required this.revealed,
    required this.complete,
    required this.shimmer,
    required super.child,
  });

  @override
  bool updateShouldNotify(_PageRevealScope oldWidget) =>
      revealed != oldWidget.revealed ||
      complete != oldWidget.complete ||
      shimmer != oldWidget.shimmer;
}

class _PageReveal extends StatelessWidget {
  final int index;
  final Widget child;

  const _PageReveal({super.key, required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_PageRevealScope>();
    if (scope == null) return child;
    final visible = scope.complete || index < scope.revealed;
    final colors = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Visibility(
          visible: visible,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: true,
          child: TickerMode(enabled: visible, child: child),
        ),
        if (!visible)
          Positioned.fill(
            child: ExcludeSemantics(
              child: AnimatedBuilder(
                animation: scope.shimmer,
                builder: (context, _) => DecoratedBox(
                  key: const ValueKey('page-shimmer'),
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      colors.surfaceContainerHighest,
                      Color.alphaBlend(
                        colors.onSurface.withValues(alpha: 0.16),
                        colors.surfaceContainerHighest,
                      ),
                      scope.shimmer.value,
                    )!.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
