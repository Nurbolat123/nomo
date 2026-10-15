// Package geo has distance and travel-time estimates used until a routing
// provider (2GIS / Yandex / Google Directions) is connected.
package geo

import "math"

type Point struct {
	Lat float64 `json:"lat"`
	Lng float64 `json:"lng"`
}

const earthRadiusM = 6371000.0

// RoadFactor converts straight-line distance to an approximate road distance.
const RoadFactor = 1.35

// AvgSpeedKmh is the assumed average city speed for ETA and trip-time estimates.
const AvgSpeedKmh = 28.0

// DistanceM returns the great-circle distance in meters.
func DistanceM(a, b Point) float64 {
	lat1, lat2 := rad(a.Lat), rad(b.Lat)
	dLat := lat2 - lat1
	dLng := rad(b.Lng - a.Lng)
	h := math.Sin(dLat/2)*math.Sin(dLat/2) + math.Cos(lat1)*math.Cos(lat2)*math.Sin(dLng/2)*math.Sin(dLng/2)
	return 2 * earthRadiusM * math.Asin(math.Min(1, math.Sqrt(h)))
}

// Route is an estimated road distance and duration between two points.
type Route struct {
	DistanceM int `json:"distance_m"`
	DurationS int `json:"duration_s"`
}

// Estimate returns the approximate road route between two points.
func Estimate(a, b Point) Route {
	d := DistanceM(a, b) * RoadFactor
	return Route{DistanceM: int(math.Round(d)), DurationS: TravelSeconds(d)}
}

// TravelSeconds is the drive time in seconds for a road distance in meters.
func TravelSeconds(roadM float64) int {
	return int(math.Round(roadM / (AvgSpeedKmh * 1000 / 3600)))
}

// Interpolate returns the point at fraction t (0..1) between a and b.
func Interpolate(a, b Point, t float64) Point {
	return Point{Lat: a.Lat + (b.Lat-a.Lat)*t, Lng: a.Lng + (b.Lng-a.Lng)*t}
}

// Offset moves a point north and east by the given meters.
func Offset(p Point, northM, eastM float64) Point {
	dLat := northM / earthRadiusM * 180 / math.Pi
	dLng := eastM / (earthRadiusM * math.Cos(rad(p.Lat))) * 180 / math.Pi
	return Point{Lat: p.Lat + dLat, Lng: p.Lng + dLng}
}

// Bearing returns the heading in degrees from a to b.
func Bearing(a, b Point) float64 {
	lat1, lat2 := rad(a.Lat), rad(b.Lat)
	dLng := rad(b.Lng - a.Lng)
	y := math.Sin(dLng) * math.Cos(lat2)
	x := math.Cos(lat1)*math.Sin(lat2) - math.Sin(lat1)*math.Cos(lat2)*math.Cos(dLng)
	return math.Mod(math.Atan2(y, x)*180/math.Pi+360, 360)
}

func rad(d float64) float64 { return d * math.Pi / 180 }
