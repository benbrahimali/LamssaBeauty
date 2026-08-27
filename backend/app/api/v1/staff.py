"""Coiffeurs : profil public, créneaux disponibles, agenda personnel (§3.2, §3.3)."""
from datetime import date

from beanie import PydanticObjectId
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.deps import get_salon, my_staff_profile
from app.core.timeutils import local_day_bounds, to_local, utcnow
from app.models.documents import (
    Booking,
    PortfolioItem,
    Review,
    Salon,
    Service,
    StaffMember,
    User,
)
from app.models.enums import ACTIVE_BOOKING_STATUSES, ReviewStatus
from app.schemas.booking import SlotsResponse
from app.services.booking_service import available_slots

router = APIRouter()


@router.get("/me", summary="Mon profil coiffeur")
async def my_profile(staff: StaffMember = Depends(my_staff_profile)):
    salon = await Salon.get(staff.salon_id)
    return {"staff": staff, "salon": salon}


@router.get("/me/agenda", summary="Mon planning du jour")
async def my_agenda(
    day: date | None = None, staff: StaffMember = Depends(my_staff_profile)
):
    """Le coiffeur ne voit que SES rendez-vous (§2.5 — cloisonnement des rôles)."""
    target = day or to_local(utcnow()).date()
    start, end = local_day_bounds(target)
    bookings = (
        await Booking.find(
            Booking.staff_id == staff.id, Booking.start >= start, Booking.start < end
        )
        .sort("+start")
        .to_list()
    )
    return {
        "date": str(target),
        "count": len(bookings),
        "upcoming": sum(1 for b in bookings if b.status in ACTIVE_BOOKING_STATUSES),
        "bookings": bookings,
    }


@router.get("/{staff_id}", summary="Profil public d'un coiffeur")
async def staff_profile(staff_id: PydanticObjectId):
    staff = await StaffMember.get(staff_id)
    if not staff:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Coiffeur introuvable")
    salon = await Salon.get(staff.salon_id)
    user = await User.get(staff.user_id)
    portfolio = (
        await PortfolioItem.find(PortfolioItem.staff_id == staff_id)
        .sort("-created_at")
        .limit(24)
        .to_list()
    )
    reviews = (
        await Review.find(
            Review.staff_id == staff_id, Review.status == ReviewStatus.PUBLISHED
        )
        .sort("-created_at")
        .limit(10)
        .to_list()
    )
    services = await Service.find(
        {
            "salon_id": staff.salon_id,
            "active": True,
            **({"_id": {"$in": staff.service_ids}} if staff.service_ids else {}),
        }
    ).to_list()
    return {
        "staff": staff,
        "name": staff.display_name or (user.name if user else ""),
        "avatar_url": user.avatar_url if user else None,
        "salon": {"id": str(salon.id), "name": salon.name, "type": salon.type}
        if salon
        else None,
        "services": services,
        "portfolio": portfolio,
        "reviews": reviews,
    }


@router.get("/{staff_id}/slots", response_model=SlotsResponse, summary="Créneaux disponibles")
async def slots(
    staff_id: PydanticObjectId,
    day: date = Query(..., alias="date"),
    service_ids: list[PydanticObjectId] = Query(default=[]),
):
    staff = await StaffMember.get(staff_id)
    if not staff:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Coiffeur introuvable")
    salon = await get_salon(staff.salon_id)
    return await available_slots(
        staff=staff, salon=salon, day=day, service_ids=service_ids or None
    )


@router.get("/{staff_id}/reviews", summary="Avis reçus par un coiffeur")
async def staff_reviews(staff_id: PydanticObjectId, limit: int = Query(20, ge=1, le=100)):
    return (
        await Review.find(
            Review.staff_id == staff_id, Review.status == ReviewStatus.PUBLISHED
        )
        .sort("-created_at")
        .limit(limit)
        .to_list()
    )
