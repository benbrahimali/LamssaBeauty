"""Module Caisse (§3.4) — agrégations, tséb9a, clôture de journée, P&L mensuel."""
from collections import defaultdict
from datetime import date, datetime

from beanie import PydanticObjectId
from fastapi import HTTPException, status
from pymongo.errors import DuplicateKeyError

from app.core.timeutils import local_day_bounds, local_month_bounds, utcnow
from app.models.documents import (
    Advance,
    CashClosure,
    CashMovement,
    Expense,
    RecurringCharge,
    Salon,
    StaffMember,
    Transaction,
    User,
)
from app.models.enums import (
    AdvanceStatus,
    CashMovementType,
    ChargePeriod,
    PaymentMethod,
    PaymentSource,
)


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
        # Pourboires gardés par le salon : nuls tant qu'il les laisse à
        # l'équipe, ce qui reste le cas par défaut.
        "salon_tips_total": round(
            sum(getattr(t, "salon_tip", 0.0) for t in transactions), 2
        ),
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


def drawer_balance(
    opening: float,
    cash_in: float,
    deposits: float,
    cash_expenses: float,
    cash_advances: float,
    withdrawals: float,
) -> float:
    """Ce que le tiroir devrait contenir, à partir de ses seules causes.

    Isolé du stockage pour rester vérifiable : c'est le chiffre que le gérant
    va comparer à ce qu'il compte à la main, et il n'a droit à aucune
    approximation.
    """
    return round(
        opening + cash_in + deposits - cash_expenses - cash_advances - withdrawals, 2
    )


async def opening_float(salon_id: PydanticObjectId, day: date) -> float:
    """Ce que le tiroir contenait en ouvrant.

    Le gérant peut l'avoir déclaré ; sinon c'est ce qu'il a laissé en fermant
    la veille. À défaut de tout historique, zéro — un fond de caisse inventé
    fausserait le premier écart constaté.
    """
    declared = await CashMovement.find(
        CashMovement.salon_id == salon_id,
        CashMovement.day == day,
        CashMovement.type == CashMovementType.OPENING_FLOAT,
    ).sort("-created_at").first_or_none()
    if declared is not None:
        return round(declared.amount, 2)

    previous = await CashClosure.find(
        CashClosure.salon_id == salon_id, CashClosure.day < day
    ).sort("-day").first_or_none()
    return round(previous.closing_float, 2) if previous else 0.0


async def treasury(salon_id: PydanticObjectId, day: date) -> dict:
    """État du tiroir pour une journée : ce qui doit s'y trouver, et pourquoi.

    Espèces et banque sont tenues séparément : une carte bancaire ne remplit
    pas le tiroir, et les confondre est la première cause d'écart inexpliqué à
    la clôture.
    """
    start, end = local_day_bounds(day)

    txs = await Transaction.find(
        Transaction.salon_id == salon_id,
        Transaction.paid_at >= start,
        Transaction.paid_at < end,
    ).to_list()

    # Le client règle la prestation ET le pourboire : les deux entrent dans le
    # tiroir. La part du coiffeur y dort jusqu'à la paie.
    def encaisse(t: Transaction) -> float:
        return t.amount + t.tip + getattr(t, "salon_tip", 0.0)

    cash_in = round(
        sum(encaisse(t) for t in txs if t.method == PaymentMethod.CASH), 2
    )
    card_total = round(
        sum(encaisse(t) for t in txs if t.method == PaymentMethod.CARD), 2
    )
    online_total = round(
        sum(encaisse(t) for t in txs if t.method == PaymentMethod.ONLINE), 2
    )

    expenses = await Expense.find(
        Expense.salon_id == salon_id, Expense.spent_at >= start, Expense.spent_at < end
    ).to_list()
    cash_expenses = round(
        sum(e.amount for e in expenses if e.paid_from == PaymentSource.CASH), 2
    )
    bank_expenses = round(
        sum(e.amount for e in expenses if e.paid_from == PaymentSource.BANK), 2
    )

    # Une tséb9a sort du tiroir le jour où elle est accordée, pas le jour où
    # elle est demandée.
    advances = await Advance.find(
        Advance.salon_id == salon_id,
        Advance.status != AdvanceStatus.PENDING,
        Advance.status != AdvanceStatus.REJECTED,
        Advance.decided_at >= start,
        Advance.decided_at < end,
    ).to_list()
    cash_advances = round(
        sum(a.amount for a in advances if a.paid_from == PaymentSource.CASH), 2
    )

    movements = await CashMovement.find(
        CashMovement.salon_id == salon_id, CashMovement.day == day
    ).sort("created_at").to_list()
    deposits = round(
        sum(m.amount for m in movements if m.type == CashMovementType.DEPOSIT), 2
    )
    withdrawals = round(
        sum(m.amount for m in movements if m.type == CashMovementType.WITHDRAWAL), 2
    )

    ouverture = await opening_float(salon_id, day)
    attendu = drawer_balance(
        ouverture, cash_in, deposits, cash_expenses, cash_advances, withdrawals
    )

    closure = await CashClosure.find_one(
        CashClosure.salon_id == salon_id, CashClosure.day == day
    )

    return {
        "day": day.isoformat(),
        "opening_float": ouverture,
        "cash_in": cash_in,
        "deposits": deposits,
        "cash_expenses": cash_expenses,
        "cash_advances": cash_advances,
        "withdrawals": withdrawals,
        "expected_cash": attendu,
        # Côté banque : ce que le TPE et le PSP doivent verser, moins ce qui a
        # été réglé par virement. Ne touche jamais le tiroir.
        "card_total": card_total,
        "online_total": online_total,
        "bank_expenses": bank_expenses,
        "bank_total": round(card_total + online_total - bank_expenses, 2),
        "movements": [
            {
                "id": str(m.id),
                "type": m.type,
                "amount": round(m.amount, 2),
                "label": m.label,
                "created_at": m.created_at,
            }
            for m in movements
        ],
        "closed": closure is not None,
        "counted_cash": closure.counted_cash if closure else None,
        "cash_variance": closure.cash_variance if closure else 0.0,
        "variance_reason": closure.variance_reason if closure else "",
        "closing_float": closure.closing_float if closure else 0.0,
    }


