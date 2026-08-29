"""Stockage Cloudinary et règles des reels (§3.2, §3.8).

Le fournisseur n'est pas joignable en test. Ce qui est vérifié ici, c'est ce
qui doit tenir sans lui : la signature des requêtes, la dégradation sans clés,
la dérivation de la vignette, et le plafond de durée des reels.
"""
import hashlib

import pytest
from fastapi import HTTPException

from app.core.config import settings
from app.services import cloudinary_service as cloud


@pytest.fixture(autouse=True)
def _restore_keys():
    saved = (
        settings.CLOUDINARY_CLOUD_NAME,
        settings.CLOUDINARY_API_KEY,
        settings.CLOUDINARY_API_SECRET,
    )
    yield
    (
        settings.CLOUDINARY_CLOUD_NAME,
        settings.CLOUDINARY_API_KEY,
        settings.CLOUDINARY_API_SECRET,
    ) = saved


def _configure():
    settings.CLOUDINARY_CLOUD_NAME = "lamssa"
    settings.CLOUDINARY_API_KEY = "123456789"
    settings.CLOUDINARY_API_SECRET = "secret-de-test"


# ── Disponibilité ────────────────────────────────────────────────────────────
def test_sans_cles_le_stockage_cloud_est_inactif():
    settings.CLOUDINARY_CLOUD_NAME = ""
    assert cloud.is_configured() is False


def test_une_seule_cle_manquante_suffit_a_desactiver():
    """Une configuration à moitié remplie doit être traitée comme absente."""
    _configure()
    settings.CLOUDINARY_API_SECRET = ""
    assert cloud.is_configured() is False


@pytest.mark.asyncio
async def test_sans_cles_l_envoi_echoue_en_503_et_pas_en_500():
    settings.CLOUDINARY_CLOUD_NAME = ""
    with pytest.raises(HTTPException) as exc:
        await cloud.upload(b"data", "photo.jpg", "lamssa/salons")
    assert exc.value.status_code == 503


# ── Signature ────────────────────────────────────────────────────────────────
def test_la_signature_suit_l_ordre_alphabetique_des_parametres():
    """Cloudinary recalcule la sienne dans cet ordre : une autre clé est refusée."""
    _configure()
    params = {"timestamp": "1700000000", "folder": "lamssa/reels"}

    attendu = hashlib.sha1(
        b"folder=lamssa/reels&timestamp=1700000000secret-de-test"
    ).hexdigest()

    assert cloud.sign(params) == attendu


def test_deux_envois_differents_ne_partagent_pas_leur_signature():
    _configure()
    a = cloud.sign({"timestamp": "1", "folder": "a"})
    b = cloud.sign({"timestamp": "1", "folder": "b"})
    assert a != b


def test_le_secret_n_apparait_jamais_dans_la_signature():
    """La signature part sur le réseau ; le secret, jamais."""
    _configure()
    assert "secret-de-test" not in cloud.sign({"timestamp": "1"})


# ── Vignette ─────────────────────────────────────────────────────────────────
def test_la_vignette_est_derivee_de_l_url_video():
    """Pas de second envoi : Cloudinary génère l'image à la volée."""
    url = "https://res.cloudinary.com/lamssa/video/upload/v1/lamssa/reels/x.mp4"
    vignette = cloud.thumbnail_url(url)

    assert vignette.endswith(".jpg")
    assert "so_1" in vignette, "prise à la première seconde, pas sur un écran noir"
    assert "/video/upload/" in vignette


def test_une_url_inattendue_ne_casse_pas_l_affichage():
    """Un média stocké ailleurs doit rester affichable, pas produire une URL cassée."""
    url = "https://exemple.tn/video.mp4"
    assert cloud.thumbnail_url(url) == url


def test_une_url_vide_ne_leve_pas():
    assert cloud.thumbnail_url("") == ""


# ── Règles des reels ─────────────────────────────────────────────────────────
def test_la_duree_maximale_reste_celle_d_une_story():
    # Au-delà, ce n'est plus une story : personne ne la regarde jusqu'au bout
    # dans un fil.
    assert 30 <= settings.REEL_MAX_SECONDS <= 120


def test_le_poids_maximal_reste_televersable_en_3g():
    """Beaucoup de salons tunisiens publieront depuis un partage de connexion."""
    assert settings.REEL_MAX_MB <= 100


def test_les_formats_video_courants_des_telephones_sont_acceptes():
    from app.api.v1.reels import ALLOWED_VIDEO

    # MP4 sur Android, MOV sur iPhone : refuser l'un des deux exclurait
    # la moitié des utilisateurs.
    assert "video/mp4" in ALLOWED_VIDEO
    assert "video/quicktime" in ALLOWED_VIDEO


def test_une_image_n_est_pas_acceptee_comme_reel():
    from app.api.v1.reels import ALLOWED_VIDEO

    assert "image/jpeg" not in ALLOWED_VIDEO


# ── Plafond de durée ─────────────────────────────────────────────────────────
@pytest.mark.asyncio
async def test_une_video_dans_les_temps_est_acceptee():
    from app.api.v1.reels import enforce_duration

    assert await enforce_duration({"duration": 42.5, "public_id": "x"}) == 42.5


@pytest.mark.asyncio
async def test_une_video_trop_longue_est_refusee(monkeypatch):
    from app.api.v1 import reels

    with pytest.raises(HTTPException) as exc:
        await reels.enforce_duration(
            {"duration": settings.REEL_MAX_SECONDS + 1, "public_id": "trop-long"}
        )
    assert exc.value.status_code == 422
    assert str(settings.REEL_MAX_SECONDS) in exc.value.detail


@pytest.mark.asyncio
async def test_une_video_refusee_est_supprimee_du_fournisseur(monkeypatch):
    """Sinon on paierait le stockage d'un média que personne ne verra."""
    from app.api.v1 import reels

    supprimes = []

    async def fake_destroy(public_id, *, resource_type="image"):
        supprimes.append((public_id, resource_type))

    monkeypatch.setattr(reels.cloudinary_service, "destroy", fake_destroy)

    with pytest.raises(HTTPException):
        await reels.enforce_duration({"duration": 600, "public_id": "trop-long"})

    assert supprimes == [("trop-long", "video")]


@pytest.mark.asyncio
async def test_une_duree_absente_ne_bloque_pas_la_publication():
    """Cloudinary peut ne pas la renvoyer ; refuser serait pire que de laisser passer."""
    from app.api.v1.reels import enforce_duration

    assert await enforce_duration({"public_id": "x"}) == 0.0


@pytest.mark.asyncio
async def test_la_duree_pile_a_la_limite_passe():
    from app.api.v1.reels import enforce_duration

    limite = float(settings.REEL_MAX_SECONDS)
    assert await enforce_duration({"duration": limite, "public_id": "x"}) == limite
