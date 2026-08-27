"""Tâches asynchrones : rappels J-1 / H-2, expiration des PENDING, no-shows, clôture."""
import logging
from datetime import timedelta

from app.core.config import settings
from app.core.timeutils import local_day_bounds, to_local, utcnow
from app.models.documents import Booking, CashClosure, Salon, StaffMember, User
from app.models.enums import BookingStatus, NotificationType, PaymentStatus, SalonStatus
from app.services.notification_service import notify, send_sms
from app.workers.celery_app import celery_app, run_async

log = logging.getLogger("lamssa.worker")


# ─────────────────────────────────────────────────────────────────────────────
# Rappels (§3.3)
# ─────────────────────────────────────────────────────────────────────────────
async def _send_reminders() -> dict:
    now = utcnow()
    sent = {"j1": 0, "h2": 0}

    async def _remind(booking: Booking, kind: str, title: str, sms: bool) -> None:
        when = to_local(booking.start).strftime("%d/%m à %H:%M")
        salon = await Salon.get(booking.salon_id)
        body = f"{salon.name if salon else 'Votre salon'} — {when}."
        if booking.client_id:
            await notify(
                booking.client_id,
                NotificationType.REMINDER_J1 if kind == "j1" else NotificationType.REMINDER_H2,
                title,
                body,
                {"booking_id": str(booking.id)},
            )
        if sms:
            phone = booking.client_phone
            if not phone and booking.client_id:
                client = await User.get(booking.client_id)
                phone = client.phone if client else ""
            if phone:
                await send_sms(phone, f"LAMSSA — {title}. {body}")

    # J-1 : fenêtre 23 h à 25 h avant le RDV
    j1 = await Booking.find(
        Booking.status == BookingStatus.CONFIRMED,
        Booking.reminder_j1_sent == False,  # noqa: E712
        Booking.start >= now + timedelta(hours=23),
        Booking.start <= now + timedelta(hours=25),
    ).to_list()
    for booking in j1:
        await _remind(booking, "j1", "Rappel : RDV demain", sms=False)
        booking.reminder_j1_sent = True
        await booking.save()
        sent["j1"] += 1

    # H-2 : rappel court, doublé d'un SMS car c'est le moment critique du no-show
    h2 = await Booking.find(
        Booking.status == BookingStatus.CONFIRMED,
        Booking.reminder_h2_sent == False,  # noqa: E712
        Booking.start >= now + timedelta(hours=1, minutes=30),
        Booking.start <= now + timedelta(hours=2, minutes=30),
    ).to_list()
    for booking in h2:
        await _remind(booking, "h2", "C'est bientôt ton tour", sms=True)
        booking.reminder_h2_sent = True
        await booking.save()
        sent["h2"] += 1

    return sent


@celery_app.task(name="lamssa.send_reminders")
def send_reminders():
    result = run_async(_send_reminders())
    log.info("Rappels envoyés: %s", result)
    return result


# ─────────────────────────────────────────────────────────────────────────────
# Hygiène des RDV (§5.5)
# ─────────────────────────────────────────────────────────────────────────────
async def _expire_pending() -> int:
    """Un PENDING non payé libère son créneau après PENDING_TIMEOUT_MIN."""
    cutoff = utcnow() - timedelta(minutes=settings.PENDING_TIMEOUT_MIN)
    stale = await Booking.find(
        Booking.status == BookingStatus.PENDING,
        Booking.created_at <= cutoff,
        {"payment_status": {"$ne": PaymentStatus.PAID.value}},
    ).to_list()
    for booking in stale:
        booking.status = BookingStatus.CANCELLED
        booking.cancel_reason = "Expiré : non confirmé dans les délais"
        booking.updated_at = utcnow()
        await booking.save()
        if booking.client_id:
            await notify(
                booking.client_id,
                NotificationType.BOOKING_CANCELLED,
                "Réservation expirée",
                "Votre créneau a été libéré faute de confirmation.",
                {"booking_id": str(booking.id)},
            )
    return len(stale)


@celery_app.task(name="lamssa.expire_pending")
def expire_pending():
    count = run_async(_expire_pending())
    log.info("%d RDV PENDING expirés", count)
    return count


async def _mark_no_shows() -> int:
    cutoff = utcnow() - timedelta(minutes=settings.NO_SHOW_GRACE_MIN)
    missed = await Booking.find(
        Booking.status == BookingStatus.CONFIRMED, Booking.start <= cutoff
    ).to_list()
    for booking in missed:
        booking.status = BookingStatus.NO_SHOW
        booking.updated_at = utcnow()
        await booking.save()
    return len(missed)


@celery_app.task(name="lamssa.mark_no_shows")
def mark_no_shows():
    count = run_async(_mark_no_shows())
    log.info("%d RDV marqués NO_SHOW", count)
    return count


# ─────────────────────────────────────────────────────────────────────────────
# Rappel de clôture (§3.4)
# ─────────────────────────────────────────────────────────────────────────────
async def _closure_reminder() -> int:
    today = to_local(utcnow()).date()
    start, end = local_day_bounds(today)
    reminded = 0
    salons = await Salon.find(Salon.status == SalonStatus.OPEN).to_list()
    for salon in salons:
        if await CashClosure.find_one(
            CashClosure.salon_id == salon.id, CashClosure.day == today
        ):
            continue
        done = await Booking.find(
            Booking.salon_id == salon.id,
            Booking.status == BookingStatus.DONE,
            Booking.start >= start,
            Booking.start < end,
        ).count()
        if not done:
            continue
        await notify(
            salon.owner_id,
            NotificationType.CLOSURE_READY,
            "Clôture en attente",
            f"{salon.name} : {done} prestation(s) aujourd'hui, la journée n'est pas clôturée.",
            {"salon_id": str(salon.id)},
        )
        reminded += 1
    return reminded


@celery_app.task(name="lamssa.closure_reminder")
def closure_reminder():
    count = run_async(_closure_reminder())
    log.info("%d gérants relancés pour la clôture", count)
    return count


@celery_app.task(name="lamssa.notify_followers_portfolio")
def notify_followers_portfolio(staff_id: str, caption: str):
    """Prévient les clients d'un coiffeur qu'il vient de publier (§3.7)."""

    async def _run() -> int:
        from beanie import PydanticObjectId

        staff = await StaffMember.get(PydanticObjectId(staff_id))
        if not staff:
            return 0
        clients = await Booking.find(
            Booking.staff_id == staff.id, Booking.status == BookingStatus.DONE
        ).to_list()
        audience = {b.client_id for b in clients if b.client_id}
        for client_id in audience:
            await notify(
                client_id,
                NotificationType.NEW_PORTFOLIO,
                f"{staff.display_name} vient de publier",
                caption[:120] or "Découvrez sa dernière réalisation.",
                {"staff_id": staff_id},
            )
        return len(audience)

    return run_async(_run())
