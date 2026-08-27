"""Notifications (§3.7) : push FCM + SMS critique, avec historique en base.

En dev (`SMS_PROVIDER=console`, `FCM_CREDENTIALS_FILE` vide) tout est loggé au lieu
d'être envoyé : l'API reste utilisable sans compte Firebase ni crédit SMS.
"""
import logging

import httpx
from beanie import PydanticObjectId

from app.core.config import settings
from app.models.documents import Notification, User
from app.models.enums import NotificationType
from app.services import fcm

log = logging.getLogger("lamssa.notify")


async def push_to_tokens(tokens: list[str], title: str, body: str, data: dict) -> list[str]:
    """Pousse la notification et renvoie les tokens que FCM a définitivement rejetés."""
    if not tokens:
        return []
    if fcm.credentials() is None:
        log.info("[DEV push] %s | %s -> %d device(s)", title, body, len(tokens))
        return []
    return await fcm.send(
        tokens, title, body, {k: str(v) for k, v in data.items()}
    )


async def notify(
    user_id: PydanticObjectId,
    type_: NotificationType,
    title: str,
    body: str,
    data: dict | None = None,
) -> Notification:
    """Enregistre la notification (onglet Notifications de l'app) puis pousse en FCM."""
    data = data or {}
    notif = Notification(
        user_id=user_id, type=type_, title=title, body=body, data=data
    )
    await notif.insert()

    user = await User.get(user_id)
    if user and user.fcm_tokens:
        dead = await push_to_tokens(
            user.fcm_tokens, title, body, {**data, "type": type_.value}
        )
        if dead:
            # Sans cette purge, la liste enfle indéfiniment d'appareils
            # désinstallés et chaque notification paie leur échec.
            user.fcm_tokens = [t for t in user.fcm_tokens if t not in dead]
            await user.save()
    return notif


async def notify_many(
    user_ids: list[PydanticObjectId],
    type_: NotificationType,
    title: str,
    body: str,
    data: dict | None = None,
) -> None:
    for uid in {u for u in user_ids if u}:
        await notify(uid, type_, title, body, data)


async def send_sms(phone: str, message: str) -> bool:
    """SMS critique (OTP, rappel H-2). Retourne False si l'envoi a échoué."""
    if settings.SMS_PROVIDER == "console" or settings.ENV != "prod":
        log.info("[DEV SMS] %s -> %s", phone, message)
        return True
    if settings.SMS_PROVIDER == "twilio":
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                resp = await client.post(
                    f"https://api.twilio.com/2010-04-01/Accounts/{settings.TWILIO_SID}/Messages.json",
                    auth=(settings.TWILIO_SID, settings.TWILIO_TOKEN),
                    data={"To": phone, "From": settings.TWILIO_FROM, "Body": message},
                )
                return resp.status_code < 400
        except httpx.HTTPError as exc:
            log.error("Twilio injoignable: %s", exc)
            return False
    log.warning("Provider SMS '%s' non implémenté", settings.SMS_PROVIDER)
    return False
