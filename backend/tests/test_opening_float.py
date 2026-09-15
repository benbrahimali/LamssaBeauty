"""Fond de caisse déclaré par le gérant (§3.4).

Le tiroir ouvre avec ce que la veille a laissé ; le gérant peut corriger ce
montant, et l'écart avec la veille reste visible.
"""
import pytest
from bson import ObjectId
from pydantic import ValidationError

from app.models.enums import CashMovementType
from app.schemas.cash import CashMovementCreate
from app.services.cash_service import float_gap


# ── Écart avec la veille ─────────────────────────────────────────────────────
def test_sans_declaration_pas_d_ecart():
    assert float_gap(None, 220.0) == 0.0


def test_la_meme_somme_que_la_veille_ne_fait_aucun_ecart():
    assert float_gap(220.0, 220.0) == 0.0


def test_il_manque_de_l_argent_depuis_la_veille():
    """Le tiroir a été vidé en partie pendant la nuit : ça doit se voir."""
    assert float_gap(200.0, 220.0) == -20.0


def test_le_gerant_a_remis_de_l_argent_depuis_la_veille():
    assert float_gap(300.0, 220.0) == 80.0


def test_un_premier_jour_sans_historique():
    """Rien la veille : tout le fond déclaré est un écart positif, et c'est
    exact — l'argent vient d'entrer dans le tiroir."""
    assert float_gap(150.0, 0.0) == 150.0


def test_l_ecart_est_arrondi_au_centime():
    assert float_gap(100.1, 100.0) == 0.1


# ── Montants acceptés ────────────────────────────────────────────────────────
def mouvement(type_: CashMovementType, montant: float) -> CashMovementCreate:
    return CashMovementCreate(salon_id=ObjectId(), type=type_, amount=montant)


def test_un_tiroir_peut_ouvrir_vide():
    assert mouvement(CashMovementType.OPENING_FLOAT, 0).amount == 0


def test_un_fond_de_caisse_normal():
    assert mouvement(CashMovementType.OPENING_FLOAT, 200).amount == 200


@pytest.mark.parametrize("type_", [CashMovementType.DEPOSIT, CashMovementType.WITHDRAWAL])
def test_un_apport_ou_un_prelevement_de_zero_est_refuse(type_):
    with pytest.raises(ValidationError):
        mouvement(type_, 0)


@pytest.mark.parametrize("type_", list(CashMovementType))
def test_un_montant_negatif_est_toujours_refuse(type_):
    """Le sens vient du type : un montant négatif inverserait le mouvement."""
    with pytest.raises(ValidationError):
        mouvement(type_, -50)
