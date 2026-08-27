"""Relie les coupes conseillées par Style DNA à l'offre réelle (§2.4, §8.5).

Sans ce pont, l'analyse rend un conseil générique — « un fade avec du volume
dessus » — que le client doit lui-même traduire en salon, coiffeur, service et
prix. Ce module fait le lien avec le catalogue déjà en base : aucun appel de
modèle supplémentaire, donc aucun coût ajouté.
"""
import math
import unicodedata

from beanie import PydanticObjectId
from pydantic import BaseModel

from app.models.documents import Salon, Service, StaffMember
from app.models.enums import SalonStatus

#: Au-delà, proposer un coiffeur n'a plus de sens pour une coupe de quartier.
DEFAULT_RADIUS_KM = 15.0
MAX_MATCHES_PER_STYLE = 3
#: Nombre de salons examinés autour du client. Large, car tous n'auront pas de
#: coiffeur spécialisé dans la coupe conseillée.
SALON_SCAN_LIMIT = 40


class StyleMatch(BaseModel):
    """Un endroit concret où obtenir la coupe conseillée."""

    staff_id: str
    staff_name: str
    salon_id: str
    salon_name: str
    service_id: str
    service_name: str
    service_name_ar: str
    price: float
    duration_min: int
    rating_avg: float
    distance_km: float | None = None
    #: Ce qui a déclenché la correspondance — affiché tel quel dans l'app.
    matched_on: list[str] = []


def _fold(value: str) -> str:
    """Compare « Dégradé » et « degrade » : accents et casse sont du bruit ici."""
    return (
        unicodedata.normalize("NFKD", value)
        .encode("ascii", "ignore")
        .decode("ascii")
        .lower()
        .strip()
    )


def _terms(style_name: str, tags: list[str]) -> set[str]:
    """Mots-clés d'une coupe, dédupliqués et normalisés."""
    words = {_fold(t) for t in tags}
    words |= {_fold(w) for w in style_name.split() if len(w) > 2}
    return {w for w in words if w}


def _tokens(*values: str) -> set[str]:
    """Découpe en mots entiers.

    La comparaison par sous-chaîne piège : la catégorie « barbershop » contient
    « barbe », ce qui faisait correspondre toute prestation de barbier à une
    coupe de barbe. On compare donc des mots, pas des fragments.
    """
    words: set[str] = set()
    for value in values:
        words |= {w for w in _fold(value).replace("-", " ").split() if w}
    return words


def _same_word(a: str, b: str) -> bool:
    """Égalité tolérante au pluriel : « dégradés » vaut « dégradé »."""
    if not a or not b:
        return False
    return a == b or a.rstrip("s") == b.rstrip("s")


def _matches_any(terms: set[str], words: set[str]) -> bool:
    return any(_same_word(term, word) for term in terms for word in words)


def _score(terms: set[str], staff: StaffMember, service: Service) -> tuple[int, list[str]]:
    """Score de pertinence et libellés ayant déclenché la correspondance.

    La spécialité du coiffeur pèse plus que le nom du service : un salon peut
    appeler « coupe homme » une prestation que seul un de ses coiffeurs sait
    faire en fade.
    """
    hits: list[str] = []
    score = 0

    for specialty in staff.specialties:
        if _matches_any(terms, _tokens(specialty)):
            hits.append(specialty)
            score += 2

    if _matches_any(terms, _tokens(service.name, service.category)):
        hits.append(service.name)
        score += 1

    return score, hits


def _distance_km(salon: Salon, lat: float, lng: float) -> float:
    """Haversine — suffisant à l'échelle d'une ville, et évite un second appel Mongo."""
    slng, slat = salon.location.coordinates
    radius = 6371.0
    d_lat = math.radians(slat - lat)
    d_lng = math.radians(slng - lng)
    a = (
        math.sin(d_lat / 2) ** 2
        + math.cos(math.radians(lat)) * math.cos(math.radians(slat)) * math.sin(d_lng / 2) ** 2
    )
    return round(radius * 2 * math.asin(math.sqrt(a)), 1)


async def find_matches(
    styles: list,
    *,
    lat: float | None = None,
    lng: float | None = None,
    radius_km: float = DEFAULT_RADIUS_KM,
) -> dict[str, list[StyleMatch]]:
    """Pour chaque coupe conseillée, jusqu'à 3 offres réelles.

    Sans position, on ne renvoie rien : proposer un coiffeur de Sfax à un client
    de Tunis serait pire qu'un conseil générique.
    """
    if not styles or lat is None or lng is None:
        return {}

    salons = await Salon.find(
        {
            "status": SalonStatus.OPEN.value,
            "location": {
                "$nearSphere": {
                    "$geometry": {"type": "Point", "coordinates": [lng, lat]},
                    "$maxDistance": radius_km * 1000,
                }
            },
        }
    ).limit(SALON_SCAN_LIMIT).to_list()

    if not salons:
        return {}

    salon_by_id = {s.id: s for s in salons}
    salon_ids = list(salon_by_id)

    # Deux requêtes au total, quel que soit le nombre de coupes conseillées.
    staff = await StaffMember.find(
        {"salon_id": {"$in": salon_ids}, "available": True}
    ).to_list()
    services = await Service.find(
        {"salon_id": {"$in": salon_ids}, "active": True}
    ).to_list()
    service_by_id: dict[PydanticObjectId, Service] = {s.id: s for s in services}

    results: dict[str, list[StyleMatch]] = {}
    for style in styles:
        terms = _terms(style.name, style.tags)
        scored: list[tuple[int, float, float, StyleMatch]] = []

        for member in staff:
            salon = salon_by_id.get(member.salon_id)
            if salon is None:
                continue
            # Un coiffeur sans service assigné ne peut rien exécuter : le
            # proposer mènerait à une réservation impossible.
            allowed = [
                service_by_id[sid] for sid in member.service_ids if sid in service_by_id
            ]
            for service in allowed:
                score, hits = _score(terms, member, service)
                # On ne réserve pas une spécialité, on réserve un service : il
                # doit donc nommer la coupe. Retenir un coiffeur sur sa seule
                # spécialité menait à proposer « Manucure » pour un fade.
                # La spécialité garde tout son poids — mais pour classer.
                if service.name not in hits:
                    continue
                distance = _distance_km(salon, lat, lng)
                scored.append((
                    score,
                    distance,
                    service.price,
                    StyleMatch(
                        staff_id=str(member.id),
                        staff_name=member.display_name,
                        salon_id=str(salon.id),
                        salon_name=salon.name,
                        service_id=str(service.id),
                        service_name=service.name,
                        service_name_ar=service.name_ar,
                        price=service.price,
                        duration_min=service.duration_min,
                        rating_avg=member.rating_avg,
                        distance_km=distance,
                        matched_on=sorted(set(hits)),
                    ),
                ))

        # Spécialiste d'abord, proximité ensuite : un coiffeur dont c'est la
        # spécialité à 3 km vaut mieux qu'un généraliste en bas de la rue. Le
        # prix ne départage qu'à égalité parfaite, pour un classement stable.
        scored.sort(key=lambda row: (-row[0], row[1], row[2]))

        seen: set[str] = set()
        picked: list[StyleMatch] = []
        for _, _, _, match in scored:
            # Un même coiffeur ne remplit pas les trois places.
            if match.staff_id in seen:
                continue
            seen.add(match.staff_id)
            picked.append(match)
            if len(picked) == MAX_MATCHES_PER_STYLE:
                break

        if picked:
            results[style.name] = picked

    return results
