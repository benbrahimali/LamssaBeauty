"""Paie versée aux coiffeurs (§3.4).

La paie était calculée mais jamais enregistrée comme versée : aucun historique,
et une paie en espèces ne sortait pas du tiroir. Ces règles se testent sans
base de données.
"""
import pytest
from bson import ObjectId
from pydantic import ValidationError

from app.api.v1.admin import HISTORIQUE
from app.models.documents import ALL_DOCUMENTS, StaffPayout
from app.models.enums import PaymentSource
from app.schemas.cash import StaffPayoutCreate
from app.services.cash_service import drawer_balance, payout_refusal, remaining_to_pay


# ── Ce qui reste à verser ────────────────────────────────────────────────────
def test_rien_verse_tout_reste_a_payer():
    assert remaining_to_pay(150.0, []) == 150.0


def test_une_paie_complete_ne_laisse_rien():
    assert remaining_to_pay(150.0, [150.0]) == 0.0


def test_un_coiffeur_qui_retravaille_apres_la_paie_a_encore_un_reste():
    """Payé mercredi pour 100 DT, il gagne encore 40 DT jeudi : on lui doit 40."""
    assert remaining_to_pay(140.0, [100.0]) == 40.0


def test_plusieurs_versements_s_additionnent():
    assert remaining_to_pay(200.0, [80.0, 70.0]) == 50.0


def test_une_avance_posterieure_peut_rendre_le_reste_negatif():
    """Payé 150, puis une tséb9a de 30 accordée : il a touché 30 de trop."""
    assert remaining_to_pay(120.0, [150.0]) == -30.0


def test_les_centimes_ne_derivent_pas():
    assert remaining_to_pay(0.3, [0.1, 0.2]) == 0.0


# ── Quand verser est refusé ──────────────────────────────────────────────────
def test_un_reste_positif_se_verse():
    assert payout_refusal(remaining=40.0, day_closed=False) is None


@pytest.mark.parametrize("reste", [0.0, -30.0, 0.004])
def test_rien_a_verser(reste):
    """Verser zéro ou un montant négatif n'a pas de sens : il n'y a rien à
    remettre, ou c'est l'employé qui doit au salon."""
    refus = payout_refusal(remaining=reste, day_closed=False)
    assert refus is not None and "Rien" in refus


def test_une_journee_cloturee_est_figee():
    """Le tiroir est compté et le total banque inscrit au rapport : un
    versement ce jour-là rendrait le rapport faux, en espèces comme par virement."""
    refus = payout_refusal(remaining=40.0, day_closed=True)
    assert refus is not None and "clôturée" in refus


def test_rien_a_verser_prime_sur_la_cloture():
    assert "Rien" in payout_refusal(remaining=0.0, day_closed=True)


# ── Le tiroir ────────────────────────────────────────────────────────────────
def test_une_paie_en_especes_sort_du_tiroir():
    avant = drawer_balance(200, 300, 0, 0, 0, 0)
    apres = drawer_balance(200, 300, 0, 0, 0, 0, payouts=150)
    assert avant == 500
    assert apres == 350


def test_sans_paie_le_tiroir_est_inchange():
    """Les appels existants, sans ce paramètre, gardent le même résultat."""
    assert drawer_balance(200, 300, 50, 20, 10, 30) == drawer_balance(
        200, 300, 50, 20, 10, 30, payouts=0
    )


# ── La demande ───────────────────────────────────────────────────────────────
def test_par_defaut_la_paie_sort_du_tiroir():
    demande = StaffPayoutCreate(salon_id=ObjectId(), staff_id=ObjectId())
    assert demande.paid_from is PaymentSource.CASH
    assert demande.week_of is None


def test_la_demande_ne_porte_pas_de_montant():
    """Le serveur verse ce qui reste dû : un montant tapé à la main pourrait
    payer deux fois la même semaine."""
    assert "amount" not in StaffPayoutCreate.model_fields


def test_la_note_est_bornee():
    with pytest.raises(ValidationError):
        StaffPayoutCreate(salon_id=ObjectId(), staff_id=ObjectId(), note="x" * 201)


# ── La trace ─────────────────────────────────────────────────────────────────
def test_les_versements_sont_une_collection_enregistree():
    assert StaffPayout in ALL_DOCUMENTS
    assert StaffPayout.Settings.name == "staff_payouts"


def test_un_salon_qui_a_paye_son_equipe_ne_se_supprime_pas():
    assert StaffPayout in HISTORIQUE
