"""Reels vidéo (§3.8) — courtes vidéos publiées par un coiffeur ou un salon.

Le fil est **public** : un visiteur sans compte doit pouvoir regarder, sinon
les reels n'attirent personne. Seules la publication, le like et la suppression
demandent un compte.

La durée est plafonnée à `REEL_MAX_SECONDS` et vérifiée sur la mesure de
Cloudinary, jamais sur une valeur déclarée par le client : l'app pourrait
annoncer 30 s pour une vidéo de dix minutes.
"""
from datetime import timedelta

from beanie import PydanticObjectId
from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile, status

from app.core.config import settings
from app.core.deps import get_salon
from app.core.security import current_user, optional_user
from app.core.timeutils import utcnow
from app.models.documents import Reel, Salon, StaffMember, User
from app.models.enums import Role
from app.services import cloudinary_service

router = APIRouter()

ALLOWED_VIDEO = {
    "video/mp4": ".mp4",
    "video/quicktime": ".mov",
    "video/x-matroska": ".mkv",
    "video/webm": ".webm",
}


async def _author_context(user: User) -> tuple[PydanticObjectId, PydanticObjectId | None]:
    """Salon et coiffeur au nom desquels publier.

    Un coiffeur publie en son nom ; un gérant publie au nom du salon. Un client
    n'a rien à publier — le fil resterait crédible seulement si ce qu'on y voit
    vient de professionnels identifiés.
    """
    staff = await StaffMember.find_one(StaffMember.user_id == user.id)
    if staff:
        return staff.salon_id, staff.id

    if user.role is Role.OWNER:
        salon = await Salon.find_one(Salon.owner_id == user.id)
        if salon:
            return salon.id, None

    raise HTTPException(
        status.HTTP_403_FORBIDDEN,
        "Seuls les coiffeurs et les gérants de salon peuvent publier un reel.",
    )


async def enforce_duration(uploaded: dict) -> float:
    """Vérifie le plafond de durée et renvoie la durée retenue.

    On se fie à la mesure de Cloudinary, jamais à une valeur envoyée par le
    client : l'app pourrait annoncer 30 s pour une vidéo de dix minutes.

    Une vidéo refusée est supprimée du fournisseur — sinon on paierait le
    stockage d'un média que personne ne verra jamais.
    """
    duration = float(uploaded.get("duration") or 0.0)
    if duration > settings.REEL_MAX_SECONDS:
        await cloudinary_service.destroy(uploaded.get("public_id", ""), resource_type="video")
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT,
            f"Vidéo trop longue ({int(duration)} s) — maximum "
            f"{settings.REEL_MAX_SECONDS} s.",
        )
    return duration


@router.post("", status_code=201, summary="Publier un reel (vidéo courte)")
async def publish(
    file: UploadFile = File(...),
    caption: str = Form(""),
    tags: str = Form(""),
    user: User = Depends(current_user),
):
    """Envoie la vidéo sur Cloudinary puis enregistre le reel.

    Une vidéo trop longue est supprimée du fournisseur avant de renvoyer
    l'erreur : sans ça, on paierait le stockage d'un média refusé.
    """
    ext = ALLOWED_VIDEO.get(file.content_type or "")
    if ext is None:
        raise HTTPException(
            status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            "Format accepté : MP4, MOV, MKV ou WebM",
        )

    salon_id, staff_id = await _author_context(user)

    payload = await file.read()
    if len(payload) > settings.REEL_MAX_MB * 1024 * 1024:
        raise HTTPException(
            status.HTTP_413_CONTENT_TOO_LARGE,
            f"Vidéo trop lourde (max {settings.REEL_MAX_MB} Mo)",
        )

    uploaded = await cloudinary_service.upload(
        payload, f"reel{ext}", f"lamssa/reels/{salon_id}", resource_type="video"
    )

    duration = await enforce_duration(uploaded)

    reel = Reel(
        salon_id=salon_id,
        staff_id=staff_id,
        author_id=user.id,
        video_url=uploaded["url"],
        thumbnail_url=cloudinary_service.thumbnail_url(uploaded["url"]),
        public_id=uploaded["public_id"],
        duration_sec=duration,
        caption=caption.strip(),
        tags=[t.strip().lower().lstrip("#") for t in tags.split(",") if t.strip()][:8],
    )
    await reel.insert()
    return (await _decorate([reel], user))[0]


