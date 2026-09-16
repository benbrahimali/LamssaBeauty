"""Réservations (§3.3) : création, agenda, machine à états, clôture de prestation."""
from datetime import date

from beanie import PydanticObjectId
from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.encoders import jsonable_encoder
from pymongo.errors import DuplicateKeyError

from app.core.deps import assert_salon_access, get_salon
from app.core.security import current_user
from app.core.timeutils import local_day_bounds, to_local, utcnow
from app.models.documents import (
    Booking,
    CashClosure,
    Review,
    Salon,
    Service,
    StaffMember,
    Transaction,
    User,
    VoidedTransaction,
    salon_is_public,
)
from app.models.enums import (
    ACTIVE_BOOKING_STATUSES,
    BookingSource,
    BookingStatus,
    NotificationType,
    PaymentMethod,
    PaymentStatus,
    Role,
)
from app.schemas.booking import (
    BookingComplete,
    BookingCreate,
    BookingStatusPatch,
    PaymentVoid,
)
from app.services.booking_service import (
    apply_transition,
    assert_can_cancel,
    available_slots,
    create_booking,
)
from app.services.notification_service import notify, notify_many
from app.services.split_engine import SplitEngine

router = APIRouter()


def mark_reviewed(bookings: list[dict], reviewed_ids: set[str]) -> list[dict]:
    """Ajoute à chaque RDV s'il a déjà reçu l'avis du client.

    Sans ce drapeau, l'app ne le retenait qu'en mémoire : après un redémarrage
    le bouton « قيّم » revenait, et le serveur refusait le second avis.
    """
    return [{**b, "reviewed": str(b.get("id") or b.get("_id")) in reviewed_ids} for b in bookings]


def void_refusal(*, day_closed: bool, method: PaymentMethod) -> str | None:
    """Pourquoi un encaissement ne peut pas être annulé — None s'il le peut."""
    if day_closed:
        # Le rapport de clôture est une pièce comptable : le modifier après
        # coup rendrait faux un document déjà remis.
        return "La journée est clôturée : cet encaissement est figé dans le rapport."
    if method is PaymentMethod.ONLINE:
        # L'argent est chez le prestataire de paiement : l'effacer ici sans
        # rembourser le client laisserait les deux côtés en désaccord.
        return "Paiement en ligne : remboursez-le au lieu d'annuler l'encaissement."
    return None


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

    # Un salon non vérifié ne prend pas de réservation en ligne. Le walk-in
    # reste possible : il est saisi par le salon lui-même, qui peut déjà
    # recevoir des clients en vrai.
    if body.source is not BookingSource.WALKIN and not salon_is_public(
        salon.verification_status
    ):
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            "Ce salon n'est pas encore ouvert aux réservations en ligne.",
        )

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
    rdvs = await Booking.find(query).sort("-start").to_list()
    avis = await Review.find(
        {"booking_id": {"$in": [b.id for b in rdvs if b.status is BookingStatus.DONE]}}
    ).to_list()
    return mark_reviewed(jsonable_encoder(rdvs), {str(a.booking_id) for a in avis})


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


@router.post("/{booking_id}/void-payment", summary="Annuler un encaissement erroné")
async def void_payment(
    booking_id: PydanticObjectId,
    body: PaymentVoid,
    user: User = Depends(current_user),
):
    """Retire un encaissement mal saisi pour le refaire au bon montant.

    Réservé au gérant du salon : un coiffeur ne doit pas pouvoir effacer ce
    qu'il a encaissé. Le coiffeur concerné est prévenu — sa part change, il
    doit le savoir.

    Le RDV repasse « en cours », hors machine à états et volontairement : ce
    n'est pas une prestation qui se défait, c'est une saisie qui se corrige,
    et le ré-encaissement repasse par le parcours normal.
    """
    booking = await _load_booking(booking_id)
    salon = await get_salon(booking.salon_id)
    if user.role is not Role.OWNER or salon.owner_id != user.id:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            "Seul le gérant du salon peut annuler un encaissement",
        )

    tx = await Transaction.find_one(Transaction.booking_id == booking.id)
    if tx is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Aucun encaissement pour ce RDV")

    cloture = tx.closed or (
        await CashClosure.find_one(
            CashClosure.salon_id == tx.salon_id,
            CashClosure.day == to_local(tx.paid_at).date(),
        )
        is not None
    )
    refus = void_refusal(day_closed=cloture, method=tx.method)
    if refus:
        raise HTTPException(status.HTTP_409_CONFLICT, refus)

    # L'archive d'abord : si la suppression échoue ensuite, on a une trace en
    # double, jamais un encaissement disparu sans trace.
    archive = VoidedTransaction(
        transaction_id=tx.id,
        booking_id=tx.booking_id,
        salon_id=tx.salon_id,
        staff_id=tx.staff_id,
        amount=tx.amount,
        method=tx.method,
        salon_share=tx.salon_share,
        staff_share=tx.staff_share,
        salon_tip=tx.salon_tip,
        tip=tx.tip,
        paid_at=tx.paid_at,
        voided_by=user.id,
        reason=body.reason.strip(),
    )
    await archive.insert()
    await tx.delete()

    booking.status = BookingStatus.IN_PROGRESS
    booking.payment_status = PaymentStatus.NONE
    booking.note = f"{booking.note} | encaissement annulé: {archive.reason}".strip(" |")
    booking.updated_at = utcnow()
    await booking.save()

    staff = await StaffMember.get(tx.staff_id)
    if staff:
        staff.cuts_count = max(0, staff.cuts_count - 1)
        await staff.save()
        if staff.user_id != user.id:
            await notify(
                staff.user_id,
                NotificationType.PAYMENT_VOIDED,
                "Encaissement annulé",
                f"{tx.amount:.2f} DT — {archive.reason}. Votre part "
                f"({tx.staff_share + tx.tip:.2f} DT) est retirée jusqu'au "
                "nouvel encaissement.",
                {"booking_id": str(booking.id)},
            )

    return {"booking": booking, "voided": archive}
