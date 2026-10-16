import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';

import '../config.dart';
import '../theme.dart';
import 'map_markers.dart';
import 'nomo_map.dart';

/// OpenStreetMap fallback for [NomoMap], used when no Yandex key is set.
class OsmMapView extends StatefulWidget {
  const OsmMapView({super.key, required this.config});
  final NomoMap config;

  @override
  State<OsmMapView> createState() => _OsmMapViewState();
}

class _OsmMapViewState extends NomoMapViewState<OsmMapView> {
  @override
  NomoMap get config => widget.config;

  final _map = fm.MapController();
  bool _ready = false;

  @override
  void didUpdateWidget(OsmMapView old) {
    super.didUpdateWidget(old);
    syncScene(old.config);
  }

  @override
  void dispose() {
    config.controller.detach(this);
    super.dispose();
  }

  // The car animates every frame: a cheap rebuild of the marker layers.
  @override
  void drawCar() => setState(() {});

  @override
  void drawRoute() => setState(() {});

  @override
  LatLng? get center => _ready ? _map.camera.center : null;

  @override
  void moveTo(LatLng p, {double? zoom, bool animate = true}) {
    if (!_ready) return;
    _map.move(p, zoom ?? _map.camera.zoom);
  }

  @override
  void fit(List<LatLng> points, {required double maxZoom, bool animate = true}) {
    if (!_ready || points.isEmpty) return;
    final p = config.padding;
    _map.fitCamera(fm.CameraFit.bounds(
      bounds: fm.LatLngBounds.fromPoints(points),
      padding: EdgeInsets.fromLTRB(p.left + 40, p.top + 40, p.right + 40, p.bottom + 40),
      maxZoom: maxZoom,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final dark = config.isDark(context);
    final ink = dark ? NomoColors.gold : NomoColors.black;
    final casing = dark ? NomoColors.black : NomoColors.white;
    final ahead = routeAhead;
    final trail = this.trail;
    final car = motion.position;
    return fm.FlutterMap(
      mapController: _map,
      options: fm.MapOptions(
        initialCenter: config.center,
        initialZoom: config.zoom,
        minZoom: 4,
        maxZoom: 19,
        onMapReady: () {
          _ready = true;
          config.controller.attach(this);
          config.onReady?.call();
        },
        interactionOptions: const fm.InteractionOptions(flags: fm.InteractiveFlag.all & ~fm.InteractiveFlag.rotate),
        onMapEvent: (e) {
          if (e.source == fm.MapEventSource.mapController || e.source == fm.MapEventSource.fitCamera) return;
          if (e is fm.MapEventMoveStart) userGestureStarted();
          if (e is fm.MapEventMoveEnd || e is fm.MapEventFlingAnimationEnd) userGestureEnded(e.camera.center);
        },
      ),
      children: [
        ColorFiltered(
          colorFilter: dark ? _darkFilter : _lightFilter,
          child: fm.TileLayer(urlTemplate: NomoConfig.tileUrl, userAgentPackageName: 'com.nomo.app', maxZoom: 19),
        ),
        if (config.heat.isNotEmpty)
          fm.CircleLayer(circles: [
            for (final h in config.heat)
              fm.CircleMarker(
                point: LatLng(h.lat, h.lng),
                radius: 500,
                useRadiusInMeter: true,
                color: NomoColors.gold.withValues(alpha: 0.12 + 0.1 * h.level),
              ),
          ]),
        fm.PolylineLayer(polylines: [
          if (trail.length >= 2)
            fm.Polyline(points: List.of(trail), strokeWidth: 5, color: dark ? const Color(0x99FFC93C) : const Color(0x80575757)),
          if (ahead.length >= 2)
            fm.Polyline(points: ahead, strokeWidth: 6, color: ink, borderStrokeWidth: 2, borderColor: casing),
        ]),
        fm.MarkerLayer(markers: [
          for (final p in config.pins) _marker(p, dark),
          if (car != null)
            fm.Marker(
              key: const ValueKey('trip-car'),
              point: car,
              width: 40,
              height: 50,
              child: Transform.rotate(angle: motion.heading * 3.141592653589793 / 180, child: const Center(child: CarMarker(width: 24))),
            ),
        ]),
        const fm.RichAttributionWidget(attributions: [fm.TextSourceAttribution('© OpenStreetMap')]),
      ],
    );
  }

  fm.Marker _marker(MapPin p, bool dark) {
    switch (p.kind) {
      case PinKind.pickup:
        return fm.Marker(
          key: ValueKey(p.id),
          point: p.point,
          width: PickupMarker.width,
          height: PickupMarker.height,
          alignment: Alignment(0, 1 - 2 * PickupMarker.anchor.y),
          child: PickupMarker(label: p.label, dark: dark),
        );
      case PinKind.destination:
        return fm.Marker(
          key: ValueKey(p.id),
          point: p.point,
          width: DestinationMarker.width,
          height: DestinationMarker.height,
          alignment: Alignment(0, 1 - 2 * DestinationMarker.anchor.y),
          child: DestinationMarker(label: p.label, dark: dark),
        );
      case PinKind.me:
        return fm.Marker(key: ValueKey(p.id), point: p.point, width: 30, height: 30, child: const Center(child: MeMarker()));
      case PinKind.car:
        return fm.Marker(
          key: ValueKey(p.id),
          point: p.point,
          width: 34,
          height: 40,
          child: Transform.rotate(
            angle: p.heading * 3.141592653589793 / 180,
            child: const Center(child: CarMarker(width: 18, highlighted: false)),
          ),
        );
    }
  }

  static const _lightFilter = ColorFilter.matrix(<double>[
    0.85, 0.1, 0.05, 0, 8, //
    0.1, 0.85, 0.05, 0, 8,
    0.1, 0.1, 0.8, 0, 8,
    0, 0, 0, 1, 0,
  ]);

  static const _darkFilter = ColorFilter.matrix(<double>[
    -0.8, -0.1, -0.05, 0, 235, //
    -0.1, -0.8, -0.05, 0, 235,
    -0.1, -0.1, -0.75, 0, 235,
    0, 0, 0, 1, 0,
  ]);
}
