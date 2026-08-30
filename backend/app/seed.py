"""Jeu de données de démonstration — `python -m app.seed`.

Crée 3 salons tunisiens, leur équipe, leur catalogue, des RDV et une journée de
caisse déjà encaissée, afin de tester l'app pro sans saisie manuelle.
"""
import asyncio
import random
import sys
from datetime import timedelta

from beanie import PydanticObjectId

from app.core.db import init_db
from app.core.timeutils import combine_local, to_local, utcnow
from app.services import public_code
from app.models.documents import (
    ALL_DOCUMENTS,
    Advance,
    CashMovement,
    Booking,
    GeoPoint,
    PortfolioItem,
    Review,
    Salon,
    Service,
    StaffMember,
    Transaction,
    User,
)
from app.models.enums import (
    AdvanceStatus,
    CashMovementType,
    BookingSource,
    BookingStatus,
    CommissionType,
    PaymentMethod,
    Role,
    SalonType,
)
from app.services.split_engine import SplitEngine

SALONS = [
    {
        "name": "Barbier El Menzah",
        "type": SalonType.BARBERSHOP,
        "coords": [10.1795, 36.8412],
        "address": "Rue du Lac, El Menzah 6",
        "city": "Tunis",
        "services": [
            ("Coupe homme", "قص شعر", 15, 30),
            ("Skin fade", "فايد", 25, 45),
            ("Barbe", "لحية", 10, 20),
            ("Coupe + barbe", "قص + لحية", 22, 50),
        ],
        "staff": [("Ahmed Trabelsi", 1, 50), ("Youssef Ben Ali", 2, 55)],
    },
    {
        "name": "Rania Beauty Lounge",
        "type": SalonType.FEMME,
        "coords": [10.1658, 36.8625],
        "address": "Avenue Habib Bourguiba, Ariana",
        "city": "Ariana",
        "services": [
            ("Brushing", "تجفيف", 30, 45),
            ("Coloration", "صباغة", 120, 120),
            ("Soin capillaire", "علاج الشعر", 60, 60),
            ("Manucure", "مانيكير", 25, 40),
        ],
        "staff": [("Rania Gharbi", 1, 60), ("Ines Mabrouk", 2, 50), ("Sonia Khelifi", 3, 45)],
    },
    {
        "name": "Studio Mariées Carthage",
        "type": SalonType.MARIEES,
        "coords": [10.3236, 36.8525],
        "address": "Rue Hannibal, Carthage",
        "city": "Carthage",
        "services": [
            ("Pack mariée complet", "باكاج عروسة", 450, 240),
            ("Maquillage soirée", "مكياج", 90, 60),
            ("Chignon", "شينيون", 70, 75),
        ],
        "staff": [("Leila Hammami", 1, 55)],
    },
]

TAGS = ["fade", "degrade", "barbe", "balayage", "chignon", "mariee", "coloration"]


async def wipe() -> None:
    for model in ALL_DOCUMENTS:
        collection = (
            model.get_pymongo_collection()
            if hasattr(model, "get_pymongo_collection")
            else model.get_motor_collection()
        )
        await collection.drop()


