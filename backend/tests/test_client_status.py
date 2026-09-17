"""Ce qu'un client peut faire de son propre rendez-vous (§5.5).

Il pouvait confirmer lui-même un RDV en attente de paiement en ligne — donc
réserver sans payer. Et un gérant qui réservait dans un autre salon échappait
au délai d'annulation, parce que la règle regardait son rôle et non sa place
dans ce salon.
"""
from datetime import timedelta
from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from app.api.v1.bookings import client_may_set
from app.core.timeutils import utcnow
from app.models.enums import BookingStatus, Role
from app.services.booking_service import assert_can_cancel


# ── Ce que le client peut demander ───────────────────────────────────────────
def test_un_client_peut_annuler_son_rdv():
    assert client_may_set(BookingStatus.CANCELLED) is True


@pytest.mark.parametrize(
    "statut",
    [BookingStatus.CONFIRMED, BookingStatus.IN_PROGRESS, BookingStatus.NO_SHOW, BookingStatus.DONE],
)
def test_le_reste_est_reserve_au_salon(statut):
    """Confirmer lui-même un RDV en attente de paiement : réserver sans payer."""
    assert client_may_set(statut) is False


# ── Délai d'annulation ───────────────────────────────────────────────────────
def _rdv_dans(minutes):
    return SimpleNamespace(start=utcnow() + timedelta(minutes=minutes))


SALON = SimpleNamespace(cancellation_window_h=2)


@pytest.mark.asyncio
async def test_un_gerant_qui_reserve_ailleurs_respecte_le_delai():
    """Il est client dans ce salon : son rôle de gérant ne l'en dispense pas."""
    gerant = SimpleNamespace(role=Role.OWNER)
    with pytest.raises(HTTPException) as exc:
        await assert_can_cancel(_rdv_dans(30), SALON, gerant, for_salon=False)
    assert exc.value.status_code == 409


@pytest.mark.asyncio
async def test_le_salon_annule_sans_delai():
    coiffeur = SimpleNamespace(role=Role.CLIENT)
    await assert_can_cancel(_rdv_dans(30), SALON, coiffeur, for_salon=True)


@pytest.mark.asyncio
async def test_un_client_dans_les_temps_peut_annuler():
    client = SimpleNamespace(role=Role.CLIENT)
    await assert_can_cancel(_rdv_dans(24 * 60), SALON, client, for_salon=False)


@pytest.mark.asyncio
async def test_sans_precision_le_comportement_d_origine_est_garde():
    """Les autres appels, qui ne passent pas `for_salon`, ne changent pas."""
    gerant = SimpleNamespace(role=Role.OWNER)
    await assert_can_cancel(_rdv_dans(30), SALON, gerant)
