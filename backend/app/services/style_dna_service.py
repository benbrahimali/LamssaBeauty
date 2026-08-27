"""Style DNA (§2.4 « Could », §8.5) — analyse d'un selfie par un modèle vision.

Choix d'architecture : l'analyse tourne **côté serveur**, jamais dans l'app.
Une clé API embarquée dans un binaire mobile est extractible en quelques minutes ;
le selfie transite donc vers le backend, qui seul détient la clé.

Le selfie n'est **jamais** écrit sur disque ni journalisé — l'écran promet
« الصورة ما تتحفظش » (la photo n'est pas conservée) et le code doit tenir cette promesse.
"""
import base64
import json
import logging

from anthropic import (
    APIConnectionError,
    APIStatusError,
    AsyncAnthropic,
    RateLimitError,
)
from fastapi import HTTPException, status
from pydantic import BaseModel, Field, ValidationError

from app.core.config import settings

log = logging.getLogger("lamssa.styledna")

ALLOWED_MEDIA = {"image/jpeg", "image/png", "image/webp"}

FACE_SHAPES = ["oval", "round", "square", "heart", "oblong", "diamond", "triangle"]


# ─────────────────────────────────────────────────────────────────────────────
# Contrat de sortie
# ─────────────────────────────────────────────────────────────────────────────
class StyleSuggestion(BaseModel):
    name: str
    name_ar: str
    description_ar: str
    match_score: int
    tags: list[str]
    recommended: bool


class StyleDnaResult(BaseModel):
    face_detected: bool
    face_shape: str = ""
    shape_label_ar: str = ""
    confidence: float = 0.0
    analysis_ar: str = ""
    styles: list[StyleSuggestion] = Field(default_factory=list)
    avoid_ar: list[str] = Field(default_factory=list)
    model: str = ""

    #: Où obtenir chaque coupe, par nom de coupe (§2.4). Rempli après l'appel
    #: au modèle, à partir du catalogue réel : le modèle ne voit jamais ces
    #: données et ne peut donc pas inventer un coiffeur.
    matches: dict[str, list] = Field(default_factory=dict)


#: Schéma imposé au modèle. Les contraintes numériques (`minimum`/`maximum`) ne
#: sont pas supportées par les structured outputs — les bornes sont donc décrites
#: en langage naturel dans les `description`, puis re-vérifiées côté Python.
RESULT_SCHEMA = {
    "type": "object",
    "properties": {
        "face_detected": {
            "type": "boolean",
            "description": "false si l'image ne montre pas un visage humain exploitable",
        },
        "face_shape": {
            "type": "string",
            "enum": FACE_SHAPES,
            "description": "Forme de visage dominante",
        },
        "shape_label_ar": {
            "type": "string",
            "description": "Nom de la forme en arabe tunisien, ex. « وجه بيضاوي »",
        },
        "confidence": {
            "type": "number",
            "description": "Confiance entre 0 et 1",
        },
        "analysis_ar": {
            "type": "string",
            "description": (
                "2 phrases max en arabe tunisien expliquant les proportions observées "
                "(longueur/largeur, mâchoire, pommettes, front)"
            ),
        },
        "styles": {
            "type": "array",
            "description": "3 à 5 coupes adaptées, de la plus à la moins pertinente",
            "items": {
                "type": "object",
                "properties": {
                    "name": {"type": "string", "description": "Nom de la coupe (latin)"},
                    "name_ar": {"type": "string", "description": "Nom en arabe tunisien"},
                    "description_ar": {
                        "type": "string",
                        "description": "1 phrase : pourquoi cette coupe va à cette forme",
                    },
                    "match_score": {
                        "type": "integer",
                        "description": "Compatibilité de 0 à 100",
                    },
                    "tags": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "1 à 3 mots-clés courts en arabe",
                    },
                    "recommended": {
                        "type": "boolean",
                        "description": "true pour la meilleure option uniquement",
                    },
                },
                "required": [
                    "name",
                    "name_ar",
                    "description_ar",
                    "match_score",
                    "tags",
                    "recommended",
                ],
                "additionalProperties": False,
            },
        },
        "avoid_ar": {
            "type": "array",
            "items": {"type": "string"},
            "description": "1 à 3 coupes à éviter pour cette forme, en arabe",
        },
    },
    "required": [
        "face_detected",
        "face_shape",
        "shape_label_ar",
        "confidence",
        "analysis_ar",
        "styles",
        "avoid_ar",
    ],
    "additionalProperties": False,
}

