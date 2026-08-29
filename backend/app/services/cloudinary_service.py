"""Stockage des médias sur Cloudinary (§3.2, §3.8).

Photos de salon et reels vidéo. On signe les requêtes côté serveur plutôt que
d'utiliser un `upload_preset` non signé : un preset embarqué dans l'app
permettrait à n'importe qui d'envoyer ce qu'il veut sur le compte, et la
facturation suit le volume.

Sans clés configurées, l'appelant retombe sur le disque local : le
développement ne doit pas dépendre d'un compte externe.
"""
import hashlib
import logging
import time

import httpx
from fastapi import HTTPException, status

from app.core.config import settings

log = logging.getLogger("lamssa.cloudinary")

API_BASE = "https://api.cloudinary.com/v1_1"
#: Une vidéo met bien plus longtemps à monter qu'une photo.
IMAGE_TIMEOUT = 60
VIDEO_TIMEOUT = 180


def is_configured() -> bool:
    return bool(
        settings.CLOUDINARY_CLOUD_NAME
        and settings.CLOUDINARY_API_KEY
        and settings.CLOUDINARY_API_SECRET
    )


def sign(params: dict[str, str]) -> str:
    """Signature Cloudinary : SHA-1 des paramètres triés + l'API secret.

    L'ordre alphabétique n'est pas un détail esthétique — c'est celui que
    Cloudinary recalcule de son côté, une autre clé produirait une signature
    refusée.
    """
    payload = "&".join(f"{k}={params[k]}" for k in sorted(params))
    return hashlib.sha1(
        f"{payload}{settings.CLOUDINARY_API_SECRET}".encode("utf-8")
    ).hexdigest()


async def _post(resource_type: str, endpoint: str, data: dict, files=None, timeout=60):
    url = f"{API_BASE}/{settings.CLOUDINARY_CLOUD_NAME}/{resource_type}/{endpoint}"
    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            resp = await client.post(url, data=data, files=files)
    except httpx.HTTPError as exc:
        log.warning("Cloudinary injoignable: %s", exc)
        raise HTTPException(
            status.HTTP_504_GATEWAY_TIMEOUT, "L'envoi du média a échoué, réessaie."
        ) from exc

    if resp.status_code >= 400:
        log.warning("Cloudinary %s: %s", resp.status_code, resp.text[:300])
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY, "Le média n'a pas pu être enregistré."
        )
    return resp.json()


async def upload(
    payload: bytes,
    filename: str,
    folder: str,
    *,
    resource_type: str = "image",
) -> dict:
    """Envoie un média et renvoie `{url, public_id, duration}`.

    `duration` n'est renseigné que pour les vidéos — c'est Cloudinary qui la
    mesure, et c'est la seule valeur digne de confiance : un client peut
    annoncer n'importe quoi.
    """
    if not is_configured():
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "Cloudinary n'est pas configuré sur ce serveur.",
        )

    params = {"folder": folder, "timestamp": str(int(time.time()))}
    data = {
        **params,
        "api_key": settings.CLOUDINARY_API_KEY,
        "signature": sign(params),
    }
    body = await _post(
        resource_type,
        "upload",
        data,
        files={"file": (filename, payload)},
        timeout=VIDEO_TIMEOUT if resource_type == "video" else IMAGE_TIMEOUT,
    )
    return {
        "url": body.get("secure_url", ""),
        "public_id": body.get("public_id", ""),
        "duration": float(body["duration"]) if body.get("duration") else None,
        "width": body.get("width"),
        "height": body.get("height"),
    }


async def destroy(public_id: str, *, resource_type: str = "image") -> None:
    """Supprime un média. Utilisé pour ne pas payer le stockage d'un refus."""
    if not is_configured() or not public_id:
        return
    params = {"public_id": public_id, "timestamp": str(int(time.time()))}
    try:
        await _post(
            resource_type,
            "destroy",
            {
                **params,
                "api_key": settings.CLOUDINARY_API_KEY,
                "signature": sign(params),
            },
        )
    except HTTPException:
        # Un ménage raté ne doit pas faire échouer la requête de l'utilisateur.
        log.warning("Cloudinary : suppression de %s échouée", public_id)


def thumbnail_url(video_url: str) -> str:
    """Vignette d'un reel, dérivée de l'URL de la vidéo.

    Cloudinary génère l'image à la volée : pas de second envoi, et le fil peut
    afficher une miniature sans télécharger la vidéo entière.
    """
    if not video_url:
        return ""
    if "/video/upload/" in video_url:
        base = video_url.replace("/video/upload/", "/video/upload/so_1,w_640,c_fill/")
        return base.rsplit(".", 1)[0] + ".jpg"
    return video_url
