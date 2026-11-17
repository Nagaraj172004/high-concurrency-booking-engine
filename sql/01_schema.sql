-- ============================================================================
-- High-Concurrency Booking Engine (BookMyShow-style) — P1 Schema
-- MySQL 8.0+  |  InnoDB  |  utf8mb4
-- ============================================================================
-- Design goals:
--   1) 1NF / 2NF / 3NF / BCNF
--   2) No double-booked seats (UNIQUE show+seat inventory)
--   3) Timed holds (hold_expires_at + status)
--   4) Idempotent payment webhooks (UNIQUE provider+event_id)
-- ============================================================================

CREATE DATABASE IF NOT EXISTS booking_engine
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE booking_engine;

SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS payment_webhook_event;
DROP TABLE IF EXISTS payment;
DROP TABLE IF EXISTS booking_seat;
DROP TABLE IF EXISTS booking;
DROP TABLE IF EXISTS show_seat;
DROP TABLE IF EXISTS `show`;
DROP TABLE IF EXISTS seat;
DROP TABLE IF EXISTS screen;
DROP TABLE IF EXISTS theatre;
DROP TABLE IF EXISTS city;
DROP TABLE IF EXISTS movie;
DROP TABLE IF EXISTS `user`;
SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------------------
-- Reference / catalogue
-- ---------------------------------------------------------------------------

CREATE TABLE city (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  name          VARCHAR(100)    NOT NULL,
  state         VARCHAR(100)    NOT NULL,
  created_at    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_city_name_state (name, state)
) ENGINE=InnoDB;

CREATE TABLE theatre (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  city_id       BIGINT UNSIGNED NOT NULL,
  name          VARCHAR(150)    NOT NULL,
  address_line  VARCHAR(255)    NOT NULL,
  created_at    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_theatre_city_name (city_id, name),
  KEY idx_theatre_city (city_id),
  CONSTRAINT fk_theatre_city
    FOREIGN KEY (city_id) REFERENCES city(id)
) ENGINE=InnoDB;

CREATE TABLE screen (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  theatre_id    BIGINT UNSIGNED NOT NULL,
  name          VARCHAR(50)     NOT NULL,
  total_seats   INT UNSIGNED    NOT NULL,
  created_at    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_screen_theatre_name (theatre_id, name),
  KEY idx_screen_theatre (theatre_id),
  CONSTRAINT fk_screen_theatre
    FOREIGN KEY (theatre_id) REFERENCES theatre(id)
) ENGINE=InnoDB;

-- Physical seats belong to a screen (not to a show). Layout is stable.
CREATE TABLE seat (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  screen_id     BIGINT UNSIGNED NOT NULL,
  row_label     VARCHAR(5)      NOT NULL,
  seat_number   SMALLINT UNSIGNED NOT NULL,
  seat_type     ENUM('REGULAR','PREMIUM','RECLINER') NOT NULL DEFAULT 'REGULAR',
  PRIMARY KEY (id),
  UNIQUE KEY uk_seat_layout (screen_id, row_label, seat_number),
  KEY idx_seat_screen (screen_id),
  CONSTRAINT fk_seat_screen
    FOREIGN KEY (screen_id) REFERENCES screen(id)
) ENGINE=InnoDB;

CREATE TABLE movie (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  title           VARCHAR(200)    NOT NULL,
  language        VARCHAR(40)     NOT NULL,
  duration_mins   SMALLINT UNSIGNED NOT NULL,
  certification   VARCHAR(10)     NOT NULL DEFAULT 'UA',
  created_at      DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_movie_title_language (title, language)
) ENGINE=InnoDB;

CREATE TABLE `user` (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  email         VARCHAR(150)    NOT NULL,
  phone         VARCHAR(20)     NOT NULL,
  full_name     VARCHAR(120)    NOT NULL,
  created_at    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_user_email (email),
  UNIQUE KEY uk_user_phone (phone)
) ENGINE=InnoDB;

