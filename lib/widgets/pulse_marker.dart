import 'package:flutter/material.dart';

class PulseMarker extends StatefulWidget {
  final Color color;
  final double size;
  final Widget child;

  const PulseMarker({
    super.key,
    this.color = Colors.blue,
    this.size = 24.0,
    required this.child,
  });

  @override
  State<PulseMarker> createState() => _PulseMarkerState();
}

class _PulseMarkerState extends State<PulseMarker> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Container(
              width: widget.size + (widget.size * 3 * _animation.value),
              height: widget.size + (widget.size * 3 * _animation.value),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 0.4 * (1.0 - _animation.value)),
              ),
            ),
            Container(
              width: widget.size + (widget.size * 1.5 * _animation.value),
              height: widget.size + (widget.size * 1.5 * _animation.value),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 0.6 * (1.0 - _animation.value)),
              ),
            ),
            widget.child,
          ],
        );
      },
    );
  }
}
