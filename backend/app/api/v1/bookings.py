"""Réservations (§3.3) : création, agenda, machine à états, clôture de prestation."""
from datetime import date

from beanie import PydanticObjectId
from fastapi import APIRouter, Depends, HTTPException, Query, status
from pymongo.errors import DuplicateKeyError

from app.core.deps import assert_salon_access, get_salon
from app.core.security import current_user
from app.core.timeutils import local_day_bounds, to_local, utcnow
from app.models.documents import (
    Booking,
    Salon,
    Service,
    StaffMember,
    Transaction,
    User,
)
from app.models.enums import (
    ACTIVE_BOOKING_STATUSES,
    BookingSource,
    BookingStatus,
    NotificationType,
    PaymentStatus,
    Role,
)
from app.schemas.booking import BookingComplete, BookingCreate, BookingStatusPatch
from app.services.booking_service import (
    apply_transition,
    assert_can_cancel,
    available_slots,
    create_booking,
)
from app.services.notification_service import notify, notify_many
from app.services.split_engine import SplitEngine

router = APIRouter()


async def _load_booking(booking_id: PydanticObjectId) -> Booking:
    booking = await Booking.get(booking_id)
    if not booking:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "RDV introuvable")
    return booking


async def _assert_can_act(booking: Booking, user: User) -> Salon:
    """Le client propriétaire du RDV, le gérant du salon ou un membre de l'équipe."""
    if booking.client_id == user.id:
        return await get_salon(booking.salon_id)
    return await assert_salon_access(booking.salon_id, user)


async def _pick_any_staff(
    salon: Salon, service_ids: list[PydanticObjectId], start
) -> StaffMember:
    """Option « peu importe » : premier coiffeur réellement libre sur ce créneau."""
    day = to_local(start).date()
    members = await StaffMember.find(
        StaffMember.salon_id == salon.id, StaffMember.available == True  # noqa: E712
    ).to_list()
    wanted = start.isoformat()
    for member in members:
        result = await available_slots(
            staff=member, salon=salon, day=day, service_ids=service_ids
        )
        if any(s["start"] == wanted for s in result["slots"]):
            return member
    raise HTTPException(
        status.HTTP_409_CONFLICT, "Aucun coiffeur disponible sur ce créneau"
    )


@router.post("", status_code=201, summary="Créer un RDV (app ou walk-in)")
async def book(body: BookingCreate, user: User = Depends(current_user)):
    salon = await get_salon(body.salon_id)

    if body.source is BookingSource.WALKIN:
        # Un walk-in n'est saisi que depuis l'app pro, pour garder la caisse exacte.
        await assert_salon_access(salon.id, user)
        client_id = None
    else:
        client_id = user.id

    if body.staff_id is None:
        staff = await _pick_any_staff(salon, body.service_ids, body.start)
    else:
        staff = await StaffMember.get(body.staff_id)
        if not staff:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Coiffeur introuvable")

    booking = await create_booking(
        salon=salon,
        staff=staff,
        client_id=client_id,
        service_ids=body.service_ids,
        start=body.start,
        source=body.source,
        client_name=body.client_name,
        client_phone=body.client_phone,
        note=body.note,
    )

    when = to_local(booking.start).strftime("%d/%m à %H:%M")
    qui = booking.client_name or user.name or "Un client"

    # Le coiffeur concerné et le gérant du salon. `notify_many` déduplique :
    # quand le patron coupe lui-même, il ne reçoit pas deux fois la même chose.
    await notify_many(
        [staff.user_id, salon.owner_id],
        NotificationType.BOOKING_CONFIRMED,
        "Nouveau rendez-vous",
        f"{qui} — {when} avec {staff.display_name or 'votre équipe'}",
        {"booking_id": str(booking.id), "salon_id": str(salon.id)},
    )
    return booking


@router.get("/me", summary="Mes réservations (client)")
async def my_bookings(
    upcoming: bool | None = None, user: User = Depends(current_user)
):
    query: dict = {"client_id": user.id}
    if upcoming is True:
        query["start"] = {"$gte": utcnow()}
        query["status"] = {"$in": ACTIVE_BOOKING_STATUSES}
    elif upcoming is False:
        query["status"] = {
            "$in": [BookingStatus.DONE, BookingStatus.CANCELLED, BookingStatus.NO_SHOW]
        }
    return await Booking.find(query).sort("-start").to_list()


@router.get("/salon/{salon_id}", summary="Agenda du jour d'un salon (gérant/staff)")
async def salon_agenda(
    salon_id: PydanticObjectId,
    day: date | None = Query(None, alias="date"),
    staff_id: PydanticObjectId | None = None,
    user: User = Depends(current_user),
):
    await assert_salon_access(salon_id, user)
    target = day or to_local(utcnow()).date()
    start, end = local_day_bounds(target)

    query: dict = {"salon_id": salon_id, "start": {"$gte": start, "$lt": end}}
    if user.role is Role.STAFF:
        # Un coiffeur ne voit que sa propre colonne d'agenda.
        member = await StaffMember.find_one(
            StaffMember.salon_id == salon_id, StaffMember.user_id == user.id
        )
        query["staff_id"] = member.id
    elif staff_id:
        query["staff_id"] = staff_id

    bookings = await Booking.find(query).sort("+start").to_list()
    return {
        "date": str(target),
        "count": len(bookings),
        "revenue_expected": round(
            sum(b.price_total for b in bookings if b.status is not BookingStatus.CANCELLED), 2
        ),
        "bookings": bookings,
    }


