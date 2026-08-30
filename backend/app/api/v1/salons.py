"""Salons : recherche géolocalisée (§3.2), fiche publique, administration (§3.5)."""
from datetime import datetime

from beanie import PydanticObjectId
from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, status

from app.core.config import settings
from app.core.deps import get_salon, owned_salon
from app.core.security import current_user
from app.core.timeutils import TZ, day_key, parse_hhmm, to_local, utcnow
from app.models.documents import (
    DEFAULT_HOURS,
    Booking,
    GeoPoint,
    Review,
    Salon,
    Service,
    StaffMember,
    TimeOff,
    User,
)
from app.models.enums import (
    ACTIVE_BOOKING_STATUSES,
    ReviewStatus,
    Role,
    SalonStatus,
    SalonType,
    SubscriptionStatus,
)
from app.schemas.salon import (
    SalonCard,
    SalonCreate,
    SalonUpdate,
    ServiceCreate,
    ServiceUpdate,
    StaffCreate,
    StaffUpdate,
    TimeOffCreate,
)
from app.services import public_code
from app.services.storage_service import save_image

router = APIRouter()


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────
def is_open_now(salon: Salon, now: datetime | None = None) -> bool:
    now = to_local(now or utcnow(), TZ)
    if salon.status is SalonStatus.CLOSED:
        return False
    if salon.closed_until and salon.closed_until > utcnow():
        return False
    hours = salon.hours.get(day_key(now.date())) or DEFAULT_HOURS[day_key(now.date())]
    if hours.closed:
        return False
    current = now.time()
    if not (parse_hhmm(hours.open) <= current < parse_hhmm(hours.close)):
        return False
    if hours.break_start and hours.break_end:
        if parse_hhmm(hours.break_start) <= current < parse_hhmm(hours.break_end):
            return False
    return True


async def _to_card(salon: Salon, distance_m: float | None = None) -> SalonCard:
    services = await Service.find(
        Service.salon_id == salon.id, Service.active == True  # noqa: E712
    ).to_list()
    staff_count = await StaffMember.find(StaffMember.salon_id == salon.id).count()
    return SalonCard(
        id=str(salon.id),
        name=salon.name,
        type=salon.type,
        address=salon.address,
        city=salon.city,
        lat=salon.location.lat,
        lng=salon.location.lng,
        photos=salon.photos,
        rating_avg=salon.rating_avg,
        rating_count=salon.rating_count,
        status=salon.status,
        is_open_now=is_open_now(salon),
        distance_km=round(distance_m / 1000, 2) if distance_m is not None else None,
        price_from=min((s.price for s in services), default=None),
        staff_count=staff_count,
    )


# ─────────────────────────────────────────────────────────────────────────────
# Recherche & fiche publique
# ─────────────────────────────────────────────────────────────────────────────
@router.get("", response_model=list[SalonCard], summary="Rechercher des salons")
async def search_salons(
    near: str | None = Query(None, description="lat,lng — ex. 36.8065,10.1815"),
    type: SalonType | None = None,
    max_km: float = Query(10, gt=0, le=200),
    open_now: bool = False,
    min_rating: float = Query(0, ge=0, le=5),
    q: str | None = Query(None, description="Recherche par nom"),
    limit: int = Query(50, ge=1, le=100),
):
    """Recherche géo 2dsphere + filtres type/note/distance/« disponible maintenant »."""
    match: dict = {"status": SalonStatus.OPEN.value}
    if type:
        match["type"] = type.value
    if min_rating:
        match["rating_avg"] = {"$gte": min_rating}
    if q:
        match["name"] = {"$regex": q.strip(), "$options": "i"}

    if near:
        try:
            lat, lng = (float(x) for x in near.split(","))
        except ValueError:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "Paramètre `near` attendu : lat,lng")
        pipeline = [
            {
                "$geoNear": {
                    "near": {"type": "Point", "coordinates": [lng, lat]},
                    "distanceField": "distance_m",
                    "maxDistance": max_km * 1000,
                    "query": match,
                    "spherical": True,
                }
            },
            {"$limit": limit},
        ]
        raw = await Salon.aggregate(pipeline).to_list()
        cards = [
            await _to_card(Salon.model_validate(doc), doc.get("distance_m"))
            for doc in raw
        ]
    else:
        salons = await Salon.find(match).limit(limit).to_list()
        cards = [await _to_card(s) for s in salons]

    if open_now:
        cards = [c for c in cards if c.is_open_now]
    return cards


