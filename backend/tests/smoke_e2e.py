"""Smoke test bout en bout — nécessite MongoDB + Redis actifs.

Déroule le parcours réel du cahier des charges : onboarding gérant, équipe, catalogue,
réservation client, paiement en ligne, encaissement avec split, tséb9a, clôture, avis.

    python -m tests.smoke_e2e
"""
import asyncio
import os
import sys
from datetime import timedelta

import httpx

os.environ.setdefault("MONGO_DB", "lamssa_smoke")

from app.core.db import init_db, redis  # noqa: E402
from app.core.timeutils import combine_local, to_local, utcnow  # noqa: E402
from app.main import app  # noqa: E402
from app.models.documents import ALL_DOCUMENTS  # noqa: E402

# Sous Git Bash / cmd.exe la sortie est en cp1252 et les coches font planter le
# script avant le premier test. On force l'UTF-8 quand c'est possible.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

OK, KO = "  ✓", "  ✗"
failures: list[str] = []


def check(label: str, condition: bool, detail: str = "") -> None:
    print(f"{OK if condition else KO} {label}" + (f" — {detail}" if detail else ""))
    if not condition:
        failures.append(label)


async def token_for(client: httpx.AsyncClient, phone: str, name: str = "") -> str:
    await client.post("/api/v1/auth/otp/request", json={"phone": phone})
    resp = await client.post(
        "/api/v1/auth/otp/verify", json={"phone": phone, "code": "000000", "name": name}
    )
    resp.raise_for_status()
    return resp.json()["access_token"]


def auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


