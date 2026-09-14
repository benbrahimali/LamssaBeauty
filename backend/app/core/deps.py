"""Dépendances métier réutilisables : accès salon, profil staff, cloisonnement des rôles."""
from beanie import PydanticObjectId
from fastapi import Depends, HTTPException, Path, status

from app.core.security import current_user, require_role
from app.models.documents import (
    HIDDEN_VERIFICATION,
    Salon,
    StaffMember,
    User,
    salon_is_public,
    salons_hidden_from,
)
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


# ─────────────────────────────────────────────────────────────────────────────
# Salons non vérifiés (§2.5) : invisibles du public, visibles de ceux qui les
# préparent.
# ─────────────────────────────────────────────────────────────────────────────
async def can_see_salon(salon: Salon, viewer: User | None) -> bool:
    if salon_is_public(salon.verification_status):
        return True
    if viewer is None:
        return False
    if viewer.is_admin or salon.owner_id == viewer.id:
        return True
    member = await StaffMember.find_one(
        StaffMember.salon_id == salon.id, StaffMember.user_id == viewer.id
    )
    return member is not None


async def hidden_salon_ids(viewer: User | None) -> list[PydanticObjectId]:
    """Salons à retirer des fils publics pour ce visiteur."""
    hidden = await Salon.find(
        {"verification_status": {"$in": list(HIDDEN_VERIFICATION)}}
    ).to_list()
    if not hidden:
        return []
    member_of: set[PydanticObjectId] = set()
    if viewer is not None:
        member_of = {
            m.salon_id
            for m in await StaffMember.find(StaffMember.user_id == viewer.id).to_list()
        }
    return salons_hidden_from(
        [(s.id, s.owner_id) for s in hidden],
        viewer_id=viewer.id if viewer else None,
        is_admin=bool(viewer and viewer.is_admin),
        member_of=member_of,
    )


def without_salons(query: dict, hidden: list) -> dict:
    """Ajoute à une requête l'exclusion des salons cachés.

    Garde un éventuel filtre `salon_id` déjà posé : écraser la clé rendrait
    le fil d'un salon précis identique au fil général.
    """
    if not hidden:
        return query
    condition: dict = {"$nin": list(hidden)}
    if "salon_id" in query:
        condition["$eq"] = query["salon_id"]
    return {**query, "salon_id": condition}
