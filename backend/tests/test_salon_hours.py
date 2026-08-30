"""Horaires du salon : c'est le gérant qui décide (§3.1, §3.5).

Le dimanche fermé n'est qu'un défaut de création. Beaucoup de salons tunisiens
ouvrent 7j/7 et doivent pouvoir le déclarer — l'app ne leur impose aucune
semaine type.
"""
import pytest

from app.models.documents import DEFAULT_HOURS, DayHours


def fusion(existant: dict, envoye: dict) -> dict:
    """Ce que fait la route PATCH : fusionner, jamais remplacer."""
    return {**existant, **envoye}


# ── Le défaut de création ────────────────────────────────────────────────────
def test_la_semaine_par_defaut_couvre_les_sept_jours():
    """Un jour absent retomberait sur un défaut implicite ailleurs dans le
    code : mieux vaut que les sept existent dès la création."""
    assert set(DEFAULT_HOURS) == {"mon", "tue", "wed", "thu", "fri", "sat", "sun"}


def test_le_dimanche_est_ferme_par_defaut():
    assert DEFAULT_HOURS["sun"].closed is True


def test_les_autres_jours_sont_ouverts_par_defaut():
    for jour in ("mon", "tue", "wed", "thu", "fri", "sat"):
        assert DEFAULT_HOURS[jour].closed is False


def test_le_defaut_n_est_pas_une_regle():
    """Rien n'empêche un dimanche ouvert : c'est tout l'objet de ce volet."""
    assert DayHours(closed=False, open="10:00", close="16:00").closed is False


# ── La fusion, cœur du correctif ─────────────────────────────────────────────
def test_ouvrir_le_dimanche_ne_touche_pas_aux_autres_jours():
    """Sans fusion, le PATCH remplaçait tout le dictionnaire : les six autres
    jours disparaissaient et retombaient en silence sur les valeurs par
    défaut. Un gérant perdait ainsi ses horaires du lundi."""
    semaine = {j: h.model_copy() for j, h in DEFAULT_HOURS.items()}
    semaine["mon"] = DayHours(open="08:00", close="20:00")

    apres = fusion(semaine, {"sun": DayHours(closed=False, open="10:00", close="16:00")})

    assert len(apres) == 7
    assert apres["mon"].open == "08:00", "le lundi personnalisé doit survivre"
    assert apres["sun"].closed is False


def test_un_jour_envoye_ecrase_ce_jour_la():
    semaine = {j: h.model_copy() for j, h in DEFAULT_HOURS.items()}

    apres = fusion(semaine, {"mon": DayHours(open="07:30", close="21:00")})

    assert apres["mon"].open == "07:30"
    assert apres["tue"].open == "09:00", "les autres restent intacts"


def test_refermer_un_jour_est_possible():
    """Un salon peut revenir en arrière : ouvrir n'est pas irréversible."""
    semaine = fusion(DEFAULT_HOURS, {"sun": DayHours(closed=False)})
    apres = fusion(semaine, {"sun": DayHours(closed=True)})

    assert apres["sun"].closed is True


def test_envoyer_toute_la_semaine_reste_possible():
    ouvert_partout = {j: DayHours(closed=False) for j in DEFAULT_HOURS}
    apres = fusion(DEFAULT_HOURS, ouvert_partout)

    assert all(not h.closed for h in apres.values()), "un salon 7j/7 est légitime"


def test_une_fusion_vide_ne_change_rien():
    apres = fusion(DEFAULT_HOURS, {})
    assert apres == DEFAULT_HOURS


# ── La pause ─────────────────────────────────────────────────────────────────
def test_la_pause_est_optionnelle():
    h = DayHours()
    assert h.break_start is None and h.break_end is None


def test_une_pause_se_declare_des_deux_cotes():
    h = DayHours(break_start="12:30", break_end="13:30")
    assert h.break_start == "12:30"
    assert h.break_end == "13:30"


@pytest.mark.parametrize("ouverture,fermeture", [("08:00", "20:00"), ("10:00", "16:00")])
def test_des_amplitudes_variees_sont_acceptees(ouverture, fermeture):
    h = DayHours(open=ouverture, close=fermeture)
    assert h.open == ouverture and h.close == fermeture
