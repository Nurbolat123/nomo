package geo

import (
	"math"
	"testing"
)

func TestEncodeDecode(t *testing.T) {
	// Example from Google's polyline documentation.
	pts := []Point{{38.5, -120.2}, {40.7, -120.95}, {43.252, -126.453}}
	enc := Encode(pts)
	if enc != "_p~iF~ps|U_ulLnnqC_mqNvxq`@" {
		t.Fatalf("Encode = %q", enc)
	}
	dec, err := Decode(enc)
	if err != nil || len(dec) != 3 {
		t.Fatalf("Decode: %v %v", dec, err)
	}
	for i := range pts {
		if math.Abs(dec[i].Lat-pts[i].Lat) > 1e-6 || math.Abs(dec[i].Lng-pts[i].Lng) > 1e-6 {
			t.Fatalf("point %d = %v, want %v", i, dec[i], pts[i])
		}
	}
	if _, err := Decode("_p~iF~ps|U_"); err == nil {
		t.Fatal("truncated polyline accepted")
	}
	if p, err := Decode(""); err != nil || len(p) != 0 {
		t.Fatal("empty polyline must decode to no points")
	}
}

func TestAlongAndHead(t *testing.T) {
	a := Point{51.2300, 51.3600}
	b := Offset(a, 1000, 0) // 1 km north
	c := Offset(b, 0, 1000) // then 1 km east
	path := []Point{a, b, c}
	if l := Length(path); math.Abs(l-2000) > 5 {
		t.Fatalf("Length = %v", l)
	}
	p, h := Along(path, 500)
	if math.Abs(DistanceM(a, p)-500) > 2 || math.Abs(h) > 1 {
		t.Fatalf("Along(500) = %v heading %v", p, h)
	}
	p, h = Along(path, 1500)
	if math.Abs(DistanceM(b, p)-500) > 2 || math.Abs(h-90) > 1 {
		t.Fatalf("Along(1500) = %v heading %v", p, h)
	}
	if p, _ := Along(path, 5000); p != c {
		t.Fatal("Along past the end must return the last point")
	}
	head := Head(path, 1200)
	if len(head) != 3 || math.Abs(Length(head)-1200) > 3 {
		t.Fatalf("Head(1200) = %v (len %v)", head, Length(head))
	}
	if r := Reverse(path); r[0] != c || r[2] != a {
		t.Fatal("Reverse")
	}
}
