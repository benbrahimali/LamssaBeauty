"""Client FCM HTTP v1 (§3.7).

L'API legacy (`POST /fcm/send` + `Authorization: key=…`) a été fermée par Google
le 22/07/2024 : aucune « server key » n'est plus délivrée. L'API v1 s'authentifie
avec le compte de service du projet Firebase, via un jeton OAuth2 obtenu en
échangeant une assertion JWT signée RS256 par la clé privée du compte.

On signe l'assertion nous-mêmes (PyJWT est déjà une dépendance) plutôt que
d'ajouter `google-auth`, dont le rafraîchissement est bloquant et devrait donc
tourner dans un thread pour ne pas figer la boucle asyncio.
"""
from __future__ import annotations

import asyncio
import json
import logging
import time
from pathlib import Path

import httpx
import jwt

from app.core.config import settings

log = logging.getLogger("lamssa.fcm")

SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
GRANT_TYPE = "urn:ietf:params:oauth:grant-type:jwt-bearer"
TOKEN_TTL_SEC = 3600
# On renouvelle un peu avant l'échéance : un jeton qui expire pendant le vol
# ferait échouer l'envoi sans raison visible.
REFRESH_MARGIN_SEC = 120

# Codes renvoyés par FCM quand le token d'appareil est mort pour de bon
# (app désinstallée, token remplacé). Tout autre code est temporaire : on garde
# le token et on réessaiera à la prochaine notification.
DEAD_TOKEN_CODES = {"UNREGISTERED", "INVALID_ARGUMENT", "SENDER_ID_MISMATCH"}


class _Credentials:
    """Compte de service chargé une seule fois, avec son jeton d'accès en cache."""

    def __init__(self, path: Path) -> None:
        data = json.loads(path.read_text(encoding="utf-8"))
        missing = {"client_email", "private_key", "token_uri", "project_id"} - set(data)
        if missing:
            raise ValueError(f"{path} : champs manquants {sorted(missing)}")
        self.client_email: str = data["client_email"]
        self.private_key: str = data["private_key"]
        self.token_uri: str = data["token_uri"]
        self.project_id: str = data["project_id"]
        self._token: str = ""
        self._expires_at: float = 0.0
        self._lock = asyncio.Lock()

    async def access_token(self, client: httpx.AsyncClient) -> str:
        # Le verrou évite que dix notifications simultanées déclenchent dix
        # échanges de jeton au démarrage.
        async with self._lock:
            if self._token and time.time() < self._expires_at:
                return self._token

            now = int(time.time())
            assertion = jwt.encode(
                {
                    "iss": self.client_email,
                    "scope": SCOPE,
                    "aud": self.token_uri,
                    "iat": now,
                    "exp": now + TOKEN_TTL_SEC,
                },
                self.private_key,
                algorithm="RS256",
            )
            resp = await client.post(
                self.token_uri,
                data={"grant_type": GRANT_TYPE, "assertion": assertion},
            )
            resp.raise_for_status()
            payload = resp.json()
            self._token = payload["access_token"]
            self._expires_at = (
                time.time() + payload.get("expires_in", TOKEN_TTL_SEC) - REFRESH_MARGIN_SEC
            )
            return self._token


_creds: _Credentials | None = None
_creds_loaded = False


def credentials() -> _Credentials | None:
    """Charge le compte de service, ou None si le push n'est pas configuré.

    Un fichier absent ou illisible n'est pas une erreur fatale : l'API doit
    tourner sans compte Firebase (dev, CI), les push sont alors seulement loggés.
    """
    global _creds, _creds_loaded
    if _creds_loaded:
        return _creds
    _creds_loaded = True

    raw = settings.FCM_CREDENTIALS_FILE.strip()
    if not raw:
        return None
    path = Path(raw)
    if not path.is_absolute():
        # Chemin relatif = relatif à backend/, pas au répertoire courant du process.
        path = Path(__file__).resolve().parents[2] / path
    if not path.is_file():
        log.warning("FCM désactivé : %s introuvable", path)
        return None
    try:
        _creds = _Credentials(path)
        log.info("FCM v1 actif sur le projet %s", _creds.project_id)
    except (ValueError, json.JSONDecodeError) as exc:
        log.error("FCM désactivé : compte de service illisible (%s)", exc)
    return _creds


def reset_cache() -> None:
    """Recharge le compte de service au prochain appel (tests)."""
    global _creds, _creds_loaded
    _creds, _creds_loaded = None, False


def _error_code(body: dict) -> str:
    """Extrait le code d'erreur FCM, qui vit dans les `details` et pas à la racine."""
    error = body.get("error", {})
    for detail in error.get("details", []):
        if detail.get("@type", "").endswith("FcmError"):
            return detail.get("errorCode", "")
    return error.get("status", "")


async def send(
    tokens: list[str], title: str, body: str, data: dict[str, str]
) -> list[str]:
    """Envoie une notification et renvoie les tokens à supprimer définitivement.

    L'API v1 n'accepte qu'un destinataire par requête — il n'y a pas d'équivalent
    REST à `registration_ids`. On parallélise donc les envois.
    """
    creds = credentials()
    if creds is None:
        return []

    project_id = settings.FCM_PROJECT_ID.strip() or creds.project_id
    url = f"https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"

    async with httpx.AsyncClient(timeout=10) as client:
        try:
            access_token = await creds.access_token(client)
        except (httpx.HTTPError, KeyError) as exc:
            log.warning("FCM : jeton OAuth2 refusé (%s)", exc)
            return []

        headers = {"Authorization": f"Bearer {access_token}"}

        async def send_one(token: str) -> str | None:
            message = {
                "token": token,
                "notification": {"title": title, "body": body},
                "data": data,
                "android": {"priority": "HIGH"},
                "apns": {"headers": {"apns-priority": "10"}},
            }
            try:
                resp = await client.post(url, json={"message": message}, headers=headers)
            except httpx.HTTPError as exc:  # réseau : jamais fatal pour la requête en cours
                log.warning("FCM injoignable: %s", exc)
                return None
            if resp.status_code < 400:
                return None
            try:
                code = _error_code(resp.json())
            except ValueError:
                code = ""
            if code in DEAD_TOKEN_CODES:
                return token
            log.warning("FCM %s (%s): %s", resp.status_code, code, resp.text[:200])
            return None

        results = await asyncio.gather(*(send_one(t) for t in tokens))

    return [t for t in results if t]
