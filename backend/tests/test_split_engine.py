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


# ── Coût produit retenu avant partage (§3.4) ─────────────────────────────────
def test_le_cout_produit_est_retenu_avant_le_partage():
    """Sur une couleur, le salon achète le produit seul.

    Partager le prix brut lui ferait payer la moitié d'un produit qu'il a
    avancé : l'employé toucherait 25 sur une couleur à 50 dont 12 de produit,
    alors que le salon n'aurait encaissé que 38 nets.
    """
    r = SplitEngine.compute(50, commission_pct=50, product_cost=12)

    assert r.staff_share == 19.0, "la moitié de 38, pas de 50"
    assert r.salon_share == 31.0, "19 de marge + 12 de produit avancé"
    assert r.product_cost == 12.0


def test_sans_cout_produit_le_calcul_ne_change_pas():
    """Garde-fou : la nouveauté ne doit rien modifier pour les salons qui
    n'en déclarent pas."""
    avec = SplitEngine.compute(50, commission_pct=50, product_cost=0)
    sans = SplitEngine.compute(50, commission_pct=50)
    assert avec.staff_share == sans.staff_share == 25.0


def test_un_produit_plus_cher_que_la_prestation_ne_laisse_rien_a_partager():
    """Cas limite d'une saisie erronée : le résultat doit rester cohérent."""
    r = SplitEngine.compute(20, commission_pct=50, product_cost=35)

    assert r.staff_share == 0.0
    assert r.salon_share == 20.0
    assert r.product_cost == 20.0, "on ne retient pas plus que le prix payé"


def test_la_part_fixe_se_calcule_aussi_apres_le_produit():
    """Sinon un employé garanti à 10 DT toucherait plus que ce que la
    prestation a rapporté au salon."""
    r = SplitEngine.compute(
        30,
        commission_type=CommissionType.FIXED_PLUS_PERCENT,
        commission_fixed=10,
        commission_pct=50,
        product_cost=20,
    )
    # Base de 10 : la part fixe l'absorbe entièrement.
    assert r.staff_share == 10.0
    assert r.salon_share == 20.0


def test_un_cout_produit_negatif_est_refuse():
    with pytest.raises(ValueError):
        SplitEngine.compute(50, product_cost=-5)


# ── Politique de pourboire ───────────────────────────────────────────────────
def test_par_defaut_le_pourboire_revient_entierement_a_l_employe():
    r = SplitEngine.compute(40, commission_pct=50, tip=10)
    assert r.tip == 10.0
    assert r.salon_tip == 0.0


def test_un_salon_peut_mettre_les_pourboires_en_commun():
    """Certains salons les partagent : la règle appartient au gérant."""
    r = SplitEngine.compute(40, commission_pct=50, tip=10, tip_staff_pct=0)
    assert r.tip == 0.0
    assert r.salon_tip == 10.0


def test_le_pourboire_peut_etre_partage():
    r = SplitEngine.compute(40, commission_pct=50, tip=10, tip_staff_pct=60)
    assert r.tip == 6.0
    assert r.salon_tip == 4.0


def test_le_pourboire_n_entre_jamais_dans_le_split_de_la_prestation():
    """Il s'ajoute, il ne se commissionne pas."""
    sans = SplitEngine.compute(40, commission_pct=50)
    avec = SplitEngine.compute(40, commission_pct=50, tip=10)
    assert avec.staff_share == sans.staff_share
    assert avec.salon_share == sans.salon_share


def test_une_part_de_pourboire_hors_bornes_est_refusee():
    with pytest.raises(ValueError):
        SplitEngine.compute(40, tip=10, tip_staff_pct=120)


# ── Priorité des règles ──────────────────────────────────────────────────────
class _Objet:
    def __init__(self, **kw):
        self.__dict__.update(kw)


def test_le_taux_du_service_prime_sur_celui_du_coiffeur():
    """Une couleur laisse moins de marge : le salon la commissionne à part."""
    staff = _Objet(commission_pct=50)
    service = _Objet(commission_pct=35, product_cost=0)
    assert SplitEngine.rate_for(staff, service) == 35


def test_sans_taux_de_service_on_retombe_sur_le_coiffeur():
    staff = _Objet(commission_pct=45)
    service = _Objet(commission_pct=None, product_cost=0)
    assert SplitEngine.rate_for(staff, service) == 45


def test_sans_coiffeur_ni_service_le_salon_fait_foi():
    salon = _Objet(default_split_pct=40)
    assert SplitEngine.rate_for(None, None, salon) == 40


def test_la_regle_du_salon_se_lit_de_bout_en_bout():
    """Cas complet : couleur à 60 DT, 15 de produit, commissionnée à 35 %."""
    staff = _Objet(
        commission_pct=50,
        commission_type=CommissionType.PERCENT,
        commission_fixed=0,
    )
    service = _Objet(commission_pct=35, product_cost=15)
    salon = _Objet(default_split_pct=50, tip_staff_pct=100)

    r = SplitEngine.for_staff(60, staff, tip=5, service=service, salon=salon)
    assert r.staff_share == 15.75, "35 % de 45"
    assert r.salon_share == 44.25
    assert r.tip == 5.0
