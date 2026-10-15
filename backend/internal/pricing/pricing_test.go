package pricing

import (
	"testing"
	"time"
)

var economy = Tariff{Code: "economy", BaseFare: 300, PerKm: 120, PerMin: 20, MinFare: 700, FreeWaitMin: 3, WaitPerMin: 30, CancelFee: 300, CommissionPct: 15}

func TestPrice(t *testing.T) {
	// 5 km, 10 min: 300 + 600 + 200 = 1100
	if got := Price(economy, 5000, 600, 1); got != 1100 {
		t.Fatalf("price = %d, want 1100", got)
	}
	// short trip falls back to the minimum fare
	if got := Price(economy, 500, 60, 1); got != 700 {
		t.Fatalf("min fare = %d, want 700", got)
	}
	// surge multiplies and rounds up to 10
	if got := Price(economy, 5000, 600, 1.3); got != 1430 {
		t.Fatalf("surge price = %d, want 1430", got)
	}
	// surge below 1 is ignored
	if got := Price(economy, 5000, 600, 0.5); got != 1100 {
		t.Fatalf("surge<1 price = %d, want 1100", got)
	}
}

func TestSurge(t *testing.T) {
	cases := []struct {
		orders, drivers int
		want            float64
	}{
		{0, 0, 1}, {3, 5, 1}, {5, 5, 1}, {10, 5, 1.3}, {20, 5, 1.8}, {50, 2, 2}, {4, 0, 1.8},
	}
	for _, c := range cases {
		if got := Surge(c.orders, c.drivers); got != c.want {
			t.Errorf("Surge(%d,%d) = %v, want %v", c.orders, c.drivers, got, c.want)
		}
	}
}

func TestWaitingFee(t *testing.T) {
	arrived := time.Date(2026, 1, 1, 10, 0, 0, 0, time.UTC)
	if got := WaitingFee(economy, arrived, arrived.Add(2*time.Minute)); got != 0 {
		t.Fatalf("within free wait = %d", got)
	}
	// 4m30s waited: 1m30s over → 2 started minutes × 30
	if got := WaitingFee(economy, arrived, arrived.Add(4*time.Minute+30*time.Second)); got != 60 {
		t.Fatalf("waiting fee = %d, want 60", got)
	}
}

func TestCancelFee(t *testing.T) {
	now := time.Now()
	if got := CancelFee(economy, "searching", time.Time{}, now); got != 0 {
		t.Fatal("searching cancel must be free")
	}
	if got := CancelFee(economy, "assigned", now.Add(-time.Minute), now); got != 0 {
		t.Fatal("cancel within free window must be free")
	}
	if got := CancelFee(economy, "assigned", now.Add(-3*time.Minute), now); got != 300 {
		t.Fatalf("late cancel = %d", got)
	}
	if got := CancelFee(economy, "arrived", now, now); got != 300 {
		t.Fatalf("arrived cancel = %d", got)
	}
}

func TestCommission(t *testing.T) {
	if got := Commission(economy, 1100); got != 165 {
		t.Fatalf("commission = %d", got)
	}
}
