"""Agrégation de caisse : totaux, ventilation par mode et par employé (§3.4)."""
from dataclasses import dataclass

from beanie import PydanticObjectId

from app.models.enums import PaymentMethod
from app.services.cash_service import _aggregate

AHMED = PydanticObjectId()
YOUSSEF = PydanticObjectId()


@dataclass
class FakeTx:
    """Substitut de Transaction : l'agrégation est purement structurelle, pas ORM."""
    staff_id: PydanticObjectId
    amount: float
    salon_share: float
    staff_share: float
    method: str
    tip: float = 0.0


def tx(staff_id, amount, salon_share, staff_share, method, tip=0.0) -> FakeTx:
    return FakeTx(staff_id, amount, salon_share, staff_share, method.value, tip)


JOURNEE = [
    tx(AHMED, 15, 7.5, 7.5, PaymentMethod.CASH),
    tx(AHMED, 25, 12.5, 12.5, PaymentMethod.CARD, tip=3),
    tx(YOUSSEF, 22, 9.9, 12.1, PaymentMethod.CASH),
    tx(YOUSSEF, 10, 4.5, 5.5, PaymentMethod.ONLINE, tip=2),
]


def test_totaux_de_la_journee():
    result = _aggregate(JOURNEE)
    assert result["transaction_count"] == 4
    assert result["total"] == 72.0
    assert result["salon_total"] == 34.4
    assert result["staff_total"] == 37.6
    assert result["tips_total"] == 5.0


def test_le_total_se_repartit_integralement():
    result = _aggregate(JOURNEE)
    assert round(result["salon_total"] + result["staff_total"], 2) == result["total"]


def test_ventilation_par_mode_de_paiement():
    result = _aggregate(JOURNEE)
    assert result["by_method"] == {"cash": 37.0, "card": 25.0, "online": 10.0}
    assert round(sum(result["by_method"].values()), 2) == result["total"]


def test_detail_par_employe():
    result = _aggregate(JOURNEE)
    ahmed = result["by_staff"][str(AHMED)]
    assert ahmed["count"] == 2
    assert ahmed["gross"] == 40.0
    assert ahmed["staff_share"] == 20.0
    assert ahmed["tips"] == 3.0

    youssef = result["by_staff"][str(YOUSSEF)]
    assert youssef["count"] == 2
    assert youssef["staff_share"] == 17.6


def test_journee_vide():
    result = _aggregate([])
    assert result == {
        "transaction_count": 0,
        "total": 0,
        "salon_total": 0,
        "staff_total": 0,
        "tips_total": 0,
        # Pourboires gardés par le salon : nuls tant qu'il les laisse à
        # l'équipe, ce qui est le réglage par défaut.
        "salon_tips_total": 0,
        "by_method": {},
        "by_staff": {},
    }
