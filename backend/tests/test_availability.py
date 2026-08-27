"""Moteur de créneaux : horaires, buffers, conflits, congés (§3.3)."""
from datetime import date, datetime, timedelta, timezone

import pytest

from app.core.timeutils import TZ, combine_local
from app.models.documents import DayHours
from app.services.availability import Interval, free_slots, slot_is_free, working_windows

JOUR = date(2026, 9, 15)          # un mardi
PASSE = datetime(2026, 9, 15, 0, 0, tzinfo=timezone.utc)


def hhmm(slots):
    return [s.astimezone(TZ).strftime("%H:%M") for s in slots]


def test_jour_ferme_ne_propose_aucun_creneau():
    slots = free_slots(
        day=JOUR, hours=DayHours(closed=True), busy=[], duration_min=30, now=PASSE
    )
    assert slots == []


def test_grille_simple_de_9h_a_11h():
    slots = free_slots(
        day=JOUR,
        hours=DayHours(open="09:00", close="11:00"),
        busy=[],
        duration_min=60,
        step_min=30,
        now=PASSE,
    )
    assert hhmm(slots) == ["09:00", "09:30", "10:00"]


def test_la_pause_dejeuner_est_retiree():
    windows = working_windows(
        JOUR,
        DayHours(open="09:00", close="18:00", break_start="12:30", break_end="13:30"),
    )
    assert len(windows) == 2
    slots = hhmm(
        free_slots(
            day=JOUR,
            hours=DayHours(
                open="09:00", close="18:00", break_start="12:30", break_end="13:30"
            ),
            busy=[],
            duration_min=60,
            step_min=60,
            now=PASSE,
        )
    )
    assert "12:00" not in slots      # déborderait sur la pause
    assert "13:30" in slots


def test_un_rdv_existant_bloque_les_creneaux_qui_le_chevauchent():
    occupe = Interval(combine_local(JOUR, "10:00"), combine_local(JOUR, "11:00"))
    slots = hhmm(
        free_slots(
            day=JOUR,
            hours=DayHours(open="09:00", close="12:00"),
            busy=[occupe],
            duration_min=30,
            step_min=30,
            now=PASSE,
        )
    )
    assert slots == ["09:00", "09:30", "11:00", "11:30"]


def test_un_conge_bloque_comme_un_rdv():
    conge = Interval(combine_local(JOUR, "09:00"), combine_local(JOUR, "12:00"))
    slots = free_slots(
        day=JOUR,
        hours=DayHours(open="09:00", close="12:00"),
        busy=[conge],
        duration_min=30,
        now=PASSE,
    )
    assert slots == []


def test_une_prestation_longue_doit_tenir_avant_la_fermeture():
    slots = hhmm(
        free_slots(
            day=JOUR,
            hours=DayHours(open="09:00", close="11:00"),
            busy=[],
            duration_min=120,
            step_min=30,
            now=PASSE,
        )
    )
    assert slots == ["09:00"]


def test_les_creneaux_passes_sont_ecartes():
    maintenant = combine_local(JOUR, "10:00")
    slots = hhmm(
        free_slots(
            day=JOUR,
            hours=DayHours(open="09:00", close="12:00"),
            busy=[],
            duration_min=30,
            step_min=30,
            now=maintenant,
        )
    )
    assert slots == ["10:00", "10:30", "11:00", "11:30"]


def test_delai_minimum_de_reservation():
    maintenant = combine_local(JOUR, "10:00")
    slots = hhmm(
        free_slots(
            day=JOUR,
            hours=DayHours(open="09:00", close="12:00"),
            busy=[],
            duration_min=30,
            step_min=30,
            now=maintenant,
            min_lead_min=45,
        )
    )
    assert slots[0] == "11:00"


def test_slot_is_free_refuse_hors_horaires():
    assert not slot_is_free(
        start=combine_local(JOUR, "20:00"),
        duration_min=30,
        day_hours=DayHours(open="09:00", close="19:00"),
        busy=[],
    )


def test_slot_is_free_accepte_un_creneau_valide():
    assert slot_is_free(
        start=combine_local(JOUR, "14:00"),
        duration_min=45,
        day_hours=DayHours(open="09:00", close="19:00"),
        busy=[Interval(combine_local(JOUR, "15:00"), combine_local(JOUR, "16:00"))],
    )


def test_slot_is_free_detecte_le_chevauchement_partiel():
    assert not slot_is_free(
        start=combine_local(JOUR, "14:30"),
        duration_min=45,
        day_hours=DayHours(open="09:00", close="19:00"),
        busy=[Interval(combine_local(JOUR, "15:00"), combine_local(JOUR, "16:00"))],
    )


def test_deux_rdv_bout_a_bout_ne_se_chevauchent_pas():
    """Le buffer est déjà inclus dans la durée : 14:00-15:00 et 15:00-16:00 cohabitent."""
    assert slot_is_free(
        start=combine_local(JOUR, "15:00"),
        duration_min=60,
        day_hours=DayHours(open="09:00", close="19:00"),
        busy=[Interval(combine_local(JOUR, "14:00"), combine_local(JOUR, "15:00"))],
    )


def test_duree_nulle_refusee():
    with pytest.raises(ValueError):
        free_slots(day=JOUR, hours=DayHours(), busy=[], duration_min=0, now=PASSE)


def test_horaires_incoherents_ne_produisent_rien():
    assert working_windows(JOUR, DayHours(open="19:00", close="09:00")) == []
