"""Moteur de créneaux (§3.3) — cœur pur, sans I/O, donc testable unitairement."""
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from app.core.timeutils import TZ, as_utc, combine_local
from app.models.documents import DayHours


@dataclass(frozen=True)
class Interval:
    start: datetime
    end: datetime

    def overlaps(self, other_start: datetime, other_end: datetime) -> bool:
        return self.start < other_end and self.end > other_start


def working_windows(
    day: date, hours: DayHours, tz: ZoneInfo = TZ
) -> list[Interval]:
    """Plages travaillées du jour, pause déjeuner déduite."""
    if hours.closed:
        return []
    opening = combine_local(day, hours.open, tz)
    closing = combine_local(day, hours.close, tz)
    if closing <= opening:  # horaires incohérents => jour non travaillé
        return []

    if hours.break_start and hours.break_end:
        pause_start = combine_local(day, hours.break_start, tz)
        pause_end = combine_local(day, hours.break_end, tz)
        if opening < pause_start and pause_end < closing:
            return [Interval(opening, pause_start), Interval(pause_end, closing)]
    return [Interval(opening, closing)]


def free_slots(
    *,
    day: date,
    hours: DayHours,
    busy: list[Interval],
    duration_min: int,
    step_min: int = 15,
    tz: ZoneInfo = TZ,
    now: datetime | None = None,
    min_lead_min: int = 0,
) -> list[datetime]:
    """Créneaux de départ possibles pour une prestation de `duration_min` minutes.

    Un créneau est retenu si la prestation entière (durée + buffer déjà inclus dans
    `duration_min`) tient dans une plage travaillée et ne chevauche aucun RDV ni congé.
    Les créneaux passés — ou trop proches selon `min_lead_min` — sont écartés.
    """
    if duration_min <= 0:
        raise ValueError("La durée doit être strictement positive")

    now = as_utc(now or datetime.now(timezone.utc))
    earliest = now + timedelta(minutes=min_lead_min)
    step = timedelta(minutes=step_min)
    duration = timedelta(minutes=duration_min)

    slots: list[datetime] = []
    for window in working_windows(day, hours, tz):
        cursor = window.start
        while cursor + duration <= window.end:
            slot_end = cursor + duration
            if cursor >= earliest and not any(b.overlaps(cursor, slot_end) for b in busy):
                slots.append(cursor)
            cursor += step
    return slots


def slot_is_free(
    *,
    start: datetime,
    duration_min: int,
    day_hours: DayHours,
    busy: list[Interval],
    tz: ZoneInfo = TZ,
) -> bool:
    """Vérifie qu'un créneau précis est dans les horaires et libre de tout conflit."""
    start = as_utc(start)
    end = start + timedelta(minutes=duration_min)
    local_day = start.astimezone(tz).date()
    windows = working_windows(local_day, day_hours, tz)
    inside = any(w.start <= start and end <= w.end for w in windows)
    return inside and not any(b.overlaps(start, end) for b in busy)
