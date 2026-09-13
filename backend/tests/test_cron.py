"""Tâches planifiées déclenchées par un cron externe (§3.3, §3.4).

Sur Render gratuit Celery beat ne tourne pas : sans cette route, aucun rappel
J-1 ni H-2 ne partait. Le cron l'appelle plus souvent que le beat — ce n'est
sûr que si l'accès est protégé et si la relance de clôture ne part qu'une fois
par soir.
"""
from datetime import datetime

import pytest

from app.api.v1.internal import HEURE_CLOTURE, cle_cloture, cloture_due, secret_valide


# ── Le secret ────────────────────────────────────────────────────────────────
def test_le_bon_secret_ouvre_la_route():
    assert secret_valide("s3cr3t-long", "s3cr3t-long") is True


def test_un_mauvais_secret_est_refuse():
    assert secret_valide("autre", "s3cr3t-long") is False


def test_un_secret_absent_est_refuse():
    assert secret_valide(None, "s3cr3t-long") is False
    assert secret_valide("", "s3cr3t-long") is False


def test_sans_secret_configure_rien_n_ouvre():
    """Défaut sûr : une configuration oubliée ferme la route au lieu de
    l'ouvrir à tout internet."""
    assert secret_valide("", "") is False
    assert secret_valide("nimporte", "") is False


def test_un_prefixe_du_secret_ne_suffit_pas():
    assert secret_valide("s3cr3t", "s3cr3t-long") is False


# ── La relance de clôture : une fois par soir ────────────────────────────────
@pytest.mark.parametrize("heure", [0, 9, 14, 20])
def test_pas_de_relance_avant_21h(heure):
    """Relancer un gérant en pleine journée, c'est lui reprocher de ne pas
    avoir fermé un salon encore ouvert."""
    assert cloture_due(datetime(2026, 9, 14, heure, 59)) is False


@pytest.mark.parametrize("heure", [21, 22, 23])
def test_relance_a_partir_de_21h(heure):
    assert cloture_due(datetime(2026, 9, 14, heure, 0)) is True


def test_l_heure_est_celle_du_beat_celery():
    """Même comportement qu'avant la bascule : la relance partait à 21 h."""
    assert HEURE_CLOTURE == 21


def test_une_cle_par_jour_local():
    """C'est cette clé, posée une seule fois, qui empêche la relance de repartir
    à chacun des appels du cron entre 21 h et minuit."""
    soir = datetime(2026, 9, 14, 21, 5)
    plus_tard = datetime(2026, 9, 14, 23, 55)
    lendemain = datetime(2026, 9, 15, 21, 5)

    assert cle_cloture(soir) == cle_cloture(plus_tard)
    assert cle_cloture(soir) != cle_cloture(lendemain)
