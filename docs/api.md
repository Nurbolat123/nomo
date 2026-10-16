# Nomo API

Base URL: `https://api.<домен>`. JSON everywhere. Auth: `Authorization: Bearer <access_token>`.
Errors: `{"error": {"code": "…", "message": "текст для пользователя"}}`.
Money in whole tenge (`currency` field), distances in meters, durations in seconds.

## Auth
| Method | Path | Body | Notes |
| --- | --- | --- | --- |
| POST | /v1/auth/request-code | `{phone, role}` role = passenger \| driver | 429 with `resend_in` if too soon |
| POST | /v1/auth/verify | `{phone, code, role}` | → `{tokens:{access_token, refresh_token, expires_in}, user_id, is_new}` |
| POST | /v1/auth/refresh | `{refresh_token}` | → `{tokens}` |
| POST | /v1/admin/login | `{email, password}` | → `{tokens}` (role admin) |

## Everyone signed in
| Method | Path | Notes |
| --- | --- | --- |
| GET / PATCH / DELETE | /v1/me | profile `{name, email, locale}`; DELETE removes the account (409 during an active trip) |
| POST | /v1/push-tokens | `{token, platform}` |
| GET | /v1/tariffs | active tariffs |
| GET | /v1/orders/{id} | own orders only |
| GET / POST | /v1/orders/{id}/messages | chat; POST `{body}` while the trip is active |
| GET | /v1/orders/{id}/call | `{phone}` to dial the other side |
| GET | /v1/ws?token=… | WebSocket, see below |

## Passenger
| Method | Path | Notes |
| --- | --- | --- |
| POST | /v1/quotes | `{from:{lat,lng,addr}, to:{…}, route?}` → per tariff `{tariff, name, price, surge, eta_s, distance_m, duration_s}` |
| GET | /v1/drivers/nearby?lat=&lng= | free cars for the map |
| POST | /v1/orders | `{from, to, tariff, payment_method: cash\|card, payment_method_id?, comment?, child_seat?, with_pet?, route?}`; the order returns `route` (encoded polyline) |
| GET | /v1/orders, /v1/orders/active | history (30), current trip or `null` |
| POST | /v1/orders/{id}/cancel | `{reason?}`; fee after 2 min from assignment or once the driver arrived |
| POST | /v1/orders/{id}/rate | `{rating 1-5, comment?}` once, after completion |
| POST | /v1/orders/{id}/tip | `{amount}` card trips only |
| GET / POST / DELETE | /v1/payment-methods | POST `{token, brand, last4}` — token from the acquirer, never a card number |
| GET / POST / DELETE | /v1/places | saved places `{label, addr, lat, lng}` |

## Driver
| Method | Path | Notes |
| --- | --- | --- |
| GET | /v1/driver/profile | status new → pending → approved / rejected / blocked |
| PUT | /v1/driver/car | `{name, car_make, car_model, car_color, car_plate, car_year}` |
| POST | /v1/driver/documents | multipart `kind` (license, sts, osago, car_photo, selfie) + `file` (JPG/PNG/PDF ≤ 10 MB) |
| POST | /v1/driver/submit | sends to review when car + all 5 documents are present |
| POST | /v1/driver/online | `{online, lat?, lng?}` approved drivers only |
| POST | /v1/driver/location | `{lat, lng, heading}` (prefer the WebSocket) |
| GET | /v1/driver/offer | current offer or `null` |
| POST | /v1/driver/offers/{id}/accept \| decline | 409 if the offer is gone |
| GET | /v1/driver/orders, /v1/driver/orders/active | |
| POST | /v1/driver/orders/{id}/arrived → start → complete | strict order of statuses |
| POST | /v1/driver/orders/{id}/cancel | before pickup; the order goes back to search |
| POST | /v1/driver/orders/{id}/rate | rate the passenger |
| GET | /v1/driver/earnings | today / week: trips, earned, cash, card, tips, commission; balance |
| GET | /v1/driver/demand | order density cells for the last 30 min |

## Admin
`GET /v1/admin/live`, `GET /v1/admin/stats?days=`, `GET /v1/admin/drivers?status=`, `GET /v1/admin/drivers/{id}`,
`POST /v1/admin/drivers/{id}/status {status, note, classes}`, `GET /v1/admin/files/{path}`,
`GET /v1/admin/tariffs`, `PUT /v1/admin/tariffs/{code}`, `GET /v1/admin/orders?status=&phone=`, `POST /v1/admin/orders/{id}/cancel`.

## Road route hint

`route: {distance_m, duration_s, polyline}` — the driving route the app built with Yandex MapKit
(Google encoded polyline, precision 5). The server uses it for the price only if the line starts and ends
within 350 m of the points, its length matches `distance_m` (±25 %), the distance is 0.95–3× the straight
line and the average speed is 4–110 km/h; otherwise it falls back to straight line × 1.35. Accepted
routes are stored and returned as `order.route` / `offer.route`.

## Order statuses
`searching → assigned → arrived → in_progress → completed`, or `cancelled` / `no_drivers` (search timed out, 3 min).

## WebSocket events (server → app)
`{"type": "...", "data": …}`

| type | to | data |
| --- | --- | --- |
| order.updated | passenger and driver | full order |
| offer.new | driver | offer `{order_id, price, from, to, pickup_eta_s, expires_at, …}` |
| offer.cancelled | driver | `{order_id}` |
| driver.location | passenger | `{order_id, lat, lng, heading}` |
| chat.message | both | message |
| driver.status | driver | driver profile after admin review |

App → server (driver): `{"type":"location","lat":…,"lng":…,"heading":…}` every few seconds while online.

## Dispatch
Nearest free approved driver of the tariff class (Redis GEO, ETA = straight line × 1.35 at 28 km/h) gets the
offer for 15 s; on decline/timeout the next one; radius 2 → 4 → 7 km; gives up after 3 min (`no_drivers`).
Price = (base + km × rate + min × rate) × surge, not below the minimum, rounded up to 10;
surge = 1 + 0.25 × (orders/free drivers − 1) within ~3 km, max 2.0.