async def close_day(
    salon: Salon,
    day: date,
    actor: User,
    counted_cash: float | None = None,
    withdrawal: float = 0.0,
    variance_reason: str = "",
) -> CashClosure:
    """Clôture : agrège, déduit les tséb9as, verrouille les transactions (§5.4).

    Le comptage du tiroir est facultatif : beaucoup de gérants ferment sans
    compter, et un `counted_cash` inventé afficherait un écart nul mensonger.
    Quand le comptage a lieu, c'est lui qui fait foi — l'écart est enregistré
    tel quel plutôt que corrigé en silence, et c'est le montant compté, non le
    théorique, qui devient le fond de caisse du lendemain.
    """
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

    tresor = await treasury(salon.id, day)
    attendu = tresor["expected_cash"]
    reel = round(counted_cash, 2) if counted_cash is not None else None
    ecart = round(reel - attendu, 2) if reel is not None else 0.0

    # Le fond de caisse du lendemain, c'est ce qui reste réellement dans le
    # tiroir une fois le prélèvement du soir retiré.
    en_caisse = reel if reel is not None else attendu
    withdrawal = round(max(withdrawal, 0.0), 2)
    if withdrawal > en_caisse:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            f"Prélèvement de {withdrawal:.2f} DT impossible : "
            f"la caisse ne contient que {en_caisse:.2f} DT",
        )

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
        opening_float=tresor["opening_float"],
        expected_cash=attendu,
        counted_cash=reel,
        cash_variance=ecart,
        variance_reason=variance_reason.strip(),
        withdrawal=withdrawal,
        closing_float=round(en_caisse - withdrawal, 2),
        bank_total=tresor["bank_total"],
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


#: Jours moyens d'un mois et d'une année, décimales comprises : utiliser 30 et
#: 365 ferait dériver le prorata de 6 jours par an, soit un loyer sous-compté.
DAYS_PER_MONTH = 365.25 / 12
DAYS_PER_YEAR = 365.25


def daily_cost(amount: float, period: ChargePeriod) -> float:
    """Coût journalier d'une charge, quel que soit son rythme.

    Ramener toutes les charges au jour est ce qui rend les périodes
    comparables : sans ça, la semaine où le loyer tombe paraîtrait
    catastrophique et les trois autres, excellentes.
    """
    match period:
        case ChargePeriod.WEEKLY:
            return amount / 7
        case ChargePeriod.YEARLY:
            return amount / DAYS_PER_YEAR
        case _:
            return amount / DAYS_PER_MONTH


