"""Build submission PDF for High-Concurrency Booking Engine (P1 + P2)."""
from __future__ import annotations

from pathlib import Path

from fpdf import FPDF

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "submission" / "High_Concurrency_Booking_Engine_P1_P2.pdf"


class Doc(FPDF):
    def header(self) -> None:
        if self.page_no() == 1:
            return
        self.set_font("Helvetica", "I", 8)
        self.set_text_color(100, 100, 100)
        self.cell(0, 5, "High-Concurrency Booking Engine - P1 & P2 | Nagaraju S", align="R")
        self.ln(6)

    def footer(self) -> None:
        self.set_y(-12)
        self.set_font("Helvetica", "I", 8)
        self.set_text_color(120, 120, 120)
        self.cell(0, 8, f"Page {self.page_no()}/{{nb}}", align="C")

    def _end_block(self) -> None:
        self.set_x(self.l_margin)

    def h1(self, text: str) -> None:
        self.set_font("Helvetica", "B", 16)
        self.set_text_color(20, 20, 20)
        self.multi_cell(0, 8, text)
        self._end_block()
        self.ln(2)

    def h2(self, text: str) -> None:
        self.ln(2)
        self.set_font("Helvetica", "B", 12)
        self.set_text_color(25, 25, 25)
        self.multi_cell(0, 6, text)
        self._end_block()
        y = self.get_y()
        self.set_draw_color(40, 40, 40)
        self.set_line_width(0.3)
        self.line(self.l_margin, y, 210 - self.r_margin, y)
        self.ln(3)

    def h3(self, text: str) -> None:
        self.ln(1)
        self.set_font("Helvetica", "B", 10.5)
        self.set_text_color(30, 30, 30)
        self.multi_cell(0, 5, text)
        self._end_block()
        self.ln(1)

    def body(self, text: str) -> None:
        self.set_font("Helvetica", "", 9.5)
        self.set_text_color(30, 30, 30)
        self.multi_cell(0, 4.5, text)
        self._end_block()
        self.ln(1)

    def bullet(self, text: str) -> None:
        self.set_font("Helvetica", "", 9.5)
        self.set_text_color(30, 30, 30)
        self.multi_cell(0, 4.5, f"- {text}")
        self._end_block()

    def code(self, text: str) -> None:
        self.set_fill_color(245, 245, 245)
        self.set_font("Courier", "", 7.5)
        self.set_text_color(20, 20, 20)
        x = self.l_margin
        w = 210 - self.l_margin - self.r_margin
        for line in text.strip("\n").splitlines():
            if self.get_y() > 270:
                self.add_page()
            # escape is handled by fpdf for most; keep ASCII
            safe = line.replace("\t", "  ")
            self.set_x(x)
            self.cell(w, 4, safe[:115], ln=1, fill=True)
        self.ln(2)

    def table(self, headers: list[str], rows: list[list[str]], col_widths: list[float]) -> None:
        self.set_font("Helvetica", "B", 8.5)
        self.set_fill_color(230, 230, 230)
        for h, w in zip(headers, col_widths):
            self.cell(w, 6, h, border=1, fill=True)
        self.ln()
        self.set_font("Helvetica", "", 8)
        for row in rows:
            if self.get_y() > 270:
                self.add_page()
                self.set_font("Helvetica", "B", 8.5)
                for h, w in zip(headers, col_widths):
                    self.cell(w, 6, h, border=1, fill=True)
                self.ln()
                self.set_font("Helvetica", "", 8)
            for cell, w in zip(row, col_widths):
                self.cell(w, 5.5, cell[:40], border=1)
            self.ln()
        self.ln(2)


