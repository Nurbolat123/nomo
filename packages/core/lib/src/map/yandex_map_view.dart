import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:yandex_maps_mapkit/mapkit.dart' as ym;
import 'package:yandex_maps_mapkit/mapkit_factory.dart' as ymf;
import 'package:yandex_maps_mapkit/ui_view.dart' as ymv;
import 'package:yandex_maps_mapkit/yandex_map.dart' as ymw;

import '../theme.dart';
import 'map_markers.dart';
import 'nomo_map.dart';

ym.Point _pt(LatLng p) => ym.Point(latitude: p.latitude, longitude: p.longitude);
LatLng _ll(ym.Point p) => LatLng(p.latitude, p.longitude);

/// Yandex MapKit implementation of [NomoMap].
class YandexMapView extends StatefulWidget {
  const YandexMapView({super.key, required this.config});
  final NomoMap config;

  @override
  State<YandexMapView> createState() => _YandexMapViewState();
}

class _YandexMapViewState extends NomoMapViewState<YandexMapView> {
  @override
  NomoMap get config => widget.config;

  ym.MapWindow? _window;
  ym.Map? get _map => _window?.map;
  late final AppLifecycleListener _lifecycle;
  bool _started = false;

  // Draw order: heat → trail → route → pins → car.
  ym.MapObjectCollection? _heatLayer, _lineLayer, _pinLayer, _carLayer;
  ym.PolylineMapObject? _trailLine, _routeLine;
  ym.PlacemarkMapObject? _car;
  final _pins = <String, (MapPin, ym.PlacemarkMapObject)>{};
  bool? _darkApplied;

  // MapKit keeps weak references to listeners: hold them here.
  late final _cameraListener = _CameraListener(this);

  @override
  void initState() {
    super.initState();
    _start();
    _lifecycle = AppLifecycleListener(onResume: _start, onInactive: _stop);
  }

  void _start() {
    if (_started) return;
    _started = true;
    ymf.mapkit.onStart();
  }

  void _stop() {
    if (!_started) return;
    _started = false;
    ymf.mapkit.onStop();
  }

  @override
  void dispose() {
    _map?.removeCameraListener(_cameraListener);
    controllerDetach();
    _lifecycle.dispose();
    _stop();
    super.dispose();
  }

  void controllerDetach() => config.controller.detach(this);

  void _onMapCreated(ym.MapWindow window) {
    _window = window;
    final map = window.map;
    map.rotateGesturesEnabled = false;
    map.tiltGesturesEnabled = false;
    map.move(ym.CameraPosition(_pt(config.center), zoom: config.zoom, azimuth: 0, tilt: 0));
    map.addCameraListener(_cameraListener);
    final root = map.mapObjects;
    _heatLayer = root.addCollection();
    _lineLayer = root.addCollection();
    _pinLayer = root.addCollection();
    _carLayer = root.addCollection();
    config.controller.attach(this);
    _applyAll();
    config.onReady?.call();
  }

  @override
  void didUpdateWidget(YandexMapView old) {
    super.didUpdateWidget(old);
    syncScene(old.config);
    if (!listEquals(old.config.heat, config.heat)) _heatDirty = true;
    _applyAll();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Theme (night mode) or screen size may have changed.
    _applyAll();
  }

  bool _heatDirty = true;

  void _applyAll() {
    if (_window == null || !mounted) return;
    final dark = config.isDark(context);
    if (_darkApplied != dark) {
      _darkApplied = dark;
      _map!.nightModeEnabled = dark;
      _trailLine = null;
      _routeLine = null;
      _lineLayer!.clear();
      _pins.clear();
      _pinLayer!.clear();
      _car = null;
      _carLayer!.clear();
    }
    _updateFocusRect();
    if (_heatDirty) {
      _heatDirty = false;
      _drawHeat();
    }
    drawRoute();
    _drawPins();
    drawCar();
  }

