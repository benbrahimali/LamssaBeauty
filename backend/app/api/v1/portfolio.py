"""Portfolio coiffeur & fil « En vogue » (§3.8) — le levier d'acquisition organique."""
from datetime import timedelta

from beanie import PydanticObjectId
from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, status

from app.core.deps import my_staff_profile
from app.core.security import current_user, optional_user
from app.core.timeutils import utcnow
from app.models.documents import PortfolioItem, Salon, StaffMember, User
from app.schemas.social import PortfolioCreate
from app.services.storage_service import save_image

router = APIRouter()


@router.post("/upload", summary="Uploader une photo de réalisation")
async def upload(file: UploadFile, staff: StaffMember = Depends(my_staff_profile)):
    url = await save_image(file, f"portfolio/{staff.id}")
    return {"url": url}


@router.post("", status_code=201, summary="Publier une réalisation")
async def publish(body: PortfolioCreate, staff: StaffMember = Depends(my_staff_profile)):
    item = PortfolioItem(
        staff_id=staff.id,
        salon_id=staff.salon_id,
        image_url=body.image_url,
        before_url=body.before_url,
        caption=body.caption,
        tags=[t.strip().lower().lstrip("#") for t in body.tags if t.strip()][:8],
    )
    await item.insert()
    staff.portfolio_count += 1
    await staff.save()
    return item


@router.get("/trending", summary="Fil « En vogue » local")
async def trending(
    days: int = Query(14, ge=1, le=90),
    tag: str | None = None,
    salon_id: PydanticObjectId | None = None,
    limit: int = Query(30, ge=1, le=100),
    viewer: User | None = Depends(optional_user),
):
    """Classement simple : publications récentes triées par likes puis fraîcheur."""
    query: dict = {"created_at": {"$gte": utcnow() - timedelta(days=days)}}
    if tag:
        query["tags"] = tag.strip().lower().lstrip("#")
    if salon_id:
        query["salon_id"] = salon_id

    items = (
        await PortfolioItem.find(query)
        .sort([("likes", -1), ("created_at", -1)])
        .limit(limit)
        .to_list()
    )
    return await _decorate(items, viewer)


@router.get("/staff/{staff_id}", summary="Portfolio d'un coiffeur")
async def staff_portfolio(
    staff_id: PydanticObjectId,
    limit: int = Query(40, ge=1, le=100),
    viewer: User | None = Depends(optional_user),
):
    items = (
        await PortfolioItem.find(PortfolioItem.staff_id == staff_id)
        .sort("-created_at")
        .limit(limit)
        .to_list()
    )
    return await _decorate(items, viewer)


@router.post("/{item_id}/like", summary="Aimer / retirer son like")
async def toggle_like(item_id: PydanticObjectId, user: User = Depends(current_user)):
    item = await PortfolioItem.get(item_id)
    if not item:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Publication introuvable")
    if user.id in item.liked_by:
        item.liked_by.remove(user.id)
    else:
        item.liked_by.append(user.id)
    item.likes = len(item.liked_by)
    await item.save()
    return {"likes": item.likes, "liked_by_me": user.id in item.liked_by}


@router.delete("/{item_id}", summary="Supprimer une publication")
async def delete_item(
    item_id: PydanticObjectId, staff: StaffMember = Depends(my_staff_profile)
):
    item = await PortfolioItem.get(item_id)
    if not item:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Publication introuvable")
    if item.staff_id != staff.id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Publication d'un autre coiffeur")
    await item.delete()
    staff.portfolio_count = max(0, staff.portfolio_count - 1)
    await staff.save()
    return {"removed": str(item_id)}


async def _decorate(items: list[PortfolioItem], viewer: User | None) -> list[dict]:
    """Ajoute nom du coiffeur, nom du salon et état du like — en 2 requêtes, pas N."""
    if not items:
        return []
    staff_ids = {i.staff_id for i in items}
    salon_ids = {i.salon_id for i in items}
    members = {
        m.id: m for m in await StaffMember.find({"_id": {"$in": list(staff_ids)}}).to_list()
    }
    salons = {s.id: s for s in await Salon.find({"_id": {"$in": list(salon_ids)}}).to_list()}

    return [
        {
            **item.model_dump(mode="json", exclude={"liked_by"}),
            "staff_name": members[item.staff_id].display_name
            if item.staff_id in members
            else "",
            "salon_name": salons[item.salon_id].name if item.salon_id in salons else "",
            "liked_by_me": bool(viewer and viewer.id in item.liked_by),
        }
        for item in items
    ]
