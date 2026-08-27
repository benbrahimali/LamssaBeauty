"""Logique métier réservation : durées, créneaux, verrou anti-conflit, machine à états."""
from datetime import date, datetime, timedelta

from beanie import PydanticObjectId
from fastapi import HTTPException, status

from app.core.config import settings
from app.core.db import redis
from app.core.timeutils import as_utc, day_key, local_day_bounds, to_local, utcnow
from app.models.documents import (
    Booking,
    DEFAULT_HOURS,
    DayHours,
    Salon,
    Service,
    StaffMember,
    TimeOff,
    User,
)
from app.models.enums import (
    ACTIVE_BOOKING_STATUSES,
    BOOKING_TRANSITIONS,
    BookingSource,
    BookingStatus,
    Role,
    SalonStatus,
)
from app.services.availability import Interval, free_slots, slot_is_free


# ─────────────────────────────────────────────────────────────────────────────
# Services & durées
# ─────────────────────────────────────────────────────────────────────────────
async def resolve_services(
    salon_id: PydanticObjectId, service_ids: list[PydanticObjectId]
) -> list[Service]:
    """Charge les services demandés en vérifiant qu'ils appartiennent bien au salon."""
    if not service_ids:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Aucun service sélectionné")
    services = await Service.find({"_id": {"$in": service_ids}}).to_list()
    found = {s.id for s in services}
    if len(found) != len(set(service_ids)):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Service introuvable")
    for s in services:
        if s.salon_id != salon_id:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST, f"Le service « {s.name} » n'est pas de ce salon"
            )
        if not s.active:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST, f"Le service « {s.name} » n'est plus proposé"
            )
    return services


def total_duration(services: list[Service]) -> int:
    """Durée bloquée dans l'agenda : somme des durées + buffers (§3.3)."""
    return sum(s.duration_min + s.buffer_min for s in services)


def total_price(services: list[Service]) -> float:
    return round(sum(s.price for s in services), 2)


# ─────────────────────────────────────────────────────────────────────────────
# Disponibilités
# ─────────────────────────────────────────────────────────────────────────────
def salon_day_hours(salon: Salon, day: date) -> DayHours:
    return salon.hours.get(day_key(day)) or DEFAULT_HOURS[day_key(day)]


async def busy_intervals(
    staff_id: PydanticObjectId, window_start: datetime, window_end: datetime
) -> list[Interval]:
    """RDV actifs + congés du coiffeur sur la fenêtre — tout ce qui bloque un créneau."""
    bookings = await Booking.find(
        Booking.staff_id == staff_id,
        {"status": {"$in": ACTIVE_BOOKING_STATUSES}},
        Booking.start < window_end,
        Booking.end > window_start,
    ).to_list()
    time_off = await TimeOff.find(
        TimeOff.staff_id == staff_id,
        TimeOff.start < window_end,
        TimeOff.end > window_start,
    ).to_list()
    return [Interval(as_utc(b.start), as_utc(b.end)) for b in bookings] + [
        Interval(as_utc(t.start), as_utc(t.end)) for t in time_off
    ]


async def available_slots(
    *,
    staff: StaffMember,
    salon: Salon,
    day: date,
    service_ids: list[PydanticObjectId] | None = None,
) -> dict:
    """Créneaux libres d'un coiffeur pour un jour donné (§6 GET /staff/{id}/slots)."""
    if not staff.available or salon.status is SalonStatus.CLOSED:
        return {"date": str(day), "duration_min": 0, "slots": []}

    if service_ids:
        services = await resolve_services(salon.id, service_ids)
        _assert_staff_can_perform(staff, service_ids)
        duration = total_duration(services)
    else:
        # Sans service précisé, on montre la grille sur la plus courte prestation.
        catalogue = await Service.find(
            Service.salon_id == salon.id, Service.active == True  # noqa: E712
        ).to_list()
        if not catalogue:
            return {"date": str(day), "duration_min": 0, "slots": []}
        duration = min(s.duration_min + s.buffer_min for s in catalogue)

    start_bound, end_bound = local_day_bounds(day)
    busy = await busy_intervals(staff.id, start_bound, end_bound)
    slots = free_slots(
        day=day,
        hours=salon_day_hours(salon, day),
        busy=busy,
        duration_min=duration,
        step_min=settings.SLOT_STEP_MIN,
        now=utcnow(),
    )
    return {
        "date": str(day),
        "duration_min": duration,
        "slots": [
            {"time": to_local(s).strftime("%H:%M"), "start": s.isoformat()} for s in slots
        ],
    }


def _assert_staff_can_perform(staff: StaffMember, service_ids: list[PydanticObjectId]) -> None:
    """Un coiffeur n'exécute que les services que le gérant lui a autorisés (§3.5)."""
    if not staff.service_ids:
        return  # liste vide = polyvalent
    unauthorized = set(service_ids) - set(staff.service_ids)
    if unauthorized:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            "Ce coiffeur ne réalise pas l'un des services demandés",
        )


