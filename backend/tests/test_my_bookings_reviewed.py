"""« Mes rendez-vous » dit si l'avis a déjà été laissé (§3.8).

L'app ne le retenait qu'en mémoire : après un redémarrage, le bouton « قيّم »
revenait sur un RDV déjà noté, et le serveur refusait le second avis.
"""
from app.api.v1.bookings import mark_reviewed


def test_un_rdv_deja_note_est_signale():
    rdvs = [{"id": "b1", "status": "DONE"}, {"id": "b2", "status": "DONE"}]

    marques = mark_reviewed(rdvs, {"b1"})

    assert marques[0]["reviewed"] is True
    assert marques[1]["reviewed"] is False


def test_sans_avis_aucun_rdv_n_est_marque():
    assert mark_reviewed([{"id": "b1"}], set()) == [{"id": "b1", "reviewed": False}]


def test_l_identifiant_mongo_brut_est_reconnu():
    """Selon la sérialisation, l'identifiant sort en `id` ou en `_id`."""
    assert mark_reviewed([{"_id": "b1"}], {"b1"})[0]["reviewed"] is True


def test_le_reste_du_rdv_est_conserve():
    marque = mark_reviewed([{"id": "b1", "price_total": 25.0}], {"b1"})[0]
    assert marque["price_total"] == 25.0


def test_la_liste_d_origine_n_est_pas_modifiee():
    rdvs = [{"id": "b1"}]
    mark_reviewed(rdvs, {"b1"})
    assert "reviewed" not in rdvs[0]