async def profit_and_loss(
    salon_id: PydanticObjectId, start: datetime, end: datetime
) -> dict:
    """Compte de résultat du salon sur une période (§3.4).

    Ce que la caisse du jour ne dit pas : elle montre ce qui est entré, pas ce
    qu'il reste une fois l'équipe payée et les charges fixes couvertes.

    Les pourboires sont exclus du résultat. Ils transitent par la caisse quand
    le client paie par carte, mais ils appartiennent à l'employé : les compter
    en revenu gonflerait artificiellement le résultat du salon.
    """
    txs = await Transaction.find(
        {"salon_id": salon_id, "paid_at": {"$gte": start, "$lt": end}}
    ).to_list()
    expenses = await Expense.find(
        {"salon_id": salon_id, "spent_at": {"$gte": start, "$lt": end}}
    ).to_list()
    charges = await RecurringCharge.find(
        {
            "salon_id": salon_id,
            "active": True,
            "started_at": {"$lt": end},
            "$or": [{"ended_at": None}, {"ended_at": {"$gte": start}}],
        }
    ).to_list()

    jours = max((end - start).total_seconds() / 86400, 0.0)

    revenus = round(sum(t.amount for t in txs), 2)
    part_equipe = round(sum(t.staff_share for t in txs), 2)
    pourboires = round(sum(t.tip for t in txs), 2)
    # Un salon qui met les pourboires en commun les encaisse réellement : les
    # ignorer sous-estimerait son résultat.
    pourboires_salon = round(sum(getattr(t, "salon_tip", 0.0) for t in txs), 2)
    marge = round(revenus - part_equipe + pourboires_salon, 2)

    par_categorie: dict[str, float] = {}
    for e in expenses:
        par_categorie[e.category] = round(
            par_categorie.get(e.category, 0.0) + e.amount, 2
        )

    lignes_charges = []
    for c in charges:
        montant = round(daily_cost(c.amount, c.period) * jours, 2)
        par_categorie[c.category] = round(par_categorie.get(c.category, 0.0) + montant, 2)
        lignes_charges.append(
            {
                "id": str(c.id),
                "label": c.label,
                "category": c.category,
                "period": c.period.value,
                "amount": c.amount,
                "prorated": montant,
            }
        )

    depenses = round(sum(e.amount for e in expenses), 2)
    charges_total = round(sum(l["prorated"] for l in lignes_charges), 2)
    resultat = round(marge - depenses - charges_total, 2)

    return {
        "start": start.isoformat(),
        "end": end.isoformat(),
        "days": round(jours, 2),
        "revenue": revenus,
        "staff_share": part_equipe,
        "gross_margin": marge,
        "expenses": depenses,
        "recurring_charges": charges_total,
        "result": resultat,
        # Un résultat sans son taux ne dit pas s'il est bon : 500 DT sur
        # 10 000 de chiffre n'a rien à voir avec 500 sur 1 500.
        "margin_pct": round(100 * resultat / revenus, 1) if revenus else 0.0,
        "tips_collected": pourboires,
        "salon_tips": pourboires_salon,
        "by_category": dict(sorted(par_categorie.items(), key=lambda kv: -kv[1])),
        "charges": lignes_charges,
        "transaction_count": len(txs),
    }


