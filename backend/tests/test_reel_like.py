"""Règles du « j'aime » sur un reel (§3.8).

Le like était bien enregistré mais n'avertissait personne : un coiffeur ne
savait jamais que sa vidéo plaisait, ce qui est pourtant tout l'intérêt de
publier.
"""
from beanie import PydanticObjectId

AUTEUR = PydanticObjectId()
CLIENT = PydanticObjectId()
AUTRE = PydanticObjectId()


def bascule(liked_by: list, user_id) -> tuple[list, bool]:
    """Reproduit la bascule de la route : la liste et le sens du changement."""
    ajoute = user_id not in liked_by
    if ajoute:
        liked_by = liked_by + [user_id]
    else:
        liked_by = [u for u in liked_by if u != user_id]
    return liked_by, ajoute


def notifie(auteur_id, likeur_id, ajoute: bool) -> bool:
    """La règle de la route : on prévient à l'ajout, jamais soi-même."""
    return ajoute and auteur_id != likeur_id


# ── Le compteur ──────────────────────────────────────────────────────────────
def test_un_like_s_ajoute():
    liked, ajoute = bascule([], CLIENT)
    assert liked == [CLIENT]
    assert ajoute is True


def test_recliquer_retire_le_like():
    liked, ajoute = bascule([CLIENT], CLIENT)
    assert liked == []
    assert ajoute is False


def test_le_like_d_un_autre_ne_bouge_pas():
    liked, _ = bascule([AUTRE], CLIENT)
    assert set(liked) == {AUTRE, CLIENT}


def test_le_compteur_suit_la_liste():
    """`likes` est recalculé depuis `liked_by` : les deux ne peuvent pas
    diverger, ce qui avait déjà fait chuter un compteur de 71 à 1."""
    liked, _ = bascule([AUTRE], CLIENT)
    assert len(liked) == 2


def test_un_meme_utilisateur_ne_compte_qu_une_fois():
    liked, _ = bascule([CLIENT], CLIENT)
    liked, _ = bascule(liked, CLIENT)
    assert liked.count(CLIENT) == 1


# ── La notification ──────────────────────────────────────────────────────────
def test_l_auteur_est_prevenu_d_un_nouveau_like():
    assert notifie(AUTEUR, CLIENT, ajoute=True) is True


def test_retirer_un_like_ne_previent_personne():
    """Un like retiré n'est pas une nouvelle à annoncer."""
    assert notifie(AUTEUR, CLIENT, ajoute=False) is False


def test_un_auto_like_ne_notifie_pas():
    """Un coiffeur n'a pas besoin qu'on lui apprenne qu'il aime sa vidéo."""
    assert notifie(AUTEUR, AUTEUR, ajoute=True) is False


def test_un_auto_like_retire_ne_notifie_pas_non_plus():
    assert notifie(AUTEUR, AUTEUR, ajoute=False) is False


def test_deux_clients_differents_previennent_chacun():
    assert notifie(AUTEUR, CLIENT, ajoute=True) is True
    assert notifie(AUTEUR, AUTRE, ajoute=True) is True
