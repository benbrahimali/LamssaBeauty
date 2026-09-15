"""Annuler un encaissement erroné (§3.4).

Sans correction possible, une saisie de 250 DT au lieu de 25 faussait la caisse,
la part du coiffeur, la clôture et la paie. L'annulation doit rester encadrée :
jamais sur une journée clôturée, jamais sur un paiement en ligne, jamais sans
raison ni trace.
"""
import pytest
from pydantic import ValidationError

from app.api.v1.admin import HISTORIQUE
from app.api.v1.bookings import void_refusal
from app.models.documents import ALL_DOCUMENTS, VoidedTransaction
from app.models.enums import PaymentMethod
from app.schemas.booking import PaymentVoid


# ── Ce qui peut s'annuler ────────────────────────────────────────────────────
@pytest.mark.parametrize("method", [PaymentMethod.CASH, PaymentMethod.CARD])
def test_un_encaissement_du_jour_s_annule(method):
    assert void_refusal(day_closed=False, method=method) is None


def test_une_journee_cloturee_est_figee():
    """Le rapport de clôture est une pièce comptable déjà remise."""
    refus = void_refusal(day_closed=True, method=PaymentMethod.CASH)
    assert refus is not None and "clôturée" in refus


def test_un_paiement_en_ligne_se_rembourse_il_ne_s_annule_pas():
    """L'argent est chez le prestataire : l'effacer ici sans rembourser le
    client laisserait les deux côtés en désaccord."""
    refus = void_refusal(day_closed=False, method=PaymentMethod.ONLINE)
    assert refus is not None and "rembourse" in refus


def test_la_cloture_prime_sur_le_mode_de_paiement():
    refus = void_refusal(day_closed=True, method=PaymentMethod.ONLINE)
    assert "clôturée" in refus


# ── La raison ────────────────────────────────────────────────────────────────
def test_une_raison_est_obligatoire():
    with pytest.raises(ValidationError):
        PaymentVoid(reason="")


def test_une_raison_d_un_caractere_ne_suffit_pas():
    with pytest.raises(ValidationError):
        PaymentVoid(reason="x")


def test_une_vraie_raison_est_acceptee():
    assert PaymentVoid(reason="250 au lieu de 25").reason == "250 au lieu de 25"


def test_une_raison_interminable_est_refusee():
    with pytest.raises(ValidationError):
        PaymentVoid(reason="a" * 201)


# ── La trace ─────────────────────────────────────────────────────────────────
def test_l_archive_est_une_collection_enregistree():
    """Sans enregistrement au démarrage, l'archive échouerait au premier usage."""
    assert VoidedTransaction in ALL_DOCUMENTS
    assert VoidedTransaction.Settings.name == "voided_transactions"


def test_un_salon_avec_des_annulations_ne_se_supprime_pas():
    """Supprimer le salon effacerait la trace des annulations."""
    assert VoidedTransaction in HISTORIQUE


def test_l_archive_garde_de_quoi_reconstituer_l_encaissement():
    champs = set(VoidedTransaction.model_fields)
    assert {
        "transaction_id", "booking_id", "staff_id", "amount", "method",
        "salon_share", "staff_share", "tip", "salon_tip", "paid_at",
        "voided_at", "voided_by", "reason",
    } <= champs
