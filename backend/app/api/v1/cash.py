"""Caisse (§3.4) — cœur différenciant : split, dépenses, clôture, rapports."""
import os
from datetime import date, datetime

from beanie import PydanticObjectId
from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import FileResponse

from app.core.deps import my_staff_profile
from app.core.security import require_role
from app.core.timeutils import to_local, utcnow
from app.models.documents import CashClosure, Expense, Salon, StaffMember, User
from app.models.enums import NotificationType, Role
from app.schemas.cash import ClosureCreate, ExpenseCreate
from app.services.cash_service import (
    close_day,
    day_summary,
    monthly_report,
    staff_day_summary,
    staff_month_balance,
)
from app.services.notification_service import notify
from app.services.report_service import generate_closure_report

router = APIRouter()


async def _my_salon(salon_id: PydanticObjectId, user: User) -> Salon:
    """Garde-fou : la caisse d'un salon n'est visible que par son propriétaire."""
    salon = await Salon.get(salon_id)
    if not salon:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Salon introuvable")
    if salon.owner_id != user.id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Pas votre salon")
    return salon


# ─────────────────────────────────────────────────────────────────────────────
# Vue gérant
# ─────────────────────────────────────────────────────────────────────────────
@router.get("/today", summary="Caisse du jour (gérant)")
async def cash_today(
    salon_id: PydanticObjectId, user: User = Depends(require_role(Role.OWNER))
):
    salon = await _my_salon(salon_id, user)
    return await day_summary(salon.id, to_local(utcnow()).date())


@router.get("/day", summary="Caisse d'une journée donnée (gérant)")
async def cash_day(
    salon_id: PydanticObjectId,
    day: date = Query(..., alias="date"),
    user: User = Depends(require_role(Role.OWNER)),
):
    salon = await _my_salon(salon_id, user)
    return await day_summary(salon.id, day)


@router.get("/monthly", summary="P&L mensuel du salon (gérant)")
async def cash_monthly(
    salon_id: PydanticObjectId,
    year: int = Query(..., ge=2024, le=2100),
    month: int = Query(..., ge=1, le=12),
    user: User = Depends(require_role(Role.OWNER)),
):
    salon = await _my_salon(salon_id, user)
    return await monthly_report(salon.id, year, month)


# ─────────────────────────────────────────────────────────────────────────────
# Vue coiffeur — strictement cloisonnée (§2.5)
# ─────────────────────────────────────────────────────────────────────────────
@router.get("/me", summary="Ma caisse personnelle (coiffeur)")
async def cash_me(
    day: date | None = Query(None, alias="date"),
    staff: StaffMember = Depends(my_staff_profile),
):
    return await staff_day_summary(staff, day or to_local(utcnow()).date())


@router.get("/me/balance", summary="Mon solde du mois, avances déduites")
async def my_balance(
    year: int | None = None,
    month: int | None = None,
    staff: StaffMember = Depends(my_staff_profile),
):
    now = to_local(utcnow())
    return await staff_month_balance(staff, year or now.year, month or now.month)


# ─────────────────────────────────────────────────────────────────────────────
# Dépenses salon
# ─────────────────────────────────────────────────────────────────────────────
@router.post("/expenses", status_code=201, summary="Saisir une dépense salon")
async def add_expense(
    salon_id: PydanticObjectId,
    body: ExpenseCreate,
    user: User = Depends(require_role(Role.OWNER)),
):
    salon = await _my_salon(salon_id, user)
    expense = Expense(
        salon_id=salon.id,
        label=body.label,
        amount=body.amount,
        category=body.category,
        spent_at=body.spent_at or utcnow(),
        created_by=user.id,
    )
    await expense.insert()
    return expense


@router.get("/expenses", summary="Dépenses du salon")
async def list_expenses(
    salon_id: PydanticObjectId,
    since: datetime | None = None,
    user: User = Depends(require_role(Role.OWNER)),
):
    salon = await _my_salon(salon_id, user)
    query: dict = {"salon_id": salon.id}
    if since:
        query["spent_at"] = {"$gte": since}
    return await Expense.find(query).sort("-spent_at").limit(200).to_list()


@router.delete("/expenses/{expense_id}", summary="Supprimer une dépense")
async def delete_expense(
    expense_id: PydanticObjectId, user: User = Depends(require_role(Role.OWNER))
):
    expense = await Expense.get(expense_id)
    if not expense:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Dépense introuvable")
    await _my_salon(expense.salon_id, user)
    await expense.delete()
    return {"removed": str(expense_id)}


# ─────────────────────────────────────────────────────────────────────────────
# Clôture de journée (§5.4)
# ─────────────────────────────────────────────────────────────────────────────
@router.post("/closures", status_code=201, summary="Clôturer la journée")
async def create_closure(
    body: ClosureCreate, user: User = Depends(require_role(Role.OWNER))
):
    salon = await _my_salon(body.salon_id, user)
    day = body.day or to_local(utcnow()).date()
    closure = await close_day(salon, day, user)

    try:
        closure.report_path = generate_closure_report(salon, closure)
        await closure.save()
    except Exception as exc:  # noqa: BLE001 — la clôture prime sur le rapport
        import logging

        logging.getLogger("lamssa.cash").warning("Rapport non généré : %s", exc)

    await notify(
        user.id,
        NotificationType.CLOSURE_READY,
        "Journée clôturée",
        f"{salon.name} — {closure.total:.2f} DT encaissés, "
        f"{closure.salon_total:.2f} DT pour le salon.",
        {"closure_id": str(closure.id)},
    )
    return closure


@router.get("/closures", summary="Historique des clôtures")
async def list_closures(
    salon_id: PydanticObjectId,
    limit: int = Query(30, ge=1, le=180),
    user: User = Depends(require_role(Role.OWNER)),
):
    salon = await _my_salon(salon_id, user)
    return (
        await CashClosure.find(CashClosure.salon_id == salon.id)
        .sort("-day")
        .limit(limit)
        .to_list()
    )


@router.get("/closures/{closure_id}/report", summary="Télécharger le rapport de clôture")
async def download_report(
    closure_id: PydanticObjectId, user: User = Depends(require_role(Role.OWNER))
):
    closure = await CashClosure.get(closure_id)
    if not closure:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Clôture introuvable")
    salon = await _my_salon(closure.salon_id, user)

    if not closure.report_path or not os.path.exists(closure.report_path):
        closure.report_path = generate_closure_report(salon, closure)
        await closure.save()
    return FileResponse(
        closure.report_path,
        filename=os.path.basename(closure.report_path),
        media_type="application/pdf"
        if closure.report_path.endswith(".pdf")
        else "text/plain",
    )
