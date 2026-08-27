"""Historique des notifications in-app (§3.7)."""
from beanie import PydanticObjectId
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.security import current_user
from app.models.documents import Notification, User

router = APIRouter()


@router.get("", summary="Mes notifications")
async def list_notifications(
    unread_only: bool = False,
    limit: int = Query(50, ge=1, le=200),
    user: User = Depends(current_user),
):
    query: dict = {"user_id": user.id}
    if unread_only:
        query["read"] = False
    items = await Notification.find(query).sort("-created_at").limit(limit).to_list()
    unread = await Notification.find(
        Notification.user_id == user.id, Notification.read == False  # noqa: E712
    ).count()
    return {"unread": unread, "items": items}


@router.patch("/{notification_id}/read", summary="Marquer comme lue")
async def mark_read(notification_id: PydanticObjectId, user: User = Depends(current_user)):
    notif = await Notification.get(notification_id)
    if not notif or notif.user_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Notification introuvable")
    notif.read = True
    await notif.save()
    return notif


@router.post("/read-all", summary="Tout marquer comme lu")
async def mark_all_read(user: User = Depends(current_user)):
    result = await Notification.find(
        Notification.user_id == user.id, Notification.read == False  # noqa: E712
    ).update({"$set": {"read": True}})
    return {"updated": getattr(result, "modified_count", 0)}
