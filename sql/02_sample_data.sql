-- ============================================================================
-- Sample data for High-Concurrency Booking Engine (P1)
-- Run after 01_schema.sql
-- ============================================================================

USE booking_engine;

-- Cities
INSERT INTO city (id, name, state) VALUES
  (1, 'Bengaluru', 'Karnataka'),
  (2, 'Mumbai', 'Maharashtra');

-- Theatres
INSERT INTO theatre (id, city_id, name, address_line) VALUES
  (1, 1, 'PVR Orion Mall', 'Dr Rajkumar Road, Rajajinagar, Bengaluru'),
  (2, 1, 'INOX Garuda Mall', 'Magrath Road, Bengaluru');

-- Screens
INSERT INTO screen (id, theatre_id, name, total_seats) VALUES
  (1, 1, 'Audi 1', 8),
  (2, 1, 'Audi 2', 6),
  (3, 2, 'Screen 1', 6);

-- Seats (small demo layouts)
INSERT INTO seat (id, screen_id, row_label, seat_number, seat_type) VALUES
  -- PVR Orion Audi 1
  (1, 1, 'A', 1, 'REGULAR'),
  (2, 1, 'A', 2, 'REGULAR'),
  (3, 1, 'A', 3, 'REGULAR'),
  (4, 1, 'A', 4, 'REGULAR'),
  (5, 1, 'B', 1, 'PREMIUM'),
  (6, 1, 'B', 2, 'PREMIUM'),
  (7, 1, 'B', 3, 'RECLINER'),
  (8, 1, 'B', 4, 'RECLINER'),
  -- PVR Orion Audi 2
  (9,  2, 'A', 1, 'REGULAR'),
  (10, 2, 'A', 2, 'REGULAR'),
  (11, 2, 'A', 3, 'REGULAR'),
  (12, 2, 'B', 1, 'PREMIUM'),
  (13, 2, 'B', 2, 'PREMIUM'),
  (14, 2, 'B', 3, 'PREMIUM'),
  -- INOX Screen 1
  (15, 3, 'A', 1, 'REGULAR'),
  (16, 3, 'A', 2, 'REGULAR'),
  (17, 3, 'A', 3, 'REGULAR'),
  (18, 3, 'B', 1, 'PREMIUM'),
  (19, 3, 'B', 2, 'PREMIUM'),
  (20, 3, 'B', 3, 'PREMIUM');

-- Movies
INSERT INTO movie (id, title, language, duration_mins, certification) VALUES
  (1, 'Kalki 2898 AD', 'Telugu', 181, 'UA'),
  (2, 'Deadpool & Wolverine', 'English', 128, 'A'),
  (3, 'Pushpa 2', 'Telugu', 200, 'UA');

-- Users
INSERT INTO `user` (id, email, phone, full_name) VALUES
  (1, 'nagaraj@example.com', '8660411338', 'Nagaraju S'),
  (2, 'priya@example.com',   '9876543210', 'Priya Sharma');

-- Shows on 2026-11-20 at PVR Orion Mall (theatre_id = 1) — matches UI "next 7 dates" idea
INSERT INTO `show` (id, movie_id, screen_id, show_date, start_time, end_time, base_price) VALUES
  (1, 1, 1, '2026-11-20', '10:00:00', '13:05:00', 250.00),
  (2, 1, 1, '2026-11-20', '14:00:00', '17:05:00', 300.00),
  (3, 2, 2, '2026-11-20', '11:30:00', '13:40:00', 350.00),
  (4, 2, 2, '2026-11-20', '18:00:00', '20:10:00', 400.00),
  (5, 3, 1, '2026-11-20', '20:30:00', '23:55:00', 280.00),
  -- another theatre / date for contrast
  (6, 1, 3, '2026-11-20', '15:00:00', '18:05:00', 270.00),
  (7, 2, 1, '2026-11-21', '10:00:00', '12:10:00', 250.00);

-- Inventory: one show_seat row per seat for shows 1..5 (PVR Orion on 2026-11-20)
INSERT INTO show_seat (show_id, seat_id, status)
SELECT sh.id, st.id, 'AVAILABLE'
FROM `show` sh
JOIN seat st ON st.screen_id = sh.screen_id
WHERE sh.id IN (1, 2, 3, 4, 5, 6, 7);

-- Example: user 1 holds seats A1,A2 on show 1 for 10 minutes
-- (In production Redis SET NX EX + this DB update happen together.)
UPDATE show_seat
SET status = 'HELD',
    hold_token = '11111111-1111-1111-1111-111111111111',
    hold_expires_at = '2026-11-20 09:40:00.000',
    version = version + 1
WHERE show_id = 1
  AND seat_id IN (1, 2)
  AND status = 'AVAILABLE';

INSERT INTO booking (
  id, user_id, show_id, status, hold_token, hold_expires_at, total_amount
) VALUES (
  1, 1, 1, 'HOLD',
  '11111111-1111-1111-1111-111111111111',
  '2026-11-20 09:40:00.000',
  500.00
);

INSERT INTO booking_seat (booking_id, show_seat_id, price)
SELECT 1, ss.id, 250.00
FROM show_seat ss
WHERE ss.show_id = 1 AND ss.seat_id IN (1, 2);

-- Example confirmed booking on show 3 (Audi 2) seats A1
UPDATE show_seat
SET status = 'BOOKED',
    hold_token = NULL,
    hold_expires_at = NULL,
    version = version + 1
WHERE show_id = 3 AND seat_id = 9 AND status = 'AVAILABLE';

INSERT INTO booking (
  id, user_id, show_id, status, hold_token, hold_expires_at, total_amount
) VALUES (
  2, 2, 3, 'CONFIRMED',
  '22222222-2222-2222-2222-222222222222',
  '2026-11-20 10:00:00.000',
  350.00
);

INSERT INTO booking_seat (booking_id, show_seat_id, price)
SELECT 2, ss.id, 350.00
FROM show_seat ss
WHERE ss.show_id = 3 AND ss.seat_id = 9;

INSERT INTO payment (
  id, booking_id, provider, provider_payment_id, amount, status
) VALUES (
  1, 2, 'RAZORPAY', 'pay_ABC123XYZ', 350.00, 'SUCCESS'
);

-- Idempotent webhook already processed for that payment
INSERT INTO payment_webhook_event (
  provider, event_id, payment_id, payload_hash
) VALUES (
  'RAZORPAY',
  'evt_payment_captured_001',
  1,
  SHA2('{"event":"payment.captured","id":"evt_payment_captured_001"}', 256)
);