async def main() -> int:
    await init_db()
    for model in ALL_DOCUMENTS:
        await model.get_pymongo_collection().drop()
    await redis.flushdb()
    await init_db()  # recrée les index après le drop

    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as c:
        # ── 1. Onboarding gérant ─────────────────────────────────────────────
        owner = await token_for(c, "+21699111111", "Rania")
        resp = await c.post(
            "/api/v1/salons",
            headers=auth(owner),
            json={
                "name": "Salon Smoke",
                "type": "mixte",
                "lat": 36.8065,
                "lng": 10.1815,
                "address": "Tunis Centre",
                "cancellation_window_h": 2,
            },
        )
        check("Création du salon", resp.status_code == 201, str(resp.status_code))
        salon_id = resp.json()["id"]

        me = await c.get("/api/v1/auth/me", headers=auth(owner))
        check("Le créateur devient OWNER", me.json()["user"]["role"] == "OWNER")

        # ── 2. Catalogue + équipe ────────────────────────────────────────────
        resp = await c.post(
            f"/api/v1/salons/{salon_id}/services",
            headers=auth(owner),
            json={"name": "Skin fade", "price": 25, "duration_min": 45, "buffer_min": 10},
        )
        check("Ajout d'un service", resp.status_code == 201, str(resp.status_code))
        service_id = resp.json()["id"]

        resp = await c.post(
            f"/api/v1/salons/{salon_id}/staff",
            headers=auth(owner),
            json={
                "phone": "+21699222222",
                "display_name": "Ahmed",
                "chair_number": 1,
                "commission_pct": 60,
                "service_ids": [service_id],
            },
        )
        check("Ajout d'un coiffeur (60 %)", resp.status_code == 201, str(resp.status_code))
        staff_id = resp.json()["id"]

        resp = await c.post(
            f"/api/v1/salons/{salon_id}/staff",
            headers=auth(owner),
            json={"phone": "+21699222222", "display_name": "Ahmed"},
        )
        check("Doublon d'équipe refusé", resp.status_code == 409, str(resp.status_code))

        # ── 3. Recherche géo ─────────────────────────────────────────────────
        resp = await c.get("/api/v1/salons", params={"near": "36.8065,10.1815", "max_km": 5})
        found = [s for s in resp.json() if s["id"] == salon_id]
        check("Recherche 2dsphere « près de moi »", bool(found),
              f"{found[0]['distance_km']} km" if found else "absent")

        resp = await c.get("/api/v1/salons", params={"near": "34.7,10.7", "max_km": 5})
        check("Salon hors rayon exclu", all(s["id"] != salon_id for s in resp.json()))

        # ── 4. Créneaux & réservation ────────────────────────────────────────
        # Premier jour réellement ouvert : viser « demain » en dur faisait
        # échouer le test chaque fois qu'il tombait un dimanche, jour de
        # fermeture par défaut.
        slots, payload = [], {}
        jour_ouvert = (to_local(utcnow()) + timedelta(days=1)).date()
        for offset in range(1, 8):
            jour_ouvert = (to_local(utcnow()) + timedelta(days=offset)).date()
            resp = await c.get(
                f"/api/v1/staff/{staff_id}/slots",
                params={"date": str(jour_ouvert), "service_ids": [service_id]},
            )
            payload = resp.json()
            slots = payload["slots"]
            if slots:
                break

        check("Créneaux calculés", len(slots) > 0, f"{len(slots)} créneaux")
        check("Durée = service + buffer", payload.get("duration_min") == 55)
        if not slots:
            print("\nAucun créneau sur 7 jours — arrêt.")
            return 1

        client_token = await token_for(c, "+21698333333", "Mehdi")
        start = slots[len(slots) // 2]["start"]
        resp = await c.post(
            "/api/v1/bookings",
            headers=auth(client_token),
            json={
                "salon_id": salon_id,
                "staff_id": staff_id,
                "service_ids": [service_id],
                "start": start,
            },
        )
        check("Réservation créée", resp.status_code == 201, str(resp.status_code))
        booking = resp.json()
        booking_id = booking["id"]
        check("Statut initial PENDING", booking["status"] == "PENDING")
        check("Prix figé sur le RDV", booking["price_total"] == 25.0)

        # Double réservation du même créneau
        other = await token_for(c, "+21698444444", "Sarra")
        resp = await c.post(
            "/api/v1/bookings",
            headers=auth(other),
            json={
                "salon_id": salon_id,
                "staff_id": staff_id,
                "service_ids": [service_id],
                "start": start,
            },
        )
        check("Double réservation refusée (409)", resp.status_code == 409, str(resp.status_code))

        resp = await c.get(
            f"/api/v1/staff/{staff_id}/slots",
            params={"date": str(jour_ouvert), "service_ids": [service_id]},
        )
        check("Le créneau disparaît de la grille",
              all(s["start"] != start for s in resp.json()["slots"]))

        # ── 5. Paiement en ligne (provider mock) ─────────────────────────────
        resp = await c.post(
            "/api/v1/payments/checkout", headers=auth(client_token),
            json={"booking_id": booking_id},
        )
        check("Checkout initié", resp.status_code == 200, str(resp.status_code))
        pay = resp.json()
        check("Commission plateforme 2,5 %", pay["platform_fee"] == 0.625, str(pay["platform_fee"]))

        ref = pay["checkout_url"].split("/")[-2]
        resp = await c.post(f"/api/v1/payments/mock/{ref}/pay")
        check("Paiement simulé accepté", resp.status_code == 200, str(resp.status_code))

        resp = await c.get(f"/api/v1/bookings/{booking_id}", headers=auth(client_token))
        check("RDV passé en CONFIRMED après paiement", resp.json()["status"] == "CONFIRMED")
        check("payment_status = paid", resp.json()["payment_status"] == "paid")

        # ── 6. Cloisonnement des rôles (§2.5) ────────────────────────────────
        staff_token = await token_for(c, "+21699222222")
        resp = await c.get("/api/v1/cash/today", params={"salon_id": salon_id},
                           headers=auth(staff_token))
        check("STAFF sur /cash/today -> 403", resp.status_code == 403, str(resp.status_code))

        resp = await c.get("/api/v1/cash/today", params={"salon_id": salon_id},
                           headers=auth(client_token))
        check("CLIENT sur /cash/today -> 403", resp.status_code == 403, str(resp.status_code))

        resp = await c.get("/api/v1/cash/today", params={"salon_id": salon_id})
        check("Sans token -> 401", resp.status_code == 401, str(resp.status_code))

        # ── 7. Encaissement + split ──────────────────────────────────────────
        resp = await c.post(
            f"/api/v1/bookings/{booking_id}/complete",
            headers=auth(owner),
            json={"method": "cash", "tip": 5},
        )
        check("Prestation encaissée", resp.status_code == 200, str(resp.status_code))
        split = resp.json()["split"]
        check("Split 60/40 sur 25 DT", (split["staff_share"], split["salon_share"]) == (15.0, 10.0),
              f"{split['staff_share']} / {split['salon_share']}")
        check("Pourboire hors split, 100 % employé", split["staff_payout"] == 20.0)

        resp = await c.post(
            f"/api/v1/bookings/{booking_id}/complete",
            headers=auth(owner), json={"method": "cash"},
        )
        check("Double encaissement refusé", resp.status_code == 409, str(resp.status_code))

        # ── 8. Vue coiffeur cloisonnée ───────────────────────────────────────
        resp = await c.get("/api/v1/cash/me", headers=auth(staff_token))
        mine = resp.json()
        check("Le coiffeur voit SA caisse", mine["my_share"] == 15.0 and mine["tips"] == 5.0,
              f"part {mine['my_share']}, pourboires {mine['tips']}")

        # ── 9. Tséb9a ────────────────────────────────────────────────────────
        resp = await c.post("/api/v1/advances", headers=auth(staff_token),
                            json={"salon_id": salon_id, "amount": 8, "reason": "courses"})
        check("Demande de tséb9a", resp.status_code == 201, str(resp.status_code))
        advance_id = resp.json()["id"]

        resp = await c.post("/api/v1/advances", headers=auth(staff_token),
                            json={"salon_id": salon_id, "amount": 5})
        check("Deuxième demande en attente refusée", resp.status_code == 409, str(resp.status_code))

        resp = await c.patch(f"/api/v1/advances/{advance_id}", headers=auth(owner),
                             json={"approve": True})
        check("Tséb9a approuvée", resp.json()["status"] == "approved")

        # ── 10. Dépense + caisse du jour ─────────────────────────────────────
        await c.post("/api/v1/cash/expenses", params={"salon_id": salon_id},
                     headers=auth(owner), json={"label": "Produits", "amount": 4})

        resp = await c.get("/api/v1/cash/today", params={"salon_id": salon_id},
                           headers=auth(owner))
        caisse = resp.json()
        check("Total du jour", caisse["total"] == 25.0, str(caisse["total"]))
        check("Part salon / part équipe",
              (caisse["salon_total"], caisse["staff_total"]) == (10.0, 15.0))
        check("Ventilation cash", caisse["by_method"] == {"cash": 25.0}, str(caisse["by_method"]))
        check("Dépenses déduites du net salon", caisse["net_salon"] == 6.0, str(caisse["net_salon"]))
        check("Nom de l'employé résolu",
              list(caisse["by_staff"].values())[0]["name"] == "Ahmed")

        # ── 11. Clôture ──────────────────────────────────────────────────────
        resp = await c.post("/api/v1/cash/closures", headers=auth(owner),
                            json={"salon_id": salon_id})
        check("Clôture créée", resp.status_code == 201, str(resp.status_code))
        closure = resp.json()
        check("Tséb9a déduite à la clôture", closure["advances_deducted"] == 8.0,
              str(closure["advances_deducted"]))
        ligne = list(closure["by_staff"].values())[0]
        check("Net employé = part + pourboire - avance", ligne["net_payout"] == 12.0,
              str(ligne["net_payout"]))
        check("Rapport généré", bool(closure["report_path"]), str(closure["report_path"]))

        resp = await c.post("/api/v1/cash/closures", headers=auth(owner),
                            json={"salon_id": salon_id})
        check("Double clôture refusée", resp.status_code == 409, str(resp.status_code))

        resp = await c.get(f"/api/v1/cash/closures/{closure['id']}/report", headers=auth(owner))
        check("Rapport téléchargeable", resp.status_code == 200 and len(resp.content) > 500,
              f"{len(resp.content)} octets")

        # ── 12. Avis vérifié ─────────────────────────────────────────────────
        resp = await c.post("/api/v1/reviews", headers=auth(client_token),
                            json={"booking_id": booking_id, "rating": 5, "comment": "Top"})
        check("Avis déposé sur RDV terminé", resp.status_code == 201, str(resp.status_code))

        resp = await c.post("/api/v1/reviews", headers=auth(client_token),
                            json={"booking_id": booking_id, "rating": 4})
        check("Second avis refusé", resp.status_code == 409, str(resp.status_code))

        resp = await c.get(f"/api/v1/salons/{salon_id}")
        check("Note du salon recalculée", resp.json()["salon"]["rating_avg"] == 5.0)

        # ── 13. Walk-in ──────────────────────────────────────────────────────
        # 08h30 : avant l'ouverture affichée (09h00). Un client de passage doit tout de
        # même pouvoir être saisi, sinon la caisse du salon devient fausse.
        walkin_start = combine_local(jour_ouvert, "08:30")
        resp = await c.post(
            "/api/v1/bookings", headers=auth(owner),
            json={
                "salon_id": salon_id, "staff_id": staff_id, "service_ids": [service_id],
                "start": walkin_start.isoformat(), "source": "walkin",
                "client_name": "Client passage",
            },
        )
        check("Walk-in hors horaires accepté et confirmé d'office",
              resp.status_code == 201 and resp.json()["status"] == "CONFIRMED",
              str(resp.status_code))

        resp = await c.post(
            "/api/v1/bookings", headers=auth(owner),
            json={
                "salon_id": salon_id, "staff_id": staff_id, "service_ids": [service_id],
                "start": walkin_start.isoformat(), "source": "walkin",
                "client_name": "Deuxième passage",
            },
        )
        check("Walk-in en doublon sur la même chaise refusé",
              resp.status_code == 409, str(resp.status_code))

        passe = (to_local(utcnow()) - timedelta(minutes=30)).replace(tzinfo=None)
        resp = await c.post(
            "/api/v1/bookings", headers=auth(owner),
            json={
                "salon_id": salon_id, "staff_id": staff_id, "service_ids": [service_id],
                "start": passe.isoformat(), "source": "walkin", "client_name": "En cours",
            },
        )
        check("Walk-in en cours (heure passée) accepté", resp.status_code == 201,
              str(resp.status_code))

        resp = await c.post(
            "/api/v1/bookings", headers=auth(client_token),
            json={
                "salon_id": salon_id, "staff_id": staff_id, "service_ids": [service_id],
                "start": combine_local(jour_ouvert, "08:30").isoformat(),
            },
        )
        check("RDV client hors horaires toujours refusé", resp.status_code == 409,
              str(resp.status_code))

        resp = await c.post(
            "/api/v1/bookings", headers=auth(client_token),
            json={
                "salon_id": salon_id, "staff_id": staff_id, "service_ids": [service_id],
                "start": walkin_start.isoformat(), "source": "walkin",
                "client_name": "Fraude",
            },
        )
        check("Walk-in interdit à un client", resp.status_code == 403, str(resp.status_code))

        # ── 14. Refresh token ────────────────────────────────────────────────
        r1 = await c.post("/api/v1/auth/otp/request", json={"phone": "+21698555555"})
        r2 = await c.post("/api/v1/auth/otp/verify",
                          json={"phone": "+21698555555", "code": "000000"})
        refresh = r2.json()["refresh_token"]
        resp = await c.post("/api/v1/auth/refresh", json={"refresh_token": refresh})
        check("Refresh accepté", resp.status_code == 200, str(resp.status_code))
        resp = await c.post("/api/v1/auth/refresh", json={"refresh_token": refresh})
        check("Rejeu du refresh refusé (rotation)", resp.status_code == 401, str(resp.status_code))

    await redis.aclose()
    print()
    if failures:
        print(f"{len(failures)} échec(s) : " + ", ".join(failures))
        return 1
    print("Parcours complet validé.")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
