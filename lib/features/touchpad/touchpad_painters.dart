import 'package:flutter/material.dart';

class TouchpadPainter extends CustomPainter {
  const TouchpadPainter({this.activePoint, required this.points});

  final Offset? activePoint;
  final List<Offset> points;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.02)
      ..strokeWidth = 1.0;

    const double spacing = 45.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (points.isNotEmpty) {
      final trailPaint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      for (int i = 0; i < points.length - 1; i++) {
        final opacity = (i / points.length).clamp(0.0, 1.0);
        trailPaint.color = const Color(
          0xFF00FFCC,
        ).withValues(alpha: opacity * 0.45);
        trailPaint.strokeWidth = opacity * 6.5 + 1.5;

        final glowPaint = Paint()
          ..color = const Color(0xFF00FFCC).withValues(alpha: opacity * 0.16)
          ..strokeCap = StrokeCap.round
          ..strokeWidth = trailPaint.strokeWidth * 3.5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
          ..style = PaintingStyle.stroke;

        canvas.drawLine(points[i], points[i + 1], glowPaint);
        canvas.drawLine(points[i], points[i + 1], trailPaint);
      }
    }

    if (activePoint != null) {
      final outerGlow = Paint()
        ..color = const Color(0xFF8A2387).withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawCircle(activePoint!, 32, outerGlow);

      final midGlow = Paint()
        ..color = const Color(0xFFE94057).withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(activePoint!, 18, midGlow);

      final core = Paint()
        ..color = const Color(0xFF00FFCC)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(activePoint!, 6, core);
    }
  }

  @override
  bool shouldRepaint(covariant TouchpadPainter oldDelegate) => true;
}

class ScrollStripPainter extends CustomPainter {
  const ScrollStripPainter({this.activePoint});

  final Offset? activePoint;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(size.width / 2, 16),
      Offset(size.width / 2, size.height - 16),
      linePaint,
    );

    if (activePoint != null) {
      final center = Offset(
        size.width / 2,
        activePoint!.dy.clamp(16.0, size.height - 16.0),
      );

      final glowPaint = Paint()
        ..color = const Color(0xFFE94057).withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawCircle(center, 20, glowPaint);

      final corePaint = Paint()
        ..color = const Color(0xFFE94057)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, 5, corePaint);
    }
  }

  @override
  bool shouldRepaint(covariant ScrollStripPainter oldDelegate) => true;
}
