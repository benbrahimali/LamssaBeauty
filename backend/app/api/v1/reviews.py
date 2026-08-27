"""Avis post-RDV (§3.8) — uniquement sur un RDV réellement terminé."""
from beanie import PydanticObjectId
from fastapi import APIRouter, Depends, HTTPException, Query, status
from pymongo.errors import DuplicateKeyError

from app.core.security import current_user, require_role
from app.models.documents import Booking, Review, Salon, StaffMember, User
from app.models.enums import BookingStatus, NotificationType, ReviewStatus, Role
from app.schemas.social import ReviewCreate
from app.services.notification_service import notify

router = APIRouter()


async def _recompute_rating(doc, target_id: PydanticObjectId, field: str) -> None:
    """Met à jour la note moyenne dénormalisée d'un salon ou d'un coiffeur."""
    pipeline = [
        {"$match": {field: target_id, "status": ReviewStatus.PUBLISHED.value}},
        {"$group": {"_id": None, "avg": {"$avg": "$rating"}, "n": {"$sum": 1}}},
    ]
    result = await Review.aggregate(pipeline).to_list()
    doc.rating_avg = round(result[0]["avg"], 2) if result else 0.0
    doc.rating_count = result[0]["n"] if result else 0
    await doc.save()


@router.post("", status_code=201, summary="Laisser un avis")
async def create_review(body: ReviewCreate, user: User = Depends(current_user)):
    booking = await Booking.get(body.booking_id)
    if not booking:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "RDV introuvable")
    if booking.client_id != user.id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Ce RDV n'est pas le vôtre")
    if booking.status is not BookingStatus.DONE:
        raise HTTPException(
            status.HTTP_409_CONFLICT, "Vous pourrez noter une fois la prestation terminée"
        )

    review = Review(
        booking_id=booking.id,
        salon_id=booking.salon_id,
        staff_id=booking.staff_id,
        client_id=user.id,
        rating=body.rating,
        comment=body.comment.strip(),
    )
    try:
        await review.insert()
    except DuplicateKeyError:
        raise HTTPException(status.HTTP_409_CONFLICT, "Vous avez déjà noté ce RDV")

    salon = await Salon.get(booking.salon_id)
    staff = await StaffMember.get(booking.staff_id)
    if salon:
        await _recompute_rating(salon, salon.id, "salon_id")
    if staff:
        await _recompute_rating(staff, staff.id, "staff_id")
        await notify(
            staff.user_id,
            NotificationType.NEW_REVIEW,
            f"Nouvel avis {body.rating}/5",
            (body.comment[:120] or "Un client vient de vous noter."),
            {"review_id": str(review.id)},
        )
    return review


@router.get("/salon/{salon_id}", summary="Avis d'un salon")
async def salon_reviews(
    salon_id: PydanticObjectId,
    limit: int = Query(20, ge=1, le=100),
    skip: int = Query(0, ge=0),
):
    return (
        await Review.find(
            Review.salon_id == salon_id, Review.status == ReviewStatus.PUBLISHED
        )
        .sort("-created_at")
        .skip(skip)
        .limit(limit)
        .to_list()
    )


@router.patch("/{review_id}/moderate", summary="Masquer/republier un avis (modération)")
async def moderate(
    review_id: PydanticObjectId,
    hide: bool = True,
    user: User = Depends(require_role(Role.OWNER)),
):
    review = await Review.get(review_id)
    if not review:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Avis introuvable")
    salon = await Salon.get(review.salon_id)
    if not salon or salon.owner_id != user.id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Pas votre salon")

    review.status = ReviewStatus.HIDDEN if hide else ReviewStatus.PUBLISHED
    await review.save()
    await _recompute_rating(salon, salon.id, "salon_id")
    staff = await StaffMember.get(review.staff_id)
    if staff:
        await _recompute_rating(staff, staff.id, "staff_id")
    return review