async def pilot(
    salon,
    start: datetime,
    end: datetime,
    now: datetime | None = None,
) -> dict:
    """Pilotage : où en est le salon par rapport à son seuil et à son objectif.

    Le seuil de rentabilité dépend de ce que le salon reverse à son équipe.
    À 50 % de commission, chaque dinar encaissé n'en laisse que 50 centimes
    pour couvrir le loyer : il faut donc encaisser le double des charges. Un
    salon qui emploie des salariés — commission nulle — atteint son seuil bien
    plus tôt. C'est pour ça qu'aucun seuil universel n'aurait de sens.
    """
    compte = await profit_and_loss(salon.id, start, end)

    # Charges fixes ET dépenses ponctuelles : un séchoir acheté ce mois-ci est
    # un coût à couvrir au même titre que le loyer. Ne compter que les charges
    # récurrentes annoncerait un seuil déjà atteint alors qu'il ne l'est pas.
    charges_periode = compte["expenses"] + compte["recurring_charges"]
    revenus = compte["revenue"]

    # Part reversée à l'équipe, mesurée sur la période. Sans activité, on
    # retombe sur le partage par défaut du salon : c'est ce qu'il applique.
    part_equipe = (
        compte["staff_share"] / revenus if revenus > 0 else salon.default_split_pct / 100
    )
    marge_unitaire = 1 - part_equipe

    # Marge nulle ou négative : aucun volume ne couvrirait les charges. Le dire
    # vaut mieux qu'afficher un seuil astronomique ou une division par zéro.
    seuil = (
        round(charges_periode / marge_unitaire, 2)
        if marge_unitaire > 0.01 and charges_periode > 0
        else None
    )

    maintenant = now or utcnow()
    jours_total = max((end - start).total_seconds() / 86400, 0.0)
    jours_ecoules = min(max((maintenant - start).total_seconds() / 86400, 0.0), jours_total)

    # Projection au rythme observé. Sous un jour de recul, elle dirait
    # n'importe quoi : une grosse matinée annoncerait un mois record.
    projection = (
        round(revenus * jours_total / jours_ecoules, 2) if jours_ecoules >= 1 else None
    )

    objectif = salon.monthly_revenue_target or 0.0

    return {
        **compte,
        "break_even": seuil,
        "break_even_reached": seuil is not None and revenus >= seuil,
        "missing_to_break_even": round(max(seuil - revenus, 0), 2) if seuil else None,
        "staff_ratio": round(part_equipe * 100, 1),
        # Règles de rémunération en vigueur : l'app les affiche et les édite
        # depuis le même écran que le résultat, puisqu'elles le déterminent.
        "tip_staff_pct": getattr(salon, "tip_staff_pct", 100.0),
        "default_split_pct": salon.default_split_pct,
        "target": objectif or None,
        "target_progress_pct": round(100 * revenus / objectif, 1) if objectif else None,
        "projected_revenue": projection,
        "days_elapsed": round(jours_ecoules, 1),
        "days_total": round(jours_total, 1),
        # Le rythme suffit-il ? Comparer le réalisé à ce qu'il faudrait avoir
        # atteint à cette date, plutôt qu'à l'objectif entier.
        "on_track": (
            None
            if not objectif or jours_ecoules < 1
            else revenus >= objectif * jours_ecoules / jours_total
        ),
    }


async def payroll(
    *,
    staff_ids: list[PydanticObjectId],
    start: datetime,
    end: datetime,
    names: dict[PydanticObjectId, str] | None = None,
) -> list[dict]:
    """Ce que chaque coiffeur a gagné sur la période, tséb9as déduites (§3.4).

    C'est le document que le gérant a réellement en main le jour de la paie :
    ce qui a été encaissé, la part de l'employé, ses pourboires, ce qu'il a
    déjà touché en avance, et le reste à lui donner.

    Les tséb9as comptées sont les approuvées **et** les soldées : une avance
    déjà déduite lors d'une clôture doit rester visible dans le décompte de la
    semaine, sinon le total ne correspond plus à ce qui est sorti de la caisse.
    """
    if not staff_ids:
        return []

    # Requêtes en dictionnaire plutôt qu'en expressions Beanie : ces dernières
    # exigent un modèle initialisé, ce qui rendrait l'agrégation — du calcul
    # d'argent — impossible à tester sans base.
    txs = await Transaction.find(
        {
            "staff_id": {"$in": staff_ids},
            "paid_at": {"$gte": start, "$lt": end},
        }
    ).to_list()
    advances = await Advance.find(
        {
            "staff_id": {"$in": staff_ids},
            "status": {"$in": [AdvanceStatus.APPROVED, AdvanceStatus.SETTLED]},
            "requested_at": {"$gte": start, "$lt": end},
        }
    ).to_list()

    lignes: dict[PydanticObjectId, dict] = {
        sid: {
            "staff_id": str(sid),
            "name": (names or {}).get(sid, ""),
            "services": 0,
            "gross": 0.0,
            "earned": 0.0,
            "tips": 0.0,
            "advances": 0.0,
        }
        for sid in staff_ids
    }

    for t in txs:
        ligne = lignes.get(t.staff_id)
        if ligne is None:
            continue
        ligne["services"] += 1
        ligne["gross"] += t.amount
        ligne["earned"] += t.staff_share
        ligne["tips"] += t.tip

    for a in advances:
        ligne = lignes.get(a.staff_id)
        if ligne is not None:
            ligne["advances"] += a.amount

    resultat = []
    for ligne in lignes.values():
        for cle in ("gross", "earned", "tips", "advances"):
            ligne[cle] = round(ligne[cle], 2)
        # Peut être négatif : un employé qui a pris plus d'avance qu'il n'a
        # gagné doit le voir, c'est précisément ce que la tséb9a rend possible.
        ligne["balance"] = round(ligne["earned"] + ligne["tips"] - ligne["advances"], 2)
        resultat.append(ligne)

    resultat.sort(key=lambda l: l["earned"], reverse=True)
    return resultat


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
