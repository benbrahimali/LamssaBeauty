"""Génération d'images de coupe (§2.4, §8.5) — fournisseur Google Gemini.

Deux usages, volontairement séparés parce qu'ils n'engagent pas la même chose :

1. **Illustration de référence** — une coupe dessinée sur un visage générique,
   selon le genre. Aucune donnée personnelle ne quitte le serveur, et le
   résultat est mis en cache : la même coupe n'est facturée qu'une fois.

2. **Essayage sur selfie** — le visage du client est envoyé au fournisseur.
   C'est une donnée biométrique au sens de la loi tunisienne 2004-63 : elle
   exige un consentement explicite, elle n'est jamais stockée, et l'appel est
   refusé sans ce consentement.

Le modèle vision (Claude) et le modèle d'image (Gemini) sont deux fournisseurs
distincts : Claude ne génère pas d'images.
"""
import base64
import hashlib
import logging
import os

import httpx
from fastapi import HTTPException, status

from app.core.config import settings

log = logging.getLogger("lamssa.imagegen")

API_URL = "https://generativelanguage.googleapis.com/v1beta/interactions"
CACHE_DIR = "./media/style-preview"
#: Une illustration de coupe met plus longtemps qu'un appel JSON classique.
TIMEOUT_SEC = 90

GENDER_SUBJECT = {
    "male": "un homme tunisien",
    "female": "une femme tunisienne",
}

#: Cadrage volontairement neutre : on illustre une coupe, pas une personne.
PREVIEW_PROMPT = (
    "Photographie de coiffure professionnelle, cadrage portrait trois-quarts, "
    "fond studio uni neutre, éclairage doux. Le sujet est {subject} adulte, "
    "visage volontairement générique et neutre. Coiffure : {style}. {details} "
    "Montre nettement la coupe, les longueurs et les finitions sur les côtés. "
    "Pas de texte, pas de logo, pas de filigrane."
)

TRYON_PROMPT = (
    "Modifie uniquement la coiffure de la personne sur cette photo pour lui "
    "donner : {style}. {details} Conserve son visage, sa peau, ses traits, son "
    "expression et l'arrière-plan strictement identiques. Ne change ni l'âge, "
    "ni la morphologie, ni la couleur de peau. Rendu photoréaliste."
)


def is_configured() -> bool:
    return bool(settings.GEMINI_API_KEY)


def _require_key() -> str:
    if not settings.GEMINI_API_KEY:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "La génération d'images n'est pas configurée sur ce serveur "
            "(GEMINI_API_KEY manquante).",
        )
    return settings.GEMINI_API_KEY


def extract_image(payload: dict) -> bytes | None:
    """Récupère les octets de l'image dans la réponse.

    La forme exacte varie selon la version de l'API (`steps[].content[].data`,
    `output_image.data`…). Plutôt que de coder un chemin qui cassera au
    prochain changement, on cherche le premier bloc qui ressemble à une image.
    """
    def walk(node) -> bytes | None:
        if isinstance(node, dict):
            data = node.get("data")
            mime = str(node.get("mime_type") or node.get("mimeType") or "")
            if isinstance(data, str) and (mime.startswith("image/") or not mime):
                if node.get("type") in {"image", None} and len(data) > 256:
                    try:
                        return base64.b64decode(data, validate=True)
                    except (ValueError, TypeError):
                        pass
            for value in node.values():
                found = walk(value)
                if found:
                    return found
        elif isinstance(node, list):
            for item in node:
                found = walk(item)
                if found:
                    return found
        return None

    return walk(payload)


def _is_permanent_quota(body: str) -> bool:
    """Distingue « quota épuisé » de « quota inexistant ».

    Les deux arrivent en 429. Seul le corps les sépare : une limite gratuite à
    zéro veut dire que le modèle demande un compte facturé, et aucune attente
    n'y changera rien.
    """
    return "free_tier" in body and "limit: 0" in body


