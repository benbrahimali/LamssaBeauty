"""Avis clients vus par le coiffeur et le gérant (§3.8).

Le coiffeur recevait « Nouvel avis 2/5 » sans pouvoir le lire, et le gérant,
qui modère, n'était jamais prévenu.
"""
from datetime import datetime, timezone
from types import SimpleNamespace

from bson import ObjectId

from app.api.v1.reviews import review_recipients
from app.api.v1.staff import review_card

COIFFEUR, GERANT = ObjectId(), ObjectId()


# ── Qui est prévenu ──────────────────────────────────────────────────────────
def test_le_coiffeur_et_le_gerant_sont_prevenus():
    assert review_recipients(COIFFEUR, GERANT) == [(COIFFEUR, "staff"), (GERANT, "owner")]


def test_un_gerant_qui_coupe_lui_meme_ne_recoit_qu_une_notification():
    assert review_recipients(GERANT, GERANT) == [(GERANT, "staff")]


def test_sans_coiffeur_le_gerant_est_quand_meme_prevenu():
    assert review_recipients(None, GERANT) == [(GERANT, "owner")]


def test_sans_salon_le_coiffeur_est_quand_meme_prevenu():
    assert review_recipients(COIFFEUR, None) == [(COIFFEUR, "staff")]


# ── Ce que le coiffeur lit ───────────────────────────────────────────────────
def _avis(**champs):
    base = dict(
        id=ObjectId(),
        rating=4,
        comment="Très bon dégradé",
        created_at=datetime(2026, 9, 16, 18, tzinfo=timezone.utc),
        client_id=ObjectId(),
        booking_id=ObjectId(),
        salon_id=ObjectId(),
    )
    base.update(champs)
    return SimpleNamespace(**base)


def test_le_coiffeur_lit_la_note_le_mot_et_la_date():
    carte = review_card(_avis())
    assert carte["rating"] == 4
    assert carte["comment"] == "Très bon dégradé"
    assert carte["created_at"].day == 16


def test_le_client_reste_anonyme():
    """Ni le client ni le rendez-vous : rien qui permette de retrouver qui a noté."""
    assert set(review_card(_avis())) == {"id", "rating", "comment", "created_at"}


def test_un_avis_sans_commentaire_garde_sa_note():
    carte = review_card(_avis(comment="", rating=2))
    assert carte["rating"] == 2
    assert carte["comment"] == ""
