"""Dépendances métier réutilisables : accès salon, profil staff, cloisonnement des rôles."""
from beanie import PydanticObjectId
from fastapi import Depends, HTTPException, Path, status

from app.core.security import current_user, require_role
from app.models.documents import Salon, StaffMember, User
from app.models.enums import Role


async def get_salon(salon_id: PydanticObjectId) -> Salon:
    salon = await Salon.get(salon_id)
    if not salon:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Salon introuvable")
    return salon


async def owned_salon(
    salon_id: PydanticObjectId = Path(...),
    user: User = Depends(require_role(Role.OWNER)),
) -> Salon:
    """Le gérant ne peut administrer QUE ses propres salons."""
    salon = await get_salon(salon_id)
    if salon.owner_id != user.id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Ce salon ne vous appartient pas")
    return salon


async def my_staff_profile(user: User = Depends(current_user)) -> StaffMember:
    profile = await StaffMember.find_one(StaffMember.user_id == user.id)
    if not profile:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND, "Aucun profil coiffeur rattaché à ce compte"
        )
    return profile


async def assert_salon_access(salon_id: PydanticObjectId, user: User) -> Salon:
    """Autorise le gérant propriétaire ou un membre du staff rattaché au salon."""
    salon = await get_salon(salon_id)
    if user.role == Role.OWNER and salon.owner_id == user.id:
        return salon
    member = await StaffMember.find_one(
        StaffMember.salon_id == salon_id, StaffMember.user_id == user.id
    )
    if member:
        return salon
    raise HTTPException(status.HTTP_403_FORBIDDEN, "Vous n'êtes pas rattaché à ce salon")
