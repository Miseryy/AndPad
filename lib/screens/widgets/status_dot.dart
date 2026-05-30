import 'package:flutter/material.dart';

class StatusDot extends StatefulWidget {
  const StatusDot({super.key, required this.color, this.pulse = false});

  final Color color;
  final bool pulse;

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (widget.pulse) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.pulse && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 1.0 + (widget.pulse ? _controller.value * 0.6 : 0.0);
        final opacity = widget.pulse ? 1.0 - _controller.value * 0.5 : 1.0;

        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: opacity),
                boxShadow: [
                  BoxShadow(
                    color: widget.color,
                    blurRadius: widget.pulse ? 6 : 2,
                    spreadRadius: widget.pulse ? 1 : 0,
                  ),
                ],
              ),
            ),
            if (widget.pulse)
              Transform.scale(
                scale: scale,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.color.withValues(alpha: 0.3),
                      width: 1.0,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
