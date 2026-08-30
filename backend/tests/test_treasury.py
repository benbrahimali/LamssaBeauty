"""Trésorerie : ce que le tiroir devrait contenir, et l'écart au comptage (§3.4).

La caisse du jour dit ce qui a été encaissé ; ce module dit ce qui est
physiquement dans le tiroir. Les deux divergent dès qu'une carte bancaire, un
achat de produits ou une tséb9a entre en jeu — et c'est cette divergence que
les gérants n'arrivent pas à suivre à la main.
"""
import pytest

from app.services.cash_service import drawer_balance


def caisse(
    opening=0.0,
    cash_in=0.0,
    deposits=0.0,
    cash_expenses=0.0,
    cash_advances=0.0,
    withdrawals=0.0,
) -> float:
    return drawer_balance(
        opening, cash_in, deposits, cash_expenses, cash_advances, withdrawals
    )


# ── Ce qui remplit le tiroir ─────────────────────────────────────────────────
def test_un_tiroir_vide_sans_activite_reste_vide():
    assert caisse() == 0


def test_le_fond_de_caisse_est_deja_dans_le_tiroir():
    """Il n'est pas un revenu : il était là avant la première coupe."""
    assert caisse(opening=50) == 50


def test_les_encaissements_especes_s_ajoutent_au_fond():
    assert caisse(opening=50, cash_in=320) == 370


def test_un_apport_du_gerant_remplit_le_tiroir_sans_etre_un_gain():
    """Remettre de la monnaie pour rendre l'appoint n'enrichit personne."""
    assert caisse(opening=20, deposits=100) == 120


# ── Ce qui le vide ───────────────────────────────────────────────────────────
def test_un_achat_paye_du_tiroir_le_diminue():
    assert caisse(opening=50, cash_in=300, cash_expenses=45) == 305


def test_une_tsebqa_versee_en_especes_sort_du_tiroir():
    """L'avance quitte la caisse le jour où elle est remise, pas à la paie."""
    assert caisse(cash_in=400, cash_advances=80) == 320


def test_un_prelevement_du_gerant_sort_du_tiroir():
    assert caisse(cash_in=500, withdrawals=300) == 200


def test_toutes_les_sorties_se_cumulent():
    assert caisse(
        opening=50, cash_in=620, deposits=30, cash_expenses=45,
        cash_advances=80, withdrawals=400,
    ) == 175


# ── Ce qui ne le concerne pas ────────────────────────────────────────────────
def test_une_journee_entierement_par_carte_ne_remplit_pas_le_tiroir():
    """Le TPE verse à la banque : le tiroir du soir contient son fond, rien de plus.

    Confondre les deux est la première cause d'écart inexpliqué — le gérant
    cherche 800 DT qui n'ont jamais été en espèces.
    """
    assert caisse(opening=50, cash_in=0) == 50


def test_le_tiroir_peut_devenir_negatif_et_le_dit():
    """Un solde négatif est une anomalie réelle : on l'affiche au lieu de le
    ramener à zéro, sinon le gérant ne verra jamais le problème."""
    assert caisse(opening=20, cash_expenses=90) == -70


# ── Arrondis ─────────────────────────────────────────────────────────────────
def test_les_centimes_ne_derivent_pas():
    assert caisse(opening=10.005, cash_in=0.005) == pytest.approx(10.01)


def test_le_solde_est_arrondi_au_centime():
    solde = caisse(cash_in=33.333, cash_expenses=11.111)
    assert solde == round(solde, 2)


# ── L'écart de caisse ────────────────────────────────────────────────────────
def ecart(compte: float, attendu: float) -> float:
    return round(compte - attendu, 2)


def test_un_comptage_exact_ne_laisse_aucun_ecart():
    assert ecart(370, caisse(opening=50, cash_in=320)) == 0


def test_il_manque_de_l_argent_l_ecart_est_negatif():
    assert ecart(360, caisse(opening=50, cash_in=320)) == -10


def test_il_y_a_trop_d_argent_l_ecart_est_positif():
    """Un excédent est aussi une erreur : un encaissement n'a pas été saisi."""
    assert ecart(385, caisse(opening=50, cash_in=320)) == 15


# ── Le fond de caisse du lendemain ───────────────────────────────────────────
def cloture(compte: float, preleve: float) -> float:
    return round(compte - preleve, 2)


def test_ce_qui_reste_le_soir_ouvre_la_journee_suivante():
    assert cloture(370, 300) == 70


def test_un_gerant_qui_ne_preleve_rien_laisse_tout_en_caisse():
    assert cloture(370, 0) == 370


def test_vider_entierement_le_tiroir_ouvre_le_lendemain_a_zero():
    assert cloture(370, 370) == 0
