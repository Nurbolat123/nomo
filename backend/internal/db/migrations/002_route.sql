-- Road route of the trip (pickup → destination), Google encoded polyline,
-- as built by the passenger app with Yandex MapKit.
ALTER TABLE orders ADD COLUMN IF NOT EXISTS route_polyline text NOT NULL DEFAULT '';
