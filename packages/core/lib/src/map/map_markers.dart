import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme.dart';

/// Marker visuals shared by the Yandex and OSM maps. Sizes are fixed so the
/// Yandex placemark anchor (relative to the widget) can be computed.

/// Top-down car, nose pointing up (heading 0 = north).
class CarMarker extends StatelessWidget {
  const CarMarker({super.key, this.width = 22, this.highlighted = true});
  final double width;

  /// The car of the current trip gets a gold roof light and a halo.
  final bool highlighted;

  double get height => width * 1.9;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(width, height), painter: _CarPainter(highlighted));
}

class _CarPainter extends CustomPainter {
  _CarPainter(this.highlighted);
  final bool highlighted;

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.06, h * 0.02, w * 0.88, h * 0.96), Radius.circular(w * 0.32));
    c.drawShadow(Path()..addRRect(body), const Color(0xFF000000), 2.5, true);
    c.drawRRect(body.inflate(w * 0.06), Paint()..color = NomoColors.white);
    c.drawRRect(body, Paint()..color = NomoColors.black);
    final glass = Paint()..color = const Color(0xFF3A3F45);
    // Windshield and rear window.
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.2, h * 0.2, w * 0.6, h * 0.17), Radius.circular(w * 0.12)), glass);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.22, h * 0.72, w * 0.56, h * 0.11), Radius.circular(w * 0.1)), glass);
    // Headlights.
    final light = Paint()..color = const Color(0xFFFFF4C8);
    c.drawOval(Rect.fromLTWH(w * 0.14, h * 0.035, w * 0.18, h * 0.05), light);
    c.drawOval(Rect.fromLTWH(w * 0.68, h * 0.035, w * 0.18, h * 0.05), light);
    if (highlighted) {
      c.drawCircle(Offset(w / 2, h * 0.52), w * 0.16, Paint()..color = NomoColors.gold);
    }
  }

  @override
  bool shouldRepaint(_CarPainter o) => o.highlighted != highlighted;
}

/// Pickup point with an optional bubble above it ("4 мин").
class PickupMarker extends StatelessWidget {
  const PickupMarker({super.key, this.label, this.dark = false});
  final String? label;
  final bool dark;

  static const dot = 26.0;
  static const bubble = 30.0;
  static const gap = 4.0;
  static const width = 120.0;
  static double get height => bubble + gap + dot;

  /// Anchor of the dot centre inside the widget (for Yandex placemarks).
  static math.Point<double> get anchor => math.Point(0.5, (bubble + gap + dot / 2) / height);

  @override
  Widget build(BuildContext context) {
    final ink = dark ? NomoColors.gold : NomoColors.black;
    final paper = dark ? NomoColors.black : NomoColors.white;
    return SizedBox(
      width: width,
      height: height,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: bubble,
          child: label == null
              ? null
              : _Bubble(text: label!, bg: NomoColors.black, fg: NomoColors.white),
        ),
        const SizedBox(height: gap),
        Container(
          width: dot,
          height: dot,
          decoration: BoxDecoration(
            color: ink,
            shape: BoxShape.circle,
            border: Border.all(color: paper, width: 3),
            boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2))],
          ),
          child: Center(child: Container(width: 8, height: 8, decoration: BoxDecoration(color: paper, shape: BoxShape.circle))),
        ),
      ]),
    );
  }
}

/// Destination flag with an optional label (arrival time).
class DestinationMarker extends StatelessWidget {
  const DestinationMarker({super.key, this.label, this.dark = false});
  final String? label;
  final bool dark;

  static const box = 24.0;
  static const bubble = 30.0;
  static const gap = 4.0;
  static const width = 120.0;
  static double get height => bubble + gap + box;
  static math.Point<double> get anchor => math.Point(0.5, (bubble + gap + box / 2) / height);

  @override
  Widget build(BuildContext context) {
    final ink = dark ? NomoColors.gold : NomoColors.black;
    final paper = dark ? NomoColors.black : NomoColors.white;
    return SizedBox(
      width: width,
      height: height,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(height: bubble, child: label == null ? null : _Bubble(text: label!, bg: NomoColors.gold, fg: NomoColors.black)),
        const SizedBox(height: gap),
        Container(
          width: box,
          height: box,
          decoration: BoxDecoration(
            color: ink,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: paper, width: 3),
            boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2))],
          ),
          child: Center(child: Container(width: 6, height: 6, color: paper)),
        ),
      ]),
    );
  }
}

/// The user's own location (blue dot).
class MeMarker extends StatelessWidget {
  const MeMarker({super.key});
  static const size = 22.0;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF2F80ED),
          shape: BoxShape.circle,
          border: Border.all(color: NomoColors.white, width: 3.5),
          boxShadow: const [BoxShadow(color: Color(0x402F80ED), blurRadius: 10, spreadRadius: 4)],
        ),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.bg, required this.fg});
  final String text;
  final Color bg, fg;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(15),
            boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2))],
          ),
          child: Text(
            text,
            maxLines: 1,
            textDirection: TextDirection.ltr,
            style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w800, height: 1.1, decoration: TextDecoration.none),
          ),
        ),
      );
}
