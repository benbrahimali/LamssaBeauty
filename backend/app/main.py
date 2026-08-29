"""LAMSSA API — point d'entrée FastAPI (cf. cahier des charges §4.3, §6)."""
import logging
import os
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from app.api.v1 import (
    advances,
    auth,
    bookings,
    cash,
    notifications,
    payments,
    portfolio,
    reels,
    reviews,
    salons,
    staff,
    style_dna,
)
from app.core.config import settings
from app.core.db import close_db, init_db
from app.core.responses import LamssaJSONResponse

logging.basicConfig(
    level=logging.INFO if settings.ENV != "prod" else logging.WARNING,
    format="%(asctime)s %(levelname)-7s %(name)s | %(message)s",
)
log = logging.getLogger("lamssa")


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    log.info("LAMSSA API démarrée en mode %s", settings.ENV)
    yield
    await close_db()


app = FastAPI(
    title="LAMSSA API",
    version="1.0.0",
    description=(
        "Plateforme de réservation & gestion de salons de coiffure et beauté — Tunisie.\n\n"
        "Rôles : `CLIENT`, `STAFF` (coiffeur), `OWNER` (gérant). "
        "Toutes les routes protégées attendent un header `Authorization: Bearer <access_token>`."
    ),
    lifespan=lifespan,
    default_response_class=LamssaJSONResponse,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def timing(request: Request, call_next):
    """Objectif §2.5 : P95 < 300 ms. On expose la latence pour pouvoir la mesurer."""
    started = time.perf_counter()
    response = await call_next(request)
    elapsed_ms = (time.perf_counter() - started) * 1000
    response.headers["X-Response-Time-ms"] = f"{elapsed_ms:.1f}"
    if elapsed_ms > 300:
        log.warning("Lent: %s %s -> %.0f ms", request.method, request.url.path, elapsed_ms)
    return response


@app.exception_handler(ValueError)
async def value_error_handler(request: Request, exc: ValueError):
    return JSONResponse(status_code=400, content={"detail": str(exc)})


V1 = "/api/v1"
app.include_router(auth.router, prefix=f"{V1}/auth", tags=["auth"])
app.include_router(salons.router, prefix=f"{V1}/salons", tags=["salons"])
app.include_router(staff.router, prefix=f"{V1}/staff", tags=["staff"])
app.include_router(bookings.router, prefix=f"{V1}/bookings", tags=["bookings"])
app.include_router(cash.router, prefix=f"{V1}/cash", tags=["caisse"])
app.include_router(advances.router, prefix=f"{V1}/advances", tags=["tséb9a"])
app.include_router(payments.router, prefix=f"{V1}/payments", tags=["paiements"])
app.include_router(reviews.router, prefix=f"{V1}/reviews", tags=["avis"])
app.include_router(portfolio.router, prefix=f"{V1}/portfolio", tags=["portfolio"])
app.include_router(reels.router, prefix=f"{V1}/reels", tags=["reels"])
app.include_router(notifications.router, prefix=f"{V1}/notifications", tags=["notifications"])
app.include_router(style_dna.router, prefix=f"{V1}/style-dna", tags=["style dna"])

# En dev, les médias uploadés sont servis depuis le disque ; en prod ils vont sur S3/R2.
os.makedirs("./media", exist_ok=True)
app.mount("/media", StaticFiles(directory="./media"), name="media")


@app.get("/health", tags=["infra"], summary="Sonde de disponibilité")
async def health():
    from app.core.db import redis
    from app.models.documents import User

    checks = {"api": "ok"}
    try:
        await User.find_one({})
        checks["mongo"] = "ok"
    except Exception as exc:  # noqa: BLE001
        checks["mongo"] = f"ko: {exc}"
    try:
        await redis.ping()
        checks["redis"] = "ok"
    except Exception as exc:  # noqa: BLE001
        checks["redis"] = f"ko: {exc}"

    healthy = all(v == "ok" for v in checks.values())
    return JSONResponse(
        status_code=200 if healthy else 503,
        content={"status": "ok" if healthy else "degraded", **checks},
    )