SYSTEM_PROMPT = """Tu es un barbier-styliste tunisien expérimenté qui conseille dans \
l'application LAMSSA. On te montre le selfie d'un client et tu déduis la forme de son \
visage, puis tu proposes les coupes qui lui iront le mieux.

Méthode d'analyse — raisonne sur les proportions, pas sur l'apparence générale :
- rapport longueur du visage / largeur aux pommettes
- largeur du front comparée aux pommettes et à la mâchoire
- angularité de la mâchoire et forme du menton

Règles :
- Tiens compte du sexe apparent, de la longueur et de la texture de cheveux visibles : \
propose des coupes réellement réalisables à partir de ce qu'a la personne.
- Écris en arabe tunisien (dialecte), pas en arabe littéraire.
- Sois concret : « fade côtés + volume dessus », pas « une coupe moderne ».
- Ne commente jamais l'attractivité, le poids, l'âge, l'origine ou la peau. Tu parles \
uniquement de géométrie du visage et de coiffure.
- Si l'image ne montre pas un visage humain exploitable (trop floue, de dos, plusieurs \
visages, objet), mets face_detected à false et laisse les autres champs vides ou à zéro."""


def _client() -> AsyncAnthropic:
    if not settings.ANTHROPIC_API_KEY:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "Style DNA n'est pas configuré sur ce serveur (ANTHROPIC_API_KEY manquante).",
        )
    return AsyncAnthropic(api_key=settings.ANTHROPIC_API_KEY)


def is_configured() -> bool:
    return bool(settings.ANTHROPIC_API_KEY)


def _extract_json(blocks) -> dict:
    """Récupère le JSON du premier bloc texte de la réponse."""
    for block in blocks:
        if getattr(block, "type", None) == "text":
            return json.loads(block.text)
    raise ValueError("Réponse sans bloc texte")


def normalize(result: StyleDnaResult) -> StyleDnaResult:
    """Borne les scores et trie les coupes.

    Les structured outputs garantissent la *forme* du JSON, pas des valeurs dans
    l'intervalle attendu : `confidence: 1.4` ou `match_score: 120` passeraient le
    schéma. On les ramène ici plutôt que de laisser l'app afficher 120 %.
    """
    result.confidence = min(max(result.confidence, 0.0), 1.0)
    for style in result.styles:
        style.match_score = min(max(style.match_score, 0), 100)
    result.styles.sort(key=lambda s: s.match_score, reverse=True)
    return result


async def analyze_selfie(
    image_bytes: bytes,
    media_type: str,
    *,
    hint: str = "",
) -> StyleDnaResult:
    """Analyse un selfie et renvoie forme du visage + coupes conseillées."""
    if media_type not in ALLOWED_MEDIA:
        raise HTTPException(
            status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, "Format accepté : JPEG, PNG ou WebP"
        )
    if len(image_bytes) > settings.STYLE_DNA_MAX_IMAGE_MB * 1024 * 1024:
        raise HTTPException(
            status.HTTP_413_CONTENT_TOO_LARGE,
            f"Selfie trop lourd (max {settings.STYLE_DNA_MAX_IMAGE_MB} Mo)",
        )

    client = _client()
    prompt = "Analyse ce selfie et propose les coupes adaptées."
    if hint.strip():
        prompt += f"\n\nPrécision du client : {hint.strip()[:280]}"

    try:
        response = await client.beta.messages.create(
            model=settings.STYLE_DNA_MODEL,
            max_tokens=8000,
            system=SYSTEM_PROMPT,
            # Fallback serveur : une décision d'un classifieur de sécurité est
            # re-servie par un autre modèle au lieu de renvoyer un refus sec.
            betas=["server-side-fallback-2026-07-01"],
            fallbacks="default",
            output_config={
                "effort": settings.STYLE_DNA_EFFORT,
                "format": {"type": "json_schema", "schema": RESULT_SCHEMA},
            },
            messages=[
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "image",
                            "source": {
                                "type": "base64",
                                "media_type": media_type,
                                "data": base64.standard_b64encode(image_bytes).decode(),
                            },
                        },
                        {"type": "text", "text": prompt},
                    ],
                }
            ],
        )
    except RateLimitError:
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS, "Style DNA saturé, réessaie dans un instant."
        )
    except APIConnectionError:
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY, "Service d'analyse injoignable."
        )
    except APIStatusError as exc:
        log.error("Style DNA %s: %s", exc.status_code, str(exc)[:300])
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, "Analyse indisponible.")
    finally:
        await client.close()

    # Un refus arrive en HTTP 200 : il faut le lire avant `content`.
    if response.stop_reason == "refusal":
        log.warning(
            "Style DNA refus (%s)",
            getattr(response.stop_details, "category", None),
        )
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "Cette image ne peut pas être analysée. Essaie un autre selfie.",
        )

    try:
        result = StyleDnaResult.model_validate(_extract_json(response.content))
    except (ValueError, ValidationError) as exc:
        log.error("Style DNA réponse illisible: %s", exc)
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, "Analyse illisible, réessaie.")

    result.model = response.model
    return normalize(result)
