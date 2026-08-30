"""Console d'administration (§9).

Un administrateur surveille l'ensemble de la plateforme ; un gérant administre
SON salon. Confondre les deux donnerait à n'importe quel gérant la liste des
salons de ses concurrents.
"""
import re

import pytest

from app.api.v1.admin import TEST_SALON
from app.core.config import Settings


# ── Le drapeau administrateur ────────────────────────────────────────────────
def test_les_numeros_admins_sont_normalises():
    """Saisis avec des espaces, ils ne correspondraient à aucun compte."""
    s = Settings(ADMIN_PHONES="+216 99 000 000")
    assert s.admin_phones == {"+21699000000"}


def test_plusieurs_numeros_se_separent_par_des_virgules():
    s = Settings(ADMIN_PHONES="+21699000000,+21698000000")
    assert s.admin_phones == {"+21699000000", "+21698000000"}


def test_aucun_admin_par_defaut():
    """Défaut sûr : la console n'ouvre à personne tant qu'on ne l'a pas dit.

    `_env_file=None` isole du .env de la machine : sans ça le test mesurerait
    la configuration du développeur, pas le défaut du code.
    """
    assert Settings(_env_file=None).admin_phones == set()


def test_une_liste_vide_n_ouvre_a_personne():
    assert Settings(ADMIN_PHONES="").admin_phones == set()
    assert Settings(ADMIN_PHONES="  ,  ").admin_phones == set()


def test_un_numero_illisible_n_empeche_pas_le_demarrage():
    """Il n'ouvre simplement aucun accès — un serveur qui refuse de démarrer
    pour une virgule en trop serait pire."""
    s = Settings(ADMIN_PHONES="pas-un-numero,+21699000000")
    assert s.admin_phones == {"+21699000000"}


def test_les_espaces_autour_des_virgules_sont_tolores():
    s = Settings(ADMIN_PHONES=" +21699000000 , +21698000000 ")
    assert len(s.admin_phones) == 2


# ── Le motif des salons de test ──────────────────────────────────────────────
@pytest.mark.parametrize("nom", [
    "Salon Test 1788087009201",
    "Salon Test 1",
])
def test_un_salon_cree_par_les_tests_est_reconnu(nom):
    assert TEST_SALON.match(nom)


@pytest.mark.parametrize("nom", [
    "Salon Test du quartier",      # un vrai salon qui s'appellerait ainsi
    "Salon Test",                  # sans horodatage
    "Mon Salon Test 123",          # le motif est ancré au début
    "Salon Test 123 bis",          # et à la fin
    "salon test 123",              # la casse compte
    "Barbier El Menzah",
])
def test_un_salon_reel_n_est_jamais_pris_pour_un_artefact(nom):
    """Le nom reste du texte saisi par un humain : le motif doit être strict,
    parce qu'une correspondance de trop efface le salon de quelqu'un."""
    assert not TEST_SALON.match(nom)


def test_le_motif_est_ancre_des_deux_cotes():
    assert TEST_SALON.pattern.startswith("^")
    assert TEST_SALON.pattern.endswith("$")


# ── La règle de suppression ──────────────────────────────────────────────────
def supprimable(nom: str, historique: dict) -> bool:
    """Les deux barrières de la purge : le nom ET l'absence d'historique."""
    return bool(TEST_SALON.match(nom)) and not historique


def test_un_salon_de_test_vierge_se_supprime():
    assert supprimable("Salon Test 123", {}) is True


def test_un_salon_de_test_avec_historique_est_conserve():
    """Même nommé comme un artefact : s'il a produit quelque chose, la paie
    d'un coiffeur en dépend."""
    assert supprimable("Salon Test 123", {"Transaction": 4}) is False


def test_un_salon_reel_vierge_n_est_pas_supprime_pour_autant():
    """Le nom seul décide de l'appartenance ; l'absence d'historique ne suffit
    jamais à faire d'un salon un artefact."""
    assert supprimable("Nouveau Salon", {}) is False


def test_un_seul_enregistrement_suffit_a_proteger():
    for collection in ["Booking", "Transaction", "Review", "Reel", "CashClosure"]:
        assert supprimable("Salon Test 9", {collection: 1}) is False
