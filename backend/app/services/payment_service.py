"""Paiement en ligne (§3.6) — adaptateurs Konnect / Flouci + provider `mock` pour le dev.

Le reste du code ne connaît que l'interface `PaymentProvider`, ce qui permet de
changer de PSP sans toucher aux routes ni au module caisse.
"""
import hashlib
import hmac
import logging
import uuid
from abc import ABC, abstractmethod

import httpx
from fastapi import HTTPException, status

from app.core.config import settings

log = logging.getLogger("lamssa.payment")


class CheckoutSession:
    def __init__(self, ref: str, url: str, raw: dict | None = None):
        self.ref = ref
        self.url = url
        self.raw = raw or {}


class PaymentProvider(ABC):
    name = "abstract"

    @abstractmethod
    async def create_checkout(
        self, *, amount: float, order_id: str, phone: str, description: str
    ) -> CheckoutSession: ...

    @abstractmethod
    async def verify(self, ref: str) -> bool:
        """Confirme auprès du PSP qu'un paiement est bien encaissé."""

    def parse_webhook(self, payload: dict, query: dict) -> tuple[str, bool]:
        """Retourne (référence PSP, payé ?)."""
        ref = query.get("payment_ref") or payload.get("payment_ref") or payload.get("ref", "")
        paid = str(payload.get("status", "")).lower() in {"completed", "success", "paid"}
        return ref, paid


class MockProvider(PaymentProvider):
    """Provider de développement : génère une URL locale de simulation."""

    name = "mock"

    async def create_checkout(self, *, amount, order_id, phone, description) -> CheckoutSession:
        ref = f"mock_{uuid.uuid4().hex[:16]}"
        log.info("[DEV paiement] %s %.2f %s (%s)", ref, amount, settings.CURRENCY, description)
        return CheckoutSession(ref, f"/api/v1/payments/mock/{ref}/pay")

    async def verify(self, ref: str) -> bool:
        return ref.startswith("mock_")


class KonnectProvider(PaymentProvider):
    name = "konnect"

    async def create_checkout(self, *, amount, order_id, phone, description) -> CheckoutSession:
        body = {
            "receiverWalletId": settings.KONNECT_WALLET_ID,
            "token": settings.CURRENCY,
            "amount": int(round(amount * 1000)),  # Konnect raisonne en millimes
            "type": "immediate",
            "description": description,
            "acceptedPaymentMethods": ["wallet", "bank_card", "e-DINAR"],
            "lifespan": 15,
            "checkoutForm": False,
            "orderId": order_id,
            "webhook": f"{settings.PAYMENT_SUCCESS_URL}",
            "successUrl": settings.PAYMENT_SUCCESS_URL,
            "failUrl": settings.PAYMENT_FAIL_URL,
            "phoneNumber": phone,
        }
        async with httpx.AsyncClient(timeout=20) as client:
            resp = await client.post(
                f"{settings.KONNECT_API_URL}/payments/init-payment",
                json=body,
                headers={"x-api-key": settings.KONNECT_API_KEY},
            )
        if resp.status_code >= 400:
            log.error("Konnect init-payment %s: %s", resp.status_code, resp.text[:300])
            raise HTTPException(status.HTTP_502_BAD_GATEWAY, "Paiement indisponible")
        data = resp.json()
        return CheckoutSession(data["paymentRef"], data["payUrl"], data)

    async def verify(self, ref: str) -> bool:
        async with httpx.AsyncClient(timeout=20) as client:
            resp = await client.get(
                f"{settings.KONNECT_API_URL}/payments/{ref}",
                headers={"x-api-key": settings.KONNECT_API_KEY},
            )
        if resp.status_code >= 400:
            return False
        return resp.json().get("payment", {}).get("status") == "completed"


class FloucIProvider(PaymentProvider):
    name = "flouci"

    async def create_checkout(self, *, amount, order_id, phone, description) -> CheckoutSession:
        body = {
            "app_token": settings.FLOUCI_APP_TOKEN,
            "app_secret": settings.FLOUCI_APP_SECRET,
            "amount": str(int(round(amount * 1000))),
            "accept_card": "true",
            "session_timeout_secs": 1200,
            "success_link": settings.PAYMENT_SUCCESS_URL,
            "fail_link": settings.PAYMENT_FAIL_URL,
            "developer_tracking_id": order_id,
        }
        async with httpx.AsyncClient(timeout=20) as client:
            resp = await client.post(f"{settings.FLOUCI_API_URL}/generate_payment", json=body)
        if resp.status_code >= 400:
            log.error("Flouci generate_payment %s: %s", resp.status_code, resp.text[:300])
            raise HTTPException(status.HTTP_502_BAD_GATEWAY, "Paiement indisponible")
        data = resp.json().get("result", {})
        return CheckoutSession(data.get("payment_id", ""), data.get("link", ""), data)

    async def verify(self, ref: str) -> bool:
        async with httpx.AsyncClient(timeout=20) as client:
            resp = await client.get(
                f"{settings.FLOUCI_API_URL}/verify_payment/{ref}",
                headers={"apppublic": settings.FLOUCI_APP_TOKEN,
                         "appsecret": settings.FLOUCI_APP_SECRET},
            )
        if resp.status_code >= 400:
            return False
        return resp.json().get("result", {}).get("status") == "SUCCESS"


_PROVIDERS: dict[str, type[PaymentProvider]] = {
    "mock": MockProvider,
    "konnect": KonnectProvider,
    "flouci": FloucIProvider,
}


def get_provider() -> PaymentProvider:
    cls = _PROVIDERS.get(settings.PSP_PROVIDER)
    if cls is None:
        raise HTTPException(
            status.HTTP_500_INTERNAL_SERVER_ERROR,
            f"PSP inconnu : {settings.PSP_PROVIDER}",
        )
    return cls()


def platform_fee(amount: float) -> float:
    """Commission plateforme sur paiement en ligne (2–3 % selon §3.6)."""
    return round(amount * settings.PLATFORM_FEE_PCT / 100, 3)


def verify_webhook_signature(raw_body: bytes, signature: str | None) -> None:
    """Empêche qu'un tiers marque un RDV comme payé en appelant le webhook."""
    if settings.ENV != "prod" or settings.PSP_PROVIDER == "mock":
        return
    if not signature:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Signature webhook manquante")
    expected = hmac.new(
        settings.PSP_WEBHOOK_SECRET.encode(), raw_body, hashlib.sha256
    ).hexdigest()
    if not hmac.compare_digest(expected, signature):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Signature webhook invalide")
