import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:yandex_maps_mapkit/directions.dart' as ymd;
import 'package:yandex_maps_mapkit/mapkit.dart' as ym;

import '../config.dart';
import 'route_math.dart';

/// A driving route between two points.
class RoadRoute {
  const RoadRoute({required this.points, required this.distanceM, required this.durationS, this.estimated = false});

  final List<LatLng> points;
  final int distanceM;

  /// Travel time with current traffic when the router knows it.
  final int durationS;

  /// True for the straight-line fallback (no road data).
  final bool estimated;

  String get polyline => RouteMath.encode(points);

  /// What the backend accepts as a route hint (null for estimates).
  Map<String, dynamic>? toHint() =>
      estimated ? null : {'distance_m': distanceM, 'duration_s': durationS, 'polyline': polyline};
}

abstract class RouteService {
  Future<RoadRoute?> drive(LatLng from, LatLng to);
}

/// Straight line with an average city speed. Used without a Yandex key.
class StraightRouteService implements RouteService {
  @override
  Future<RoadRoute?> drive(LatLng from, LatLng to) async {
    final d = RouteMath.distance(from, to) * 1.35;
    return RoadRoute(points: [from, to], distanceM: d.round(), durationS: (d / (28000 / 3600)).round(), estimated: true);
  }
}

/// Driving routes from Yandex MapKit (requires the full `yandex_maps_mapkit`
/// package and an initialised MapKit key).
class YandexRouteService implements RouteService {
  YandexRouteService() : _router = ymd.DirectionsFactory.instance.createDrivingRouter(ymd.DrivingRouterType.Combined);

  final ymd.DrivingRouter _router;

  // MapKit keeps only weak references to listeners and sessions: hold them
  // until the request finishes.
  final _inFlight = <Object>{};

  // Yandex terms allow caching router results for up to 30 days; a short
  // in-memory cache is enough to avoid repeated requests for the same trip.
  final _cache = <String, RoadRoute>{};

  @override
  Future<RoadRoute?> drive(LatLng from, LatLng to) {
    final key = '${from.latitude.toStringAsFixed(4)},${from.longitude.toStringAsFixed(4)}'
        '>${to.latitude.toStringAsFixed(4)},${to.longitude.toStringAsFixed(4)}';
    final cached = _cache[key];
    if (cached != null) return Future.value(cached);

    final done = Completer<RoadRoute?>();
    late final ymd.DrivingSessionRouteListener listener;
    ymd.DrivingSession? session;
    void finish(RoadRoute? r) {
      _inFlight
        ..remove(listener)
        ..remove(session);
      if (!done.isCompleted) done.complete(r);
    }

    listener = ymd.DrivingSessionRouteListener(
      onDrivingRoutes: (routes) {
        if (routes.isEmpty) return finish(null);
        final r = routes.first;
        final w = r.metadata.weight;
        final points = r.geometry.points.map((p) => LatLng(p.latitude, p.longitude)).toList();
        final route = RoadRoute(
          points: points,
          distanceM: w.distance.value.round(),
          durationS: w.timeWithTraffic.value.round(),
        );
        if (_cache.length > 50) _cache.clear();
        _cache[key] = route;
        finish(route);
      },
      onDrivingRoutesError: (_) => finish(null),
    );
    _inFlight.add(listener);
    session = _router.requestRoutes(
      const ymd.DrivingOptions(routesCount: 1),
      const ymd.DrivingVehicleOptions(),
      listener,
      points: [
        ym.RequestPoint(ym.Point(latitude: from.latitude, longitude: from.longitude), ym.RequestPointType.Waypoint, null, null, null),
        ym.RequestPoint(ym.Point(latitude: to.latitude, longitude: to.longitude), ym.RequestPointType.Waypoint, null, null, null),
      ],
    );
    _inFlight.add(session);
    return done.future.timeout(const Duration(seconds: 12), onTimeout: () {
      session?.cancel();
      finish(null);
      return null;
    });
  }
}

/// Picks Yandex routing when a MapKit key is configured; falls back to a
/// straight line if Yandex can't build a route.
class _FallbackRouteService implements RouteService {
  _FallbackRouteService(this.primary);
  final RouteService primary;
  final _straight = StraightRouteService();

  @override
  Future<RoadRoute?> drive(LatLng from, LatLng to) async {
    try {
      final r = await primary.drive(from, to);
      if (r != null && r.points.length >= 2) return r;
    } catch (_) {}
    return _straight.drive(from, to);
  }
}

final routeServiceProvider = Provider<RouteService>((ref) {
  if (NomoConfig.hasYandexMaps) return _FallbackRouteService(YandexRouteService());
  return StraightRouteService();
});