  void _updateFocusRect() {
    final w = _window;
    if (w == null) return;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final p = config.padding;
    final width = w.width().toDouble(), height = w.height().toDouble();
    if (width <= 0 || height <= 0) return;
    final left = (p.left * dpr).clamp(0.0, width / 2 - 1);
    final top = (p.top * dpr).clamp(0.0, height / 2 - 1);
    final right = (width - p.right * dpr).clamp(width / 2 + 1, width);
    final bottom = (height - p.bottom * dpr).clamp(height / 2 + 1, height);
    w.focusRect = ym.ScreenRect(ym.ScreenPoint(x: left, y: top), ym.ScreenPoint(x: right, y: bottom));
  }

  // ---- lines ----

  @override
  void drawRoute() {
    final layer = _lineLayer;
    if (layer == null) return;
    final dark = _darkApplied ?? false;

    final trail = this.trail;
    if (trail.length >= 2) {
      final line = _trailLine ??= layer.addPolylineWithGeometry(ym.Polyline(trail.map(_pt).toList()))
        ..zIndex = 1
        ..strokeWidth = 5
        ..outlineWidth = 0
        ..setStrokeColor(dark ? const Color(0x99FFC93C) : const Color(0x80575757));
      line.geometry = ym.Polyline(trail.map(_pt).toList());
      line.visible = true;
    } else {
      _trailLine?.visible = false;
    }

    final ahead = routeAhead;
    if (ahead.length >= 2) {
      final line = _routeLine ??= layer.addPolylineWithGeometry(ym.Polyline(ahead.map(_pt).toList()))
        ..zIndex = 2
        ..strokeWidth = 6
        ..outlineWidth = 2
        ..outlineColor = dark ? NomoColors.black : NomoColors.white
        ..setStrokeColor(dark ? NomoColors.gold : NomoColors.black);
      line.geometry = ym.Polyline(ahead.map(_pt).toList());
      line.visible = true;
    } else {
      _routeLine?.visible = false;
    }
  }

  void _drawHeat() {
    final layer = _heatLayer;
    if (layer == null) return;
    layer.clear();
    for (final h in config.heat) {
      layer.addCircle(ym.Circle(ym.Point(latitude: h.lat, longitude: h.lng), radius: 500))
        ..strokeWidth = 0
        ..strokeColor = const Color(0x00000000)
        ..fillColor = NomoColors.gold.withValues(alpha: 0.12 + 0.1 * h.level);
    }
  }

  // ---- pins ----

  void _drawPins() {
    final layer = _pinLayer;
    if (layer == null) return;
    final dark = _darkApplied ?? false;
    final wanted = {for (final p in config.pins) p.id: p};
    for (final id in _pins.keys.toList()) {
      if (!wanted.containsKey(id)) {
        layer.remove(_pins.remove(id)!.$2);
      }
    }
    for (final pin in config.pins) {
      final existing = _pins[pin.id];
      if (existing != null && existing.$1 == pin) continue;
      if (existing != null && existing.$1.kind == pin.kind && existing.$1.label == pin.label) {
        // Same look, new position/heading.
        existing.$2
          ..geometry = _pt(pin.point)
          ..direction = pin.heading;
        _pins[pin.id] = (pin, existing.$2);
        continue;
      }
      if (existing != null) layer.remove(existing.$2);
      final (view, style) = _pinView(pin, dark);
      final pm = layer.addPlacemarkWithViewStyle(_pt(pin.point), view, style)..direction = pin.heading;
      _pins[pin.id] = (pin, pm);
    }
  }

  (ymv.ViewProvider, ym.IconStyle) _pinView(MapPin pin, bool dark) {
    Widget wrap(Widget w) => Directionality(textDirection: TextDirection.ltr, child: w);
    switch (pin.kind) {
      case PinKind.pickup:
        return (
          ymv.ViewProvider(builder: () => wrap(PickupMarker(label: pin.label, dark: dark))),
          ym.IconStyle(anchor: PickupMarker.anchor, zIndex: 20),
        );
      case PinKind.destination:
        return (
          ymv.ViewProvider(builder: () => wrap(DestinationMarker(label: pin.label, dark: dark))),
          ym.IconStyle(anchor: DestinationMarker.anchor, zIndex: 20),
        );
      case PinKind.me:
        return (
          ymv.ViewProvider(builder: () => wrap(const MeMarker())),
          const ym.IconStyle(anchor: math.Point(0.5, 0.5), zIndex: 10),
        );
      case PinKind.car:
        return (
          ymv.ViewProvider(builder: () => wrap(const CarMarker(width: 18, highlighted: false)), id: 'car-small', cacheable: true),
          const ym.IconStyle(anchor: math.Point(0.5, 0.5), rotationType: ym.RotationType.Rotate, flat: true, zIndex: 15),
        );
    }
  }

