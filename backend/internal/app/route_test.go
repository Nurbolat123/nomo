package app

import (
	"testing"

	"github.com/nomo-taxi/nomo/backend/internal/geo"
)

func TestResolveRoute(t *testing.T) {
	from := Place{Lat: 51.2333, Lng: 51.3667}
	corner := geo.Offset(geo.Point{Lat: from.Lat, Lng: from.Lng}, 0, 2000)
	end := geo.Offset(corner, -1500, 0)
	to := Place{Lat: end.Lat, Lng: end.Lng}
	path := []geo.Point{{Lat: from.Lat, Lng: from.Lng}, corner, end}
	poly := geo.Encode(path)

	// Good hint: road 3.5 km, 9 minutes.
	r, stored := resolveRoute(from, to, &RouteHint{DistanceM: 3500, DurationS: 540, Polyline: poly})
	if r.DistanceM != 3500 || r.DurationS != 540 || stored == "" {
		t.Fatalf("good hint rejected: %+v %q", r, stored)
	}

	// No hint → straight-line estimate, nothing stored.
	est := geo.Estimate(geo.Point{Lat: from.Lat, Lng: from.Lng}, end)
	if r, stored := resolveRoute(from, to, nil); r != est || stored != "" {
		t.Fatalf("nil hint: %+v %q", r, stored)
	}

	// Cheating: distance far below the drawn line.
	if r, stored := resolveRoute(from, to, &RouteHint{DistanceM: 900, DurationS: 120, Polyline: poly}); r != est || stored != "" {
		t.Fatalf("short distance accepted: %+v", r)
	}

	// Route that starts somewhere else.
	far := geo.Encode([]geo.Point{geo.Offset(path[0], 2000, 0), corner, end})
	if r, _ := resolveRoute(from, to, &RouteHint{DistanceM: 4000, DurationS: 600, Polyline: far}); r != est {
		t.Fatal("route with wrong start accepted")
	}

	// Implausible duration is replaced by the speed estimate, distance kept.
	r, _ = resolveRoute(from, to, &RouteHint{DistanceM: 3500, DurationS: 10, Polyline: poly})
	if r.DistanceM != 3500 || r.DurationS != geo.TravelSeconds(3500) {
		t.Fatalf("bad duration not corrected: %+v", r)
	}

	// Garbage polyline.
	if r, _ := resolveRoute(from, to, &RouteHint{DistanceM: 3500, DurationS: 540, Polyline: "~~~"}); r != est {
		t.Fatal("garbage polyline accepted")
	}
}