async def seed() -> None:
    # Sous Git Bash / cmd.exe la sortie est en cp1252 : les coches du récapitulatif
    # feraient planter le script une fois les données déjà écrites.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    await init_db()
    await wipe()
    # Vider une collection supprime aussi ses index. Sans cette seconde
    # initialisation, l'index 2dsphere disparaît et « GET /salons?near= »
    # renvoie 500 jusqu'au prochain redémarrage de l'API.
    await init_db()
    random.seed(42)

    client_users = []
    for i, name in enumerate(
        ["Mehdi Ferjani", "Sarra Bouzid", "Karim Nasri", "Nour Chaabane", "Wael Jlassi"]
    ):
        user = User(phone=f"+2169800000{i}", name=name, role=Role.CLIENT, locale="fr")
        await user.insert()
        client_users.append(user)

    now = utcnow()
    today = to_local(now).date()

    for index, blueprint in enumerate(SALONS):
        owner = User(
            phone=f"+2169900000{index}",
            name=f"Gérant {blueprint['name']}",
            role=Role.OWNER,
        )
        await owner.insert()

        salon = Salon(
            owner_id=owner.id,
            name=blueprint["name"],
            type=blueprint["type"],
            location=GeoPoint(coordinates=blueprint["coords"]),
            address=blueprint["address"],
            city=blueprint["city"],
            phone=owner.phone,
            description="Salon partenaire LAMSSA — démo.",
            trial_ends_at=now + timedelta(days=30),
        )
        # `assign` insère lui-même : il doit réessayer si le code est déjà pris.
        await public_code.assign(salon)

        services = []
        for name, name_ar, price, duration in blueprint["services"]:
            service = Service(
                salon_id=salon.id,
                name=name,
                name_ar=name_ar,
                price=float(price),
                duration_min=duration,
                buffer_min=10,
                category=blueprint["type"].value,
            )
            await service.insert()
            services.append(service)

        members = []
        for staff_index, (name, chair, pct) in enumerate(blueprint["staff"]):
            staff_user = User(
                phone=f"+21697{index}0000{staff_index}", name=name, role=Role.STAFF
            )
            await staff_user.insert()
            member = StaffMember(
                salon_id=salon.id,
                user_id=staff_user.id,
                display_name=name,
                chair_number=chair,
                commission_type=CommissionType.PERCENT,
                commission_pct=float(pct),
                service_ids=[s.id for s in services],
                bio="Spécialiste maison.",
                specialties=random.sample(TAGS, 2),
            )
            await member.insert()
            members.append(member)

            for k in range(3):
                await PortfolioItem(
                    staff_id=member.id,
                    salon_id=salon.id,
                    image_url=f"/media/demo/{blueprint['type'].value}_{staff_index}_{k}.jpg",
                    caption=f"Réalisation {k + 1} — {name}",
                    tags=random.sample(TAGS, 2),
                    # `likes` est un compteur dénormalisé de `liked_by`, et
                    # l'API le recalcule à chaque like. Un compteur inventé sans
                    # `liked_by` correspondant s'effondrerait dès le premier
                    # like réel (71 → 1) : la démo aurait l'air cassée. On
                    # remplit donc de vrais identifiants — les cinq clients de
                    # démo, complétés par des « likers » anonymes.
                    liked_by=(likers := random.sample(
                        [c.id for c in client_users], k=random.randint(0, len(client_users))
                    ) + [PydanticObjectId() for _ in range(random.randint(0, 60))]),
                    likes=len(likers),
                ).insert()
            member.portfolio_count = 3
            await member.save()

        # ── Journée écoulée : RDV terminés + transactions (caisse du jour) ──
        # Le seed peut tourner à n'importe quelle heure. Avant l'ouverture, les
        # créneaux « métier » (9 h et plus) sont tous à venir : sans repli, la
        # caisse du jour serait vide et la démo montrerait un salon sans recette.
        day_start = combine_local(today, "00:00")
        elapsed = (now - day_start).total_seconds()
        total_slots = len(members) * 3
        placed = 0

        for hour_offset, member in enumerate(members):
            for slot in range(3):
                service = random.choice(services)
                start = combine_local(today, f"{9 + hour_offset * 2 + slot:02d}:00")
                if start >= now:
                    # Repli : on répartit sur le temps déjà écoulé depuis minuit,
                    # en heure locale, pour que la transaction reste « du jour ».
                    start = day_start + timedelta(
                        seconds=elapsed * (placed + 1) / (total_slots + 1)
                    )
                placed += 1
                client = random.choice(client_users)
                walkin = slot == 2
                booking = Booking(
                    salon_id=salon.id,
                    staff_id=member.id,
                    client_id=None if walkin else client.id,
                    service_ids=[service.id],
                    service_names=[service.name],
                    price_total=service.price,
                    start=start,
                    end=start + timedelta(minutes=service.duration_min + service.buffer_min),
                    status=BookingStatus.DONE,
                    source=BookingSource.WALKIN if walkin else BookingSource.APP,
                    client_name="Client passage" if walkin else client.name,
                )
                await booking.insert()

                split = SplitEngine.for_staff(
                    service.price, member, tip=random.choice([0, 0, 2, 5])
                )
                await Transaction(
                    booking_id=booking.id,
                    salon_id=salon.id,
                    staff_id=member.id,
                    amount=split.amount,
                    method=random.choice(
                        [PaymentMethod.CASH, PaymentMethod.CASH, PaymentMethod.CARD]
                    ),
                    salon_share=split.salon_share,
                    staff_share=split.staff_share,
                    tip=split.tip,
                    paid_at=start + timedelta(minutes=service.duration_min),
                ).insert()
                member.cuts_count += 1

                if not walkin and random.random() < 0.6:
                    review = Review(
                        booking_id=booking.id,
                        salon_id=salon.id,
                        staff_id=member.id,
                        client_id=client.id,
                        rating=random.choice([4, 5, 5, 5]),
                        comment=random.choice(
                            ["Impeccable !", "Très pro, je reviens.", "Top qualité."]
                        ),
                    )
                    await review.insert()
            await member.save()

        # ── RDV à venir (agenda de demain) ──
        for slot, member in enumerate(members):
            service = random.choice(services)
            start = combine_local(today + timedelta(days=1), f"{10 + slot:02d}:00")
            client = random.choice(client_users)
            await Booking(
                salon_id=salon.id,
                staff_id=member.id,
                client_id=client.id,
                service_ids=[service.id],
                service_names=[service.name],
                price_total=service.price,
                start=start,
                end=start + timedelta(minutes=service.duration_min + service.buffer_min),
                status=BookingStatus.CONFIRMED,
                client_name=client.name,
            ).insert()

        # ── Fond de caisse du jour ──
        # Sans lui, la trésorerie de démo démarre à zéro et le premier achat
        # de produits affiche un tiroir négatif : aucun salon ne fonctionne
        # ainsi, on ouvre toujours avec de la monnaie.
        await CashMovement(
            salon_id=salon.id,
            type=CashMovementType.OPENING_FLOAT,
            amount=200.0,
            label="Fond de caisse",
            day=to_local(utcnow()).date(),
            created_by=salon.owner_id,
        ).insert()

        # ── Une tséb9a en attente pour tester le circuit de validation ──
        await Advance(
            salon_id=salon.id,
            staff_id=members[0].id,
            amount=float(random.choice([50, 80, 100])),
            reason="Avance début de mois",
            status=AdvanceStatus.PENDING,
        ).insert()

        # Notes moyennes dénormalisées
        for target, field in ((salon, "salon_id"), *[(m, "staff_id") for m in members]):
            result = await Review.aggregate(
                [
                    {"$match": {field: target.id, "status": "published"}},
                    {"$group": {"_id": None, "avg": {"$avg": "$rating"}, "n": {"$sum": 1}}},
                ]
            ).to_list()
            if result:
                target.rating_avg = round(result[0]["avg"], 2)
                target.rating_count = result[0]["n"]
                await target.save()

        print(f"✔ {salon.name} — {len(members)} membre(s), {len(services)} service(s)")

    print("\nComptes de démo (OTP dev : 000000)")
    print("  Gérants  : +21699000000 / +21699000001 / +21699000002")
    print("  Coiffeurs: +21697000000 (Ahmed) / +21697100000 (Rania)")
    print("  Clients  : +21698000000 … +21698000004")


if __name__ == "__main__":
    asyncio.run(seed())