@router.get(
    "/code/{code}",
    summary="Fiche salon par code public (QR en vitrine, partage WhatsApp)",
)
async def salon_by_code(code: str):
    """Résout le code imprimé sur le QR. Public : c'est tout l'intérêt du partage.

    Déclarée avant `/{salon_id}` : sinon FastAPI ferait correspondre « code » à
    un identifiant de salon et renverrait une erreur de validation.
    """
    cleaned = public_code.normalize(code)
    salon = await Salon.find_one(Salon.public_code == cleaned)
    if salon is None:
        raise HTTPException(404, "Aucun salon pour ce code")
    return await _salon_detail(salon)


@router.get("/{salon_id}", summary="Fiche salon (photos, équipe, services, avis)")
async def salon_detail(salon_id: PydanticObjectId):
    return await _salon_detail(await get_salon(salon_id))


async def _salon_detail(salon: Salon):
    salon_id = salon.id
    staff = await StaffMember.find(StaffMember.salon_id == salon_id).to_list()
    services = await Service.find(
        Service.salon_id == salon_id, Service.active == True  # noqa: E712
    ).to_list()
    reviews = (
        await Review.find(
            Review.salon_id == salon_id, Review.status == ReviewStatus.PUBLISHED
        )
        .sort("-created_at")
        .limit(10)
        .to_list()
    )
    return {
        "salon": salon,
        "is_open_now": is_open_now(salon),
        "staff": staff,
        "services": services,
        "reviews": reviews,
    }


# ─────────────────────────────────────────────────────────────────────────────
# Onboarding & administration du salon (§3.1, §3.5)
# ─────────────────────────────────────────────────────────────────────────────
@router.post("", status_code=201, summary="Créer son salon (onboarding gérant)")
async def create_salon(body: SalonCreate, user: User = Depends(current_user)):
    """Créer un salon promeut automatiquement l'utilisateur au rôle OWNER."""
    from datetime import timedelta

    salon = Salon(
        owner_id=user.id,
        name=body.name,
        type=body.type,
        location=body.to_location(),
        address=body.address,
        city=body.city,
        phone=body.phone or user.phone,
        description=body.description,
        hours=body.hours or dict(DEFAULT_HOURS),
        default_split_pct=body.default_split_pct,
        cancellation_window_h=body.cancellation_window_h,
        subscription_status=SubscriptionStatus.TRIAL,
        trial_ends_at=utcnow() + timedelta(days=settings.TRIAL_DAYS),
    )
    await public_code.assign(salon)

    if user.role is not Role.OWNER:
        user.role = Role.OWNER
        await user.save()
    return salon


@router.get(
    "/{salon_id}/share",
    summary="Code public et liens de partage (QR vitrine, WhatsApp)",
)
async def salon_share(salon: Salon = Depends(owned_salon)):
    """Ce que le gérant imprime ou envoie à ses clients.

    Attribue le code au passage : les salons créés avant cette fonctionnalité
    n'en ont pas, et ils ne doivent pas rester sans QR pour autant.
    """
    if not salon.public_code:
        await public_code.assign(salon)

    base = settings.PUBLIC_WEB_BASE.rstrip("/")
    return {
        "code": salon.public_code,
        # Encodé dans le QR : une URL https reste ouvrable par n'importe quel
        # appareil photo, là où un schéma applicatif ne mène nulle part sans l'app.
        "url": f"{base}/s/{salon.public_code}",
        "deep_link": f"{settings.APP_SCHEME}://salon/{salon.public_code}",
        "share_text": (
            f"احجز في {salon.name} 💈\n"
            f"{base}/s/{salon.public_code}\n"
            f"كود: {salon.public_code}"
        ),
    }


@router.patch("/{salon_id}", summary="Modifier son salon")
async def update_salon(body: SalonUpdate, salon: Salon = Depends(owned_salon)):
    data = body.model_dump(exclude_none=True)
    lat, lng = data.pop("lat", None), data.pop("lng", None)
    if lat is not None and lng is not None:
        salon.location = GeoPoint(coordinates=[lng, lat])
    elif lat is not None or lng is not None:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, "Fournissez lat ET lng pour déplacer le salon"
        )
    # Les horaires se modifient jour par jour : remplacer le dictionnaire
    # entier effacerait les six autres jours, qui retomberaient en silence sur
    # les valeurs par défaut. Un gérant qui ouvre le dimanche perdrait ainsi
    # ses horaires du lundi sans le savoir.
    hours = data.pop("hours", None)
    if hours is not None:
        salon.hours = {**salon.hours, **hours}

    for field, value in data.items():
        setattr(salon, field, value)
    await salon.save()
    return salon