async def _call(parts: list[dict]) -> bytes:
    key = _require_key()
    body = {"model": settings.GEMINI_IMAGE_MODEL, "input": parts}

    try:
        async with httpx.AsyncClient(timeout=TIMEOUT_SEC) as client:
            resp = await client.post(
                API_URL,
                json=body,
                headers={"x-goog-api-key": key, "Content-Type": "application/json"},
            )
    except httpx.HTTPError as exc:
        log.warning("Gemini injoignable: %s", exc)
        raise HTTPException(
            status.HTTP_504_GATEWAY_TIMEOUT, "Le générateur d'images ne répond pas."
        ) from exc

    if resp.status_code >= 400:
        log.warning("Gemini %s: %s", resp.status_code, resp.text[:300])
        # Le message renvoyé doit correspondre à ce que l'utilisateur peut
        # faire. « Essaie une autre coupe » sur un quota épuisé est un mauvais
        # conseil : changer de coupe ne débloque rien, seule l'attente ou un
        # paiement le fera.
        if resp.status_code == 429:
            # « limit: 0 » sur le palier gratuit n'est pas un quota consommé :
            # le modèle n'y est tout simplement pas offert. Dire « réessaie plus
            # tard » ferait attendre indéfiniment — c'est une facturation à
            # activer, donc un problème de serveur, pas d'utilisateur.
            if _is_permanent_quota(resp.text):
                log.error(
                    "Gemini : %s indisponible sans facturation (quota gratuit à 0)",
                    settings.GEMINI_IMAGE_MODEL,
                )
                raise HTTPException(
                    status.HTTP_503_SERVICE_UNAVAILABLE,
                    "La génération d'images n'est pas disponible sur ce serveur.",
                )
            raise HTTPException(
                status.HTTP_429_TOO_MANY_REQUESTS,
                "Le générateur d'images a atteint sa limite. Réessaie plus tard.",
            )
        if resp.status_code in (401, 403):
            raise HTTPException(
                status.HTTP_503_SERVICE_UNAVAILABLE,
                "La génération d'images n'est pas disponible sur ce serveur.",
            )
        # 400 côté fournisseur = souvent un filtre de sécurité : là, changer de
        # coupe a du sens. On ne renvoie pas son message brut, il n'est pas
        # rédigé pour un client.
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY,
            "L'image n'a pas pu être générée. Essaie une autre coupe.",
        )

    image = extract_image(resp.json())
    if image is None:
        log.warning("Gemini : réponse sans image (%s)", resp.text[:200])
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY, "Le générateur n'a pas renvoyé d'image."
        )
    return image


def cache_key(style: str, gender: str) -> str:
    """Identifiant stable d'une illustration — même coupe, même fichier."""
    raw = f"{style.strip().lower()}|{gender}|{settings.GEMINI_IMAGE_MODEL}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:24]


def cached_path(key: str) -> str:
    return os.path.join(CACHE_DIR, f"{key}.jpg")


async def preview(style: str, *, gender: str = "male", details: str = "") -> str:
    """Illustration de référence d'une coupe. Renvoie une URL servie par l'API.

    Mise en cache sur disque : une coupe populaire n'est payée qu'une fois, quel
    que soit le nombre de clients à qui elle est conseillée.
    """
    subject = GENDER_SUBJECT.get(gender, GENDER_SUBJECT["male"])
    key = cache_key(style, gender)
    path = cached_path(key)
    url = f"/media/style-preview/{key}.jpg"

    if os.path.isfile(path):
        return url

    image = await _call([
        {
            "type": "text",
            "text": PREVIEW_PROMPT.format(
                subject=subject, style=style, details=details
            ),
        }
    ])

    os.makedirs(CACHE_DIR, exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(image)
    return url


async def try_on(
    selfie: bytes,
    media_type: str,
    style: str,
    *,
    details: str = "",
    consent: bool = False,
) -> bytes:
    """Applique une coupe sur le selfie du client.

    Le selfie transite en mémoire et l'image produite est renvoyée directement :
    ni l'un ni l'autre n'est écrit sur disque ou rattaché au compte.
    """
    if not consent:
        # Envoyer un visage à un tiers sans accord explicite serait un
        # traitement de donnée biométrique non consenti (loi 2004-63).
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            "L'essayage envoie ta photo à un service externe : il faut ton "
            "accord explicite.",
        )

    return await _call([
        {
            "type": "text",
            "text": TRYON_PROMPT.format(style=style, details=details),
        },
        {
            "type": "image",
            "mime_type": media_type,
            "data": base64.standard_b64encode(selfie).decode("ascii"),
        },
    ])
