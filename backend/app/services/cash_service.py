"""Module Caisse (§3.4) — agrégations, tséb9a, clôture de journée, P&L mensuel."""
from collections import defaultdict
from datetime import date

from beanie import PydanticObjectId
from fastapi import HTTPException, status
from pymongo.errors import DuplicateKeyError

from app.core.timeutils import local_day_bounds, local_month_bounds, utcnow
from app.models.documents import (
    Advance,
    CashClosure,
    Expense,
    Salon,
    StaffMember,
    Transaction,
    User,
)
from app.models.enums import AdvanceStatus


def _blank_staff_row() -> dict:
    return {"count": 0, "gross": 0.0, "staff_share": 0.0, "salon_share": 0.0, "tips": 0.0}


def _aggregate(transactions: list[Transaction]) -> dict:
    by_staff: dict[str, dict] = defaultdict(_blank_staff_row)
    by_method: dict[str, float] = defaultdict(float)

    for t in transactions:
        row = by_staff[str(t.staff_id)]
        row["count"] += 1
        row["gross"] = round(row["gross"] + t.amount, 2)
        row["staff_share"] = round(row["staff_share"] + t.staff_share, 2)
        row["salon_share"] = round(row["salon_share"] + t.salon_share, 2)
        row["tips"] = round(row["tips"] + t.tip, 2)
        by_method[t.method] = round(by_method[t.method] + t.amount, 2)

    return {
        "transaction_count": len(transactions),
        "total": round(sum(t.amount for t in transactions), 2),
        "salon_total": round(sum(t.salon_share for t in transactions), 2),
        "staff_total": round(sum(t.staff_share for t in transactions), 2),
        "tips_total": round(sum(t.tip for t in transactions), 2),
        "by_method": dict(by_method),
        "by_staff": dict(by_staff),
    }


async def _decorate_staff_names(by_staff: dict[str, dict]) -> dict[str, dict]:
    """Remplace les ObjectId nus par des lignes lisibles pour l'app pro."""
    if not by_staff:
        return by_staff
    ids = [PydanticObjectId(k) for k in by_staff]
    members = {m.id: m for m in await StaffMember.find({"_id": {"$in": ids}}).to_list()}
    # display_name est optionnel : on retombe sur le compte utilisateur si besoin.
    missing = [m.user_id for m in members.values() if not m.display_name]
    fallback = {
        u.id: (u.name or u.phone)
        for u in await User.find({"_id": {"$in": missing}}).to_list()
    } if missing else {}

    for staff_id, row in by_staff.items():
        member = members.get(PydanticObjectId(staff_id))
        row["name"] = (
            (member.display_name or fallback.get(member.user_id, "—")) if member else "—"
        )
        row["chair"] = member.chair_number if member else None
    return by_staff


async def day_summary(salon_id: PydanticObjectId, day: date) -> dict:
    """Caisse agrégée d'une journée : total, part salon, part équipe, cash/carte, par employé."""
    start, end = local_day_bounds(day)
    txs = await Transaction.find(
        Transaction.salon_id == salon_id,
        Transaction.paid_at >= start,
        Transaction.paid_at < end,
    ).to_list()

    summary = _aggregate(txs)
    summary["by_staff"] = await _decorate_staff_names(summary["by_staff"])
    summary["day"] = str(day)

    expenses = await Expense.find(
        Expense.salon_id == salon_id, Expense.spent_at >= start, Expense.spent_at < end
    ).to_list()
    summary["expenses_total"] = round(sum(e.amount for e in expenses), 2)
    summary["net_salon"] = round(summary["salon_total"] - summary["expenses_total"], 2)

    pending = await Advance.find(
        Advance.salon_id == salon_id, Advance.status == AdvanceStatus.PENDING
    ).to_list()
    summary["advances_pending"] = round(sum(a.amount for a in pending), 2)
    summary["advances_pending_count"] = len(pending)

    closure = await CashClosure.find_one(
        CashClosure.salon_id == salon_id, CashClosure.day == day
    )
    summary["closed"] = closure is not None
    summary["closure_id"] = str(closure.id) if closure else None
    return summary


async def staff_day_summary(staff: StaffMember, day: date) -> dict:
    """Vue coiffeur (§3.4) : SES services, SES gains, SES pourboires — rien d'autre."""
    start, end = local_day_bounds(day)
    txs = await Transaction.find(
        Transaction.staff_id == staff.id,
        Transaction.paid_at >= start,
        Transaction.paid_at < end,
    ).sort("-paid_at").to_list()

    advances = await Advance.find(
        Advance.staff_id == staff.id,
        {"status": {"$in": [AdvanceStatus.PENDING, AdvanceStatus.APPROVED]}},
    ).to_list()

    return {
        "day": str(day),
        "count": len(txs),
        "gross": round(sum(t.amount for t in txs), 2),
        "my_share": round(sum(t.staff_share for t in txs), 2),
        "tips": round(sum(t.tip for t in txs), 2),
        "payout": round(sum(t.staff_share + t.tip for t in txs), 2),
        "advances_outstanding": round(
            sum(a.amount for a in advances if a.status is AdvanceStatus.APPROVED), 2
        ),
        "advances_pending": round(
            sum(a.amount for a in advances if a.status is AdvanceStatus.PENDING), 2
        ),
        "transactions": txs,
    }