#: Au-delà, la fiche devient un catalogue qu'on ne fait plus défiler.
MAX_SALON_PHOTOS = 10


@router.post("/{salon_id}/photos", summary="Ajouter une photo au salon")
async def upload_photo(file: UploadFile, salon: Salon = Depends(owned_salon)):
    if len(salon.photos) >= MAX_SALON_PHOTOS:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            f"Maximum {MAX_SALON_PHOTOS} photos — supprime-en une d'abord.",
        )
    url = await save_image(file, f"salons/{salon.id}")
    salon.photos.append(url)
    await salon.save()
    return {"url": url, "photos": salon.photos}


@router.delete("/{salon_id}/photos", summary="Retirer une photo du salon")
async def delete_photo(url: str, salon: Salon = Depends(owned_salon)):
    """Une photo mal cadrée doit pouvoir être retirée, sinon elle reste à vie.

    La photo est identifiée par son URL et non par un index : deux suppressions
    concurrentes décaleraient les positions et effaceraient la mauvaise.
    """
    if url not in salon.photos:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Photo introuvable")
    salon.photos.remove(url)
    await salon.save()
    return {"photos": salon.photos}


# ─────────────────────────────────────────────────────────────────────────────
# Catalogue de services
# ─────────────────────────────────────────────────────────────────────────────
@router.get("/{salon_id}/services", summary="Catalogue des services")
async def list_services(salon_id: PydanticObjectId, include_inactive: bool = False):
    query = {"salon_id": salon_id}
    if not include_inactive:
        query["active"] = True
    return await Service.find(query).to_list()


@router.post("/{salon_id}/services", status_code=201, summary="Ajouter un service")
async def create_service(body: ServiceCreate, salon: Salon = Depends(owned_salon)):
    service = Service(salon_id=salon.id, **body.model_dump())
    await service.insert()
    return service


@router.patch("/{salon_id}/services/{service_id}", summary="Modifier un service")
async def update_service(
    service_id: PydanticObjectId, body: ServiceUpdate, salon: Salon = Depends(owned_salon)
):
    service = await Service.get(service_id)
    if not service or service.salon_id != salon.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Service introuvable")
    for field, value in body.model_dump(exclude_none=True).items():
        setattr(service, field, value)
    await service.save()
    return service


@router.delete("/{salon_id}/services/{service_id}", summary="Retirer un service")
async def delete_service(service_id: PydanticObjectId, salon: Salon = Depends(owned_salon)):
    """Désactivation logique : les RDV et transactions passés doivent rester lisibles."""
    service = await Service.get(service_id)
    if not service or service.salon_id != salon.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Service introuvable")
    service.active = False
    await service.save()
    return {"deactivated": str(service.id)}


# ─────────────────────────────────────────────────────────────────────────────
# Équipe & chaises
# ─────────────────────────────────────────────────────────────────────────────
@router.get("/{salon_id}/staff", summary="Équipe du salon")
async def list_staff(salon_id: PydanticObjectId):
    return await StaffMember.find(StaffMember.salon_id == salon_id).to_list()


@router.post("/{salon_id}/staff", status_code=201, summary="Inviter un membre d'équipe")
async def add_staff(body: StaffCreate, salon: Salon = Depends(owned_salon)):
    """Rattache un coiffeur par numéro ; le compte est créé s'il n'existe pas encore."""
    member_user = await User.find_one(User.phone == body.phone)
    if not member_user:
        member_user = User(phone=body.phone, name=body.display_name, role=Role.STAFF)
        await member_user.insert()
    elif member_user.role is Role.CLIENT:
        member_user.role = Role.STAFF
        await member_user.save()

    if await StaffMember.find_one(
        StaffMember.salon_id == salon.id, StaffMember.user_id == member_user.id
    ):
        raise HTTPException(status.HTTP_409_CONFLICT, "Ce membre fait déjà partie de l'équipe")

    payload = body.model_dump(exclude={"phone"})
    member = StaffMember(
        salon_id=salon.id,
        user_id=member_user.id,
        **{**payload, "display_name": body.display_name or member_user.name},
    )
    await member.insert()
    return member


