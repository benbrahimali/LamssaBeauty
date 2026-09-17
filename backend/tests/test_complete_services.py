"""Encaisser les prestations réellement faites (§3.4).

Le client ajoute une prestation sur place, ou l'une des prévues n'est pas faite :
le prix et le partage doivent porter sur ce qui a eu lieu, prestation par
prestation — une couleur ne se partage pas comme une coupe.
"""
from types import SimpleNamespace

import pytest
from bson import ObjectId
from pydantic import ValidationError

from app.api.v1.bookings import service_changes, services_change_note
from app.models.enums import CommissionType
from app.schemas.booking import BookingComplete
from app.services.split_engine import SplitEngine


def coiffeur(**kw):
    base = dict(commission_type=CommissionType.PERCENT, commission_pct=50.0, commission_fixed=0.0)
    base.update(kw)
    return SimpleNamespace(**base)


def prestation(prix, taux=None, produit=0.0):
    return SimpleNamespace(price=prix, commission_pct=taux, product_cost=produit)


SALON = SimpleNamespace(default_split_pct=50.0, tip_staff_pct=100.0)
COUPE = prestation(15)
COULEUR = prestation(50, taux=40, produit=12)


# ── Partage prestation par prestation ────────────────────────────────────────
def test_une_seule_prestation_se_partage_comme_avant():
    seule = SplitEngine.for_services(15, coiffeur(), [COUPE], salon=SALON)
    avant = SplitEngine.for_staff(15, coiffeur(), service=COUPE, salon=SALON)
    assert seule == avant


def test_chaque_prestation_applique_son_taux_et_son_produit():
    """Coupe 15 à 50 % : 7,50. Couleur 50, 12 de produit, 40 % : (50−12)×40 % = 15,20."""
    r = SplitEngine.for_services(65, coiffeur(), [COUPE, COULEUR], salon=SALON)

    assert r.staff_share == 22.7
    assert r.salon_share == 42.3
    assert r.product_cost == 12


def test_l_ordre_des_prestations_ne_change_pas_le_partage():
    a = SplitEngine.for_services(65, coiffeur(), [COUPE, COULEUR], salon=SALON)
    b = SplitEngine.for_services(65, coiffeur(), [COULEUR, COUPE], salon=SALON)
    assert a.staff_share == b.staff_share


def test_une_remise_se_repartit_au_prorata_des_prix():
    """52 DT au lieu de 65 (−20 %) : coupe 12, couleur 40."""
    r = SplitEngine.for_services(52, coiffeur(), [COUPE, COULEUR], salon=SALON)

    assert r.amount == 52
    assert r.staff_share == round(12 * 0.5 + (40 - 12) * 0.4, 2)
    assert round(r.salon_share + r.staff_share, 2) == 52, "aucun centime perdu"


def test_le_pourboire_n_est_compte_qu_une_fois():
    r = SplitEngine.for_services(65, coiffeur(), [COUPE, COULEUR], tip=10, salon=SALON)
    assert r.tip == 10
    assert r.salon_tip == 0


def test_en_fixe_plus_pourcentage_le_fixe_n_est_pas_multiplie():
    """Le fixe est une garantie par rendez-vous, pas par prestation."""
    employe = coiffeur(commission_type=CommissionType.FIXED_PLUS_PERCENT, commission_fixed=10.0)

    r = SplitEngine.for_services(30, employe, [prestation(15), prestation(15)], salon=SALON)

    assert r.staff_share == 10 + (30 - 10) * 0.5


def test_un_salarie_ne_touche_rien_sur_aucune_prestation():
    employe = coiffeur(commission_type=CommissionType.SALON_KEEPS_ALL)
    r = SplitEngine.for_services(65, employe, [COUPE, COULEUR], salon=SALON)
    assert r.staff_share == 0
    assert r.salon_share == 65


def test_des_prestations_gratuites_ne_divisent_pas_par_zero():
    r = SplitEngine.for_services(20, coiffeur(), [prestation(0), prestation(0)], salon=SALON)
    assert r.staff_share == 10


# ── Ce qui a changé ──────────────────────────────────────────────────────────
def test_une_prestation_ajoutee_sur_place():
    coupe, barbe = ObjectId(), ObjectId()
    assert service_changes([coupe], [coupe, barbe]) == ([barbe], [])


def test_une_prestation_pas_faite():
    a, b, c = ObjectId(), ObjectId(), ObjectId()
    assert service_changes([a, b, c], [a, c]) == ([], [b])


def test_une_prestation_remplacee():
    fade, coupe = ObjectId(), ObjectId()
    assert service_changes([fade], [coupe]) == ([coupe], [fade])


def test_rien_ne_change_si_seul_l_ordre_change():
    a, b = ObjectId(), ObjectId()
    assert service_changes([a, b], [b, a]) == ([], [])


def test_un_doublon_ne_compte_pas_comme_un_ajout():
    a = ObjectId()
    assert service_changes([a], [a, a]) == ([], [])


def test_la_note_dit_ce_qui_a_change():
    assert services_change_note(["Barbe"], ["Fade"]) == "prestations modifiées : + Barbe, − Fade"
    assert services_change_note([], []) == ""


# ── La demande ───────────────────────────────────────────────────────────────
def test_sans_liste_les_prestations_restent_celles_du_rdv():
    assert BookingComplete().service_ids is None


def test_une_liste_vide_est_refusee():
    """Un rendez-vous sans prestation faite s'annule, il ne s'encaisse pas à zéro."""
    with pytest.raises(ValidationError):
        BookingComplete(service_ids=[])
