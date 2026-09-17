"""Confirmation des RDV et clients absents (§3.3, §5.5).

Un RDV payé au salon restait « en attente » sans bouton pour le confirmer, et
la tâche des RDV non payés l'annulait au bout de quinze minutes. Et un client
servi puis encaissé tard devenait « absent » vingt minutes après son heure.
"""
from datetime import datetime, timedelta, timezone

import pytest
from pydantic import ValidationError

from app.api.v1.bookings import no_show_too_early
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
def test_un_client_servi_le_matin_n_est_pas_absent_l_apres_midi():
    """RDV à 10:00, encaissé à 15:00 : la tâche ne doit pas l'avoir déclaré absent."""
    maintenant = datetime(2026, 9, 17, 14, tzinfo=timezone.utc)  # 15:00 à Tunis
    rdv_du_matin = datetime(2026, 9, 17, 9, tzinfo=timezone.utc)  # 10:00 à Tunis

    assert not rdv_du_matin < no_show_cutoff(maintenant)


def test_un_rdv_de_la_veille_non_encaisse_est_declare_absent():
    maintenant = datetime(2026, 9, 17, 8, tzinfo=timezone.utc)
    hier_soir = datetime(2026, 9, 16, 17, tzinfo=timezone.utc)

    assert hier_soir < no_show_cutoff(maintenant)


def test_le_delai_de_grace_reste_respecte_juste_apres_minuit():
    """RDV à 23:50, 00:05 le lendemain : trop tôt pour le dire absent."""
    maintenant = datetime(2026, 9, 16, 23, 5, tzinfo=timezone.utc)  # 00:05 à Tunis
    rdv = datetime(2026, 9, 16, 22, 50, tzinfo=timezone.utc)  # 23:50 à Tunis la veille

    assert not rdv < no_show_cutoff(maintenant)


def test_ma_jach_avant_l_heure_est_refuse():
    maintenant = datetime(2026, 9, 17, 9, tzinfo=timezone.utc)
    assert no_show_too_early(maintenant + timedelta(minutes=30), maintenant) is True
    assert no_show_too_early(maintenant - timedelta(minutes=1), maintenant) is False


def test_un_client_marque_absent_peut_etre_encaisse():
    assert_transition(BookingStatus.NO_SHOW, BookingStatus.IN_PROGRESS)
