"""Stockage des médias (§4.1).

Trois destinations, choisies par la configuration : Cloudinary (photos de salon
et reels), S3/R2, ou le disque local. L'ordre n'est pas arbitraire — Cloudinary
sait redimensionner et générer les vignettes des vidéos, ce que ni S3 ni le
disque ne font.
"""
import logging
import os
import uuid

from fastapi import HTTPException, UploadFile, status

from app.core.config import settings
from app.services import cloudinary_service

log = logging.getLogger("lamssa.storage")

ALLOWED = {"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp"}
LOCAL_DIR = "./media"


async def save_image(file: UploadFile, folder: str) -> str:
    """Valide puis enregistre une image, et retourne son URL publique."""
    ext = ALLOWED.get(file.content_type or "")
    if ext is None:
        raise HTTPException(
            status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, "Format accepté : JPEG, PNG ou WebP"
        )
    payload = await file.read()
    if len(payload) > settings.MAX_UPLOAD_MB * 1024 * 1024:
        raise HTTPException(
            status.HTTP_413_CONTENT_TOO_LARGE,
            f"Image trop lourde (max {settings.MAX_UPLOAD_MB} Mo)",
        )

    if cloudinary_service.is_configured():
        result = await cloudinary_service.upload(
            payload, f"{uuid.uuid4().hex}{ext}", f"lamssa/{folder}"
        )
        return result["url"]

    key = f"{folder}/{uuid.uuid4().hex}{ext}"
    if settings.S3_KEY and settings.S3_ENDPOINT:
        return _upload_s3(key, payload, file.content_type)

    path = os.path.join(LOCAL_DIR, key)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(payload)
    return f"/media/{key}"


def _upload_s3(key: str, payload: bytes, content_type: str) -> str:
    try:
        import boto3
    except ImportError:
        raise HTTPException(
            status.HTTP_500_INTERNAL_SERVER_ERROR,
            "boto3 requis pour le stockage S3 (pip install boto3)",
        )
    client = boto3.client(
        "s3",
        endpoint_url=settings.S3_ENDPOINT,
        aws_access_key_id=settings.S3_KEY,
        aws_secret_access_key=settings.S3_SECRET,
    )
    client.put_object(
        Bucket=settings.S3_BUCKET, Key=key, Body=payload, ContentType=content_type
    )
    base = settings.S3_PUBLIC_BASE or f"{settings.S3_ENDPOINT}/{settings.S3_BUCKET}"
    return f"{base.rstrip('/')}/{key}"