  // ---- the trip car ----

  @override
  void drawCar() {
    final layer = _carLayer;
    if (layer == null) return;
    final pos = motion.position;
    if (pos == null) {
      if (_car != null) {
        layer.remove(_car!);
        _car = null;
      }
      return;
    }
    final car = _car ??= layer.addPlacemarkWithViewStyle(
      _pt(pos),
      ymv.ViewProvider(
        builder: () => const Directionality(textDirection: TextDirection.ltr, child: CarMarker(width: 24)),
        id: 'car-main',
        cacheable: true,
      ),
      const ym.IconStyle(anchor: math.Point(0.5, 0.5), rotationType: ym.RotationType.Rotate, flat: true, zIndex: 100),
    );
    car
      ..geometry = _pt(pos)
      ..direction = motion.heading;
  }

  // ---- camera ----

  @override
  LatLng? get center {
    final m = _map;
    return m == null ? null : _ll(m.cameraPosition.target);
  }

  @override
  void moveTo(LatLng p, {double? zoom, bool animate = true}) {
    final m = _map;
    if (m == null) return;
    final cur = m.cameraPosition;
    m.move(
      ym.CameraPosition(_pt(p), zoom: zoom ?? cur.zoom, azimuth: 0, tilt: 0),
      animation: animate ? const ym.Animation(type: ym.AnimationType.Smooth, duration: 0.8) : const ym.Animation(),
    );
  }

  @override
  void fit(List<LatLng> points, {required double maxZoom, bool animate = true}) {
    final m = _map;
    if (m == null || points.isEmpty) return;
    var minLat = points.first.latitude, maxLat = minLat, minLng = points.first.longitude, maxLng = minLng;
    for (final p in points) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    // A little air around the points.
    final dLat = (maxLat - minLat) * 0.12 + 0.0005, dLng = (maxLng - minLng) * 0.12 + 0.0005;
    final box = ym.BoundingBox(
      ym.Point(latitude: minLat - dLat, longitude: minLng - dLng),
      ym.Point(latitude: maxLat + dLat, longitude: maxLng + dLng),
    );
    final pos = m.cameraPositionForGeometry(ym.Geometry.fromBoundingBox(box), focusRect: _window?.focusRect);
    m.move(
      ym.CameraPosition(pos.target, zoom: math.min(pos.zoom, maxZoom), azimuth: 0, tilt: 0),
      animation: animate ? const ym.Animation(type: ym.AnimationType.Smooth, duration: 0.8) : const ym.Animation(),
    );
  }

  void _onCamera(ym.CameraPosition pos, ym.CameraUpdateReason reason, bool finished) {
    if (reason != ym.CameraUpdateReason.Gestures) return;
    if (!finished) {
      if (!_gesture) {
        _gesture = true;
        userGestureStarted();
      }
    } else {
      _gesture = false;
      userGestureEnded(_ll(pos.target));
    }
  }

  bool _gesture = false;

  @override
  Widget build(BuildContext context) {
    return ymw.YandexMap(onMapCreated: _onMapCreated, platformViewType: ymw.PlatformViewType.Hybrid);
  }
}

class _CameraListener implements ym.MapCameraListener {
  _CameraListener(this._state);
  final _YandexMapViewState _state;

  @override
  void onCameraPositionChanged(ym.Map map, ym.CameraPosition cameraPosition, ym.CameraUpdateReason cameraUpdateReason, bool finished) {
    _state._onCamera(cameraPosition, cameraUpdateReason, finished);
  }
}
