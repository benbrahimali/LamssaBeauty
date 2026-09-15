"""Authentification par OTP SMS (§3.1) + gestion du compte courant."""
import logging
import random

from fastapi import APIRouter, Depends, HTTPException, UploadFile, status

from app.core.config import settings
from app.core.db import redis
from app.core.security import create_tokens, current_user, revoke_refresh, rotate_refresh
from app.models.documents import (
    StaffMember,
    User,
    may_have_avatar,
    may_self_activate_pro,
)
from app.services import cloudinary_service
from app.services.storage_service import save_image
from app.schemas.auth import (
    AuthOut,
    DeviceToken,
    MeUpdate,
    OTPRequest,
    OTPVerify,
    RefreshRequest,
    TokenPair,
    UserOut,
)

router = APIRouter()
log = logging.getLogger("lamssa.auth")

OTP_KEY = "otp:{phone}"
ATTEMPTS_KEY = "otp:attempts:{phone}"
COOLDOWN_KEY = "otp:cooldown:{phone}"


def _user_out(user: User) -> UserOut:
    return UserOut(
        id=str(user.id),
        phone=user.phone,
        name=user.name,
        role=user.role,
        locale=user.locale,
        avatar_url=user.avatar_url,
    )


@router.post("/otp/request", summary="Envoyer un code OTP par SMS")
async def request_otp(body: OTPRequest):
    cooldown = COOLDOWN_KEY.format(phone=body.phone)
    if await redis.get(cooldown):
        ttl = await redis.ttl(cooldown)
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            f"Patientez {max(ttl, 1)} s avant de redemander un code",
        )

    code = f"{random.randint(0, 999999):06d}"
    await redis.set(OTP_KEY.format(phone=body.phone), code, ex=settings.OTP_TTL_SEC)
    await redis.delete(ATTEMPTS_KEY.format(phone=body.phone))
    await redis.set(cooldown, "1", ex=settings.OTP_RESEND_COOLDOWN_SEC)

    from app.services.notification_service import send_sms

    await send_sms(body.phone, f"LAMSSA : votre code de connexion est {code}")
    if not settings.is_prod:
        log.info("[DEV OTP] %s -> %s", body.phone, code)

    payload = {"sent": True, "expires_in": settings.OTP_TTL_SEC}
    if not settings.is_prod:
        payload["dev_code"] = code   # confort de dev, jamais exposé en prod
    return payload


@router.post("/otp/verify", response_model=AuthOut, summary="Vérifier l'OTP et obtenir un JWT")
async def verify_otp(body: OTPVerify):
    attempts_key = ATTEMPTS_KEY.format(phone=body.phone)
    attempts = int(await redis.get(attempts_key) or 0)
    if attempts >= settings.OTP_MAX_ATTEMPTS:
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS, "Trop de tentatives — redemandez un code"
        )

    stored = await redis.get(OTP_KEY.format(phone=body.phone))
    dev_bypass = (
        not settings.is_prod
        and settings.OTP_DEV_CODE
        and body.code == settings.OTP_DEV_CODE
    )
    if not dev_bypass and (not stored or stored != body.code):
        await redis.incr(attempts_key)
        await redis.expire(attempts_key, settings.OTP_TTL_SEC)
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Code OTP invalide ou expiré")

    await redis.delete(OTP_KEY.format(phone=body.phone), attempts_key)

    user = await User.find_one(User.phone == body.phone)
    if not user:
        user = User(phone=body.phone, name=body.name, locale=body.locale)
        await user.insert()
    elif body.name and not user.name:
        user.name = body.name
        await user.save()

    # Le drapeau se recalcule à chaque connexion à partir de la configuration :
    # retirer un numéro de ADMIN_PHONES retire l'accès, sans avoir à toucher
    # la base.
    admin = user.phone in settings.admin_phones
    if user.is_admin != admin:
        user.is_admin = admin
        await user.save()

    tokens = await create_tokens(str(user.id), user.role)
    return AuthOut(**tokens, user=_user_out(user))


@router.post("/refresh", response_model=TokenPair, summary="Renouveler l'access token")
async def refresh(body: RefreshRequest):
    return TokenPair(**await rotate_refresh(body.refresh_token))


@router.post("/logout", status_code=204, summary="Révoquer la session")
async def logout(body: RefreshRequest):
    await revoke_refresh(body.refresh_token)


