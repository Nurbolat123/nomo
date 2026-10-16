import 'package:flutter_test/flutter_test.dart';
import 'package:nomo_core/nomo_core.dart';

void main() {
  test('polyline encode/decode matches the Google example and the backend', () {
    const pts = [LatLng(38.5, -120.2), LatLng(40.7, -120.95), LatLng(43.252, -126.453)];
    final enc = RouteMath.encode(pts);
    expect(enc, '_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    final dec = RouteMath.decode(enc);
    expect(dec.length, 3);
    for (var i = 0; i < 3; i++) {
      expect(dec[i].latitude, closeTo(pts[i].latitude, 1e-6));
      expect(dec[i].longitude, closeTo(pts[i].longitude, 1e-6));
    }
    expect(RouteMath.decode('_p~iF~ps|U_'), isEmpty, reason: 'truncated input');
    expect(RouteMath.decode(''), isEmpty);
  });

  test('bearing and angle interpolation', () {
    const a = LatLng(51.23, 51.36);
    expect(RouteMath.bearing(a, const LatLng(51.24, 51.36)), closeTo(0, 0.5));
    expect(RouteMath.bearing(a, const LatLng(51.23, 51.37)), closeTo(90, 0.5));
    // 350° → 10° goes through north, not backwards through 180°.
    expect(RouteMath.lerpAngle(350, 10, 0.5), closeTo(0, 1e-9));
    expect(RouteMath.lerpAngle(10, 350, 0.25), closeTo(5, 1e-9));
  });

  test('projection cuts off the driven part of the route', () {
    const a = LatLng(51.2300, 51.3600);
    const b = LatLng(51.2390, 51.3600); // ~1 km north
    const c = LatLng(51.2390, 51.3744); // ~1 km east
    final route = [a, b, c];
    final total = RouteMath.length(route);
    expect(total, closeTo(2000, 30));

    // Car halfway up the first leg, 20 m off to the side.
    const car = LatLng(51.2345, 51.36029);
    final p = RouteMath.project(route, car);
    expect(p.segment, 0);
    expect(p.offRouteM, closeTo(20, 3));
    final ahead = RouteMath.remaining(route, p);
    expect(ahead.length, 3);
    expect(RouteMath.length(ahead), closeTo(1500, 30));
    expect(RouteMath.length(RouteMath.passed(route, p)), closeTo(500, 30));

    // On the second leg, searching forward from segment 1.
    final p2 = RouteMath.project(route, const LatLng(51.2390, 51.3700), fromSegment: 1);
    expect(p2.segment, 1);
    expect(RouteMath.length(RouteMath.remaining(route, p2)), closeTo(305, 20));
  });

  test('straight-line fallback route has no hint for the server', () async {
    final r = await StraightRouteService().drive(const LatLng(51.23, 51.36), const LatLng(51.24, 51.36));
    expect(r, isNotNull);
    expect(r!.estimated, isTrue);
    expect(r.toHint(), isNull);
    expect(r.distanceM, closeTo(1112 * 1.35, 15));
  });
}
