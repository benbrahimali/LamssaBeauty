"""Pourquoi un jour n'est pas réservable (§3.3, §3.5).

Le calendrier client proposait quatorze jours identiques : il fallait tous les
essayer pour trouver celui où le coiffeur travaille. Pire, « complet » et « le
coiffeur est en congé » se ressemblaient — le client réessayait au lendemain
au lieu de changer de coiffeur.
"""
import pytest

from app.core.timeutils import WEEKDAY_KEYS
from app.services.booking_service import unavailability_reason


def motif(salon_closed=False, staff_unavailable=False, is_day_off=False, slot_count=5):
    return unavailability_reason(
        salon_closed=salon_closed,
        staff_unavailable=staff_unavailable,
        is_day_off=is_day_off,
        slot_count=slot_count,
    )


# ── Le jour normal ───────────────────────────────────────────────────────────
def test_un_jour_avec_des_creneaux_n_a_pas_de_motif():
    assert motif() is None


# ── Chaque cause prise seule ─────────────────────────────────────────────────
def test_le_salon_ferme_le_dit():
    assert motif(salon_closed=True, slot_count=0) == "salon_closed"


def test_le_coiffeur_suspendu_le_dit():
    assert motif(staff_unavailable=True, slot_count=0) == "staff_unavailable"


def test_le_repos_hebdomadaire_le_dit():
    assert motif(is_day_off=True, slot_count=0) == "day_off"


def test_une_journee_pleine_le_dit():
    assert motif(slot_count=0) == "full"


# ── L'ordre des causes ───────────────────────────────────────────────────────
def test_un_salon_ferme_prime_sur_le_repos_du_coiffeur():
    """Le repos du coiffeur n'explique rien un jour où le salon est fermé :
    tous ses collègues sont absents aussi."""
    assert motif(salon_closed=True, is_day_off=True, slot_count=0) == "salon_closed"


def test_un_salon_ferme_prime_sur_complet():
    """« Complet » enverrait le client réessayer demain alors que le problème
    n'est pas la demande."""
    assert motif(salon_closed=True, slot_count=0) == "salon_closed"


def test_le_repos_prime_sur_complet():
    """Un jour de repos n'est pas une journée pleine : le client doit changer
    de coiffeur, pas d'horaire."""
    assert motif(is_day_off=True, slot_count=0) == "day_off"


def test_un_coiffeur_suspendu_prime_sur_son_repos():
    assert motif(staff_unavailable=True, is_day_off=True, slot_count=0) == "staff_unavailable"


# ── Le cas qui trompe ────────────────────────────────────────────────────────
def test_un_jour_de_repos_qui_garderait_des_creneaux_reste_un_repos():
    """Défense en profondeur : si le calcul des créneaux oubliait le repos, le
    motif ne doit pas pour autant annoncer le jour comme ouvert."""
    assert motif(is_day_off=True, slot_count=12) == "day_off"


def test_un_salon_ferme_avec_des_creneaux_reste_ferme():
    assert motif(salon_closed=True, slot_count=12) == "salon_closed"


# ── Les clés de jours ────────────────────────────────────────────────────────
def test_la_semaine_commence_lundi():
    """Un décalage ici poserait le repos du dimanche sur le lundi."""
    assert WEEKDAY_KEYS[0] == "mon"
    assert WEEKDAY_KEYS[6] == "sun"
    assert len(WEEKDAY_KEYS) == 7


@pytest.mark.parametrize("jour", WEEKDAY_KEYS)
def test_chaque_jour_de_la_semaine_peut_etre_un_repos(jour):
    from app.schemas.salon import _valid_days

    assert _valid_days([jour]) == [jour]


def test_un_jour_inconnu_est_refuse():
    """« lundi » ne bloquerait aucun créneau et personne ne s'en apercevrait
    avant qu'un client se déplace pour rien."""
    from app.schemas.salon import _valid_days

    with pytest.raises(ValueError, match="Jour inconnu"):
        _valid_days(["lundi"])


def test_les_doublons_sont_reduits_et_remis_dans_l_ordre():
    from app.schemas.salon import _valid_days

    assert _valid_days(["sun", "mon", "sun"]) == ["mon", "sun"]


def test_aucun_repos_reste_une_liste_vide():
    from app.schemas.salon import _valid_days

    assert _valid_days([]) == []