@router.get("", summary="Fil public des reels")
async def feed(
    days: int = Query(30, ge=1, le=365),
    tag: str | None = None,
    salon_id: PydanticObjectId | None = None,
    staff_id: PydanticObjectId | None = None,
    limit: int = Query(20, ge=1, le=50),
    viewer: User | None = Depends(optional_user),
):
    """Récents d'abord, puis les plus vus.

    L'ordre inverse — les plus vus d'abord — figerait le fil sur les mêmes
    vidéos et n'aiderait aucun nouveau salon à se faire voir.
    """
    query: dict = {"created_at": {"$gte": utcnow() - timedelta(days=days)}}
    if tag:
        query["tags"] = tag.strip().lower().lstrip("#")
    if salon_id:
        query["salon_id"] = salon_id
    if staff_id:
        query["staff_id"] = staff_id

    reels = (
        await Reel.find(query)
        .sort([("created_at", -1), ("views", -1)])
        .limit(limit)
        .to_list()
    )
    return await _decorate(reels, viewer)


@router.post("/{reel_id}/view", status_code=204, summary="Compter une vue")
async def count_view(reel_id: PydanticObjectId):
    """Public : une vue compte même sans compte, c'est le but d'un fil ouvert."""
    reel = await Reel.get(reel_id)
    if reel is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Reel introuvable")
    reel.views += 1
    await reel.save()


@router.post("/{reel_id}/like", summary="Aimer / retirer son like")
async def toggle_like(reel_id: PydanticObjectId, user: User = Depends(current_user)):
    reel = await Reel.get(reel_id)
    if reel is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Reel introuvable")
    if user.id in reel.liked_by:
        reel.liked_by.remove(user.id)
    else:
        reel.liked_by.append(user.id)
    reel.likes = len(reel.liked_by)
    await reel.save()
    return {"likes": reel.likes, "liked_by_me": user.id in reel.liked_by}


@router.delete("/{reel_id}", summary="Supprimer son reel")
async def remove(reel_id: PydanticObjectId, user: User = Depends(current_user)):
    reel = await Reel.get(reel_id)
    if reel is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Reel introuvable")

    salon = await get_salon(reel.salon_id)
    # L'auteur peut retirer sa vidéo ; le gérant du salon aussi, puisqu'elle
    # est publiée sous l'enseigne et engage sa réputation.
    if reel.author_id != user.id and salon.owner_id != user.id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Reel d'un autre compte")

    await cloudinary_service.destroy(reel.public_id, resource_type="video")
    await reel.delete()
    return {"removed": str(reel_id)}


async def _decorate(reels: list[Reel], viewer: User | None) -> list[dict]:
    """Ajoute l'auteur et l'état du like — en 2 requêtes, pas N."""
    if not reels:
        return []

    staff_ids = {r.staff_id for r in reels if r.staff_id}
    salon_ids = {r.salon_id for r in reels}
    members = {
        m.id: m
        for m in await StaffMember.find({"_id": {"$in": list(staff_ids)}}).to_list()
    }
    salons = {
        s.id: s for s in await Salon.find({"_id": {"$in": list(salon_ids)}}).to_list()
    }

    return [
        {
            **reel.model_dump(mode="json", exclude={"liked_by"}),
            "staff_name": members[reel.staff_id].display_name
            if reel.staff_id in members
            else "",
            "salon_name": salons[reel.salon_id].name if reel.salon_id in salons else "",
            "liked_by_me": bool(viewer and viewer.id in reel.liked_by),
        }
        for reel in reels
    ]
