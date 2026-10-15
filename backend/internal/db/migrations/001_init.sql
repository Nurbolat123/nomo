CREATE TABLE IF NOT EXISTS users (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    phone        text NOT NULL,
    role         text NOT NULL CHECK (role IN ('passenger', 'driver')),
    name         text NOT NULL DEFAULT '',
    email        text NOT NULL DEFAULT '',
    locale       text NOT NULL DEFAULT 'ru',
    rating_sum   integer NOT NULL DEFAULT 0,
    rating_count integer NOT NULL DEFAULT 0,
    created_at   timestamptz NOT NULL DEFAULT now(),
    deleted_at   timestamptz,
    UNIQUE (phone, role)
);

CREATE TABLE IF NOT EXISTS drivers (
    user_id     uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    status      text NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'pending', 'approved', 'rejected', 'blocked')),
    status_note text NOT NULL DEFAULT '',
    car_make    text NOT NULL DEFAULT '',
    car_model   text NOT NULL DEFAULT '',
    car_color   text NOT NULL DEFAULT '',
    car_plate   text NOT NULL DEFAULT '',
    car_year    integer NOT NULL DEFAULT 0,
    classes     text[] NOT NULL DEFAULT ARRAY['economy'],
    online      boolean NOT NULL DEFAULT false,
    busy        boolean NOT NULL DEFAULT false,
    balance     bigint NOT NULL DEFAULT 0,
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS driver_documents (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id  uuid NOT NULL REFERENCES drivers(user_id) ON DELETE CASCADE,
    kind       text NOT NULL CHECK (kind IN ('license', 'sts', 'osago', 'car_photo', 'selfie')),
    path       text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS driver_documents_driver ON driver_documents(driver_id);

CREATE TABLE IF NOT EXISTS tariffs (
    code           text PRIMARY KEY,
    name           text NOT NULL,
    base_fare      integer NOT NULL,
    per_km         integer NOT NULL,
    per_min        integer NOT NULL,
    min_fare       integer NOT NULL,
    free_wait_min  integer NOT NULL DEFAULT 3,
    wait_per_min   integer NOT NULL DEFAULT 0,
    cancel_fee     integer NOT NULL DEFAULT 0,
    commission_pct integer NOT NULL DEFAULT 15,
    sort           integer NOT NULL DEFAULT 0,
    active         boolean NOT NULL DEFAULT true
);

-- Starting values are placeholders: set real ones in the admin panel.
INSERT INTO tariffs (code, name, base_fare, per_km, per_min, min_fare, free_wait_min, wait_per_min, cancel_fee, commission_pct, sort)
VALUES ('economy',  'Эконом',  300, 120, 20,  700, 3, 30, 300, 15, 1),
       ('comfort',  'Комфорт', 400, 160, 25, 1000, 3, 40, 400, 15, 2),
       ('business', 'Бизнес',  700, 260, 40, 2000, 5, 60, 700, 18, 3)
ON CONFLICT (code) DO NOTHING;

CREATE TABLE IF NOT EXISTS payment_methods (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    brand      text NOT NULL,
    last4      text NOT NULL,
    token      text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);

CREATE TABLE IF NOT EXISTS orders (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    passenger_id      uuid NOT NULL REFERENCES users(id),
    driver_id         uuid REFERENCES users(id),
    tariff            text NOT NULL REFERENCES tariffs(code),
    status            text NOT NULL CHECK (status IN ('searching', 'assigned', 'arrived', 'in_progress', 'completed', 'cancelled', 'no_drivers')),
    from_lat          double precision NOT NULL,
    from_lng          double precision NOT NULL,
    from_addr         text NOT NULL DEFAULT '',
    to_lat            double precision NOT NULL,
    to_lng            double precision NOT NULL,
    to_addr           text NOT NULL DEFAULT '',
    distance_m        integer NOT NULL,
    duration_s        integer NOT NULL,
    surge             numeric(4,2) NOT NULL DEFAULT 1,
    price             integer NOT NULL,
    final_price       integer,
    tip               integer NOT NULL DEFAULT 0,
    payment_method    text NOT NULL CHECK (payment_method IN ('cash', 'card')),
    payment_method_id uuid REFERENCES payment_methods(id),
    payment_ref       text NOT NULL DEFAULT '',
    payment_status    text NOT NULL DEFAULT 'none',
    comment           text NOT NULL DEFAULT '',
    child_seat        boolean NOT NULL DEFAULT false,
    with_pet          boolean NOT NULL DEFAULT false,
    cancelled_by      text NOT NULL DEFAULT '',
    cancel_reason     text NOT NULL DEFAULT '',
    cancel_fee        integer NOT NULL DEFAULT 0,
    driver_rating     integer,
    passenger_rating  integer,
    rating_comment    text NOT NULL DEFAULT '',
    created_at        timestamptz NOT NULL DEFAULT now(),
    assigned_at       timestamptz,
    arrived_at        timestamptz,
    started_at        timestamptz,
    completed_at      timestamptz,
    cancelled_at      timestamptz
);
CREATE INDEX IF NOT EXISTS orders_passenger ON orders(passenger_id, created_at DESC);
CREATE INDEX IF NOT EXISTS orders_driver ON orders(driver_id, created_at DESC);
CREATE INDEX IF NOT EXISTS orders_status ON orders(status);

CREATE TABLE IF NOT EXISTS order_offers (
    order_id   uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    driver_id  uuid NOT NULL REFERENCES users(id),
    status     text NOT NULL CHECK (status IN ('offered', 'accepted', 'declined', 'expired')),
    eta_s      integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (order_id, driver_id)
);

CREATE TABLE IF NOT EXISTS messages (
    id         bigserial PRIMARY KEY,
    order_id   uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    sender_id  uuid NOT NULL REFERENCES users(id),
    body       text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS messages_order ON messages(order_id, id);

CREATE TABLE IF NOT EXISTS driver_transactions (
    id         bigserial PRIMARY KEY,
    driver_id  uuid NOT NULL REFERENCES users(id),
    order_id   uuid REFERENCES orders(id),
    kind       text NOT NULL CHECK (kind IN ('fare', 'commission', 'tip', 'payout', 'adjustment')),
    amount     integer NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS driver_transactions_driver ON driver_transactions(driver_id, created_at DESC);

CREATE TABLE IF NOT EXISTS saved_places (
    id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    label   text NOT NULL,
    addr    text NOT NULL,
    lat     double precision NOT NULL,
    lng     double precision NOT NULL
);

CREATE TABLE IF NOT EXISTS push_tokens (
    user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token      text NOT NULL,
    platform   text NOT NULL DEFAULT '',
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, token)
);
