"""Style DNA — contrat de sortie, normalisation et garde-fous d'entrée.

L'appel vision lui-même n'est pas testé ici (il exige une clé API et facture un
appel). Ce qui est testé, c'est tout ce qui l'entoure : le schéma imposé au
modèle, la validation de sa réponse, et les refus avant tout appel réseau.
"""
import asyncio

import pytest
from fastapi import HTTPException

from app.services.style_dna_service import (
    FACE_SHAPES,
    RESULT_SCHEMA,
    StyleDnaResult,
    analyze_selfie,
    is_configured,
    normalize,
)

VALID_PAYLOAD = {
    "face_detected": True,
    "face_shape": "oval",
    "shape_label_ar": "وجه بيضاوي",
    "confidence": 0.86,
    "analysis_ar": "وجهك أطول شوية من عرضو والفك مدور.",
    "styles": [
        {
            "name": "Textured Crop",
            "name_ar": "كروب تكستشر",
            "description_ar": "يبين ملامحك بلا ما يطول الوجه.",
            "match_score": 91,
            "tags": ["عصري", "سهل"],
            "recommended": True,
        },
        {
            "name": "Skin Fade",
            "name_ar": "سكين فايد",
            "description_ar": "يوازن الجانبين مع الطول.",
            "match_score": 84,
            "tags": ["فايد"],
            "recommended": False,
        },
    ],
    "avoid_ar": ["شعر طويل مسطح"],
}


# ── Schéma imposé au modèle ──────────────────────────────────────────────────
def _walk_objects(node):
    """Parcourt récursivement tous les sous-schémas de type `object`."""
    if isinstance(node, dict):
        if node.get("type") == "object":
            yield node
        for value in node.values():
            yield from _walk_objects(value)
    elif isinstance(node, list):
        for item in node:
            yield from _walk_objects(item)


def test_chaque_objet_interdit_les_champs_libres():
    """`additionalProperties: false` est exigé partout par les structured outputs."""
    for obj in _walk_objects(RESULT_SCHEMA):
        assert obj.get("additionalProperties") is False


def test_chaque_objet_declare_toutes_ses_proprietes_comme_requises():
    for obj in _walk_objects(RESULT_SCHEMA):
        assert set(obj.get("required", [])) == set(obj["properties"])


def test_le_schema_n_utilise_aucune_contrainte_non_supportee():
    """minimum/maximum/minLength… sont rejetés — les bornes sont vérifiées en Python."""
    interdits = {"minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum",
                 "multipleOf", "minLength", "maxLength", "minItems", "maxItems",
                 "pattern", "uniqueItems"}

    def scan(node):
        if isinstance(node, dict):
            assert not (interdits & node.keys()), f"contrainte non supportée: {node}"
            for value in node.values():
                scan(value)
        elif isinstance(node, list):
            for item in node:
                scan(item)

    scan(RESULT_SCHEMA)


def test_les_formes_de_visage_sont_enumerees():
    enum = RESULT_SCHEMA["properties"]["face_shape"]["enum"]
    assert enum == FACE_SHAPES
    assert "oval" in enum and "heart" in enum


# ── Validation de la réponse ─────────────────────────────────────────────────
def test_une_reponse_conforme_est_acceptee():
    result = StyleDnaResult.model_validate(VALID_PAYLOAD)
    assert result.face_detected is True
    assert result.face_shape == "oval"
    assert len(result.styles) == 2
    assert result.styles[0].recommended is True


def test_absence_de_visage_reste_exploitable():
    """Le modèle doit pouvoir dire « pas de visage » sans champs superflus."""
    result = StyleDnaResult.model_validate({
        "face_detected": False,
        "face_shape": "",
        "shape_label_ar": "",
        "confidence": 0.0,
        "analysis_ar": "",
        "styles": [],
        "avoid_ar": [],
    })
    assert result.face_detected is False
    assert result.styles == []


# ── Normalisation ────────────────────────────────────────────────────────────
def test_les_scores_hors_bornes_sont_ramenes():
    result = StyleDnaResult.model_validate({
        **VALID_PAYLOAD,
        "confidence": 1.4,
        "styles": [
            {**VALID_PAYLOAD["styles"][0], "match_score": 120},
            {**VALID_PAYLOAD["styles"][1], "match_score": -5},
        ],
    })
    normalize(result)
    assert result.confidence == 1.0
    assert [s.match_score for s in result.styles] == [100, 0]


def test_les_coupes_sont_triees_par_pertinence():
    result = StyleDnaResult.model_validate({
        **VALID_PAYLOAD,
        "styles": [
            {**VALID_PAYLOAD["styles"][0], "match_score": 60},
            {**VALID_PAYLOAD["styles"][1], "match_score": 95},
        ],
    })
    normalize(result)
    assert [s.match_score for s in result.styles] == [95, 60]


# ── Garde-fous avant tout appel réseau ───────────────────────────────────────
def test_sans_cle_api_le_service_se_declare_indisponible():
    assert is_configured() is False


@pytest.mark.parametrize("media", ["application/pdf", "text/plain", "image/gif"])
def test_format_non_image_refuse(media):
    with pytest.raises(HTTPException) as exc:
        asyncio.run(analyze_selfie(b"x", media))
    assert exc.value.status_code == 415


def test_selfie_trop_lourd_refuse():
    with pytest.raises(HTTPException) as exc:
        asyncio.run(analyze_selfie(b"x" * (6 * 1024 * 1024), "image/jpeg"))
    assert exc.value.status_code == 413


def test_sans_cle_api_l_analyse_renvoie_503():
    """La taille et le format sont valides : c'est bien la clé qui manque."""
    with pytest.raises(HTTPException) as exc:
        asyncio.run(analyze_selfie(b"fake-jpeg-bytes", "image/jpeg"))
    assert exc.value.status_code == 503