@router.get("/{booking_id}", summary="Détail d'un RDV")
async def booking_detail(booking_id: PydanticObjectId, user: User = Depends(current_user)):
    booking = await _load_booking(booking_id)
    await _assert_can_act(booking, user)
    return booking


@router.patch("/{booking_id}", summary="Changer le statut d'un RDV")
async def patch_status(
    booking_id: PydanticObjectId,
    body: BookingStatusPatch,
    user: User = Depends(current_user),
):
    """Applique la machine à états §5.5 ; `DONE` passe obligatoirement par /complete."""
    booking = await _load_booking(booking_id)
    salon = await _assert_can_act(booking, user)

    if body.status is BookingStatus.DONE:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            "Utilisez POST /bookings/{id}/complete pour terminer une prestation",
        )
    if body.status is BookingStatus.CANCELLED:
        await assert_can_cancel(booking, salon, user)
    if body.status in (BookingStatus.IN_PROGRESS, BookingStatus.NO_SHOW) and user.role is Role.CLIENT:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Réservé au salon")

    previous = booking.status
    booking = await apply_transition(booking, body.status, user, body.reason)

    if body.status is BookingStatus.CANCELLED and booking.client_id:
        await notify(
            booking.client_id,
            NotificationType.BOOKING_CANCELLED,
            "Rendez-vous annulé",
            f"Votre RDV du {to_local(booking.start).strftime('%d/%m à %H:%M')} a été annulé.",
            {"booking_id": str(booking.id)},
        )
    elif body.status is BookingStatus.CONFIRMED and previous is BookingStatus.PENDING:
        if booking.client_id:
            await notify(
                booking.client_id,
                NotificationType.BOOKING_CONFIRMED,
                "RDV confirmé",
                f"C'est confirmé pour le {to_local(booking.start).strftime('%d/%m à %H:%M')}.",
                {"booking_id": str(booking.id)},
            )
    return booking


@router.post("/{booking_id}/complete", summary="Terminer la prestation et encaisser")
async def complete(
    booking_id: PydanticObjectId,
    body: BookingComplete,
    user: User = Depends(current_user),
):
    """Crée la Transaction et son split (§3.4).

    La commission appliquée est TOUJOURS celle du coiffeur qui a exécuté le RDV,
    même si c'est le gérant qui encaisse depuis son téléphone.
    """
    booking = await _load_booking(booking_id)
    await assert_salon_access(booking.salon_id, user)
    if user.role is Role.CLIENT:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Réservé au staff/gérant")

    if booking.status is BookingStatus.DONE:
        raise HTTPException(status.HTTP_409_CONFLICT, "Prestation déjà encaissée")
    if booking.status is BookingStatus.CONFIRMED:
        booking = await apply_transition(booking, BookingStatus.IN_PROGRESS, user)
    if booking.status is not BookingStatus.IN_PROGRESS:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            f"Impossible d'encaisser un RDV au statut {booking.status}",
        )

    staff = await StaffMember.get(booking.staff_id)
    if not staff:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Coiffeur du RDV introuvable")

    amount = body.amount_override if body.amount_override is not None else booking.price_total

    # La règle appliquée est celle du salon, ajustée pour ce coiffeur puis pour
    # cette prestation : c'est là que chaque salon retrouve son organisation.
    # Sur un RDV multi-services, le premier porte le taux — les prestations
    # d'un même rendez-vous relèvent presque toujours de la même entente.
    salon = await Salon.get(booking.salon_id)
    service = (
        await Service.get(booking.service_ids[0]) if booking.service_ids else None
    )
    split = SplitEngine.for_staff(
        amount, staff, tip=body.tip, service=service, salon=salon
    )

    tx = Transaction(
        booking_id=booking.id,
        salon_id=booking.salon_id,
        staff_id=booking.staff_id,
        amount=split.amount,
        method=body.method,
        salon_share=split.salon_share,
        staff_share=split.staff_share,
        tip=split.tip,
        salon_tip=split.salon_tip,
    )
    try:
        await tx.insert()
    except DuplicateKeyError:
        raise HTTPException(status.HTTP_409_CONFLICT, "Prestation déjà encaissée")

    booking = await apply_transition(booking, BookingStatus.DONE, user)
    if body.amount_override is not None:
        booking.note = (
            f"{booking.note} | montant ajusté: {body.override_reason}".strip(" |")
        )
    booking.payment_status = PaymentStatus.PAID
    await booking.save()

    staff.cuts_count += 1
    await staff.save()

    return {
        "booking": booking,
        "transaction": tx,
        "split": {
            "amount": split.amount,
            "salon_share": split.salon_share,
            "staff_share": split.staff_share,
            "tip": split.tip,
            "staff_payout": split.staff_payout,
            # Exposés pour que l'employé comprenne sa part : sans le coût du
            # produit, « 15,75 sur 60 DT » paraît arbitraire.
            "product_cost": split.product_cost,
            "salon_tip": split.salon_tip,
        },
    }
