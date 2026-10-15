import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config.dart';
import '../models.dart';
import '../theme.dart';

export 'package:flutter_map/flutter_map.dart' show MapController, MapCamera, CameraFit, LatLngBounds;
export 'package:latlong2/latlong.dart' show LatLng;

enum PinKind { pickup, destination, car, me }

class MapPin {
  const MapPin(this.kind, this.lat, this.lng, {this.heading = 0, this.key});
  final PinKind kind;
  final double lat, lng, heading;
  final String? key;
  LatLng get point => LatLng(lat, lng);
}

class HeatSpot {
  const HeatSpot(this.lat, this.lng, this.level);
  final double lat, lng;
  final int level; // 1..3
}

LatLng toLatLng(Place p) => LatLng(p.lat, p.lng);

/// The map used everywhere in the apps. Tiles come from [NomoConfig.tileUrl];
/// to switch to 2GIS or Yandex SDK, replace this widget's internals only.
class NomoMap extends StatelessWidget {
  const NomoMap({
    super.key,
    required this.controller,
    required this.center,
    this.zoom = 15,
    this.pins = const [],
    this.route = const [],
    this.heat = const [],
    this.onMoved,
    this.onMoveStart,
    this.padding = EdgeInsets.zero,
    this.onReady,
  });

  /// Called once the map can be moved with [controller].
  final VoidCallback? onReady;

  final MapController controller;
  final LatLng center;
  final double zoom;
  final List<MapPin> pins;
  final List<LatLng> route;
  final List<HeatSpot> heat;

  /// Called when the user stops moving the map, with the new center.
  final ValueChanged<LatLng>? onMoved;
  final VoidCallback? onMoveStart;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        minZoom: 4,
        maxZoom: 19,
        onMapReady: onReady,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
        onMapEvent: (e) {
          if (e is MapEventMoveStart && e.source != MapEventSource.mapController) onMoveStart?.call();
          if ((e is MapEventMoveEnd || e is MapEventFlingAnimationEnd) && e.source != MapEventSource.mapController) {
            onMoved?.call(e.camera.center);
          }
        },
      ),
      children: [
        ColorFiltered(
          // Muted, slightly desaturated tiles so the black UI stands out; inverted for dark mode.
          colorFilter: dark ? _darkFilter : _lightFilter,
          child: TileLayer(urlTemplate: NomoConfig.tileUrl, userAgentPackageName: 'com.nomo.app', maxZoom: 19),
        ),
        if (heat.isNotEmpty)
          CircleLayer(circles: [
            for (final h in heat)
              CircleMarker(
                point: LatLng(h.lat, h.lng),
                radius: 500,
                useRadiusInMeter: true,
                color: NomoColors.gold.withValues(alpha: 0.15 + 0.12 * h.level),
              ),
          ]),
        if (route.length >= 2)
          PolylineLayer(polylines: [
            Polyline(points: route, strokeWidth: 5, color: dark ? NomoColors.white : NomoColors.black),
          ]),
        MarkerLayer(markers: [
          for (final p in pins)
            Marker(
              key: p.key == null ? null : ValueKey(p.key),
              point: p.point,
              width: 44,
              height: 44,
              child: _pin(p, dark),
            ),
        ]),
        const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap')]),
      ],
    );
  }

  Widget _pin(MapPin p, bool dark) {
    final ink = dark ? NomoColors.white : NomoColors.black;
    final paper = dark ? NomoColors.black : NomoColors.white;
    switch (p.kind) {
      case PinKind.pickup:
        return Center(
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(color: ink, shape: BoxShape.circle, boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)]),
            child: Center(child: Container(width: 8, height: 8, decoration: BoxDecoration(color: paper, shape: BoxShape.circle))),
          ),
        );
      case PinKind.destination:
        return Center(
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(4), boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)]),
            child: Center(child: Container(width: 7, height: 7, color: paper)),
          ),
        );
      case PinKind.car:
        return Transform.rotate(
          angle: p.heading * math.pi / 180,
          child: Center(
            child: Container(
              width: 20,
              height: 34,
              decoration: BoxDecoration(color: NomoColors.black, borderRadius: BorderRadius.circular(7), boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)]),
              alignment: const Alignment(0, -0.45),
              child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: NomoColors.gold, shape: BoxShape.circle)),
            ),
          ),
        );
      case PinKind.me:
        return Center(
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: const Color(0xFF2F80ED),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)],
            ),
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

/// Pin drawn over the map center while the user picks a point.
class CenterPin extends StatelessWidget {
  const CenterPin({super.key, this.lifted = false});
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    return IgnorePointer(
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 150),
        offset: Offset(0, lifted ? -0.35 : -0.25),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
            child: const Center(child: CircleAvatar(radius: 6, backgroundColor: NomoColors.gold)),
          ),
          Container(width: 3, height: 16, color: ink),
        ]),
      ),
    );
  }
}
