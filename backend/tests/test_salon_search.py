"""Recherche de salons par nom de salon ou de coiffeur (§3.2).

Le champ de l'app annonce « صالون، حجام » : un client qui tape le prénom de
son coiffeur doit retrouver le salon où il travaille. Et le texte tapé ne doit
jamais être lu comme une expression régulière.
"""
import re

from bson import ObjectId

from app.api.v1.salons import search_clause


def motif(clause: dict) -> str:
    return clause["$or"][0]["name"]["$regex"]


def test_sans_coiffeur_correspondant_seul_le_nom_du_salon_compte():
    assert search_clause("Berber", []) == {
        "$or": [{"name": {"$regex": "Berber", "$options": "i"}}]
    }


def test_le_salon_d_un_coiffeur_trouve_est_inclus():
    salon = ObjectId()
    clause = search_clause("Rania", [salon])

    assert {"_id": {"$in": [salon]}} in clause["$or"]
    assert {"name": {"$regex": "Rania", "$options": "i"}} in clause["$or"]


def test_la_recherche_ignore_la_casse():
    assert search_clause("rania", [])["$or"][0]["name"]["$options"] == "i"


def test_les_espaces_autour_ne_comptent_pas():
    assert motif(search_clause("  Berber King  ", [])) == re.escape("Berber King")


def test_une_parenthese_ne_casse_pas_la_recherche():
    """Tapée telle quelle, « ( » produisait une expression invalide et une
    erreur serveur."""
    brut = motif(search_clause("Rania (Menzah", []))
    assert re.compile(brut).search("Studio Rania (Menzah 6)")


def test_des_caracteres_speciaux_sont_pris_a_la_lettre():
    """« .* » ne doit pas renvoyer tous les salons."""
    brut = motif(search_clause(".*", []))
    assert re.compile(brut).search("Barbier El Menzah") is None
    assert re.compile(brut).search("Salon .* test")
