"""Le split est le cœur différenciant du produit : il doit être juste au centime."""
import pytest

from app.models.enums import CommissionType
from app.services.split_engine import SplitEngine


def test_split_50_50_exemple_du_cahier():
    """15 DT à 50 % -> 7,50 / 7,50 (§2.1)."""
    result = SplitEngine.compute(15, commission_pct=50)
    assert (result.salon_share, result.staff_share) == (7.5, 7.5)


def test_split_60_40():
    result = SplitEngine.compute(25, commission_pct=60)
    assert result.staff_share == 15.0
    assert result.salon_share == 10.0


def test_le_pourboire_ne_dilue_pas_la_part_salon():
    result = SplitEngine.compute(20, commission_pct=50, tip=5)
    assert result.salon_share == 10.0
    assert result.staff_share == 10.0
    assert result.staff_payout == 15.0


def test_fixe_plus_pourcentage():
    """10 DT garantis puis 50 % du reste sur une prestation de 30 DT."""
    result = SplitEngine.compute(
        30,
        commission_type=CommissionType.FIXED_PLUS_PERCENT,
        commission_pct=50,
        commission_fixed=10,
    )
    assert result.staff_share == 20.0
    assert result.salon_share == 10.0


def test_fixe_superieur_au_montant_est_plafonne():
    result = SplitEngine.compute(
        8,
        commission_type=CommissionType.FIXED_PLUS_PERCENT,
        commission_pct=50,
        commission_fixed=10,
    )
    assert result.staff_share == 8.0
    assert result.salon_share == 0.0


def test_salarie_le_salon_garde_tout():
    result = SplitEngine.compute(45, commission_type=CommissionType.SALON_KEEPS_ALL)
    assert result.staff_share == 0.0
    assert result.salon_share == 45.0


@pytest.mark.parametrize("amount", [12.0, 15.0, 22.5, 33.33, 350.0, 0.0])
@pytest.mark.parametrize("pct", [0, 33, 45, 50, 55, 100])
def test_les_parts_se_recomposent_toujours(amount, pct):
    result = SplitEngine.compute(amount, commission_pct=pct)
    assert round(result.salon_share + result.staff_share, 2) == round(amount, 2)


def test_montant_negatif_refuse():
    with pytest.raises(ValueError):
        SplitEngine.compute(-5, commission_pct=50)


def test_commission_hors_bornes_refusee():
    with pytest.raises(ValueError):
        SplitEngine.compute(10, commission_pct=120)
