package app

import (
	"github.com/nomo-taxi/nomo/backend/internal/geo"
)

// RouteHint is the road route the app built with Yandex MapKit.
// The server cannot route by itself (MapKit routing runs on the device), so
// it accepts the app's figures but checks them against the straight line.
type RouteHint struct {
	DistanceM int    `json:"distance_m"`
	DurationS int    `json:"duration_s"`
	Polyline  string `json:"polyline"`
}

const (
	// Route ends must be close to the requested pickup and destination.
	routeEndToleranceM = 350
	// Road distance can't be shorter than the straight line or absurdly longer.
	routeMinFactor = 0.95
	routeMaxFactor = 3.0
	// Average speed bounds, km/h.
	routeMinSpeed = 4
	routeMaxSpeed = 110
)

// resolveRoute returns the route used for pricing and the polyline to store.
// A missing or implausible hint falls back to the straight-line estimate.
func resolveRoute(from, to Place, hint *RouteHint) (geo.Route, string) {
	a, b := geo.Point{Lat: from.Lat, Lng: from.Lng}, geo.Point{Lat: to.Lat, Lng: to.Lng}
	est := geo.Estimate(a, b)
	if hint == nil || hint.Polyline == "" {
		return est, ""
	}
	pts, err := geo.Decode(hint.Polyline)
	if err != nil || len(pts) < 2 {
		return est, ""
	}
	if geo.DistanceM(pts[0], a) > routeEndToleranceM || geo.DistanceM(pts[len(pts)-1], b) > routeEndToleranceM {
		return est, ""
	}
	straight := geo.DistanceM(a, b)
	length := geo.Length(pts)
	dist := float64(hint.DistanceM)
	if dist <= 0 {
		dist = length
	}
	// The stated distance must match the drawn line (±25%) and be plausible.
	if dist < straight*routeMinFactor || dist > straight*routeMaxFactor+500 || dist < length*0.75 || dist > length*1.25+200 {
		return est, ""
	}
	dur := hint.DurationS
	if dur <= 0 {
		dur = geo.TravelSeconds(dist)
	}
	kmh := dist / 1000 / (float64(dur) / 3600)
	if kmh < routeMinSpeed || kmh > routeMaxSpeed {
		dur = geo.TravelSeconds(dist)
	}
	return geo.Route{DistanceM: int(dist + 0.5), DurationS: dur}, geo.Encode(pts)
}
