"""Règles de gestion transverses : téléphone, machine à états, bornes de journée."""
from datetime import date, datetime, timezone

import pytest
from fastapi import HTTPException

from app.core.timeutils import TZ, day_key, local_day_bounds, local_month_bounds
from app.models.enums import BOOKING_TRANSITIONS, BookingStatus
from app.schemas.auth import normalize_phone
from app.services.booking_service import assert_transition


# ── Téléphone ────────────────────────────────────────────────────────────────
@pytest.mark.parametrize(
    "saisie",
    ["98123456", "+216 98 123 456", "21698123456", "+21698123456", "98 12 34 56"],
)
def test_les_formats_tunisiens_courants_convergent(saisie):
    assert normalize_phone(saisie) == "+21698123456"


def test_numero_international_conserve():
    assert normalize_phone("+33612345678") == "+33612345678"


@pytest.mark.parametrize("saisie", ["12", "abcdefgh", "+", "0123456789012345678"])
def test_numero_invalide_refuse(saisie):
    with pytest.raises(ValueError):
        normalize_phone(saisie)


# ── Machine à états du RDV (§5.5) ────────────────────────────────────────────
def test_chemin_nominal_autorise():
    assert_transition(BookingStatus.PENDING, BookingStatus.CONFIRMED)
    assert_transition(BookingStatus.CONFIRMED, BookingStatus.IN_PROGRESS)
    assert_transition(BookingStatus.IN_PROGRESS, BookingStatus.DONE)


@pytest.mark.parametrize(
    "depart,arrivee",
    [
        (BookingStatus.PENDING, BookingStatus.DONE),          # pas de raccourci
        (BookingStatus.PENDING, BookingStatus.NO_SHOW),
        (BookingStatus.DONE, BookingStatus.CANCELLED),        # une caisse ne se défait pas
        (BookingStatus.CANCELLED, BookingStatus.CONFIRMED),
        (BookingStatus.NO_SHOW, BookingStatus.DONE),
    ],
)
def test_transitions_interdites(depart, arrivee):
    with pytest.raises(HTTPException) as exc:
        assert_transition(depart, arrivee)
    assert exc.value.status_code == 409


def test_les_etats_terminaux_sont_bien_terminaux():
    for etat in (BookingStatus.DONE, BookingStatus.CANCELLED, BookingStatus.NO_SHOW):
        assert BOOKING_TRANSITIONS[etat] == set()


# ── Bornes temporelles ───────────────────────────────────────────────────────
def test_bornes_du_jour_couvrent_24h_en_heure_locale():
    start, end = local_day_bounds(date(2026, 8, 2))
    assert end - start == datetime(2026, 8, 3, tzinfo=timezone.utc) - datetime(
        2026, 8, 2, tzinfo=timezone.utc
    )
    assert start.tzinfo is timezone.utc


def test_bornes_de_mois_passent_l_annee():
    """Décembre 2026 se ferme au 1er janvier 2027 — en heure locale du salon."""
    start, end = local_month_bounds(2026, 12)
    assert start < end
    assert start.astimezone(TZ).strftime("%Y-%m-%d %H:%M") == "2026-12-01 00:00"
    assert end.astimezone(TZ).strftime("%Y-%m-%d %H:%M") == "2027-01-01 00:00"


@pytest.mark.parametrize(
    "jour,cle",
    [
        (date(2026, 9, 14), "mon"),
        (date(2026, 9, 15), "tue"),
        (date(2026, 9, 20), "sun"),
    ],
)
def test_cle_horaire_du_jour(jour, cle):
    assert day_key(jour) == cle
