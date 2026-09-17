"""Confirmation des RDV et clients absents (§3.3, §5.5).

Un RDV payé au salon restait « en attente » sans bouton pour le confirmer, et
la tâche des RDV non payés l'annulait au bout de quinze minutes. Et un client
servi puis encaissé tard devenait « absent » vingt minutes après son heure.
"""
from datetime import datetime, timedelta, timezone

import pytest
from pydantic import ValidationError

from app.api.v1.bookings import no_show_too_early
from app.core.config import Settings, settings
from app.models.enums import BookingSource, BookingStatus
from app.schemas.booking import BookingCreate
from app.services.booking_service import assert_transition, initial_status
from app.workers.tasks import no_show_cutoff


# ── Statut à la création ─────────────────────────────────────────────────────
def test_un_rdv_paye_au_salon_est_confirme_d_office():
    assert initial_status(source=BookingSource.APP, pay_online=False) is BookingStatus.CONFIRMED


def test_un_rdv_paye_en_ligne_attend_son_paiement():
    assert initial_status(source=BookingSource.APP, pay_online=True) is BookingStatus.PENDING


def test_un_walk_in_est_toujours_confirme():
    assert initial_status(source=BookingSource.WALKIN, pay_online=True) is BookingStatus.CONFIRMED


def test_une_ancienne_app_sans_mode_paie_au_salon():
    """Les versions déjà installées n'envoient pas le mode : leurs clients ne
    doivent plus voir leur RDV annulé au bout de quinze minutes."""
    corps = BookingCreate(
        salon_id="64b000000000000000000001",
        service_ids=["64b000000000000000000002"],
        start=datetime(2026, 9, 20, 10, tzinfo=timezone.utc),
    )
    assert corps.payment_mode == "on_site"


def test_un_mode_inconnu_est_refuse():
    with pytest.raises(ValidationError):
        BookingCreate(
            salon_id="64b000000000000000000001",
            service_ids=["64b000000000000000000002"],
            start=datetime(2026, 9, 20, 10, tzinfo=timezone.utc),
            payment_mode="cheque",
        )


# ── Client absent ────────────────────────────────────────────────────────────
MAINTENANT = datetime(2026, 9, 17, 10, 0, tzinfo=timezone.utc)
GRACE = settings.NO_SHOW_GRACE_MIN


def test_les_deux_delais_sont_d_une_demi_heure_par_defaut():
    """Le code fixe 30 min ; une variable d'environnement peut les changer."""
    assert Settings.model_fields["PENDING_TIMEOUT_MIN"].default == 30
    assert Settings.model_fields["NO_SHOW_GRACE_MIN"].default == 30


def test_un_client_en_retard_dans_le_delai_n_est_pas_absent():
    rdv = MAINTENANT - timedelta(minutes=GRACE - 5)
    assert not rdv < no_show_cutoff(MAINTENANT)


def test_un_client_en_retard_au_dela_du_delai_est_absent():
    rdv = MAINTENANT - timedelta(minutes=GRACE + 5)
    assert rdv < no_show_cutoff(MAINTENANT)


def test_un_rdv_a_venir_n_est_jamais_absent():
    assert not (MAINTENANT + timedelta(hours=1)) < no_show_cutoff(MAINTENANT)


def test_ma_jach_avant_l_heure_est_refuse():
    maintenant = datetime(2026, 9, 17, 9, tzinfo=timezone.utc)
    assert no_show_too_early(maintenant + timedelta(minutes=30), maintenant) is True
    assert no_show_too_early(maintenant - timedelta(minutes=1), maintenant) is False


def test_un_client_marque_absent_peut_etre_encaisse():
    assert_transition(BookingStatus.NO_SHOW, BookingStatus.IN_PROGRESS)
