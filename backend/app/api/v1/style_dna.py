"""Style DNA — analyse d'un selfie et suggestion de coupes (§2.4, §8.5)."""
from fastapi import APIRouter, Depends, File, Form, Response, UploadFile

from app.core.security import current_user
from app.models.documents import User
from app.services import image_gen_service
from app.services.style_match import find_matches
from app.services.style_dna_service import (
    StyleDnaResult,
    analyze_selfie,
    is_configured,
)

router = APIRouter()


@router.get("/status", summary="Style DNA est-il disponible ?")
async def style_dna_status():
    """Permet à l'app de masquer ce que le serveur ne peut pas rendre.

    Les deux fournisseurs sont indépendants : l'analyse peut marcher sans la
    génération d'images, et l'app doit pouvoir n'afficher que ce qui existe.
    """
    return {
        "available": is_configured(),
        "images_available": image_gen_service.is_configured(),
    }


@router.post("/preview", summary="Illustration de référence d'une coupe")
async def style_preview(
    style: str = Form(...),
    gender: str = Form("male"),
    details: str = Form(""),
    user: User = Depends(current_user),
):
    """Dessine la coupe sur un visage générique — aucune donnée personnelle.

    Le résultat est mis en cache par coupe et par genre : une coupe populaire
    n'est facturée qu'une fois.
    """
    url = await image_gen_service.preview(style, gender=gender, details=details)
    return {"url": url}


@router.post("/tryon", summary="Essayer une coupe sur son selfie")
async def style_tryon(
    file: UploadFile = File(...),
    style: str = Form(...),
    details: str = Form(""),
    consent: bool = Form(False),
    user: User = Depends(current_user),
):
    """Applique la coupe sur la photo du client.

    Le selfie part chez un fournisseur externe : c'est une donnée biométrique
    (loi 2004-63), donc `consent` doit être explicitement vrai. Ni la photo
    d'origine ni le rendu ne sont conservés.
    """
    payload = await file.read()
    image = await image_gen_service.try_on(
        payload,
        file.content_type or "application/octet-stream",
        style,
        details=details,
        consent=consent,
    )
    return Response(content=image, media_type="image/jpeg")


@router.post("/analyze", response_model=StyleDnaResult, summary="Analyser un selfie")
async def analyze(
    file: UploadFile = File(...),
    hint: str = Form(""),
    lat: float | None = Form(None),
    lng: float | None = Form(None),
    user: User = Depends(current_user),
):
    """Déduit la forme du visage et propose des coupes adaptées.

    Le selfie est tenu en mémoire le temps de l'appel puis abandonné : il n'est
    ni écrit sur disque, ni journalisé, ni rattaché au compte de l'utilisateur.

    Avec une position, chaque coupe est reliée aux coiffeurs qui savent la faire
    autour du client — sinon l'analyse resterait un conseil sans suite.
    """
    payload = await file.read()
    result = await analyze_selfie(
        payload,
        file.content_type or "application/octet-stream",
        hint=hint,
    )
    if result.face_detected and result.styles:
        result.matches = await find_matches(result.styles, lat=lat, lng=lng)
    return result
