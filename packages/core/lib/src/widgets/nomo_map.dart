import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models.dart';
import '../theme.dart';

LatLng toLatLng(Place p) => LatLng(p.lat, p.lng);

/// Pin drawn over the map centre while the user picks a point.
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
