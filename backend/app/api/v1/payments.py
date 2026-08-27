"""Paiement en ligne (§3.6) : checkout PSP, webhook, remboursement."""
import logging

from beanie import PydanticObjectId
from fastapi import APIRouter, Depends, Header, HTTPException, Request, status

from app.core.config import settings
from app.core.security import current_user, require_role
from app.core.timeutils import to_local, utcnow
from app.models.documents import Booking, Payment, Salon, User
from app.models.enums import BookingStatus, NotificationType, PaymentStatus, Role
from app.schemas.booking import CheckoutCreate, CheckoutOut
from app.services.booking_service import apply_transition
from app.services.notification_service import notify
from app.services.payment_service import (
    get_provider,
    platform_fee,
    verify_webhook_signature,
)

router = APIRouter()
log = logging.getLogger("lamssa.payment")


@router.post("/checkout", response_model=CheckoutOut, summary="Initier un paiement en ligne")
async def checkout(body: CheckoutCreate, user: User = Depends(current_user)):
    booking = await Booking.get(body.booking_id)
    if not booking:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "RDV introuvable")
    if booking.client_id != user.id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Ce RDV n'est pas le vôtre")
    if booking.payment_status is PaymentStatus.PAID:
        raise HTTPException(status.HTTP_409_CONFLICT, "RDV déjà payé")
    if booking.status not in (BookingStatus.PENDING, BookingStatus.CONFIRMED):
        raise HTTPException(
            status.HTTP_409_CONFLICT, f"RDV au statut {booking.status} — paiement impossible"
        )

    provider = get_provider()
    payment = Payment(
        booking_id=booking.id,
        salon_id=booking.salon_id,
        client_id=user.id,
        amount=booking.price_total,
        platform_fee=platform_fee(booking.price_total),
        currency=settings.CURRENCY,
        provider=provider.name,
    )
    await payment.insert()

    session = await provider.create_checkout(
        amount=booking.price_total,
        order_id=str(payment.id),
        phone=user.phone,
        description=f"LAMSSA — {', '.join(booking.service_names) or 'prestation'}",
    )
    payment.provider_ref = session.ref
    payment.checkout_url = session.url
    payment.raw = session.raw
    await payment.save()

    booking.payment_status = PaymentStatus.PENDING
    booking.payment_id = payment.id
    await booking.save()

    return CheckoutOut(
        payment_id=str(payment.id),
        checkout_url=session.url,
        provider=provider.name,
        amount=payment.amount,
        platform_fee=payment.platform_fee,
        currency=payment.currency,
    )


async def _settle(payment: Payment, paid: bool) -> Payment:
    """Applique le résultat du PSP au paiement ET au RDV (idempotent)."""
    if payment.status is PaymentStatus.PAID:
        return payment

    payment.status = PaymentStatus.PAID if paid else PaymentStatus.FAILED
    payment.paid_at = utcnow() if paid else None
    await payment.save()

    booking = await Booking.get(payment.booking_id)
    if not booking:
        return payment

    booking.payment_status = payment.status
    await booking.save()
    if paid and booking.status is BookingStatus.PENDING:
        await apply_transition(booking, BookingStatus.CONFIRMED)
    if paid and booking.client_id:
        await notify(
            booking.client_id,
            NotificationType.BOOKING_CONFIRMED,
            "Paiement reçu — RDV confirmé",
            f"{payment.amount:.2f} {payment.currency} réglés. "
            f"RDV le {to_local(booking.start).strftime('%d/%m à %H:%M')}.",
            {"booking_id": str(booking.id)},
        )
    return payment


@router.post("/webhook", summary="Webhook PSP (Konnect / Flouci)")
async def webhook(
    request: Request,
    x_signature: str | None = Header(None, alias="X-Signature"),
):
    raw = await request.body()
    verify_webhook_signature(raw, x_signature)

    try:
        payload = await request.json()
    except Exception:  # noqa: BLE001 — certains PSP notifient en query string seule
        payload = {}

    provider = get_provider()
    ref, paid = provider.parse_webhook(payload, dict(request.query_params))
    if not ref:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Référence de paiement absente")

    payment = await Payment.find_one(Payment.provider_ref == ref)
    if not payment:
        log.warning("Webhook pour une référence inconnue: %s", ref)
        return {"ignored": True}

    # On ne fait jamais confiance au corps du webhook : on revérifie auprès du PSP.
    paid = paid and await provider.verify(ref)
    await _settle(payment, paid)
    return {"received": True, "status": payment.status}


@router.get("/{payment_id}", summary="Statut d'un paiement")
async def payment_status(payment_id: PydanticObjectId, user: User = Depends(current_user)):
    payment = await Payment.get(payment_id)
    if not payment:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Paiement introuvable")
    if payment.client_id != user.id:
        salon = await Salon.get(payment.salon_id)
        if not salon or salon.owner_id != user.id:
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Accès refusé")
    return payment


@router.post("/{payment_id}/refund", summary="Rembourser (annulation dans les règles)")
async def refund(
    payment_id: PydanticObjectId, user: User = Depends(require_role(Role.OWNER))
):
    payment = await Payment.get(payment_id)
    if not payment:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Paiement introuvable")
    salon = await Salon.get(payment.salon_id)
    if not salon or salon.owner_id != user.id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Pas votre salon")
    if payment.status is not PaymentStatus.PAID:
        raise HTTPException(status.HTTP_409_CONFLICT, "Seul un paiement encaissé est remboursable")

    # Le remboursement effectif est déclenché côté PSP (back-office ou API dédiée) ;
    # on trace ici l'état pour que la caisse et le RDV restent cohérents.
    payment.status = PaymentStatus.REFUNDED
    payment.refunded_at = utcnow()
    await payment.save()

    booking = await Booking.get(payment.booking_id)
    if booking:
        booking.payment_status = PaymentStatus.REFUNDED
        await booking.save()
    return payment


@router.post("/mock/{ref}/pay", summary="[dev] Simuler un paiement réussi")
async def mock_pay(ref: str):
    """Disponible uniquement hors production, pour tester le tunnel sans PSP réel."""
    if settings.is_prod or settings.PSP_PROVIDER != "mock":
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Indisponible")
    payment = await Payment.find_one(Payment.provider_ref == ref)
    if not payment:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Paiement introuvable")
    await _settle(payment, True)
    return {"paid": True, "booking_id": str(payment.booking_id)}
