"""Tséb9a — avances sur salaire (§3.4). Demande par le staff, décision par le gérant."""
from beanie import PydanticObjectId
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.deps import my_staff_profile
from app.core.security import current_user, require_role
from app.core.timeutils import utcnow
from app.models.documents import Advance, Salon, StaffMember, User
from app.models.enums import AdvanceStatus, NotificationType, Role
from app.schemas.cash import AdvanceCreate, AdvanceDecision
from app.services.cash_service import staff_month_balance
from app.services.notification_service import notify

router = APIRouter()


@router.post("", status_code=201, summary="Demander une tséb9a")
async def request_advance(
    body: AdvanceCreate,
    user: User = Depends(current_user),
    staff: StaffMember = Depends(my_staff_profile),
):
    if staff.salon_id != body.salon_id:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, "Vous n'êtes pas rattaché à ce salon"
        )
    pending = await Advance.find(
        Advance.staff_id == staff.id, Advance.status == AdvanceStatus.PENDING
    ).count()
    if pending:
        raise HTTPException(
            status.HTTP_409_CONFLICT, "Une demande est déjà en attente de validation"
        )

    advance = Advance(
        salon_id=body.salon_id, staff_id=staff.id, amount=body.amount, reason=body.reason
    )
    await advance.insert()

    salon = await Salon.get(body.salon_id)
    if salon:
        await notify(
            salon.owner_id,
            NotificationType.ADVANCE_REQUESTED,
            "Demande de tséb9a",
            f"{staff.display_name or user.name} demande {body.amount:.2f} DT"
            + (f" — {body.reason}" if body.reason else ""),
            {"advance_id": str(advance.id)},
        )
    return advance


@router.get("/me", summary="Mes demandes d'avance")
async def my_advances(staff: StaffMember = Depends(my_staff_profile)):
    advances = (
        await Advance.find(Advance.staff_id == staff.id)
        .sort("-requested_at")
        .limit(50)
        .to_list()
    )
    now = utcnow()
    return {
        "balance": await staff_month_balance(staff, now.year, now.month),
        "advances": advances,
    }


@router.get("", summary="Demandes d'avance du salon (gérant)")
async def salon_advances(
    salon_id: PydanticObjectId,
    status_filter: AdvanceStatus | None = Query(None, alias="status"),
    user: User = Depends(require_role(Role.OWNER)),
):
    salon = await Salon.get(salon_id)
    if not salon or salon.owner_id != user.id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Pas votre salon")

    query: dict = {"salon_id": salon_id}
    if status_filter:
        query["status"] = status_filter
    advances = await Advance.find(query).sort("-requested_at").limit(100).to_list()

    members = {
        m.id: m
        for m in await StaffMember.find(StaffMember.salon_id == salon_id).to_list()
    }
    return [
        {
            **advance.model_dump(mode="json"),
            "staff_name": (members[advance.staff_id].display_name
                           if advance.staff_id in members else "—"),
        }
        for advance in advances
    ]


@router.patch("/{advance_id}", summary="Approuver ou refuser une tséb9a")
async def decide_advance(
    advance_id: PydanticObjectId,
    body: AdvanceDecision,
    user: User = Depends(require_role(Role.OWNER)),
):
    advance = await Advance.get(advance_id)
    if not advance:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Demande introuvable")
    salon = await Salon.get(advance.salon_id)
    if not salon or salon.owner_id != user.id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Pas votre salon")
    if advance.status is not AdvanceStatus.PENDING:
        raise HTTPException(
            status.HTTP_409_CONFLICT, f"Demande déjà traitée ({advance.status})"
        )

    advance.status = AdvanceStatus.APPROVED if body.approve else AdvanceStatus.REJECTED
    advance.decided_at = utcnow()
    advance.paid_from = body.paid_from
    advance.decided_by = user.id
    if body.reason:
        advance.reason = f"{advance.reason} | {body.reason}".strip(" |")
    await advance.save()

    member = await StaffMember.get(advance.staff_id)
    if member:
        await notify(
            member.user_id,
            NotificationType.ADVANCE_DECIDED,
            "Tséb9a " + ("approuvée" if body.approve else "refusée"),
            f"{advance.amount:.2f} DT — "
            + (
                "sera déduite de votre solde à la clôture."
                if body.approve
                else (body.reason or "demande refusée.")
            ),
            {"advance_id": str(advance.id), "approved": body.approve},
        )
    return advance
