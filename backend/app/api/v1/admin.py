"""Console d'administration de la plateforme (§9).

Distincte de la gestion d'un salon : un gérant administre SON salon, un
administrateur surveille l'ensemble. Aucune route d'ici ne s'appuie sur
`require_role` — la place d'un compte dans un salon ne dit rien de son droit à
voir les autres.
"""
import re
from datetime import timedelta

from beanie import PydanticObjectId
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.security import require_admin
from app.core.timeutils import local_day_bounds, to_local, utcnow
from app.models.documents import (
    Advance,
    Booking,
    CashClosure,
    CashMovement,
    Expense,
    PortfolioItem,
    RecurringCharge,
    Reel,
    Review,
    Salon,
    Service,
    StaffMember,
    Transaction,
    User,
)
from app.models.enums import ReviewStatus, Role, SalonStatus

router = APIRouter()

#: Nom des salons créés par la suite d'intégration.
#:
#: Volontairement strict : « Salon Test » suivi d'un horodatage, rien d'autre.
#: Un salon réel nommé « Salon Test du quartier » ne doit pas y correspondre.
TEST_SALON = re.compile(r"^Salon Test \d+$")

#: Tout ce qu'un salon peut avoir produit. Un salon qui a produit quoi que ce
#: soit ne se supprime pas : l'historique comptable d'un coiffeur en dépend.
HISTORIQUE = (
    Booking,
    Transaction,
    Review,
    Reel,
    CashClosure,
    Expense,
    RecurringCharge,
    Advance,
    CashMovement,
)


async def _historique(salon_id: PydanticObjectId) -> dict[str, int]:
    """Ce que le salon a produit, collection par collection."""
    compte = {}
    for modele in HISTORIQUE:
        n = await modele.find(modele.salon_id == salon_id).count()
        if n:
            compte[modele.__name__] = n
    return compte


# ─────────────────────────────────────────────────────────────────────────────
# Vue d'ensemble
# ─────────────────────────────────────────────────────────────────────────────
@router.get("/stats", summary="Chiffres de la plateforme")
async def stats(_: User = Depends(require_admin)):
    """Les repères qu'on n'a nulle part ailleurs.

    Le chiffre d'affaires est celui encaissé par les salons, pas un revenu de
    la plateforme : le distinguer évite de se raconter des histoires.
    """
    aujourdhui = to_local(utcnow()).date()
    debut_jour, fin_jour = local_day_bounds(aujourdhui)
    debut_semaine, _fin = local_day_bounds(aujourdhui - timedelta(days=6))

    transactions = await Transaction.find_all().to_list()

    return {
        "salons": {
            "total": await Salon.find_all().count(),
            "ouverts": await Salon.find(Salon.status == SalonStatus.OPEN).count(),
            "fermes": await Salon.find(Salon.status == SalonStatus.CLOSED).count(),
        },
        "comptes": {
            "total": await User.find_all().count(),
            "clients": await User.find(User.role == Role.CLIENT).count(),
            "coiffeurs": await User.find(User.role == Role.STAFF).count(),
            "gerants": await User.find(User.role == Role.OWNER).count(),
        },
        "equipes": await StaffMember.find_all().count(),
        "rdv": {
            "total": await Booking.find_all().count(),
            "aujourdhui": await Booking.find(
                Booking.start >= debut_jour, Booking.start < fin_jour
            ).count(),
            "semaine": await Booking.find(Booking.start >= debut_semaine).count(),
        },
        "encaisse": {
            "transactions": len(transactions),
            # Ce que les salons ont encaissé, tous salons confondus.
            "total": round(sum(t.amount for t in transactions), 2),
            "part_salons": round(sum(t.salon_share for t in transactions), 2),
            "part_equipes": round(sum(t.staff_share for t in transactions), 2),
        },
        "contenus": {
            "reels": await Reel.find_all().count(),
            "portfolio": await PortfolioItem.find_all().count(),
            "avis": await Review.find_all().count(),
            "avis_masques": await Review.find(
                Review.status == ReviewStatus.HIDDEN
            ).count(),
        },
    }


