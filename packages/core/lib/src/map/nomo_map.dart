import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../config.dart';
import 'car_motion.dart';
import 'osm_map_view.dart';
import 'route_math.dart';
import 'yandex_map_view.dart';

export 'package:latlong2/latlong.dart' show LatLng;
export 'car_motion.dart' show CarTarget;

enum PinKind { pickup, destination, car, me }

/// A static marker: pickup, destination, the user, or a free car nearby.
class MapPin {
  const MapPin(this.kind, this.lat, this.lng, {this.heading = 0, this.key, this.label});
  final PinKind kind;
  final double lat, lng, heading;
  final String? key;

  /// Text bubble above pickup/destination ("4 мин", "12:40").
  final String? label;

  LatLng get point => LatLng(lat, lng);
  String get id => key ?? '${kind.name}:${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';

  @override
  bool operator ==(Object other) =>
      other is MapPin &&
      other.kind == kind &&
      other.lat == lat &&
      other.lng == lng &&
      other.heading == heading &&
      other.key == key &&
      other.label == label;

  @override
  int get hashCode => Object.hash(kind, lat, lng, heading, key, label);
}

class HeatSpot {
  const HeatSpot(this.lat, this.lng, this.level);
  final double lat, lng;
  final int level; // 1..3

  @override
  bool operator ==(Object other) => other is HeatSpot && other.lat == lat && other.lng == lng && other.level == level;

  @override
  int get hashCode => Object.hash(lat, lng, level);
}

/// Moves the camera of whichever map implementation is on screen.
class NomoMapController {
  MapBackend? _backend;

  void attach(MapBackend b) => _backend = b;
  void detach(MapBackend b) {
    if (_backend == b) _backend = null;
  }

  bool get isReady => _backend != null;
  LatLng? get center => _backend?.center;

  void moveTo(LatLng p, {double? zoom, bool animate = true}) => _backend?.moveTo(p, zoom: zoom, animate: animate);

  /// Shows all points, keeping clear of the map's [NomoMap.padding].
  void fit(List<LatLng> points, {double maxZoom = 16.5, bool animate = true}) {
    if (points.isEmpty) return;
    if (points.length == 1 || RouteMath.length(points) < 30) {
      moveTo(points.first, zoom: maxZoom, animate: animate);
      return;
    }
    _backend?.fit(points, maxZoom: maxZoom, animate: animate);
  }
}

abstract class MapBackend {
  LatLng? get center;
  void moveTo(LatLng p, {double? zoom, bool animate = true});
  void fit(List<LatLng> points, {required double maxZoom, bool animate = true});
}

/// The map used in both apps. With a Yandex MapKit key it renders Yandex
/// maps; otherwise OpenStreetMap tiles. Same features either way:
///
/// * [route] — road route, drawn bold; with [car] set the part behind the
///   car is cut off as it drives (like Yandex Go);
/// * [car] — the trip's car, animated smoothly between updates and rotated
///   along its heading; [showTrail] draws the path it has driven;
/// * [followCar] — camera keeps the car (and [followWith]) in view;
/// * [pins] — pickup, destination, user and nearby cars.
class NomoMap extends StatelessWidget {
  const NomoMap({
    super.key,
    required this.controller,
    required this.center,
    this.zoom = 15,
    this.pins = const [],
    this.route = const [],
    this.car,
    this.showTrail = false,
    this.followCar = false,
    this.followWith = const [],
    this.heat = const [],
    this.padding = EdgeInsets.zero,
    this.dark,
    this.onMoved,
    this.onMoveStart,
    this.onReady,
    this.onOffRoute,
    this.onRemaining,
  });

  final NomoMapController controller;
  final LatLng center;
  final double zoom;
  final List<MapPin> pins;
  final List<LatLng> route;
  final CarTarget? car;
  final bool showTrail;
  final bool followCar;
  final List<LatLng> followWith;
  final List<HeatSpot> heat;

