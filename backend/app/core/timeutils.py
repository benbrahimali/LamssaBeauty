"""Helpers date/heure. Règle : on stocke en UTC, on raisonne métier en heure locale salon."""
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

from app.core.config import settings

TZ = ZoneInfo(settings.TIMEZONE)

WEEKDAY_KEYS = ("mon", "tue", "wed", "thu", "fri", "sat", "sun")


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def as_utc(dt: datetime) -> datetime:
    """Normalise en UTC ; un datetime naïf est considéré comme déjà UTC."""
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def to_local(dt: datetime, tz: ZoneInfo = TZ) -> datetime:
    return as_utc(dt).astimezone(tz)


def day_key(d: date) -> str:
    """Clé d'horaires ('mon'..'sun') correspondant au jour donné."""
    return WEEKDAY_KEYS[d.weekday()]


def local_day_bounds(d: date, tz: ZoneInfo = TZ) -> tuple[datetime, datetime]:
    """Bornes UTC du jour local `d` — indispensable pour la caisse du jour."""
    start = datetime.combine(d, time.min, tzinfo=tz)
    end = start + timedelta(days=1)
    return start.astimezone(timezone.utc), end.astimezone(timezone.utc)


def local_month_bounds(year: int, month: int, tz: ZoneInfo = TZ) -> tuple[datetime, datetime]:
    start = datetime(year, month, 1, tzinfo=tz)
    end = datetime(year + (month == 12), (month % 12) + 1, 1, tzinfo=tz)
    return start.astimezone(timezone.utc), end.astimezone(timezone.utc)


def local_week_bounds(d: date, tz: ZoneInfo = TZ) -> tuple[datetime, datetime]:
    """Bornes UTC de la semaine locale contenant `d`, du lundi au dimanche.

    Le lundi comme premier jour n'est pas un détail : les salons tunisiens
    paient leurs employés en fin de semaine, et une semaine qui commencerait le
    dimanche couperait le samedi — leur plus grosse journée — en deux paies.
    """
    monday = d - timedelta(days=d.weekday())
    start = datetime.combine(monday, time.min, tzinfo=tz)
    end = start + timedelta(days=7)
    return start.astimezone(timezone.utc), end.astimezone(timezone.utc)


def parse_hhmm(value: str) -> time:
    hour, minute = value.split(":")
    return time(int(hour), int(minute))


def combine_local(d: date, hhmm: str, tz: ZoneInfo = TZ) -> datetime:
    """Construit un instant UTC à partir d'un jour et d'une heure locale 'HH:MM'."""
    return datetime.combine(d, parse_hhmm(hhmm), tzinfo=tz).astimezone(timezone.utc)