def build() -> Path:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    pdf = Doc(format="A4", unit="mm")
    pdf.alias_nb_pages()
    pdf.set_auto_page_break(auto=True, margin=15)
    pdf.set_margins(14, 14, 14)
    pdf.add_page()

    pdf.h1("High-Concurrency Booking Engine")
    pdf.set_font("Helvetica", "B", 11)
    pdf.multi_cell(0, 5, "Airtribe Backend - DB & System Design  |  P1 + P2 Submission")
    pdf.set_x(pdf.l_margin)
    pdf.set_font("Helvetica", "", 9.5)
    pdf.multi_cell(0, 5, "Author: Nagaraju S  |  Stack: MySQL 8 InnoDB  |  SQL files in /sql")
    pdf.set_x(pdf.l_margin)
    pdf.ln(2)

    pdf.h2("1. Scenario")
    pdf.body(
        "BookMyShow-style ticketing: for a theatre the app shows the next 7 dates. "
        "After picking a date, users see all movies and showtimes. Thousands of users "
        "may compete for the same seats. The schema must prevent double-booking, support "
        "timed holds that auto-release, and process payment webhooks idempotently."
    )

    pdf.h2("2. Entities and attributes (P1)")
    pdf.table(
        ["Entity", "Key attributes", "Role"],
        [
            ["city", "id, name, state", "Location"],
            ["theatre", "id, city_id, name, address", "Cinema complex"],
            ["screen", "id, theatre_id, name, seats", "Auditorium"],
            ["seat", "id, screen_id, row, number, type", "Physical layout"],
            ["movie", "id, title, language, duration", "Catalogue"],
            ["show", "id, movie_id, screen_id, date, times", "One screening"],
            ["user", "id, email, phone, full_name", "Booker"],
            ["show_seat", "show_id, seat_id, status, hold_*", "Inventory (core)"],
            ["booking", "user_id, show_id, status, hold_*", "Order"],
            ["booking_seat", "booking_id, show_seat_id, price", "Line items"],
            ["payment", "booking_id, provider, provider_id", "Payment"],
            ["payment_webhook_event", "provider, event_id UNIQUE", "Idempotency"],
        ],
        [38, 78, 50],
    )

    pdf.h3("Relationships (logical)")
    pdf.bullet("city 1-* theatre 1-* screen 1-* seat")
    pdf.bullet("movie 1-* show *-1 screen; show 1-* show_seat *-1 seat")
    pdf.bullet("user 1-* booking *-1 show; booking 1-* booking_seat *-1 show_seat")
    pdf.bullet("booking 1-* payment; payment 1-* payment_webhook_event")

    pdf.h2("3. Normalization (1NF, 2NF, 3NF, BCNF)")
    pdf.bullet("1NF: All attributes atomic - no comma-separated seats or nested showtimes.")
    pdf.bullet(
        "2NF: Non-key attributes depend on full primary key. Seat type depends on seat.id, "
        "not on a composite booking key."
    )
    pdf.bullet(
        "3NF: No transitive dependency - theatre gets city via city_id; movie title is not "
        "duplicated on show."
    )
    pdf.bullet(
        "BCNF: Every determinant is a candidate key. Examples: "
        "(screen_id, show_date, start_time) uniquely identifies a show; "
        "(show_id, seat_id) uniquely identifies inventory."
    )

    pdf.h2("4. Concurrency & locking (no double-book, no lost holds)")
    pdf.h3("4.1 Inventory table show_seat")
    pdf.body(
        "One row per (show_id, seat_id) with UNIQUE(show_id, seat_id). Status is "
        "AVAILABLE | HELD | BOOKED. This makes double-booking impossible at the DB layer."
    )
    pdf.h3("4.2 Redis timed holds (fast path)")
    pdf.code("SET seat:{showId}:{seatId} = {holdToken} NX EX 600")
    pdf.body(
        "NX ensures only one holder; EX auto-releases after TTL (e.g. 10 minutes). "
        "MySQL show_seat remains the source of truth; Redis is the speed layer."
    )
    pdf.h3("4.3 Pessimistic vs optimistic")
    pdf.bullet(
        "Pessimistic: SELECT ... FOR UPDATE on show_seat rows inside the hold/confirm "
        "transaction under high contention."
    )
    pdf.bullet(
        "Optimistic: version column - UPDATE ... WHERE version = ?; retry if affected_rows = 0."
    )
    pdf.h3("4.4 Auto-release worker")
    pdf.body(
        "A cron/queue job expires holds: set show_seat back to AVAILABLE when "
        "hold_expires_at < NOW(3), and mark booking EXPIRED."
    )
    pdf.h3("4.5 Idempotent payment webhooks")
    pdf.body(
        "INSERT into payment_webhook_event with UNIQUE(provider, event_id). Duplicate "
        "event_id => no-op (HTTP 200). First insert wins, then confirm seats HELD->BOOKED."
    )
    pdf.h3("4.6 Burst handling")
    pdf.bullet("Hold-release queue: expire holds without blocking the API.")
    pdf.bullet("Webhook consumer queue: absorb provider bursts; workers are idempotent.")

    pdf.add_page()
    pdf.h2("5. Table DDL (executable MySQL) - summary")
    pdf.body(
        "Full CREATE statements are in sql/01_schema.sql. Key constraints excerpt:"
    )
    pdf.code(
        """CREATE TABLE show_seat (
  id BIGINT UNSIGNED PK AI,
  show_id, seat_id,
  status ENUM('AVAILABLE','HELD','BOOKED'),
  hold_token CHAR(36) NULL,
  hold_expires_at DATETIME(3) NULL,
  version INT UNSIGNED NOT NULL DEFAULT 0,
  UNIQUE KEY uk_show_seat (show_id, seat_id)
);

CREATE TABLE payment_webhook_event (
  provider VARCHAR(40),
  event_id VARCHAR(100),
  UNIQUE KEY uk_webhook_event (provider, event_id)
);"""
    )

    pdf.h2("6. Sample entries (from sql/02_sample_data.sql)")
    pdf.table(
        ["Table", "Example row"],
        [
            ["city", "1 | Bengaluru | Karnataka"],
            ["theatre", "1 | PVR Orion Mall | city_id=1"],
            ["screen", "1 | Audi 1 | theatre_id=1"],
            ["movie", "1 | Kalki 2898 AD | Telugu | 181m"],
            ["show", "1 | movie=1 screen=1 | 2026-11-20 10:00 | 250"],
            ["show_seat", "show=1 seat=A1 | HELD (sample hold)"],
            ["booking", "id=1 user=1 status=HOLD amount=500"],
            ["payment", "RAZORPAY pay_ABC123XYZ SUCCESS"],
            ["webhook", "evt_payment_captured_001 (idempotent)"],
        ],
        [35, 131],
    )

    pdf.h2("7. P2 - Shows on a given date at a given theatre")
    pdf.body("Theatre id = 1 (PVR Orion Mall), date = 2026-11-20:")
    pdf.code(
        """SELECT
  t.name AS theatre_name,
  m.title AS movie_title,
  m.language,
  sc.name AS screen_name,
  s.show_date,
  s.start_time,
  s.end_time,
  s.base_price
FROM `show` s
JOIN screen sc  ON sc.id = s.screen_id
JOIN theatre t  ON t.id  = sc.theatre_id
JOIN movie m    ON m.id  = s.movie_id
WHERE t.id = 1
  AND s.show_date = '2026-11-20'
ORDER BY m.title, s.start_time;"""
    )

    pdf.h3("Expected result")
    pdf.table(
        ["Movie", "Screen", "Start", "End", "Price"],
        [
            ["Deadpool & Wolverine", "Audi 2", "11:30:00", "13:40:00", "350.00"],
            ["Deadpool & Wolverine", "Audi 2", "18:00:00", "20:10:00", "400.00"],
            ["Kalki 2898 AD", "Audi 1", "10:00:00", "13:05:00", "250.00"],
            ["Kalki 2898 AD", "Audi 1", "14:00:00", "17:05:00", "300.00"],
            ["Pushpa 2", "Audi 1", "20:30:00", "23:55:00", "280.00"],
        ],
        [50, 28, 28, 28, 32],
    )

    pdf.h2("8. How to run")
    pdf.code(
        """mysql -u root -p < sql/01_schema.sql
mysql -u root -p < sql/02_sample_data.sql
mysql -u root -p < sql/03_p2_query.sql"""
    )

    pdf.h2("9. Load-test sketch (engine phase)")
    pdf.bullet("Seed one show with N seats; spawn 2N users competing for hot seats.")
    pdf.bullet("Assert confirmed bookings <= N and zero duplicate (show_id, seat_id) BOOKED.")
    pdf.bullet("Replay same webhook event_id 100x -> booking confirmed exactly once.")

    pdf.h2("10. Repository files")
    pdf.bullet("sql/01_schema.sql - CREATE DATABASE + all tables")
    pdf.bullet("sql/02_sample_data.sql - sample rows")
    pdf.bullet("sql/03_p2_query.sql - P2 solution (+ UI-shaped GROUP_CONCAT variant)")
    pdf.bullet("sql/04_concurrency_patterns.sql - hold / expire / webhook SQL")
    pdf.bullet("docs/DESIGN.md - full design write-up")

    pdf.output(str(OUT))
    return OUT


if __name__ == "__main__":
    path = build()
    print(f"Wrote {path}")
