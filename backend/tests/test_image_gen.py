"""Génération d'images de coupe (§2.4).

Le fournisseur n'est pas joignable en test : ce qui est vérifié ici, c'est ce
qui doit tenir sans lui — le refus sans consentement, la dégradation sans clé,
la stabilité du cache et l'extraction de l'image quelle que soit la forme exacte
de la réponse.
"""
import base64

import pytest
from fastapi import HTTPException

from app.core.config import settings
from app.services import image_gen_service as gen

#: Assez long pour passer le seuil qui distingue une image d'un identifiant.
FAKE_IMAGE = b"\xff\xd8\xff\xe0" + b"lamssa" * 100
FAKE_B64 = base64.standard_b64encode(FAKE_IMAGE).decode()


@pytest.fixture(autouse=True)
def _restore_key():
    original = settings.GEMINI_API_KEY
    yield
    settings.GEMINI_API_KEY = original


# ── Disponibilité ────────────────────────────────────────────────────────────
def test_sans_cle_la_fonctionnalite_se_declare_indisponible():
    settings.GEMINI_API_KEY = ""
    assert gen.is_configured() is False


def test_avec_cle_la_fonctionnalite_se_declare_disponible():
    settings.GEMINI_API_KEY = "test-key"
    assert gen.is_configured() is True


@pytest.mark.asyncio
async def test_sans_cle_l_appel_echoue_en_503_et_pas_en_500():
    """L'app doit pouvoir distinguer « non configuré » d'une panne."""
    settings.GEMINI_API_KEY = ""
    with pytest.raises(HTTPException) as exc:
        await gen.preview("Fade")
    assert exc.value.status_code == 503


# ── Consentement ─────────────────────────────────────────────────────────────
@pytest.mark.asyncio
async def test_l_essayage_est_refuse_sans_consentement_explicite():
    """Le selfie part chez un tiers : donnée biométrique, loi 2004-63.

    Le refus doit tomber AVANT tout appel réseau — d'où une clé configurée ici :
    si le consentement n'était vérifié qu'après, ce test partirait en timeout.
    """
    settings.GEMINI_API_KEY = "test-key"
    with pytest.raises(HTTPException) as exc:
        await gen.try_on(FAKE_IMAGE, "image/jpeg", "Fade", consent=False)
    assert exc.value.status_code == 403


@pytest.mark.asyncio
async def test_le_defaut_du_consentement_est_le_refus():
    settings.GEMINI_API_KEY = "test-key"
    with pytest.raises(HTTPException) as exc:
        await gen.try_on(FAKE_IMAGE, "image/jpeg", "Fade")
    assert exc.value.status_code == 403


# ── Cache ────────────────────────────────────────────────────────────────────
def test_la_meme_coupe_donne_la_meme_cle():
    assert gen.cache_key("Fade", "male") == gen.cache_key("fade", "male")
    assert gen.cache_key("Fade", "male") == gen.cache_key("  FADE  ", "male")


def test_le_genre_change_l_illustration_donc_la_cle():
    assert gen.cache_key("Fade", "male") != gen.cache_key("Fade", "female")


def test_deux_coupes_differentes_ne_partagent_pas_leur_cache():
    assert gen.cache_key("Fade", "male") != gen.cache_key("Undercut", "male")


def test_changer_de_modele_invalide_le_cache():
    """Sinon une illustration d'un ancien modèle resterait servie indéfiniment."""
    before = gen.cache_key("Fade", "male")
    original = settings.GEMINI_IMAGE_MODEL
    try:
        settings.GEMINI_IMAGE_MODEL = "autre-modele"
        assert gen.cache_key("Fade", "male") != before
    finally:
        settings.GEMINI_IMAGE_MODEL = original


def test_la_cle_est_utilisable_comme_nom_de_fichier():
    key = gen.cache_key("Fade / dégradé « spécial »", "male")
    assert key.isalnum()
    assert gen.cached_path(key).endswith(f"{key}.jpg")


# ── Extraction de l'image ────────────────────────────────────────────────────
def test_l_image_est_trouvee_dans_les_etapes():
    payload = {
        "steps": [
            {"content": [{"type": "text", "text": "ok"}]},
            {"content": [{"type": "image", "mime_type": "image/jpeg", "data": FAKE_B64}]},
        ]
    }
    assert gen.extract_image(payload) == FAKE_IMAGE


def test_l_image_est_trouvee_dans_la_propriete_de_commodite():
    """La forme de la réponse varie selon la version de l'API."""
    payload = {"output_image": {"mime_type": "image/png", "data": FAKE_B64}}
    assert gen.extract_image(payload) == FAKE_IMAGE


def test_une_reponse_sans_image_ne_leve_pas():
    assert gen.extract_image({"steps": [{"content": [{"type": "text", "text": "non"}]}]}) is None


def test_un_identifiant_court_n_est_pas_pris_pour_une_image():
    """`data: "abc"` dans un champ de métadonnées ne doit pas passer pour l'image."""
    payload = {"meta": {"data": "abc123", "type": "image"}}
    assert gen.extract_image(payload) is None


def test_une_donnee_base64_invalide_est_ignoree():
    payload = {"content": [{"type": "image", "mime_type": "image/jpeg", "data": "!" * 400}]}
    assert gen.extract_image(payload) is None


# ── Invites ──────────────────────────────────────────────────────────────────
@pytest.mark.parametrize("gender", ["male", "female"])
def test_le_sujet_de_l_illustration_suit_le_genre(gender):
    assert gender in gen.GENDER_SUBJECT


def test_un_genre_inconnu_ne_fait_pas_planter_l_invite():
    subject = gen.GENDER_SUBJECT.get("autre", gen.GENDER_SUBJECT["male"])
    assert subject


def test_l_essayage_demande_de_preserver_le_visage():
    """Sans cette consigne, le modèle « embellit » et change la personne."""
    prompt = gen.TRYON_PROMPT.format(style="Fade", details="")
    for exigence in ("visage", "expression", "peau"):
        assert exigence in prompt.lower()


# ── Traduction des erreurs du fournisseur ────────────────────────────────────
@pytest.mark.asyncio
@pytest.mark.parametrize(
    "statut_fournisseur,statut_attendu,extrait",
    [
        (429, 429, "plus tard"),      # quota épuisé : attendre, pas changer de coupe
        (403, 503, "disponible"),     # clé refusée : l'app doit masquer la fonction
        (401, 503, "disponible"),
        (400, 502, "autre coupe"),    # filtre de sécurité : changer d'invite aide
        (500, 502, "autre coupe"),
    ],
)
async def test_l_erreur_rendue_correspond_a_ce_que_l_utilisateur_peut_faire(
    monkeypatch, statut_fournisseur, statut_attendu, extrait
):
    """Un message qui conseille l'impossible est pire que pas de message."""
    import httpx

    _configure_gemini()

    class FauxClient:
        async def __aenter__(self):
            return self

        async def __aexit__(self, *a):
            return False

        async def post(self, *a, **k):
            return httpx.Response(statut_fournisseur, json={"error": {"message": "x"}})

    monkeypatch.setattr(gen.httpx, "AsyncClient", lambda *a, **k: FauxClient())

    with pytest.raises(HTTPException) as exc:
        await gen.preview("Fade")
    assert exc.value.status_code == statut_attendu
    assert extrait in exc.value.detail


def _configure_gemini():
    settings.GEMINI_API_KEY = "test-key"
