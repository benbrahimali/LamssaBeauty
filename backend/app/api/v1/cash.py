"""Caisse (§3.4) — cœur différenciant : split, dépenses, clôture, rapports."""
import os
from datetime import date, datetime

from beanie import PydanticObjectId
from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import FileResponse

from app.core.deps import my_staff_profile
from app.core.security import require_role
from app.core.timeutils import local_day_bounds, local_month_bounds, local_week_bounds, to_local, utcnow
from app.models.documents import (
    CashClosure,
    CashMovement,
    Expense,
    RecurringCharge,
    Salon,
    StaffMember,
    User,
)
from app.models.enums import NotificationType, Role
from app.schemas.cash import (
    CashMovementCreate,
    ClosureCreate,
    ExpenseCreate,
    RecurringChargeCreate,
    RecurringChargeUpdate,
)
from app.services.cash_service import (
    DAYS_PER_MONTH,
    close_day,
    daily_cost,
    day_summary,
    monthly_report,
    payroll,
    pilot,
    profit_and_loss,
    staff_day_summary,
    staff_month_balance,
    treasury,
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


@router.get("/pnl", summary="Compte de résultat du salon sur une période")
async def salon_pnl(
    salon_id: PydanticObjectId,
    start: date | None = None,
    end: date | None = None,
    user: User = Depends(require_role(Role.OWNER)),
):
    """Ce qu'il reste au salon une fois l'équipe payée et les charges couvertes.

    Par défaut, le mois en cours : c'est la maille sur laquelle un loyer et des
    salaires ont un sens. Les charges fixes sont comptées au prorata des jours
    de la période — sinon la semaine où tombe le loyer paraîtrait
    catastrophique et les trois autres, excellentes.
    """
    salon = await _my_salon(salon_id, user)
    now = to_local(utcnow())
    if start and end:
        debut, _ = local_day_bounds(start)
        _, fin = local_day_bounds(end)
    else:
        debut, fin = local_month_bounds(now.year, now.month)

    return await profit_and_loss(salon.id, debut, fin)


@router.get("/pilot", summary="Pilotage : seuil de rentabilité et objectif")
async def salon_pilot(
    salon_id: PydanticObjectId,
    start: date | None = None,
    end: date | None = None,
    user: User = Depends(require_role(Role.OWNER)),
):
    """Le compte de résultat, plus les repères qui lui donnent un sens.

    Un résultat seul ne dit pas s'il est bon. Le seuil de rentabilité dit à
    partir de combien le salon gagne de l'argent, et la projection dit si le
    rythme actuel suffira d'ici la fin de la période.
    """
    salon = await _my_salon(salon_id, user)
    now = to_local(utcnow())
    if start and end:
        debut, _ = local_day_bounds(start)
        _, fin = local_day_bounds(end)
    else:
        debut, fin = local_month_bounds(now.year, now.month)

    return await pilot(salon, debut, fin)


# ─────────────────────────────────────────────────────────────────────────────
# Charges fixes du salon (§3.4)
# ─────────────────────────────────────────────────────────────────────────────
@router.get("/charges", summary="Charges fixes du salon")
async def list_charges(
    salon_id: PydanticObjectId,
    include_inactive: bool = False,
    user: User = Depends(require_role(Role.OWNER)),
):
    salon = await _my_salon(salon_id, user)
    query: dict = {"salon_id": salon.id}
    if not include_inactive:
        query["active"] = True
    charges = await RecurringCharge.find(query).sort("-amount").to_list()

    # Le total mensuel équivalent est le chiffre que le gérant a en tête :
    # « il me faut tant par mois avant de gagner quoi que ce soit ».
    mensuel = round(
        sum(daily_cost(c.amount, c.period) * DAYS_PER_MONTH for c in charges), 2
    )
    return {"charges": charges, "monthly_equivalent": mensuel}


@router.post("/charges", status_code=201, summary="Ajouter une charge fixe")
async def create_charge(
    body: RecurringChargeCreate,
    salon_id: PydanticObjectId,
    user: User = Depends(require_role(Role.OWNER)),
):
    salon = await _my_salon(salon_id, user)
    charge = RecurringCharge(salon_id=salon.id, **body.model_dump())
    await charge.insert()
    return charge


@router.patch("/charges/{charge_id}", summary="Modifier une charge fixe")
async def update_charge(
    charge_id: PydanticObjectId,
    body: RecurringChargeUpdate,
    user: User = Depends(require_role(Role.OWNER)),
):
    charge = await RecurringCharge.get(charge_id)
    if not charge:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Charge introuvable")
    await _my_salon(charge.salon_id, user)

    data = body.model_dump(exclude_none=True)
    for champ, valeur in data.items():
        setattr(charge, champ, valeur)
    if data.get("active") is False and charge.ended_at is None:
        # Date de fin posée à la désactivation : les périodes antérieures
        # continuent de compter la charge, les suivantes non.
        charge.ended_at = utcnow()
    elif data.get("active") is True:
        charge.ended_at = None
    await charge.save()
    return charge


@router.delete("/charges/{charge_id}", summary="Supprimer une charge fixe")
async def delete_charge(
    charge_id: PydanticObjectId, user: User = Depends(require_role(Role.OWNER))
):
    """Suppression définitive — à réserver aux saisies erronées.

    Pour une charge qui a réellement existé, la désactivation vaut mieux :
    elle garde les comptes des mois passés justes.
    """
    charge = await RecurringCharge.get(charge_id)
    if not charge:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Charge introuvable")
    await _my_salon(charge.salon_id, user)
    await charge.delete()
    return {"removed": str(charge_id)}


@router.get("/payroll", summary="Paie de la semaine, par coiffeur")
async def team_payroll(
    salon_id: PydanticObjectId,
    week_of: date | None = None,
    user: User = Depends(require_role(Role.OWNER)),
):
    """Ce que le gérant doit à chaque membre de son équipe cette semaine.

    Les tséb9as accordées sur la période sont déduites : c'est le montant réel
    à remettre en main propre, pas le brut gagné.
    """
    salon = await _my_salon(salon_id, user)
    start, end = local_week_bounds(week_of or to_local(utcnow()).date())
    members = await StaffMember.find(StaffMember.salon_id == salon.id).to_list()

    lignes = await payroll(
        staff_ids=[m.id for m in members],
        start=start,
        end=end,
        names={m.id: m.display_name for m in members},
    )
    return {
        "week_start": str(to_local(start).date()),
        "week_end": str(to_local(end).date()),
        "staff": lignes,
        "total_earned": round(sum(l["earned"] + l["tips"] for l in lignes), 2),
        "total_advances": round(sum(l["advances"] for l in lignes), 2),
        "total_to_pay": round(sum(l["balance"] for l in lignes), 2),
    }


@router.get("/me/payroll", summary="Ma paie de la semaine")
async def my_payroll(
    week_of: date | None = None,
    staff: StaffMember = Depends(my_staff_profile),
):
    """La même chose vue de l'employé : ce qu'il touchera en fin de semaine."""
    start, end = local_week_bounds(week_of or to_local(utcnow()).date())
    lignes = await payroll(
        staff_ids=[staff.id],
        start=start,
        end=end,
        names={staff.id: staff.display_name},
    )
    return {
        "week_start": str(to_local(start).date()),
        "week_end": str(to_local(end).date()),
        **lignes[0],
    }


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
        paid_from=body.paid_from,
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
# Trésorerie : l'état du tiroir (§3.4)
# ─────────────────────────────────────────────────────────────────────────────
@router.get("/treasury", summary="État de la caisse : espèces attendues et banque")
async def get_treasury(
    salon_id: PydanticObjectId,
    day: date | None = None,
    user: User = Depends(require_role(Role.OWNER)),
):
    """Ce que le tiroir devrait contenir, et le détail de chaque ligne.

    Réservé au gérant : le solde de caisse n'est pas une information d'équipe.
    """
    await _my_salon(salon_id, user)
    return await treasury(salon_id, day or to_local(utcnow()).date())


@router.post("/movements", status_code=201, summary="Fond de caisse, apport ou prélèvement")
async def create_movement(
    body: CashMovementCreate, user: User = Depends(require_role(Role.OWNER))
):
    await _my_salon(body.salon_id, user)
    day = body.day or to_local(utcnow()).date()

    # Une journée clôturée est arrêtée : la rouvrir par un mouvement rendrait
    # le rapport déjà signé faux.
    if await CashClosure.find_one(
        CashClosure.salon_id == body.salon_id, CashClosure.day == day
    ):
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            f"La journée du {day} est clôturée : aucun mouvement ne peut s'y ajouter",
        )

    movement = CashMovement(
        salon_id=body.salon_id,
        type=body.type,
        amount=round(body.amount, 2),
        label=body.label.strip(),
        day=day,
        created_by=user.id,
    )
    await movement.insert()
    return movement


