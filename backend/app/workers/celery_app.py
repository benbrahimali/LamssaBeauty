"""Worker Celery (§4.2) — rappels, hygiène des RDV, rapports."""
import asyncio

from celery import Celery
from celery.schedules import crontab

from app.core.config import settings

celery_app = Celery("lamssa", broker=settings.REDIS_URI, backend=settings.REDIS_URI)
celery_app.conf.update(
    task_serializer="json",
    result_serializer="json",
    accept_content=["json"],
    timezone=settings.TIMEZONE,
    enable_utc=True,
    beat_schedule={
        "rappels-rdv": {
            "task": "lamssa.send_reminders",
            "schedule": crontab(minute="*/10"),
        },
        "expiration-pending": {
            "task": "lamssa.expire_pending",
            "schedule": crontab(minute="*/5"),
        },
        "no-shows": {
            "task": "lamssa.mark_no_shows",
            "schedule": crontab(minute="*/15"),
        },
        "rappel-cloture": {
            "task": "lamssa.closure_reminder",
            "schedule": crontab(hour=21, minute=0),
        },
    },
)

_loop: asyncio.AbstractEventLoop | None = None
_ready = False


def run_async(coro):
    """Exécute une coroutine dans le worker, en initialisant Beanie une seule fois."""
    global _loop, _ready
    if _loop is None:
        _loop = asyncio.new_event_loop()
        asyncio.set_event_loop(_loop)
    if not _ready:
        from app.core.db import init_db

        _loop.run_until_complete(init_db())
        _ready = True
    return _loop.run_until_complete(coro)
