import 'package:flutter/material.dart';

import '../theme.dart';

/// The Nomo mark: a yurt-dome "n" with a gold location dot.
class NomoMark extends StatelessWidget {
  const NomoMark({super.key, this.size = 48, this.color, this.dot = NomoColors.gold});
  final double size;
  final Color? color;
  final Color dot;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _MarkPainter(color ?? Theme.of(context).colorScheme.onSurface, dot),
      );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.color, this.dot);
  final Color color;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(24 * s, 84 * s)
      ..lineTo(24 * s, 50 * s)
      ..arcToPoint(Offset(76 * s, 50 * s), radius: Radius.circular(26 * s))
      ..lineTo(76 * s, 84 * s);
    canvas.drawPath(path, stroke);
    canvas.drawCircle(Offset(50 * s, 68 * s), 9 * s, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.color != color || old.dot != dot;
}

/// Mark + "nomo" wordmark.
class NomoLogo extends StatelessWidget {
  const NomoLogo({super.key, this.size = 40, this.color, this.suffix});
  final double size;
  final Color? color;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurface;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      NomoMark(size: size, color: c),
      SizedBox(width: size * 0.25),
      Text('nomo', style: TextStyle(fontSize: size * 0.9, fontWeight: FontWeight.w800, letterSpacing: -size * 0.04, color: c, height: 1)),
      if (suffix != null) ...[
        SizedBox(width: size * 0.2),
        Text(suffix!, style: TextStyle(fontSize: size * 0.45, fontWeight: FontWeight.w700, color: NomoColors.gold, height: 1)),
      ],
    ]);
  }
}