async def suggest_alternatives(
    staff: StaffMember, salon: Salon, around: datetime, service_ids: list[PydanticObjectId]
) -> list[str]:
    """Créneaux de repli renvoyés avec un 409 (§5.3)."""
    day = to_local(around).date()
    result = await available_slots(
        staff=staff, salon=salon, day=day, service_ids=service_ids
    )
    return [s["start"] for s in result["slots"]][:6]


# ─────────────────────────────────────────────────────────────────────────────
# Création
# ─────────────────────────────────────────────────────────────────────────────
async def create_booking(
    *,
    salon: Salon,
    staff: StaffMember,
    client_id: PydanticObjectId | None,
    service_ids: list[PydanticObjectId],
    start: datetime,
    source: BookingSource = BookingSource.APP,
    client_name: str = "",
    client_phone: str = "",
    note: str = "",
) -> Booking:
    """Crée un RDV en garantissant l'absence de double réservation.

    Verrou Redis `SETNX` (course entre requêtes concurrentes) + re-vérification en base
    à l'intérieur du verrou (source de vérité), comme spécifié §4.3.
    """
    start = as_utc(start)
    # Un walk-in décrit un client déjà sur place : il peut donc être saisi en cours de
    # prestation et hors des horaires affichés (ouverture anticipée, service tardif).
    # Le refuser fausserait la caisse, ce que le walk-in existe précisément pour éviter.
    is_walkin = source is BookingSource.WALKIN

    if staff.salon_id != salon.id:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Ce coiffeur n'est pas de ce salon")
    if not staff.available and not is_walkin:
        raise HTTPException(status.HTTP_409_CONFLICT, "Ce coiffeur est indisponible")
    if salon.status is SalonStatus.CLOSED and not is_walkin:
        raise HTTPException(status.HTTP_409_CONFLICT, "Ce salon est actuellement fermé")
    if start <= utcnow() and not is_walkin:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Créneau dans le passé")

    services = await resolve_services(salon.id, service_ids)
    _assert_staff_can_perform(staff, service_ids)
    duration = total_duration(services)
    end = start + timedelta(minutes=duration)

    lock_key = f"lock:staff:{staff.id}:{start.isoformat()}"
    if not await redis.set(lock_key, "1", nx=True, ex=settings.SLOT_LOCK_TTL_SEC):
        raise HTTPException(
            status.HTTP_409_CONFLICT, "Créneau en cours de réservation, réessayez"
        )
    try:
        busy = await busy_intervals(staff.id, start - timedelta(hours=12), end + timedelta(hours=12))
        if is_walkin:
            # Hors horaires toléré, mais jamais deux clients sur la même chaise.
            free = not any(b.overlaps(start, end) for b in busy)
        else:
            free = slot_is_free(
                start=start,
                duration_min=duration,
                day_hours=salon_day_hours(salon, to_local(start).date()),
                busy=busy,
            )
        if not free:
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                {
                    "message": "Créneau indisponible",
                    "alternatives": await suggest_alternatives(
                        staff, salon, start, service_ids
                    ),
                },
            )

        booking = Booking(
            salon_id=salon.id,
            staff_id=staff.id,
            client_id=client_id,
            service_ids=service_ids,
            service_names=[s.name for s in services],
            price_total=total_price(services),
            start=start,
            end=end,
            source=source,
            client_name=client_name,
            client_phone=client_phone,
            note=note,
            # Un walk-in est déjà « en salon » : il est confirmé d'office.
            status=BookingStatus.CONFIRMED
            if source is BookingSource.WALKIN
            else BookingStatus.PENDING,
        )
        await booking.insert()
        return booking
    finally:
        await redis.delete(lock_key)


# ─────────────────────────────────────────────────────────────────────────────
# Transitions d'état (§5.5)
# ─────────────────────────────────────────────────────────────────────────────
def assert_transition(current: BookingStatus, target: BookingStatus) -> None:
    if target not in BOOKING_TRANSITIONS[current]:
        raise HTTPException(
            status.HTTP_409_CONFLICT, f"Transition {current} → {target} interdite"
        )


async def apply_transition(
    booking: Booking, target: BookingStatus, actor: User | None = None, reason: str = ""
) -> Booking:
    """`actor` est None pour les transitions déclenchées par le système (webhook, worker)."""
    assert_transition(booking.status, target)
    if target is BookingStatus.CANCELLED:
        booking.cancelled_by = actor.id if actor else None
        booking.cancel_reason = reason
    booking.status = target
    booking.updated_at = utcnow()
    await booking.save()
    return booking


async def assert_can_cancel(booking: Booking, salon: Salon, actor: User) -> None:
    """Le client respecte la fenêtre d'annulation du salon ; le pro peut toujours annuler."""
    if actor.role in (Role.OWNER, Role.STAFF):
        return
    window = timedelta(hours=salon.cancellation_window_h or settings.DEFAULT_CANCEL_WINDOW_H)
    if as_utc(booking.start) - utcnow() < window:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            f"Annulation impossible à moins de {salon.cancellation_window_h} h du RDV — "
            "contactez le salon",
        )
