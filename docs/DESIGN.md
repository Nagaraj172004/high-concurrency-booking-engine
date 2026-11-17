# High-Concurrency Booking Engine — P1 & P2 Design Doc

**Course:** Airtribe Backend — DB & System Design  
**Assignment:** High-Concurrency Booking Engine  
**Author:** Nagaraju S  

---

## 1. Scenario

BookMyShow-style ticketing: for a theatre, the app shows the next 7 dates. After picking a date, users see all movies and showtimes at that theatre. Thousands of users may compete for the same seats. The schema and locking strategy must prevent double-booking, support timed holds, and process payment webhooks idempotently.

---

## 2. Entities, attributes, and relationships

| Entity | Attributes | Notes |
|--------|------------|-------|
| **city** | id, name, state | Location root |
| **theatre** | id, city_id, name, address_line | Cinema hall complex |
| **screen** | id, theatre_id, name, total_seats | Auditorium inside theatre |
| **seat** | id, screen_id, row_label, seat_number, seat_type | Physical layout (stable) |
| **movie** | id, title, language, duration_mins, certification | Catalogue |
| **show** | id, movie_id, screen_id, show_date, start_time, end_time, base_price | One screening |
| **user** | id, email, phone, full_name | Booker |
| **show_seat** | id, show_id, seat_id, status, hold_token, hold_expires_at, version | **Inventory** — concurrency core |
| **booking** | id, user_id, show_id, status, hold_token, hold_expires_at, total_amount, version | Order |
| **booking_seat** | id, booking_id, show_seat_id, price | Booking line items |
| **payment** | id, booking_id, provider, provider_payment_id, amount, status | Payment attempt |
| **payment_webhook_event** | id, provider, event_id, payment_id, payload_hash, processed_at | Idempotency ledger |

### ER (logical)

```
city 1──* theatre 1──* screen 1──* seat
movie 1──* show *──1 screen
show 1──* show_seat *──1 seat
user 1──* booking *──1 show
booking 1──* booking_seat *──1 show_seat
booking 1──* payment 1──* payment_webhook_event
```

---

## 3. Normalization (1NF → BCNF)

| Form | How this schema satisfies it |
|------|------------------------------|
| **1NF** | All columns atomic (no CSV seat lists, no nested showtimes). |
| **2NF** | Non-key attrs depend on full PK. Seat type depends on `seat.id`, not on `(show, seat)`. Price on a booking line is stored on `booking_seat` for that purchase. |
| **3NF** | No transitive deps: theatre city via `city_id` (not duplicated city name on theatre beyond FK). Movie title not copied onto `show`. |
| **BCNF** | Every determinant is a candidate key. Example: `(screen_id, show_date, start_time)` uniquely determines a show (`uk_show_screen_datetime`). `(show_id, seat_id)` uniquely determines inventory (`uk_show_seat`). |

---

## 4. High-concurrency locking strategy

### 4.1 Why `show_seat` exists

Availability is **not** inferred only from `booking_seat`. One row per `(show_id, seat_id)` with `UNIQUE(show_id, seat_id)` makes it **physically impossible** for two confirmed bookings to own the same seat.

Statuses: `AVAILABLE` → `HELD` → `BOOKED` (or back to `AVAILABLE` on expiry/cancel).

### 4.2 Redis timed holds (fast path)

```
SET seat:{showId}:{seatId} = {holdToken} NX EX 600
```

- `NX` — only first requester wins  
- `EX 600` — auto-release after 10 minutes (configurable)  
- Confirm path requires Redis value == booking `hold_token`

Redis is the **speed layer**; MySQL `show_seat` is the **source of truth**.

### 4.3 Database locks

| Technique | Where used |
|-----------|------------|
| **Pessimistic** `SELECT … FOR UPDATE` | Hold + confirm transactions under high contention |
| **Optimistic** `version` column | Low-conflict updates; retry if `affected_rows = 0` |
| **UNIQUE** constraints | Hard stop on double inventory / duplicate webhook / duplicate payment id |

### 4.4 Hold expiry worker

Cron/queue job every ~30s:

1. `UPDATE show_seat SET status='AVAILABLE' … WHERE status='HELD' AND hold_expires_at < NOW(3)`
2. Mark related bookings `EXPIRED`

### 4.5 Idempotent payment webhooks

1. Begin transaction  
2. `INSERT INTO payment_webhook_event (provider, event_id, …)`  
3. On duplicate key → commit nothing / return HTTP 200 (already processed)  
4. Else update `payment` + transition seats `HELD → BOOKED` + booking `CONFIRMED`  
5. Commit  

`UNIQUE (provider, event_id)` guarantees at-most-once **effect**.

### 4.6 Burst handling with queues

- **Hold-release queue** — expire holds without blocking API  
- **Webhook consumer queue** — absorb payment provider bursts; workers process idempotently  
- API stays thin: validate → enqueue / short TX → respond  

---

## 5. Indexes for scale

| Index | Purpose |
|-------|---------|
| `show(screen_id, show_date, start_time)` unique | No overlapping slot on same screen + P2 support |
| `show(screen_id, show_date)` | Theatre-date listing via screen |
| `screen(theatre_id)` | Join theatre → screens |
| `show_seat(show_id, status)` | Seat map queries |
| `show_seat(status, hold_expires_at)` | Expiry worker |
| `payment_webhook_event(provider, event_id)` unique | Idempotency |

---

## 6. P2 query

List all shows on a given date at a given theatre, with timings:

```sql
SELECT
  t.name AS theatre_name,
  m.title AS movie_title,
  m.language,
  sc.name AS screen_name,
  s.show_date,
  s.start_time,
  s.end_time,
  s.base_price
FROM `show` s
JOIN screen sc ON sc.id = s.screen_id
JOIN theatre t ON t.id = sc.theatre_id
JOIN movie m ON m.id = s.movie_id
WHERE t.id = 1
  AND s.show_date = '2026-11-20'
ORDER BY m.title, s.start_time;
```

Expected sample result (from `02_sample_data.sql`):

| Movie | Screen | Start | End | Price |
|-------|--------|-------|-----|-------|
| Deadpool & Wolverine | Audi 2 | 11:30 | 13:40 | 350 |
| Deadpool & Wolverine | Audi 2 | 18:00 | 20:10 | 400 |
| Kalki 2898 AD | Audi 1 | 10:00 | 13:05 | 250 |
| Kalki 2898 AD | Audi 1 | 14:00 | 17:05 | 300 |
| Pushpa 2 | Audi 1 | 20:30 | 23:55 | 280 |

---

## 7. Load-test sketch (for full engine phase)

Tool: k6 or Locust  

1. Seed one show with N seats  
2. Spawn `2N` virtual users all requesting the same hot seats  
3. Assert: confirmed bookings ≤ seat count; zero duplicate `(show_id, seat_id)` in `BOOKED`  
4. Replay same webhook `event_id` 100× → booking confirmed once  

---

## 8. File map

| File | Purpose |
|------|---------|
| `sql/01_schema.sql` | CREATE DATABASE + tables |
| `sql/02_sample_data.sql` | Sample rows |
| `sql/03_p2_query.sql` | P2 solution |
| `sql/04_concurrency_patterns.sql` | Hold / expire / webhook SQL patterns |
| `docs/DESIGN.md` | This document |
| `submission/*.pdf` | Submission PDF |

All SQL is executable on **MySQL 8.0+**.
