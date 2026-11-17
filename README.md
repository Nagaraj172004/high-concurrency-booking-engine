# High-Concurrency Booking Engine 

Airtribe **Backend — DB & System Design** assignment: BookMyShow-scale seat booking schema with concurrency-safe inventory, timed holds, and idempotent payment webhooks.

## What’s included (P1 + P2)

| Deliverable | Location |
|-------------|----------|
| Entity design + NF/BCNF + locking strategy | [`docs/DESIGN.md`](docs/DESIGN.md) |
| CREATE TABLE SQL | [`sql/01_schema.sql`](sql/01_schema.sql) |
| Sample INSERT data | [`sql/02_sample_data.sql`](sql/02_sample_data.sql) |
| P2 — shows for theatre + date | [`sql/03_p2_query.sql`](sql/03_p2_query.sql) |
| Concurrency SQL patterns | [`sql/04_concurrency_patterns.sql`](sql/04_concurrency_patterns.sql) |
| Submission PDF | [`submission/High_Concurrency_Booking_Engine_P1_P2.pdf`](submission/High_Concurrency_Booking_Engine_P1_P2.pdf) |

## Quick start (MySQL 8+)

From this repo root (relative paths — works on Windows / macOS / Linux):

```bash
mysql -u root -p < sql/01_schema.sql
mysql -u root -p < sql/02_sample_data.sql
mysql -u root -p < sql/03_p2_query.sql
```

Or inside the MySQL client:

```sql
SOURCE sql/01_schema.sql;
SOURCE sql/02_sample_data.sql;
SOURCE sql/03_p2_query.sql;
```

## P2 in one line

Shows at theatre `1` on `2026-11-20`:

```sql
SELECT m.title, sc.name AS screen, s.start_time, s.end_time, s.base_price
FROM `show` s
JOIN screen sc ON sc.id = s.screen_id
JOIN theatre t ON t.id = sc.theatre_id
JOIN movie m ON m.id = s.movie_id
WHERE t.id = 1 AND s.show_date = '2026-11-20'
ORDER BY m.title, s.start_time;
```

## Concurrency highlights

1. **`show_seat`** — one row per `(show_id, seat_id)` with `UNIQUE` → no double booking  
2. **Timed holds** — `hold_token` + `hold_expires_at`; Redis `SET NX EX` in production  
3. **Optimistic + pessimistic** — `version` column and `SELECT … FOR UPDATE`  
4. **Idempotent webhooks** — `UNIQUE (provider, event_id)` on `payment_webhook_event`  

## Regenerate PDF

```bash
python -m pip install fpdf2
python scripts/build_pdf.py
```

## Submission

- **PDF:** `submission/High_Concurrency_Booking_Engine_P1_P2.pdf`  
- **GitHub:** push this repo and open a PR into `main`  
- SQL must run on MySQL (provided scripts do)

## Author

Nagaraju S — Airtribe Backend SysDesign
