"""Photo de profil des coiffeurs et des gérants (§2.5, §3.2).

Ce sont eux qu'on voit dans les cartes. Les règles se testent sans base de
données, comme les autres règles du domaine.
"""
from app.api.v1.salons import attach_avatars
from app.models.documents import may_have_avatar
from app.models.enums import Role
from app.schemas.auth import MeUpdate
from app.services.cloudinary_service import public_id_from_url


# ── Qui peut avoir une photo ─────────────────────────────────────────────────
def test_un_client_n_a_pas_de_photo():
    assert may_have_avatar(role=Role.CLIENT, has_staff_profile=False) is False


def test_un_coiffeur_employe_en_a_une():
    """Son compte peut rester CLIENT : c'est sa place dans une équipe qui
    compte, pas le rôle enregistré."""
    assert may_have_avatar(role=Role.CLIENT, has_staff_profile=True) is True
    assert may_have_avatar(role=Role.STAFF, has_staff_profile=True) is True


def test_un_gerant_en_a_une():
    assert may_have_avatar(role=Role.OWNER, has_staff_profile=False) is True


def test_un_ancien_coiffeur_sans_equipe_n_en_ajoute_plus():
    assert may_have_avatar(role=Role.STAFF, has_staff_profile=False) is False


# ── Plus de lien libre ───────────────────────────────────────────────────────
def test_le_profil_n_accepte_plus_de_lien_de_photo():
    """Un lien libre laissait afficher n'importe quelle image hébergée ailleurs."""
    maj = MeUpdate(name="Rania", avatar_url="https://exemple.invalid/traceur.png")
    assert "avatar_url" not in maj.model_dump()
    assert maj.name == "Rania"


# ── Ménage Cloudinary ────────────────────────────────────────────────────────
def test_l_identifiant_cloudinary_se_retrouve_depuis_l_url():
    url = "https://res.cloudinary.com/demo/image/upload/v1712345/lamssa/avatars/u1/abc123.jpg"
    assert public_id_from_url(url) == "lamssa/avatars/u1/abc123"


def test_une_url_sans_version_fonctionne_aussi():
    url = "https://res.cloudinary.com/demo/image/upload/lamssa/avatars/u1/abc.webp"
    assert public_id_from_url(url) == "lamssa/avatars/u1/abc"


def test_on_ne_supprime_rien_hors_cloudinary():
    """Une photo stockée ailleurs — disque local en dev — n'a pas d'identifiant
    Cloudinary : tenter de la supprimer viserait une autre image."""
    assert public_id_from_url("/media/avatars/u1/abc.jpg") is None
    assert public_id_from_url("https://exemple.invalid/photo.jpg") is None


def test_sans_photo_rien_a_supprimer():
    assert public_id_from_url(None) is None
    assert public_id_from_url("") is None


# ── Photo dans l'équipe ──────────────────────────────────────────────────────
def test_chaque_membre_recoit_la_photo_de_son_compte():
    equipe = [
        {"id": "s1", "user_id": "u1", "display_name": "Rania"},
        {"id": "s2", "user_id": "u2", "display_name": "Ahmed"},
    ]
    avec = attach_avatars(equipe, {"u1": "https://res.cloudinary.com/x/rania.jpg"})

    assert avec[0]["avatar_url"] == "https://res.cloudinary.com/x/rania.jpg"
    assert avec[1]["avatar_url"] is None, "sans photo, l'app affiche les initiales"


def test_le_reste_de_la_fiche_est_conserve():
    avec = attach_avatars([{"id": "s1", "user_id": "u1", "chair_number": 2}], {})
    assert avec[0]["chair_number"] == 2
    assert avec[0]["id"] == "s1"


def test_la_liste_d_origine_n_est_pas_modifiee():
    equipe = [{"id": "s1", "user_id": "u1"}]
    attach_avatars(equipe, {"u1": "https://res.cloudinary.com/x/a.jpg"})
    assert "avatar_url" not in equipe[0]
