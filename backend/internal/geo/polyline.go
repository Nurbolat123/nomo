package geo

import (
	"errors"
	"math"
	"strings"
)

// Encode packs points into the Google encoded-polyline format (precision 5),
// the same format the apps use.
func Encode(points []Point) string {
	var b strings.Builder
	var pLat, pLng int64
	for _, p := range points {
		lat := int64(math.Round(p.Lat * 1e5))
		lng := int64(math.Round(p.Lng * 1e5))
		encodeValue(&b, lat-pLat)
		encodeValue(&b, lng-pLng)
		pLat, pLng = lat, lng
	}
	return b.String()
}

func encodeValue(b *strings.Builder, v int64) {
	v <<= 1
	if v < 0 {
		v = ^v
	}
	for v >= 0x20 {
		b.WriteByte(byte((0x20 | (v & 0x1f)) + 63))
		v >>= 5
	}
	b.WriteByte(byte(v + 63))
}

var ErrBadPolyline = errors.New("bad polyline")

// MaxPolylinePoints caps decoded routes to keep requests and rows small.
const MaxPolylinePoints = 5000

// Decode unpacks a Google encoded polyline (precision 5).
func Decode(s string) ([]Point, error) {
	var points []Point
	var lat, lng int64
	i := 0
	next := func() (int64, error) {
		var result int64
		shift := uint(0)
		for {
			if i >= len(s) {
				return 0, ErrBadPolyline
			}
			c := int64(s[i]) - 63
			i++
			if c < 0 || shift > 60 {
				return 0, ErrBadPolyline
			}
			result |= (c & 0x1f) << shift
			shift += 5
			if c < 0x20 {
				break
			}
		}
		if result&1 != 0 {
			return ^(result >> 1), nil
		}
		return result >> 1, nil
	}
	for i < len(s) {
		dLat, err := next()
		if err != nil {
			return nil, err
		}
		dLng, err := next()
		if err != nil {
			return nil, err
		}
		lat += dLat
		lng += dLng
		points = append(points, Point{Lat: float64(lat) / 1e5, Lng: float64(lng) / 1e5})
		if len(points) > MaxPolylinePoints {
			return nil, ErrBadPolyline
		}
	}
	return points, nil
}

// Length is the total length of the path in meters.
func Length(points []Point) float64 {
	var d float64
	for i := 1; i < len(points); i++ {
		d += DistanceM(points[i-1], points[i])
	}
	return d
}

// Along returns the point `dist` meters along the path and the heading of the
// segment it lies on. Past the end it returns the last point.
func Along(points []Point, dist float64) (Point, float64) {
	if len(points) == 0 {
		return Point{}, 0
	}
	if len(points) == 1 || dist <= 0 {
		if len(points) > 1 {
			return points[0], Bearing(points[0], points[1])
		}
		return points[0], 0
	}
	for i := 1; i < len(points); i++ {
		seg := DistanceM(points[i-1], points[i])
		if dist <= seg && seg > 0 {
			return Interpolate(points[i-1], points[i], dist/seg), Bearing(points[i-1], points[i])
		}
		dist -= seg
	}
	n := len(points)
	return points[n-1], Bearing(points[n-2], points[n-1])
}

// Reverse returns a reversed copy.
func Reverse(points []Point) []Point {
	out := make([]Point, len(points))
	for i, p := range points {
		out[len(points)-1-i] = p
	}
	return out
}

// Head returns the first `dist` meters of the path (ending exactly at that distance).
func Head(points []Point, dist float64) []Point {
	if len(points) < 2 {
		return points
	}
	out := []Point{points[0]}
	for i := 1; i < len(points); i++ {
		seg := DistanceM(points[i-1], points[i])
		if dist <= seg {
			if seg > 0 {
				out = append(out, Interpolate(points[i-1], points[i], dist/seg))
			}
			return out
		}
		dist -= seg
		out = append(out, points[i])
	}
	return out
}
