"""Le salon voit qui vient (§3.3).

Un RDV réservé dans l'app s'affichait « Client » : seuls les walk-in portaient
un nom. Le salon ne savait ni qui venait, ni qui appeler en cas de retard.
"""
from app.services.booking_service import attach_client_identity

COMPTES = {"u1": ("Mehdi Ben Salah", "+21698000000")}


def test_un_rdv_pris_dans_l_app_montre_le_nom_du_compte():
    (rdv,) = attach_client_identity([{"client_id": "u1", "client_name": ""}], COMPTES)
    assert rdv["client_name"] == "Mehdi Ben Salah"
    assert rdv["client_phone"] == "+21698000000"


def test_un_walk_in_garde_le_nom_saisi():
    """Le nom tapé par le salon fait foi : il n'est jamais écrasé."""
    (rdv,) = attach_client_identity(
        [{"client_id": None, "client_name": "Zboun", "client_phone": "+21622000000"}], COMPTES
    )
    assert rdv["client_name"] == "Zboun"
    assert rdv["client_phone"] == "+21622000000"


def test_un_nom_deja_present_n_est_pas_remplace():
    (rdv,) = attach_client_identity([{"client_id": "u1", "client_name": "Mehdi"}], COMPTES)
    assert rdv["client_name"] == "Mehdi"
    assert rdv["client_phone"] == "+21698000000", "le téléphone manquant est complété"


def test_un_compte_introuvable_laisse_le_rdv_tel_quel():
    (rdv,) = attach_client_identity([{"client_id": "inconnu", "client_name": ""}], COMPTES)
    assert rdv["client_name"] == ""


def test_un_nom_fait_d_espaces_compte_comme_vide():
    (rdv,) = attach_client_identity([{"client_id": "u1", "client_name": "  "}], COMPTES)
    assert rdv["client_name"] == "Mehdi Ben Salah"


def test_les_rdv_d_origine_ne_sont_pas_modifies():
    rdvs = [{"client_id": "u1", "client_name": ""}]
    attach_client_identity(rdvs, COMPTES)
    assert rdvs[0]["client_name"] == ""
