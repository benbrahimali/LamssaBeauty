"""Tâches planifiées déclenchées par HTTP (§3.3, §3.4, §5.5).

Sur un hébergement sans worker permanent — Render gratuit — Celery beat ne
tourne pas : aucun rappel J-1 ni H-2 ne partait, et rien ne le signalait. Un
service de cron externe appelle donc cette route toutes les cinq minutes. Le
travail réel reste dans `app.workers.tasks` : Celery et cette route exécutent
exactement les mêmes fonctions.

Appeler plus souvent que le beat n'est sûr que parce que chaque tâche est
idempotente — sauf la relance de clôture, qui n'a aucune marque et relancerait
chaque gérant à chaque appel. Elle ne part donc qu'une fois par jour, après
21 h, comme sous Celery.
"""
import hmac
from datetime import datetime

from fastapi import APIRouter, Header, HTTPException, status

from app.core.config import settings
from app.core.db import redis
from app.core.timeutils import to_local, utcnow
from app.workers.tasks import (
    _closure_reminder,
    _expire_pending,
    _mark_no_shows,
    _send_reminders,
)

router = APIRouter()

#: Heure locale à partir de laquelle la relance de clôture part (celle du beat).
HEURE_CLOTURE = 21

#: Durée du verrou : plus longue qu'une exécution, plus courte que l'intervalle
#: du cron, pour qu'un verrou orphelin n'empêche pas l'appel suivant.
VERROU_SEC = 240


def secret_valide(recu: str | None, attendu: str) -> bool:
    """Compare en temps constant : une comparaison ordinaire laisserait deviner
    le secret caractère par caractère en mesurant la durée des refus."""
    if not attendu or not recu:
        return False
    return hmac.compare_digest(recu.encode(), attendu.encode())


def cloture_due(maintenant_local: datetime) -> bool:
    return maintenant_local.hour >= HEURE_CLOTURE


def cle_cloture(maintenant_local: datetime) -> str:
    """Une clé par jour local : c'est ce qui limite la relance à une par soir."""
    return f"cron:cloture:{maintenant_local.date().isoformat()}"


@router.post("/cron", summary="Exécuter les tâches planifiées")
async def run_cron(x_cron_secret: str | None = Header(default=None)):
    if not settings.CRON_SECRET:
        # Désactivée tant qu'aucun secret n'est configuré : on ne dit même pas
        # qu'elle existe.
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Not Found")
    if not secret_valide(x_cron_secret, settings.CRON_SECRET):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Secret invalide")

    # Deux appels simultanés liraient les mêmes RDV avant que l'un n'ait posé
    # sa marque, et enverraient chacun le rappel.
    if not await redis.set("cron:verrou", "1", nx=True, ex=VERROU_SEC):
        return {"skipped": "exécution déjà en cours"}

    try:
        resultat = {
            "reminders": await _send_reminders(),
            "expired_pending": await _expire_pending(),
            "no_shows": await _mark_no_shows(),
            "closure_reminders": None,
        }
        local = to_local(utcnow())
        # La marque du jour est posée AVANT l'envoi : si l'envoi échoue en
        # route, mieux vaut un gérant non relancé qu'un gérant relancé vingt
        # fois par les appels suivants.
        if cloture_due(local) and await redis.set(
            cle_cloture(local), "1", nx=True, ex=26 * 3600
        ):
            resultat["closure_reminders"] = await _closure_reminder()
        return resultat
    finally:
        await redis.delete("cron:verrou")