@router.get("/me", summary="Profil courant + rattachements")
async def me(user: User = Depends(current_user)):
    memberships = await StaffMember.find(StaffMember.user_id == user.id).to_list()
    from app.models.documents import Salon

    owned = await Salon.find(Salon.owner_id == user.id).to_list()
    return {
        "user": _user_out(user),
        "staff_profiles": memberships,
        "owned_salons": [
            {
                "id": str(s.id),
                "name": s.name,
                "type": s.type,
                # Absent = salon antérieur à la vérification, donc visible.
                "verification": s.verification_status.value
                if s.verification_status
                else "verified",
                "rejection_reason": s.rejection_reason,
            }
            for s in owned
        ],
        # L'app s'en sert pour montrer ou non « ouvrir un salon ». Le serveur
        # refuse de toute façon : ce drapeau évite d'offrir un bouton qui mène
        # à un 403, il ne protège rien à lui seul.
        "can_create_salon": user.may_open_salon(),
    }


@router.post("/me/pro", summary="Se déclarer professionnel (« عندي صالون »)")
async def become_pro(user: User = Depends(current_user)):
    """Ouvre le formulaire de création au gérant qui s'inscrit.

    Ce n'est pas une porte ouverte : le salon qu'il créera reste invisible des
    clients tant que LAMSSA ne l'a pas vérifié. Un coiffeur employé est refusé —
    il travaille déjà dans un salon et n'a pas à en ouvrir un depuis ce compte.

    Idempotent : l'appeler deux fois ne change rien. Le jour où l'accès
    deviendra un abonnement, c'est ici que commencera la période d'essai.
    """
    if not user.may_open_salon():
        employe = await StaffMember.find_one(StaffMember.user_id == user.id)
        if not may_self_activate_pro(has_staff_profile=employe is not None):
            raise HTTPException(
                status.HTTP_403_FORBIDDEN,
                "Ce compte est rattaché à un salon comme coiffeur : il ne peut pas "
                "ouvrir de salon. Contactez LAMSSA si vous vous installez à votre compte.",
            )
        user.pro_access = True
        user.pro_access_until = None
        await user.save()
    return {"can_create_salon": True}


@router.post("/me/avatar", response_model=UserOut, summary="Changer sa photo de profil")
async def upload_avatar(file: UploadFile, user: User = Depends(current_user)):
    """Réservé aux coiffeurs et aux gérants — voir `may_have_avatar`.

    L'ancienne photo est retirée de Cloudinary : sans ce ménage, chaque
    changement laisserait une image orpheline, stockée et jamais affichée.
    """
    employe = await StaffMember.find_one(StaffMember.user_id == user.id)
    if not may_have_avatar(role=user.role, has_staff_profile=employe is not None):
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            "La photo de profil est réservée aux coiffeurs et aux gérants.",
        )
    ancienne = user.avatar_url
    user.avatar_url = await save_image(file, f"avatars/{user.id}")
    await user.save()
    await cloudinary_service.destroy(cloudinary_service.public_id_from_url(ancienne) or "")
    return _user_out(user)


@router.delete("/me/avatar", response_model=UserOut, summary="Retirer sa photo de profil")
async def remove_avatar(user: User = Depends(current_user)):
    """Ouvert à tous : retirer une photo ne doit jamais être refusé, même à
    un coiffeur qui a quitté son salon depuis."""
    ancienne = user.avatar_url
    if ancienne:
        user.avatar_url = None
        await user.save()
        await cloudinary_service.destroy(
            cloudinary_service.public_id_from_url(ancienne) or ""
        )
    return _user_out(user)


@router.patch("/me", response_model=UserOut, summary="Mettre à jour son profil")
async def update_me(body: MeUpdate, user: User = Depends(current_user)):
    for field, value in body.model_dump(exclude_none=True).items():
        setattr(user, field, value)
    await user.save()
    return _user_out(user)


@router.post("/me/device", status_code=204, summary="Enregistrer un token FCM")
async def register_device(body: DeviceToken, user: User = Depends(current_user)):
    if body.fcm_token not in user.fcm_tokens:
        user.fcm_tokens.append(body.fcm_token)
        await user.save()


@router.delete("/me/device", status_code=204, summary="Retirer un token FCM")
async def unregister_device(body: DeviceToken, user: User = Depends(current_user)):
    if body.fcm_token in user.fcm_tokens:
        user.fcm_tokens.remove(body.fcm_token)
        await user.save()