# ─────────────────────────────────────────────────────────────────────────────
# Salons
# ─────────────────────────────────────────────────────────────────────────────
@router.get("/salons", summary="Tous les salons")
async def list_salons(_: User = Depends(require_admin), limit: int = Query(200, le=500)):
    salons = await Salon.find_all().sort("-created_at").limit(limit).to_list()
    lignes = []
    for s in salons:
        proprietaire = await User.get(s.owner_id)
        historique = await _historique(s.id)
        lignes.append(
            {
                "id": str(s.id),
                "name": s.name,
                "type": s.type,
                "city": s.city,
                "status": s.status,
                "photos": len(s.photos),
                "owner_phone": proprietaire.phone if proprietaire else "",
                "owner_name": proprietaire.name if proprietaire else "",
                "staff": await StaffMember.find(StaffMember.salon_id == s.id).count(),
                "services": await Service.find(Service.salon_id == s.id).count(),
                "history": historique,
                # Un salon sans aucun historique peut disparaître sans laisser
                # de trou : c'est le seul cas où la suppression est sûre.
                "deletable": not historique,
                "looks_like_test": bool(TEST_SALON.match(s.name)),
            }
        )
    return {"salons": lignes, "count": len(lignes)}


@router.patch("/salons/{salon_id}/status", summary="Ouvrir ou suspendre un salon")
async def set_status(
    salon_id: PydanticObjectId,
    value: SalonStatus,
    _: User = Depends(require_admin),
):
    """Suspendre = fermer.

    On réutilise le statut existant plutôt que d'en inventer un second : deux
    notions de fermeture divergeraient au premier oubli, et le calcul des
    créneaux n'en connaît qu'une.
    """
    salon = await Salon.get(salon_id)
    if not salon:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Salon introuvable")
    salon.status = value
    await salon.save()
    return {"id": str(salon.id), "status": salon.status}


@router.delete("/salons/{salon_id}", summary="Supprimer un salon sans historique")
async def delete_salon(salon_id: PydanticObjectId, _: User = Depends(require_admin)):
    """Refusé dès qu'il existe le moindre historique.

    Supprimer un salon qui a encaissé effacerait la paie d'un coiffeur et le
    passé d'un client. Un salon devenu inactif se suspend ; il ne s'efface pas.
    """
    salon = await Salon.get(salon_id)
    if not salon:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Salon introuvable")

    historique = await _historique(salon.id)
    if historique:
        detail = ", ".join(f"{k}={v}" for k, v in historique.items())
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            f"Ce salon a un historique ({detail}) — suspendez-le au lieu de le supprimer.",
        )

    services = (await Service.find(Service.salon_id == salon.id).delete()).deleted_count
    equipe = (
        await StaffMember.find(StaffMember.salon_id == salon.id).delete()
    ).deleted_count
    await salon.delete()
    return {"removed": str(salon_id), "services": services, "staff": equipe}


# ─────────────────────────────────────────────────────────────────────────────
# Comptes
# ─────────────────────────────────────────────────────────────────────────────
@router.get("/users", summary="Tous les comptes")
async def list_users(
    _: User = Depends(require_admin),
    role: Role | None = None,
    q: str = "",
    limit: int = Query(200, le=500),
):
    query: dict = {}
    if role is not None:
        query["role"] = role
    if q.strip():
        # Recherche sur le nom ou le téléphone : c'est par l'un ou l'autre
        # qu'on cherche quelqu'un, jamais par son identifiant.
        motif = re.escape(q.strip())
        query["$or"] = [
            {"name": {"$regex": motif, "$options": "i"}},
            {"phone": {"$regex": motif}},
        ]

    users = await User.find(query).sort("-created_at").limit(limit).to_list()
    return {
        "users": [
            {
                "id": str(u.id),
                "phone": u.phone,
                "name": u.name,
                "role": u.role,
                "is_admin": u.is_admin,
                "locale": u.locale,
            }
            for u in users
        ],
        "count": len(users),
    }


# ─────────────────────────────────────────────────────────────────────────────
# Modération
# ─────────────────────────────────────────────────────────────────────────────
@router.get("/reviews", summary="Avis, pour modération")
async def list_reviews(
    _: User = Depends(require_admin),
    hidden: bool | None = None,
    limit: int = Query(100, le=300),
):
    query: dict = {}
    if hidden is not None:
        query["status"] = ReviewStatus.HIDDEN if hidden else ReviewStatus.PUBLISHED

    avis = await Review.find(query).sort("-created_at").limit(limit).to_list()
    lignes = []
    for a in avis:
        salon = await Salon.get(a.salon_id)
        lignes.append(
            {
                "id": str(a.id),
                "rating": a.rating,
                "comment": a.comment,
                "status": a.status,
                "salon": salon.name if salon else "",
                "created_at": a.created_at,
            }
        )
    return {"reviews": lignes, "count": len(lignes)}


