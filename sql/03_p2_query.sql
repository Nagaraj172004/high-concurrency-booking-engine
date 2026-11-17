-- ============================================================================
-- P2 — List all shows on a given date at a given theatre, with show timings
-- ============================================================================
-- Parameters (replace literals or use prepared statements):
--   :theatre_id = 1   (PVR Orion Mall)
--   :show_date  = '2026-11-20'
-- ============================================================================

USE booking_engine;

-- Main P2 query
SELECT
  t.id              AS theatre_id,
  t.name            AS theatre_name,
  m.id              AS movie_id,
  m.title           AS movie_title,
  m.language,
  m.duration_mins,
  m.certification,
  sc.name           AS screen_name,
  s.id              AS show_id,
  s.show_date,
  s.start_time,
  s.end_time,
  s.base_price,
  CONCAT(DATE_FORMAT(s.start_time, '%h:%i %p'), ' - ',
         DATE_FORMAT(s.end_time,   '%h:%i %p')) AS show_timing
FROM `show` AS s
JOIN screen  AS sc ON sc.id = s.screen_id
JOIN theatre AS t  ON t.id  = sc.theatre_id
JOIN movie   AS m  ON m.id  = s.movie_id
WHERE t.id = 1
  AND s.show_date = '2026-11-20'
ORDER BY m.title, s.start_time;

-- Optional: same result shaped like the BookMyShow UI (movie → list of timings)
SELECT
  m.title AS movie_title,
  m.language,
  m.certification,
  GROUP_CONCAT(
    DATE_FORMAT(s.start_time, '%h:%i %p')
    ORDER BY s.start_time
    SEPARATOR ' | '
  ) AS showtimes
FROM `show` AS s
JOIN screen  AS sc ON sc.id = s.screen_id
JOIN theatre AS t  ON t.id  = sc.theatre_id
JOIN movie   AS m  ON m.id  = s.movie_id
WHERE t.id = 1
  AND s.show_date = '2026-11-20'
GROUP BY m.id, m.title, m.language, m.certification
ORDER BY m.title;