async def close_day(salon: Salon, day: date, actor: User) -> CashClosure:
    """Clôture : agrège, déduit les tséb9as approuvées, verrouille les transactions (§5.4)."""
    if await CashClosure.find_one(CashClosure.salon_id == salon.id, CashClosure.day == day):
        raise HTTPException(status.HTTP_409_CONFLICT, f"La journée du {day} est déjà clôturée")

    start, end = local_day_bounds(day)
    txs = await Transaction.find(
        Transaction.salon_id == salon.id,
        Transaction.paid_at >= start,
        Transaction.paid_at < end,
    ).to_list()
    summary = _aggregate(txs)

    expenses = await Expense.find(
        Expense.salon_id == salon.id, Expense.spent_at >= start, Expense.spent_at < end
    ).to_list()
    expenses_total = round(sum(e.amount for e in expenses), 2)

    # Tséb9as approuvées et non encore réglées : on les impute à cette clôture.
    advances = await Advance.find(
        Advance.salon_id == salon.id,
        Advance.status == AdvanceStatus.APPROVED,
        Advance.requested_at < end,
    ).to_list()

    by_staff = summary["by_staff"]
    for adv in advances:
        row = by_staff.setdefault(str(adv.staff_id), _blank_staff_row())
        row["advance_deducted"] = round(row.get("advance_deducted", 0.0) + adv.amount, 2)
    for row in by_staff.values():
        deducted = row.get("advance_deducted", 0.0)
        row["net_payout"] = round(row["staff_share"] + row["tips"] - deducted, 2)

    advances_total = round(sum(a.amount for a in advances), 2)
    closure = CashClosure(
        salon_id=salon.id,
        day=day,
        total=summary["total"],
        salon_total=summary["salon_total"],
        staff_total=summary["staff_total"],
        tips_total=summary["tips_total"],
        expenses_total=expenses_total,
        advances_deducted=advances_total,
        net_salon=round(summary["salon_total"] - expenses_total, 2),
        by_method=summary["by_method"],
        by_staff=await _decorate_staff_names(by_staff),
        transaction_count=summary["transaction_count"],
        created_by=actor.id,
    )
    try:
        await closure.insert()
    except DuplicateKeyError:
        raise HTTPException(status.HTTP_409_CONFLICT, f"La journée du {day} est déjà clôturée")

    # Verrouillage : plus aucune modification possible sur ces transactions.
    if txs:
        await Transaction.find({"_id": {"$in": [t.id for t in txs]}}).update(
            {"$set": {"closed": True, "closure_id": closure.id}}
        )
    if advances:
        await Advance.find({"_id": {"$in": [a.id for a in advances]}}).update(
            {
                "$set": {
                    "status": AdvanceStatus.SETTLED,
                    "settled_at": utcnow(),
                    "settled_closure_id": closure.id,
                }
            }
        )
    return closure


async def monthly_report(salon_id: PydanticObjectId, year: int, month: int) -> dict:
    """P&L mensuel simple (§3.4) : CA, part salon, dépenses, résultat."""
    start, end = local_month_bounds(year, month)
    txs = await Transaction.find(
        Transaction.salon_id == salon_id,
        Transaction.paid_at >= start,
        Transaction.paid_at < end,
    ).to_list()
    expenses = await Expense.find(
        Expense.salon_id == salon_id, Expense.spent_at >= start, Expense.spent_at < end
    ).to_list()

    summary = _aggregate(txs)
    summary["by_staff"] = await _decorate_staff_names(summary["by_staff"])

    by_category: dict[str, float] = defaultdict(float)
    for e in expenses:
        by_category[e.category] = round(by_category[e.category] + e.amount, 2)
    expenses_total = round(sum(e.amount for e in expenses), 2)

    return {
        "period": f"{year}-{month:02d}",
        **summary,
        "expenses_total": expenses_total,
        "expenses_by_category": dict(by_category),
        "result": round(summary["salon_total"] - expenses_total, 2),
        "days_closed": await CashClosure.find(
            CashClosure.salon_id == salon_id,
            CashClosure.day >= start.date(),
            CashClosure.day < end.date(),
        ).count(),
    }


async def staff_month_balance(staff: StaffMember, year: int, month: int) -> dict:
    """Solde mensuel d'un employé, avances déduites — la base de sa paie."""
    start, end = local_month_bounds(year, month)
    txs = await Transaction.find(
        Transaction.staff_id == staff.id,
        Transaction.paid_at >= start,
        Transaction.paid_at < end,
    ).to_list()
    advances = await Advance.find(
        Advance.staff_id == staff.id,
        {"status": {"$in": [AdvanceStatus.APPROVED, AdvanceStatus.SETTLED]}},
        Advance.requested_at >= start,
        Advance.requested_at < end,
    ).to_list()

    earned = round(sum(t.staff_share for t in txs), 2)
    tips = round(sum(t.tip for t in txs), 2)
    advanced = round(sum(a.amount for a in advances), 2)
    return {
        "period": f"{year}-{month:02d}",
        "services": len(txs),
        "gross": round(sum(t.amount for t in txs), 2),
        "earned": earned,
        "tips": tips,
        "advances": advanced,
        "balance": round(earned + tips - advanced, 2),
    }
