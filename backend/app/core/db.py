"""Connexions MongoDB (Beanie) et Redis.

Beanie 2.x s'appuie directement sur le client asynchrone de PyMongo ; on garde un
repli sur Motor pour rester compatible avec une installation Beanie 1.x.
"""
import logging

import redis.asyncio as aioredis
from beanie import init_beanie

from app.core.config import settings
from app.models.documents import ALL_DOCUMENTS

log = logging.getLogger("lamssa.db")

try:  # Beanie >= 2 / PyMongo >= 4.9
    from pymongo import AsyncMongoClient as _MongoClient

    _USES_MOTOR = False
except ImportError:  # pragma: no cover — Beanie 1.x
    from motor.motor_asyncio import AsyncIOMotorClient as _MongoClient

    _USES_MOTOR = True

redis = aioredis.from_url(settings.REDIS_URI, decode_responses=True)

_client = None


async def init_db() -> None:
    global _client
    _client = _MongoClient(settings.MONGO_URI, tz_aware=True)
    await init_beanie(database=_client[settings.MONGO_DB], document_models=ALL_DOCUMENTS)
    log.info("MongoDB initialisé (%s/%s)", settings.MONGO_URI, settings.MONGO_DB)


async def close_db() -> None:
    if _client is not None:
        result = _client.close()
        if not _USES_MOTOR:  # AsyncMongoClient.close() est une coroutine
            await result
    await redis.aclose()
