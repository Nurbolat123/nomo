import 'package:flutter/scheduler.dart';
import 'package:latlong2/latlong.dart';

import 'route_math.dart';

/// Where the server says the car is.
class CarTarget {
  const CarTarget(this.position, {this.heading});
  final LatLng position;

  /// Degrees from north; null = derive from movement.
  final double? heading;

  @override
  bool operator ==(Object other) =>
      other is CarTarget && other.position == position && other.heading == heading;

  @override
  int get hashCode => Object.hash(position, heading);
}

/// Smoothly moves the car between position updates (they arrive every 2–3 s),
/// keeps its heading, the driven trail and the part of the route still ahead.
class CarMotion {
  CarMotion(TickerProvider vsync, this.onFrame) {
    _ticker = vsync.createTicker(_tick);
  }

  /// Called on every animation frame while the car moves.
  final void Function() onFrame;

  late final Ticker _ticker;
  LatLng? _from, _to, _pos;
  double _fromHeading = 0, _toHeading = 0, _heading = 0;
  Duration _duration = const Duration(seconds: 2);
  Duration _elapsedAtStart = Duration.zero;
  Duration _now = Duration.zero;
  DateTime? _lastTargetAt;

  final List<LatLng> trail = [];
  static const _maxTrail = 2000;
  static const _jumpM = 3000.0; // farther than this → teleport, don't animate

  List<LatLng> _route = const [];
  int _routeSegment = 0;
  RouteProjection? _projection;

  LatLng? get position => _pos;
  double get heading => _heading;
  bool get hasCar => _pos != null;

  /// Distance from the car to the route, meters (infinity without a route).
  double get offRouteM => _projection?.offRouteM ?? double.infinity;

  /// Sets the route the car follows; the part behind the car is cut off.
  set route(List<LatLng> r) {
    if (identical(r, _route)) return;
    _route = r;
    _routeSegment = 0;
    _projection = null;
    _snap();
  }

  /// Route still ahead of the car (the full route before the car appears).
  List<LatLng> get routeAhead {
    final p = _projection;
    if (p == null || _route.length < 2) return _route;
    return RouteMath.remaining(_route, p);
  }

  void setTarget(CarTarget t) {
    final now = DateTime.now();
    final since = _lastTargetAt == null ? const Duration(seconds: 2) : now.difference(_lastTargetAt!);
    _lastTargetAt = now;
    final p = t.position;
    if (_pos == null || RouteMath.distance(_pos!, p) > _jumpM) {
      _pos = _from = _to = p;
      _heading = _fromHeading = _toHeading = t.heading ?? _heading;
      _addTrail(p);
      _snap();
      onFrame();
      return;
    }
    if (_to != null && RouteMath.distance(_to!, p) < 0.5 && t.heading == null) return;
    _from = _pos;
    _to = p;
    _fromHeading = _heading;
    final moved = RouteMath.distance(_from!, p);
    _toHeading = t.heading != null && t.heading! >= 0
        ? t.heading!
        : (moved > 3 ? RouteMath.bearing(_from!, p) : _heading);
    // Arrive just as the next update is expected.
    final ms = since.inMilliseconds.clamp(300, 4000);
    _duration = Duration(milliseconds: ms);
    _elapsedAtStart = _now;
    if (!_ticker.isActive) {
      _elapsedAtStart = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    _now = elapsed;
    final from = _from, to = _to;
    if (from == null || to == null) return;
    final t = ((elapsed - _elapsedAtStart).inMicroseconds / _duration.inMicroseconds).clamp(0.0, 1.0);
    _pos = RouteMath.lerp(from, to, t);
    _heading = RouteMath.lerpAngle(_fromHeading, _toHeading, _easeOut(t));
    _addTrail(_pos!);
    _snap();
    onFrame();
    if (t >= 1) {
      _ticker.stop();
      _now = Duration.zero;
    }
  }

  void _addTrail(LatLng p) {
    if (trail.isNotEmpty && RouteMath.distance(trail.last, p) < 4) return;
    trail.add(p);
    if (trail.length > _maxTrail) trail.removeRange(0, trail.length - _maxTrail);
  }

  void _snap() {
    final p = _pos;
    if (p == null || _route.length < 2) {
      _projection = null;
      return;
    }
    // Search forward from where the car was; fall back to the whole route
    // if it seems to have jumped (e.g. after reconnecting).
    var proj = RouteMath.project(_route, p, fromSegment: _routeSegment);
    if (proj.offRouteM > 40 && _routeSegment > 0) {
      final all = RouteMath.project(_route, p);
      if (all.offRouteM < proj.offRouteM) proj = all;
    }
    _projection = proj;
    _routeSegment = proj.segment;
  }

  void clearTrail() => trail.clear();

  void reset() {
    _ticker.stop();
    _pos = _from = _to = null;
    _lastTargetAt = null;
    _projection = null;
    trail.clear();
  }

  void dispose() => _ticker.dispose();
}

double _easeOut(double t) => 1 - (1 - t) * (1 - t);
