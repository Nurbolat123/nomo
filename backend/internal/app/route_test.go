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

func TestDemoPathsFollowRoad(t *testing.T) {
	a := geo.Point{Lat: 51.2333, Lng: 51.3667}
	b := geo.Offset(a, 0, 1500)
	c := geo.Offset(b, -2000, 0)
	o := &Order{From: Place{Lat: a.Lat, Lng: a.Lng}, To: Place{Lat: c.Lat, Lng: c.Lng}, Route: geo.Encode([]geo.Point{a, b, c})}
	approach, trip := demoPaths(o)
	if len(trip) != 3 {
		t.Fatalf("trip must be the road route, got %d points", len(trip))
	}
	// The bot comes back along the first 900 m of the route and ends at the pickup.
	if d := geo.Length(approach); d < 880 || d > 920 {
		t.Fatalf("approach length = %.0f", d)
	}
	end := approach[len(approach)-1]
	if geo.DistanceM(end, a) > 2 {
		t.Fatalf("approach ends %.0f m from pickup", geo.DistanceM(end, a))
	}
	// Without a route: straight lines.
	o.Route = ""
	approach, trip = demoPaths(o)
	if len(approach) != 2 || len(trip) != 2 {
		t.Fatal("fallback paths must be straight lines")
	}
}
