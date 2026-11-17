-- ============================================================================
-- Concurrency patterns (reference SQL — not required to "run" for submission,
-- but shows how locking / holds / webhooks work against this schema)
-- ============================================================================

USE booking_engine;

-- ---------------------------------------------------------------------------
-- A) Place a timed hold (pessimistic row locks inside a transaction)
-- ---------------------------------------------------------------------------
-- START TRANSACTION;
--
-- SELECT id, status, version
-- FROM show_seat
-- WHERE show_id = 1
--   AND seat_id IN (3, 4)
--   AND status = 'AVAILABLE'
-- FOR UPDATE;
--
-- -- Application checks: row count == requested seat count
--
-- UPDATE show_seat
-- SET status = 'HELD',
--     hold_token = '33333333-3333-3333-3333-333333333333',
--     hold_expires_at = DATE_ADD(UTC_TIMESTAMP(3), INTERVAL 10 MINUTE),
--     version = version + 1
-- WHERE show_id = 1
--   AND seat_id IN (3, 4)
--   AND status = 'AVAILABLE';
--
-- INSERT INTO booking (...);
-- INSERT INTO booking_seat (...);
--
-- COMMIT;

-- ---------------------------------------------------------------------------
-- B) Optimistic hold (version check — good under low conflict)
-- ---------------------------------------------------------------------------
-- UPDATE show_seat
-- SET status = 'HELD',
--     hold_token = ?,
--     hold_expires_at = ?,
--     version = version + 1
-- WHERE id = ?
--   AND status = 'AVAILABLE'
--   AND version = ?;   -- affected_rows must be 1 else retry / fail

-- ---------------------------------------------------------------------------
-- C) Auto-release expired holds (worker / cron every 30s)
-- ---------------------------------------------------------------------------
-- START TRANSACTION;
--
-- UPDATE show_seat
-- SET status = 'AVAILABLE',
--     hold_token = NULL,
--     hold_expires_at = NULL,
--     version = version + 1
-- WHERE status = 'HELD'
--   AND hold_expires_at < UTC_TIMESTAMP(3);
--
-- UPDATE booking
-- SET status = 'EXPIRED',
--     version = version + 1
-- WHERE status IN ('HOLD', 'PENDING_PAYMENT')
--   AND hold_expires_at < UTC_TIMESTAMP(3);
--
-- COMMIT;

-- ---------------------------------------------------------------------------
-- D) Confirm after successful payment (must still own hold_token)
-- ---------------------------------------------------------------------------
-- START TRANSACTION;
--
-- SELECT * FROM booking WHERE id = ? FOR UPDATE;
--
-- UPDATE show_seat
-- SET status = 'BOOKED',
--     hold_token = NULL,
--     hold_expires_at = NULL,
--     version = version + 1
-- WHERE hold_token = ?
--   AND status = 'HELD'
--   AND hold_expires_at >= UTC_TIMESTAMP(3);
--
-- UPDATE booking SET status = 'CONFIRMED', version = version + 1 WHERE id = ?;
--
-- COMMIT;

-- ---------------------------------------------------------------------------
-- E) Idempotent payment webhook
-- ---------------------------------------------------------------------------
-- START TRANSACTION;
--
-- INSERT INTO payment_webhook_event (provider, event_id, payment_id, payload_hash)
-- VALUES ('RAZORPAY', ?, ?, ?);
-- -- If duplicate key on uk_webhook_event → ROLLBACK / return 200 OK (already processed)
--
-- UPDATE payment SET status = 'SUCCESS' WHERE id = ? AND status <> 'SUCCESS';
-- -- then run confirm path (D)
--
-- COMMIT;

-- ---------------------------------------------------------------------------
-- F) Prove no double booking is possible
-- ---------------------------------------------------------------------------
-- This must always return 0 rows:
SELECT show_id, seat_id, COUNT(*) AS cnt
FROM show_seat
GROUP BY show_id, seat_id
HAVING COUNT(*) > 1;

-- Seats cannot be both HELD and BOOKED (single row / single status):
SELECT id, show_id, seat_id, status
FROM show_seat
WHERE status IN ('HELD', 'BOOKED');