@router.patch("/reviews/{review_id}", summary="Masquer ou republier un avis")
async def moderate_review(
    review_id: PydanticObjectId,
    hidden: bool,
    _: User = Depends(require_admin),
):
    """Masquer plutôt que supprimer.

    Un avis effacé ne peut pas être rétabli si la modération était une erreur,
    et la note du salon deviendrait impossible à expliquer.
    """
    avis = await Review.get(review_id)
    if not avis:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Avis introuvable")
    avis.status = ReviewStatus.HIDDEN if hidden else ReviewStatus.PUBLISHED
    await avis.save()
    return {"id": str(avis.id), "status": avis.status}


@router.get("/reels", summary="Reels publiés")
async def list_reels(_: User = Depends(require_admin), limit: int = Query(100, le=300)):
    reels = await Reel.find_all().sort("-created_at").limit(limit).to_list()
    lignes = []
    for r in reels:
        salon = await Salon.get(r.salon_id)
        auteur = await User.get(r.author_id)
        lignes.append(
            {
                "id": str(r.id),
                "caption": r.caption,
                "salon": salon.name if salon else "",
                "author": (auteur.name or auteur.phone) if auteur else "",
                "views": r.views,
                "likes": r.likes,
                "duration_sec": r.duration_sec,
                "thumbnail_url": r.thumbnail_url,
                "created_at": r.created_at,
            }
        )
    return {"reels": lignes, "count": len(lignes)}


@router.delete("/reels/{reel_id}", summary="Retirer un reel")
async def remove_reel(reel_id: PydanticObjectId, _: User = Depends(require_admin)):
    reel = await Reel.get(reel_id)
    if not reel:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Reel introuvable")

    # La vidéo part aussi de Cloudinary : la laisser là ferait payer un
    # stockage pour un contenu que plus personne ne peut voir.
    if reel.public_id:
        from app.services import cloudinary_service

        try:
            await cloudinary_service.destroy(reel.public_id, resource_type="video")
        except Exception:  # noqa: BLE001 — le retrait prime sur le ménage
            pass

    await reel.delete()
    return {"removed": str(reel_id)}


# ─────────────────────────────────────────────────────────────────────────────
# Maintenance
# ─────────────────────────────────────────────────────────────────────────────
@router.get("/maintenance/test-data", summary="Données de test repérées")
async def scan_test_data(_: User = Depends(require_admin)):
    """Ce que la suite d'intégration a laissé derrière elle.

    Chaque exécution crée un salon qu'aucune route ne pouvait supprimer : ils
    s'accumulaient et remontaient à zéro kilomètre dans la recherche.
    """
    trouves = []
    for s in await Salon.find_all().to_list():
        if not TEST_SALON.match(s.name):
            continue
        historique = await _historique(s.id)
        trouves.append(
            {
                "id": str(s.id),
                "name": s.name,
                "history": historique,
                "deletable": not historique,
            }
        )
    return {
        "salons": trouves,
        "count": len(trouves),
        "deletable": sum(1 for t in trouves if t["deletable"]),
    }


@router.delete("/maintenance/test-data", summary="Supprimer les données de test")
async def purge_test_data(_: User = Depends(require_admin)):
    """Deux barrières, jamais une seule : le nom ET l'absence d'historique.

    Le nom seul ne suffirait pas — il reste du texte saisi par un humain, et un
    salon réel qui s'appellerait ainsi ne doit pas disparaître parce qu'il
    ressemble à un artefact.
    """
    supprimes, gardes = [], []
    for s in await Salon.find_all().to_list():
        if not TEST_SALON.match(s.name):
            continue
        historique = await _historique(s.id)
        if historique:
            gardes.append({"name": s.name, "history": historique})
            continue
        await Service.find(Service.salon_id == s.id).delete()
        await StaffMember.find(StaffMember.salon_id == s.id).delete()
        await s.delete()
        supprimes.append(s.name)

    return {"removed": supprimes, "kept": gardes, "count": len(supprimes)}