@router.get("/movements", summary="Historique des mouvements d'espèces")
async def list_movements(
    salon_id: PydanticObjectId,
    day: date | None = None,
    user: User = Depends(require_role(Role.OWNER)),
):
    await _my_salon(salon_id, user)
    query = {"salon_id": salon_id}
    if day is not None:
        query["day"] = day
    return await CashMovement.find(query).sort("-created_at").limit(200).to_list()


@router.delete("/movements/{movement_id}", summary="Supprimer un mouvement")
async def delete_movement(
    movement_id: PydanticObjectId, user: User = Depends(require_role(Role.OWNER))
):
    movement = await CashMovement.get(movement_id)
    if not movement:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Mouvement introuvable")
    await _my_salon(movement.salon_id, user)
    if await CashClosure.find_one(
        CashClosure.salon_id == movement.salon_id, CashClosure.day == movement.day
    ):
        raise HTTPException(
            status.HTTP_409_CONFLICT, "Journée clôturée : le mouvement est figé"
        )
    await movement.delete()
    return {"removed": str(movement_id)}


# ─────────────────────────────────────────────────────────────────────────────
# Clôture de journée (§5.4)
# ─────────────────────────────────────────────────────────────────────────────
@router.post("/closures", status_code=201, summary="Clôturer la journée")
async def create_closure(
    body: ClosureCreate, user: User = Depends(require_role(Role.OWNER))
):
    salon = await _my_salon(body.salon_id, user)
    day = body.day or to_local(utcnow()).date()
    closure = await close_day(
        salon,
        day,
        user,
        counted_cash=body.counted_cash,
        withdrawal=body.withdrawal,
        variance_reason=body.variance_reason,
    )

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