  /// Screen areas covered by UI (top buttons, bottom sheet).
  final EdgeInsets padding;

  /// Night style; defaults to the app theme.
  final bool? dark;

  /// The user stopped dragging the map; new centre.
  final ValueChanged<LatLng>? onMoved;

  /// The user started dragging the map.
  final VoidCallback? onMoveStart;
  final VoidCallback? onReady;

  /// The car left the route (> 70 m): time to build a new one.
  final VoidCallback? onOffRoute;

  /// Meters of route left ahead of the car, about every 2 s.
  final ValueChanged<double>? onRemaining;

  bool isDark(BuildContext context) => dark ?? Theme.of(context).brightness == Brightness.dark;

  @override
  Widget build(BuildContext context) =>
      NomoConfig.hasYandexMaps ? YandexMapView(config: this) : OsmMapView(config: this);
}

/// Behaviour shared by both map implementations: car animation, trimming the
/// route, the trail, following the car and progress callbacks.
abstract class NomoMapViewState<T extends StatefulWidget> extends State<T> with TickerProviderStateMixin implements MapBackend {
  NomoMap get config;

  late final CarMotion motion = CarMotion(this, _onCarFrame);
  Timer? _followTimer;
  DateTime _lastOffRoute = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastRemaining = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastRouteDraw = DateTime.fromMillisecondsSinceEpoch(0);
  bool _userMoving = false;

  /// Redraw the car marker (called every animation frame).
  void drawCar();

  /// Redraw route-ahead and trail lines (throttled while the car moves).
  void drawRoute();

  @override
  void initState() {
    super.initState();
    motion.route = config.route;
    if (config.car != null) motion.setTarget(config.car!);
    _followTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) => _follow());
  }

  /// Call from didUpdateWidget of the concrete view.
  void syncScene(NomoMap old) {
    if (!identical(old.route, config.route) && !listEquals(old.route, config.route)) {
      motion.route = config.route;
      drawRoute();
    }
    final car = config.car;
    if (car == null && old.car != null) {
      motion.reset();
      drawCar();
      drawRoute();
    } else if (car != null && car != old.car) {
      motion.setTarget(car);
    }
    if (config.followCar && !old.followCar) _follow(force: true);
  }

  void _onCarFrame() {
    if (!mounted) return;
    drawCar();
    final now = DateTime.now();
    if (now.difference(_lastRouteDraw) > const Duration(milliseconds: 250)) {
      _lastRouteDraw = now;
      drawRoute();
    }
    if (config.route.length >= 2 && motion.offRouteM > 70 && now.difference(_lastOffRoute) > const Duration(seconds: 15)) {
      _lastOffRoute = now;
      config.onOffRoute?.call();
    }
    if (config.onRemaining != null && config.route.length >= 2 && now.difference(_lastRemaining) > const Duration(seconds: 2)) {
      _lastRemaining = now;
      config.onRemaining!(RouteMath.length(motion.routeAhead));
    }
  }

  void userGestureStarted() {
    _userMoving = true;
    config.onMoveStart?.call();
  }

  void userGestureEnded(LatLng center) {
    _userMoving = false;
    config.onMoved?.call(center);
  }

  void _follow({bool force = false}) {
    if (!mounted || !config.followCar || _userMoving) return;
    final car = motion.position;
    if (car == null) return;
    final pts = [car, ...config.followWith];
    if (pts.length == 1) {
      moveTo(car, zoom: 16.5);
    } else {
      fit(pts, maxZoom: 16.5);
    }
  }

  /// Route ahead of the car (whole route if there is no car).
  List<LatLng> get routeAhead => motion.hasCar ? motion.routeAhead : config.route;

  /// Driven path, only when [NomoMap.showTrail] is on.
  List<LatLng> get trail => config.showTrail ? motion.trail : const [];

  @override
  void dispose() {
    _followTimer?.cancel();
    motion.dispose();
    super.dispose();
  }
}
