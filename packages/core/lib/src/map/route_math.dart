import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Geometry helpers for routes: distances, bearings, encoded polylines and
/// snapping the car onto the route to cut off the part already driven.
class RouteMath {
  static const _r = 6371000.0;

  static double distance(LatLng a, LatLng b) {
    final lat1 = _rad(a.latitude), lat2 = _rad(b.latitude);
    final dLat = lat2 - lat1, dLng = _rad(b.longitude - a.longitude);
    final h = math.pow(math.sin(dLat / 2), 2) + math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLng / 2), 2);
    return 2 * _r * math.asin(math.min(1, math.sqrt(h)));
  }

  static double length(List<LatLng> pts) {
    var d = 0.0;
    for (var i = 1; i < pts.length; i++) {
      d += distance(pts[i - 1], pts[i]);
    }
    return d;
  }

  /// Heading from a to b in degrees, 0 = north, clockwise.
  static double bearing(LatLng a, LatLng b) {
    final lat1 = _rad(a.latitude), lat2 = _rad(b.latitude);
    final dLng = _rad(b.longitude - a.longitude);
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  static LatLng lerp(LatLng a, LatLng b, double t) =>
      LatLng(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t);

  /// Interpolates angles the short way round (350° → 10° passes 0°).
  static double lerpAngle(double a, double b, double t) {
    final d = ((b - a + 540) % 360) - 180;
    return (a + d * t + 360) % 360;
  }

  /// Nearest point of the route to [p].
  static RouteProjection project(List<LatLng> route, LatLng p, {int fromSegment = 0}) {
    if (route.length < 2) {
      final only = route.isEmpty ? p : route.first;
      return RouteProjection(segment: 0, point: only, offRouteM: distance(only, p));
    }
    var best = RouteProjection(segment: 0, point: route.first, offRouteM: double.infinity);
    final start = fromSegment.clamp(0, route.length - 2);
    for (var i = start; i < route.length - 1; i++) {
      final q = _projectOnSegment(route[i], route[i + 1], p);
      final d = distance(q, p);
      if (d < best.offRouteM) best = RouteProjection(segment: i, point: q, offRouteM: d);
    }
    return best;
  }

  /// The part of the route still ahead of [p].
  static List<LatLng> remaining(List<LatLng> route, RouteProjection at) {
    if (route.length < 2) return route;
    return [at.point, ...route.sublist(at.segment + 1)];
  }

  /// The part of the route already behind [p].
  static List<LatLng> passed(List<LatLng> route, RouteProjection at) {
    if (route.length < 2) return const [];
    return [...route.sublist(0, at.segment + 1), at.point];
  }

  static LatLng _projectOnSegment(LatLng a, LatLng b, LatLng p) {
    // Local flat approximation, fine for segments of a few kilometres.
    final k = math.cos(_rad(a.latitude));
    final ax = a.longitude * k, ay = a.latitude;
    final bx = b.longitude * k, by = b.latitude;
    final px = p.longitude * k, py = p.latitude;
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) return a;
    final t = (((px - ax) * dx + (py - ay) * dy) / len2).clamp(0.0, 1.0);
    return lerp(a, b, t);
  }

  // ---- Google encoded polyline, precision 5 (same as the backend) ----

  static String encode(List<LatLng> pts) {
    final b = StringBuffer();
    var pLat = 0, pLng = 0;
    for (final p in pts) {
      final lat = (p.latitude * 1e5).round(), lng = (p.longitude * 1e5).round();
      _enc(b, lat - pLat);
      _enc(b, lng - pLng);
      pLat = lat;
      pLng = lng;
    }
    return b.toString();
  }

  static void _enc(StringBuffer b, int v) {
    var x = v < 0 ? ~(v << 1) : v << 1;
    while (x >= 0x20) {
      b.writeCharCode((0x20 | (x & 0x1f)) + 63);
      x >>= 5;
    }
    b.writeCharCode(x + 63);
  }

  /// Decodes a polyline; returns an empty list for malformed input.
  static List<LatLng> decode(String s) {
    final out = <LatLng>[];
    var i = 0, lat = 0, lng = 0;
    int? next() {
      var result = 0, shift = 0;
      while (true) {
        if (i >= s.length) return null;
        final c = s.codeUnitAt(i++) - 63;
        if (c < 0 || shift > 30) return null;
        result |= (c & 0x1f) << shift;
        shift += 5;
        if (c < 0x20) break;
      }
      return (result & 1) != 0 ? ~(result >> 1) : result >> 1;
    }

    while (i < s.length) {
      final dLat = next(), dLng = next();
      if (dLat == null || dLng == null) return const [];
      lat += dLat;
      lng += dLng;
      out.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return out;
  }

  static double _rad(double d) => d * math.pi / 180;
}

class RouteProjection {
  const RouteProjection({required this.segment, required this.point, required this.offRouteM});

  /// Index of the route segment the point falls on.
  final int segment;

  /// The snapped point on the route.
  final LatLng point;

  /// How far the original point is from the route, meters.
  final double offRouteM;
}