@router.patch("/{salon_id}/staff/{staff_id}", summary="Modifier un membre (chaise, commission)")
async def update_staff(
    staff_id: PydanticObjectId, body: StaffUpdate, salon: Salon = Depends(owned_salon)
):
    member = await StaffMember.get(staff_id)
    if not member or member.salon_id != salon.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Membre introuvable")
    for field, value in body.model_dump(exclude_none=True).items():
        setattr(member, field, value)
    await member.save()
    return member


@router.delete("/{salon_id}/staff/{staff_id}", summary="Retirer un membre de l'équipe")
async def remove_staff(staff_id: PydanticObjectId, salon: Salon = Depends(owned_salon)):
    member = await StaffMember.get(staff_id)
    if not member or member.salon_id != salon.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Membre introuvable")
    upcoming = await Booking.find(
        Booking.staff_id == staff_id,
        {"status": {"$in": ACTIVE_BOOKING_STATUSES}},
        Booking.start >= utcnow(),
    ).count()
    if upcoming:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            f"{upcoming} RDV à venir sur ce coiffeur — réaffectez-les ou annulez-les d'abord",
        )
    await member.delete()
    await sync_role(member.user_id)
    return {"removed": str(staff_id)}


async def sync_role(user_id: PydanticObjectId) -> None:
    """Remet le rôle du compte en accord avec ce qu'il possède réellement.

    Aucune route ne s'appuie aujourd'hui sur `Role.STAFF` — les accès employé
    passent par l'existence d'un `StaffMember`. Un rôle périmé n'ouvre donc
    rien. Mais le jour où quelqu'un ajoutera un `require_role(Role.STAFF)`, un
    employé renvoyé passerait la porte : on referme le piège avant.

    Un gérant reste gérant tant qu'il possède un salon, même s'il quitte une
    équipe où il coupait aussi les cheveux — d'où l'ordre des tests.
    """
    user = await User.get(user_id)
    if user is None:
        return

    if await Salon.find_one(Salon.owner_id == user.id):
        role = Role.OWNER
    elif await StaffMember.find_one(StaffMember.user_id == user.id):
        role = Role.STAFF
    else:
        role = Role.CLIENT

    if user.role is not role:
        user.role = role
        await user.save()


@router.get("/{salon_id}/ranking", summary="Classement interne de l'équipe (motivation)")
async def team_ranking(salon: Salon = Depends(owned_salon)):
    members = await StaffMember.find(StaffMember.salon_id == salon.id).to_list()
    ranked = sorted(
        members, key=lambda m: (m.cuts_count, m.rating_avg), reverse=True
    )
    return [
        {
            "rank": i + 1,
            "staff_id": str(m.id),
            "name": m.display_name,
            "chair": m.chair_number,
            "cuts": m.cuts_count,
            "rating": m.rating_avg,
        }
        for i, m in enumerate(ranked)
    ]


# ─────────────────────────────────────────────────────────────────────────────
# Congés / absences (§3.5)
# ─────────────────────────────────────────────────────────────────────────────
@router.post("/{salon_id}/timeoff", status_code=201, summary="Bloquer un congé")
async def create_timeoff(body: TimeOffCreate, salon: Salon = Depends(owned_salon)):
    if body.end <= body.start:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Fin de congé antérieure au début")
    member = await StaffMember.get(body.staff_id)
    if not member or member.salon_id != salon.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Membre introuvable")
    off = TimeOff(salon_id=salon.id, **body.model_dump())
    await off.insert()

    clashing = await Booking.find(
        Booking.staff_id == body.staff_id,
        {"status": {"$in": ACTIVE_BOOKING_STATUSES}},
        Booking.start < body.end,
        Booking.end > body.start,
    ).count()
    return {"time_off": off, "bookings_to_reschedule": clashing}


@router.get("/{salon_id}/timeoff", summary="Congés à venir")
async def list_timeoff(salon: Salon = Depends(owned_salon)):
    return await TimeOff.find(
        TimeOff.salon_id == salon.id, TimeOff.end >= utcnow()
    ).sort("+start").to_list()


@router.delete("/{salon_id}/timeoff/{off_id}", summary="Annuler un congé")
async def delete_timeoff(off_id: PydanticObjectId, salon: Salon = Depends(owned_salon)):
    off = await TimeOff.get(off_id)
    if not off or off.salon_id != salon.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Congé introuvable")
    await off.delete()
    return {"removed": str(off_id)}
