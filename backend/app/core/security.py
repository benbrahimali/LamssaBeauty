"""JWT (access + refresh avec rotation) et garde-fous de rôles (§2.5)."""
import uuid
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.config import settings
from app.core.db import redis
from app.models.documents import User
from app.models.enums import Role

bearer = HTTPBearer()
bearer_optional = HTTPBearer(auto_error=False)

REFRESH_KEY = "refresh:{jti}"


def _encode(payload: dict, expires: timedelta) -> str:
    now = datetime.now(timezone.utc)
    return jwt.encode(
        {**payload, "iat": now, "exp": now + expires},
        settings.JWT_SECRET,
        algorithm=settings.JWT_ALGO,
    )


async def create_tokens(user_id: str, role: str) -> dict:
    """Émet une paire access/refresh. Le refresh est enregistré dans Redis (révocable)."""
    jti = uuid.uuid4().hex
    access = _encode(
        {"sub": user_id, "role": role, "type": "access"},
        timedelta(minutes=settings.ACCESS_TTL_MIN),
    )
    refresh = _encode(
        {"sub": user_id, "type": "refresh", "jti": jti},
        timedelta(days=settings.REFRESH_TTL_DAYS),
    )
    await redis.set(
        REFRESH_KEY.format(jti=jti), user_id, ex=settings.REFRESH_TTL_DAYS * 86400
    )
    return {
        "access_token": access,
        "refresh_token": refresh,
        "token_type": "bearer",
        "expires_in": settings.ACCESS_TTL_MIN * 60,
    }


def decode(token: str, expected_type: str) -> dict:
    try:
        payload = jwt.decode(token, settings.JWT_SECRET, algorithms=[settings.JWT_ALGO])
    except jwt.ExpiredSignatureError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Token expiré")
    except jwt.PyJWTError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Token invalide")
    if payload.get("type") != expected_type:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Type de token invalide")
    return payload


async def rotate_refresh(refresh_token: str) -> dict:
    """Consomme un refresh token et en émet un nouveau (rotation, usage unique)."""
    payload = decode(refresh_token, "refresh")
    jti = payload.get("jti", "")
    key = REFRESH_KEY.format(jti=jti)
    if not await redis.get(key):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Session révoquée, reconnectez-vous")
    await redis.delete(key)

    user = await User.get(payload["sub"])
    if not user or not user.is_active:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Utilisateur inconnu ou désactivé")
    return await create_tokens(str(user.id), user.role)


async def revoke_refresh(refresh_token: str) -> None:
    try:
        payload = decode(refresh_token, "refresh")
    except HTTPException:
        return  # logout idempotent : un token déjà mort n'est pas une erreur
    await redis.delete(REFRESH_KEY.format(jti=payload.get("jti", "")))


async def current_user(cred: HTTPAuthorizationCredentials = Depends(bearer)) -> User:
    payload = decode(cred.credentials, "access")
    user = await User.get(payload["sub"])
    if not user or not user.is_active:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Utilisateur inconnu ou désactivé")
    return user


async def optional_user(
    cred: HTTPAuthorizationCredentials | None = Depends(bearer_optional),
) -> User | None:
    """Pour les routes publiques qui s'enrichissent si l'appelant est connecté."""
    if cred is None:
        return None
    try:
        return await current_user(cred)
    except HTTPException:
        return None


async def require_admin(user: User = Depends(current_user)) -> User:
    """Réservé aux administrateurs de la plateforme.

    Indépendant de `require_role` : l'administration ne se déduit pas de la
    place d'un compte dans un salon. Un gérant, si important soit-il, n'a
    aucune raison de voir les salons des autres.
    """
    if not user.is_admin:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, "Réservé à l'administration"
        )
    return user


def require_role(*roles: Role):
    """Middleware de rôle (§6) : un STAFF sur /cash/today reçoit 403."""

    async def dep(user: User = Depends(current_user)) -> User:
        if user.role not in roles:
            raise HTTPException(
                status.HTTP_403_FORBIDDEN,
                f"Accès refusé : rôle {user.role} — requis {', '.join(r.value for r in roles)}",
            )
        return user

    return dep