-- A show = one movie screening on one screen at one start time on a date.
-- Candidate key (screen_id, show_date, start_time) → BCNF.
CREATE TABLE `show` (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  movie_id      BIGINT UNSIGNED NOT NULL,
  screen_id     BIGINT UNSIGNED NOT NULL,
  show_date     DATE            NOT NULL,
  start_time    TIME            NOT NULL,
  end_time      TIME            NOT NULL,
  base_price    DECIMAL(10,2)   NOT NULL,
  created_at    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_show_screen_datetime (screen_id, show_date, start_time),
  KEY idx_show_date (show_date),
  KEY idx_show_movie (movie_id),
  KEY idx_show_screen_date (screen_id, show_date),
  CONSTRAINT fk_show_movie
    FOREIGN KEY (movie_id) REFERENCES movie(id),
  CONSTRAINT fk_show_screen
    FOREIGN KEY (screen_id) REFERENCES screen(id),
  CONSTRAINT chk_show_price CHECK (base_price >= 0),
  CONSTRAINT chk_show_end_after_start CHECK (end_time > start_time)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- Inventory + booking (concurrency-critical)
-- ---------------------------------------------------------------------------

-- One row per (show, seat). This is the source of truth for availability.
-- UNIQUE(show_id, seat_id) makes double-booking impossible at the DB layer.
CREATE TABLE show_seat (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  show_id           BIGINT UNSIGNED NOT NULL,
  seat_id           BIGINT UNSIGNED NOT NULL,
  status            ENUM('AVAILABLE','HELD','BOOKED') NOT NULL DEFAULT 'AVAILABLE',
  hold_token        CHAR(36)        NULL,
  hold_expires_at   DATETIME(3)     NULL,
  version           INT UNSIGNED    NOT NULL DEFAULT 0,  -- optimistic concurrency
  updated_at        DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
                                      ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_show_seat (show_id, seat_id),
  KEY idx_show_seat_status (show_id, status),
  KEY idx_hold_expiry (status, hold_expires_at),
  CONSTRAINT fk_show_seat_show
    FOREIGN KEY (show_id) REFERENCES `show`(id),
  CONSTRAINT fk_show_seat_seat
    FOREIGN KEY (seat_id) REFERENCES seat(id)
) ENGINE=InnoDB;

CREATE TABLE booking (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id           BIGINT UNSIGNED NOT NULL,
  show_id           BIGINT UNSIGNED NOT NULL,
  status            ENUM('HOLD','PENDING_PAYMENT','CONFIRMED','EXPIRED','CANCELLED')
                      NOT NULL DEFAULT 'HOLD',
  hold_token        CHAR(36)        NOT NULL,
  hold_expires_at   DATETIME(3)     NOT NULL,
  total_amount      DECIMAL(10,2)   NOT NULL,
  version           INT UNSIGNED    NOT NULL DEFAULT 0,
  created_at        DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at        DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
                                      ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_booking_hold_token (hold_token),
  KEY idx_booking_user (user_id),
  KEY idx_booking_show (show_id),
  KEY idx_booking_hold_expiry (status, hold_expires_at),
  CONSTRAINT fk_booking_user
    FOREIGN KEY (user_id) REFERENCES `user`(id),
  CONSTRAINT fk_booking_show
    FOREIGN KEY (show_id) REFERENCES `show`(id),
  CONSTRAINT chk_booking_amount CHECK (total_amount >= 0)
) ENGINE=InnoDB;

-- Line items for a booking. Seat uniqueness for live holds/bookings is
-- enforced primarily by show_seat.uk_show_seat + status transitions.
CREATE TABLE booking_seat (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id    BIGINT UNSIGNED NOT NULL,
  show_seat_id  BIGINT UNSIGNED NOT NULL,
  price         DECIMAL(10,2)   NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_booking_show_seat (booking_id, show_seat_id),
  KEY idx_booking_seat_show_seat (show_seat_id),
  CONSTRAINT fk_booking_seat_booking
    FOREIGN KEY (booking_id) REFERENCES booking(id),
  CONSTRAINT fk_booking_seat_show_seat
    FOREIGN KEY (show_seat_id) REFERENCES show_seat(id),
  CONSTRAINT chk_booking_seat_price CHECK (price >= 0)
) ENGINE=InnoDB;

CREATE TABLE payment (
  id                    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id            BIGINT UNSIGNED NOT NULL,
  provider              VARCHAR(40)     NOT NULL,
  provider_payment_id   VARCHAR(100)    NOT NULL,
  amount                DECIMAL(10,2)   NOT NULL,
  status                ENUM('INITIATED','SUCCESS','FAILED') NOT NULL DEFAULT 'INITIATED',
  created_at            DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at            DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
                                          ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_provider_payment (provider, provider_payment_id),
  KEY idx_payment_booking (booking_id),
  CONSTRAINT fk_payment_booking
    FOREIGN KEY (booking_id) REFERENCES booking(id),
  CONSTRAINT chk_payment_amount CHECK (amount >= 0)
) ENGINE=InnoDB;

-- Idempotent webhook processing: same event never applied twice.
CREATE TABLE payment_webhook_event (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  provider        VARCHAR(40)     NOT NULL,
  event_id        VARCHAR(100)    NOT NULL,
  payment_id      BIGINT UNSIGNED NULL,
  payload_hash    CHAR(64)        NOT NULL,
  processed_at    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_webhook_event (provider, event_id),
  KEY idx_webhook_payment (payment_id),
  CONSTRAINT fk_webhook_payment
    FOREIGN KEY (payment_id) REFERENCES payment(id)
) ENGINE=InnoDB;
