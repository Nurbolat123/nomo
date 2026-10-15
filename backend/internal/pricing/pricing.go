// Package pricing calculates trip prices, surge, waiting and cancellation fees.
package pricing

import (
	"math"
	"time"
)

type Tariff struct {
	Code          string `json:"code"`
	Name          string `json:"name"`
	BaseFare      int    `json:"base_fare"`
	PerKm         int    `json:"per_km"`
	PerMin        int    `json:"per_min"`
	MinFare       int    `json:"min_fare"`
	FreeWaitMin   int    `json:"free_wait_min"`
	WaitPerMin    int    `json:"wait_per_min"`
	CancelFee     int    `json:"cancel_fee"`
	CommissionPct int    `json:"commission_pct"`
	Sort          int    `json:"sort"`
	Active        bool   `json:"active"`
}

// MaxSurge caps the demand coefficient.
const MaxSurge = 2.0

// Price returns the trip price: base + km × rate + min × rate, times surge,
// never below the minimum fare, rounded up to 10.
func Price(t Tariff, distanceM, durationS int, surge float64) int {
	if surge < 1 {
		surge = 1
	}
	raw := float64(t.BaseFare) +
		float64(distanceM)/1000*float64(t.PerKm) +
		float64(durationS)/60*float64(t.PerMin)
	raw *= surge
	if raw < float64(t.MinFare)*surge {
		raw = float64(t.MinFare) * surge
	}
	return roundUp10(raw)
}

// Surge returns the demand coefficient from open orders and free drivers
// nearby: 1.0 while drivers outnumber orders, rising by 0.25 per extra order
// per driver, capped at MaxSurge.
func Surge(openOrders, freeDrivers int) float64 {
	if openOrders <= freeDrivers || openOrders == 0 {
		return 1
	}
	drivers := math.Max(1, float64(freeDrivers))
	ratio := float64(openOrders) / drivers
	s := 1 + (ratio-1)*0.25
	s = math.Min(MaxSurge, s)
	return math.Round(s*10) / 10
}

// WaitingFee is charged for each started minute the passenger kept the driver
// waiting beyond the free minutes.
func WaitingFee(t Tariff, arrivedAt, startedAt time.Time) int {
	if arrivedAt.IsZero() || startedAt.Before(arrivedAt) {
		return 0
	}
	waited := startedAt.Sub(arrivedAt)
	free := time.Duration(t.FreeWaitMin) * time.Minute
	if waited <= free {
		return 0
	}
	extraMin := int(math.Ceil((waited - free).Minutes()))
	return extraMin * t.WaitPerMin
}

// FreeCancelWindow is how long after a driver is assigned the passenger may cancel for free.
const FreeCancelWindow = 2 * time.Minute

// CancelFee returns the fee for a passenger cancellation: free while
// searching and during the first minutes after assignment; charged once the
// driver has arrived or the free window has passed.
func CancelFee(t Tariff, status string, assignedAt time.Time, now time.Time) int {
	switch status {
	case "arrived":
		return t.CancelFee
	case "assigned":
		if !assignedAt.IsZero() && now.Sub(assignedAt) > FreeCancelWindow {
			return t.CancelFee
		}
	}
	return 0
}

// Commission is the service share of a fare.
func Commission(t Tariff, fare int) int {
	return int(math.Round(float64(fare) * float64(t.CommissionPct) / 100))
}

func roundUp10(v float64) int {
	return int(math.Ceil(v/10) * 10)
}
