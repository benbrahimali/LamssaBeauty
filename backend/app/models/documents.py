"""Documents Beanie — collections MongoDB (cf. cahier des charges §4.4)."""
from datetime import date, datetime, timezone

import pymongo
from beanie import Document, PydanticObjectId
from pydantic import BaseModel, Field
from pymongo import IndexModel

from app.models.enums import (
    AdvanceStatus,
    ChargePeriod,
    BookingSource,
    BookingStatus,
    CashMovementType,
    CommissionType,
    NotificationType,
    PaymentMethod,
    PaymentSource,
    PaymentStatus,
    ReviewStatus,
    Role,
    SalonStatus,
    SalonType,
    SubscriptionStatus,
)


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class GeoPoint(BaseModel):
    """GeoJSON Point — attention à l'ordre MongoDB : [longitude, latitude]."""
    type: str = "Point"
    coordinates: list[float]

    @property
    def lng(self) -> float:
        return self.coordinates[0]

    @property
    def lat(self) -> float:
        return self.coordinates[1]


class DayHours(BaseModel):
    """Horaires d'une journée. `closed=True` => le salon ne travaille pas ce jour."""
    closed: bool = False
    open: str = "09:00"
    close: str = "19:00"
    # Pause déjeuner optionnelle, ex. ("12:30", "13:30")
    break_start: str | None = None
    break_end: str | None = None


DEFAULT_HOURS: dict[str, DayHours] = {
    d: DayHours() for d in ("mon", "tue", "wed", "thu", "fri", "sat")
} | {"sun": DayHours(closed=True)}


# ─────────────────────────────────────────────────────────────────────────────
# Utilisateurs & salons
# ─────────────────────────────────────────────────────────────────────────────
class User(Document):
    phone: str
    name: str = ""
    role: Role = Role.CLIENT

    # Administrateur de la plateforme.
    #
    # Volontairement distinct de `role` : celui-ci décrit la place d'un compte
    # DANS un salon (client, coiffeur, gérant) et toute l'app en dépend. Y
    # ajouter un quatrième rôle aurait forcé chaque écran mobile à gérer un cas
    # qui ne le concerne pas. Un administrateur reste donc un client ordinaire
    # côté application ; le drapeau n'ouvre que la console.
    is_admin: bool = False
    locale: str = "fr"                       # ar | fr (§2.5)
    avatar_url: str | None = None
    fcm_tokens: list[str] = []
    is_active: bool = True
    created_at: datetime = Field(default_factory=utcnow)

    class Settings:
        name = "users"
        indexes = [IndexModel([("phone", pymongo.ASCENDING)], unique=True)]


class Salon(Document):
    owner_id: PydanticObjectId
    name: str
    type: SalonType
    location: GeoPoint
    address: str = ""
    city: str = ""
    phone: str = ""
    photos: list[str] = []
    description: str = ""
    hours: dict[str, DayHours] = Field(default_factory=lambda: dict(DEFAULT_HOURS))

    # Caisse (§3.4)
    default_split_pct: float = 50.0

    # Part du pourboire revenant à l'employé. 100 % par défaut — c'est l'usage,
    # mais certains salons les mettent en commun ou les partagent.
    tip_staff_pct: float = 100.0

    # Objectif de chiffre d'affaires mensuel, fixé par le gérant. Zéro = pas
    # d'objectif : on n'invente pas une cible à sa place, il n'y aurait aucune
    # raison de la croire.
    monthly_revenue_target: float = 0.0

    # Chaque salon nomme ses postes de dépense comme il les tient dans son
    # cahier : imposer une liste unique obligerait à tout ranger dans « autre ».
    expense_categories: list[str] = Field(
        default_factory=lambda: ["produits", "loyer", "électricité", "eau",
                                 "entretien", "taxes", "autre"]
    )
    # Réservation (§3.3)
    cancellation_window_h: int = 2
    status: SalonStatus = SalonStatus.OPEN
    closed_until: datetime | None = None      # mode "salon fermé / congés"

    # Partage (§3.2, §8.3) — code court imprimé en QR sur la vitrine et
    # partagé sur WhatsApp. Volontairement lisible à l'œil : un client qui
    # n'arrive pas à scanner doit pouvoir le taper.
    public_code: str = ""

    # Avis (§3.8) — dénormalisés pour trier sans agrégation
    rating_avg: float = 0.0
    rating_count: int = 0

    # Abonnement plateforme (§3.6)
    subscription_status: SubscriptionStatus = SubscriptionStatus.TRIAL
    trial_ends_at: datetime | None = None

    created_at: datetime = Field(default_factory=utcnow)

    class Settings:
        name = "salons"
        indexes = [
            IndexModel([("location", pymongo.GEOSPHERE)]),
            IndexModel([("type", pymongo.ASCENDING), ("status", pymongo.ASCENDING)]),
            IndexModel([("owner_id", pymongo.ASCENDING)]),
            # `partial` : les salons créés avant l'ajout du code ont une chaîne
            # vide, qu'un index unique classique refuserait en double.
            IndexModel(
                [("public_code", pymongo.ASCENDING)],
                unique=True,
                partialFilterExpression={"public_code": {"$gt": ""}},
            ),
        ]


class StaffMember(Document):
    """Un coiffeur/esthéticienne rattaché à un salon, avec sa chaise et sa commission."""
    salon_id: PydanticObjectId
    user_id: PydanticObjectId
    display_name: str = ""
    chair_number: int = 1
    service_ids: list[PydanticObjectId] = []   # services qu'il est autorisé à exécuter

    # Split configurable par employé (§3.4)
    commission_type: CommissionType = CommissionType.PERCENT
    commission_pct: float = 50.0
    commission_fixed: float = 0.0              # part fixe garantie par prestation

    bio: str = ""
    specialties: list[str] = []
    available: bool = True                     # false => congé / suspendu

    # Jours de repos hebdomadaires ('mon'..'sun'). Le salon peut ouvrir 6j/7
    # pendant qu'un coiffeur se repose le lundi : sans cette liste, ses
    # créneaux du lundi restaient réservables et le client se présentait pour
    # rien.
    days_off: list[str] = []
    is_owner: bool = False                     # un OWNER peut aussi couper (§3.1)

    # Statistiques publiques (§3.2)
    cuts_count: int = 0
    rating_avg: float = 0.0
    rating_count: int = 0
    portfolio_count: int = 0

    created_at: datetime = Field(default_factory=utcnow)

    class Settings:
        name = "staff_members"
        indexes = [
            IndexModel(
                [("salon_id", pymongo.ASCENDING), ("user_id", pymongo.ASCENDING)],
                unique=True,
            ),
            IndexModel([("user_id", pymongo.ASCENDING)]),
        ]


class Service(Document):
    salon_id: PydanticObjectId
    name: str
    name_ar: str = ""
    price: float
    duration_min: int

    # Commission propre à cette prestation. None = on retombe sur le taux du
    # coiffeur, puis sur celui du salon. Une couleur laisse moins de marge
    # qu'une coupe : imposer un taux unique fausserait l'un ou l'autre.
    commission_pct: float | None = None

    # Coût du produit consommé, retenu par le salon avant partage. Sans lui,
    # le salon paierait la moitié d'un produit qu'il a acheté seul.
    product_cost: float = 0.0
    buffer_min: int = 10                       # temps de battement (§3.3)
    category: str = ""
    description: str = ""
    active: bool = True

    class Settings:
        name = "services"
        indexes = [IndexModel([("salon_id", pymongo.ASCENDING), ("active", pymongo.ASCENDING)])]


class TimeOff(Document):
    """Congé / absence d'un coiffeur — bloque automatiquement ses créneaux (§3.5)."""
    salon_id: PydanticObjectId
    staff_id: PydanticObjectId
    start: datetime
    end: datetime
    reason: str = ""
    created_at: datetime = Field(default_factory=utcnow)

    class Settings:
        name = "time_off"
        indexes = [IndexModel([("staff_id", pymongo.ASCENDING), ("start", pymongo.ASCENDING)])]


# ─────────────────────────────────────────────────────────────────────────────
# Réservation & caisse
# ─────────────────────────────────────────────────────────────────────────────
class Booking(Document):
    salon_id: PydanticObjectId
    staff_id: PydanticObjectId
    client_id: PydanticObjectId | None = None  # None => walk-in
    service_ids: list[PydanticObjectId]

    start: datetime
    end: datetime
    status: BookingStatus = BookingStatus.PENDING
    source: BookingSource = BookingSource.APP

    # Snapshot du prix au moment de la réservation (les tarifs peuvent bouger)
    price_total: float = 0.0
    service_names: list[str] = []

    # Identité du client walk-in (pas de compte)
    client_name: str = ""
    client_phone: str = ""
    note: str = ""

    payment_status: PaymentStatus = PaymentStatus.NONE
    payment_id: PydanticObjectId | None = None

    cancelled_by: PydanticObjectId | None = None
    cancel_reason: str = ""

    reminder_j1_sent: bool = False
    reminder_h2_sent: bool = False

    created_at: datetime = Field(default_factory=utcnow)
    updated_at: datetime = Field(default_factory=utcnow)

    class Settings:
        name = "bookings"
        indexes = [
            IndexModel([("staff_id", pymongo.ASCENDING), ("start", pymongo.ASCENDING)]),
            IndexModel([("salon_id", pymongo.ASCENDING), ("start", pymongo.ASCENDING)]),
            IndexModel([("client_id", pymongo.ASCENDING), ("start", pymongo.DESCENDING)]),
            IndexModel([("status", pymongo.ASCENDING), ("start", pymongo.ASCENDING)]),
        ]


class Transaction(Document):
    """Générée à la clôture d'un service (§3.4). Porte le split salon/employé."""
    booking_id: PydanticObjectId
    salon_id: PydanticObjectId
    staff_id: PydanticObjectId
    amount: float
    method: PaymentMethod
    salon_share: float
    staff_share: float

    # Part du pourboire gardée par le salon quand il ne les laisse pas
    # entièrement à l'employé. Sans ce champ, cet argent disparaîtrait des
    # comptes alors que le client l'a bien payé.
    salon_tip: float = 0.0
    tip: float = 0.0                           # part du pourboire revenant à l'employé
    paid_at: datetime = Field(default_factory=utcnow)
    closed: bool = False                       # verrouillée par une clôture
    closure_id: PydanticObjectId | None = None

    class Settings:
        name = "transactions"
        indexes = [
            IndexModel([("salon_id", pymongo.ASCENDING), ("paid_at", pymongo.ASCENDING)]),
            IndexModel([("staff_id", pymongo.ASCENDING), ("paid_at", pymongo.ASCENDING)]),
            IndexModel([("booking_id", pymongo.ASCENDING)], unique=True),
        ]


class Advance(Document):
    """Tséb9a — avance sur salaire demandée par le staff, validée par le gérant."""
    salon_id: PydanticObjectId
    staff_id: PydanticObjectId
    amount: float
    reason: str = ""
    paid_from: PaymentSource = PaymentSource.CASH
    status: AdvanceStatus = AdvanceStatus.PENDING
    requested_at: datetime = Field(default_factory=utcnow)
    decided_at: datetime | None = None
    decided_by: PydanticObjectId | None = None
    settled_at: datetime | None = None
    settled_closure_id: PydanticObjectId | None = None

    class Settings:
        name = "advances"
        indexes = [
            IndexModel([("salon_id", pymongo.ASCENDING), ("status", pymongo.ASCENDING)]),
            IndexModel([("staff_id", pymongo.ASCENDING), ("requested_at", pymongo.DESCENDING)]),
        ]


class Expense(Document):
    """Dépense salon (loyer, produits…) pour le P&L mensuel simple (§3.4)."""
    salon_id: PydanticObjectId
    label: str
    amount: float
    category: str = "autre"
    # Une dépense réglée par virement ne vide pas le tiroir : sans cette
    # distinction le solde théorique de la caisse dérive dès le premier loyer.
    paid_from: PaymentSource = PaymentSource.CASH
    spent_at: datetime = Field(default_factory=utcnow)
    created_by: PydanticObjectId | None = None

    class Settings:
        name = "expenses"
        indexes = [IndexModel([("salon_id", pymongo.ASCENDING), ("spent_at", pymongo.ASCENDING)])]


class CashClosure(Document):
    """Clôture de journée : fige les transactions et produit le rapport (§5.4)."""
    salon_id: PydanticObjectId
    day: date
    total: float
    salon_total: float
    staff_total: float
    tips_total: float = 0.0
    expenses_total: float = 0.0
    advances_deducted: float = 0.0
    net_salon: float = 0.0                     # salon_total - dépenses du jour
    by_method: dict[str, float] = {}
    by_staff: dict[str, dict] = {}
    transaction_count: int = 0

    # Trésorerie : ce que le tiroir devait contenir, ce qu'il contenait
    # vraiment, et ce que le gérant en a sorti. `counted_cash` reste None
    # quand personne n'a compté — on n'invente pas un écart de zéro.
    opening_float: float = 0.0
    expected_cash: float = 0.0
    counted_cash: float | None = None
    cash_variance: float = 0.0
    variance_reason: str = ""
    withdrawal: float = 0.0
    closing_float: float = 0.0
    bank_total: float = 0.0

    locked: bool = True
    report_path: str | None = None
    created_by: PydanticObjectId | None = None
    created_at: datetime = Field(default_factory=utcnow)

    class Settings:
        name = "cash_closures"
        indexes = [
            IndexModel(
                [("salon_id", pymongo.ASCENDING), ("day", pymongo.ASCENDING)], unique=True
            )
        ]


class CashMovement(Document):
    """Entrée ou sortie d'espèces sans prestation : fond de caisse, apport,
    prélèvement (§3.4).

    Le montant est toujours positif ; c'est le type qui donne le sens. Le
    rattachement se fait à une journée locale et non à un instant, parce que
    c'est la journée que le gérant clôture.
    """
    salon_id: PydanticObjectId
    type: CashMovementType
    amount: float
    label: str = ""
    day: date
    created_by: PydanticObjectId | None = None
    created_at: datetime = Field(default_factory=utcnow)

    class Settings:
        name = "cash_movements"
        indexes = [IndexModel([("salon_id", pymongo.ASCENDING), ("day", pymongo.ASCENDING)])]


class Payment(Document):
    """Paiement en ligne via PSP local (Konnect / Flouci) — §3.6."""
    booking_id: PydanticObjectId
    salon_id: PydanticObjectId
    client_id: PydanticObjectId | None = None
    amount: float
    platform_fee: float = 0.0
    currency: str = "TND"
    provider: str = "mock"
    provider_ref: str = ""
    checkout_url: str = ""
    status: PaymentStatus = PaymentStatus.PENDING
    raw: dict = {}
    created_at: datetime = Field(default_factory=utcnow)
    paid_at: datetime | None = None
    refunded_at: datetime | None = None

    class Settings:
        name = "payments"
        indexes = [
            IndexModel([("booking_id", pymongo.ASCENDING)]),
            IndexModel([("provider_ref", pymongo.ASCENDING)]),
        ]


# ─────────────────────────────────────────────────────────────────────────────
# Social : avis, portfolio, notifications
# ─────────────────────────────────────────────────────────────────────────────
class Review(Document):
    """Avis post-RDV — un seul par booking, et uniquement si le RDV est DONE."""
    booking_id: PydanticObjectId
    salon_id: PydanticObjectId
    staff_id: PydanticObjectId
    client_id: PydanticObjectId
    rating: int                                # 1..5
    comment: str = ""
    status: ReviewStatus = ReviewStatus.PUBLISHED
    created_at: datetime = Field(default_factory=utcnow)

    class Settings:
        name = "reviews"
        indexes = [
            IndexModel([("booking_id", pymongo.ASCENDING)], unique=True),
            IndexModel([("salon_id", pymongo.ASCENDING), ("created_at", pymongo.DESCENDING)]),
            IndexModel([("staff_id", pymongo.ASCENDING), ("created_at", pymongo.DESCENDING)]),
        ]


class PortfolioItem(Document):
    """Réalisation publiée par un coiffeur — alimente le fil « En vogue » (§3.8)."""
    staff_id: PydanticObjectId
    salon_id: PydanticObjectId
    image_url: str
    before_url: str | None = None
    caption: str = ""
    tags: list[str] = []
    likes: int = 0
    liked_by: list[PydanticObjectId] = []
    created_at: datetime = Field(default_factory=utcnow)

    class Settings:
        name = "portfolio_items"
        indexes = [
            IndexModel([("staff_id", pymongo.ASCENDING), ("created_at", pymongo.DESCENDING)]),
            IndexModel([("created_at", pymongo.DESCENDING), ("likes", pymongo.DESCENDING)]),
            IndexModel([("tags", pymongo.ASCENDING)]),
        ]


class Reel(Document):
    """Vidéo courte publiée par un coiffeur ou un salon (§3.8).

    Publique par construction : c'est ce qui la rend utile — un visiteur sans
    compte doit pouvoir la regarder, sinon elle n'attire personne.

    Un reel appartient soit à un coiffeur, soit au salon lui-même (compte du
    gérant) : `staff_id` est donc facultatif, `salon_id` ne l'est jamais.
    """
    salon_id: PydanticObjectId
    staff_id: PydanticObjectId | None = None
    author_id: PydanticObjectId                # utilisateur qui a publié

    video_url: str
    thumbnail_url: str = ""
    public_id: str = ""                        # référence Cloudinary, pour la suppression
    duration_sec: float = 0.0                  # mesurée par le fournisseur, pas déclarée

    caption: str = ""
    tags: list[str] = []
    views: int = 0
    likes: int = 0
    liked_by: list[PydanticObjectId] = []
    created_at: datetime = Field(default_factory=utcnow)

    class Settings:
        name = "reels"
        indexes = [
            # Fil « En vogue » : récents d'abord, puis les plus aimés.
            IndexModel([("created_at", pymongo.DESCENDING), ("likes", pymongo.DESCENDING)]),
            IndexModel([("salon_id", pymongo.ASCENDING), ("created_at", pymongo.DESCENDING)]),
            IndexModel([("staff_id", pymongo.ASCENDING), ("created_at", pymongo.DESCENDING)]),
            IndexModel([("tags", pymongo.ASCENDING)]),
        ]


class RecurringCharge(Document):
    """Charge fixe du salon : loyer, salaire, abonnement, taxe (§3.4).

    Chaque salon décrit ses propres charges avec leur rythme. Sans elles, le
    « net » de la caisse ne dit rien du résultat réel : un salon peut encaisser
    3 000 DT dans le mois et perdre de l'argent une fois le loyer payé.
    """
    salon_id: PydanticObjectId
    label: str
    amount: float
    category: str = "autre"
    period: ChargePeriod = ChargePeriod.MONTHLY

    # Une charge supprimée fausserait l'historique : on la désactive, et les
    # périodes déjà analysées gardent le montant qui s'y appliquait.
    active: bool = True
    started_at: datetime = Field(default_factory=utcnow)
    ended_at: datetime | None = None

    created_at: datetime = Field(default_factory=utcnow)

    class Settings:
        name = "recurring_charges"
        indexes = [
            IndexModel([("salon_id", pymongo.ASCENDING), ("active", pymongo.ASCENDING)]),
        ]


class Notification(Document):
    user_id: PydanticObjectId
    type: NotificationType
    title: str
    body: str
    data: dict = {}
    read: bool = False
    created_at: datetime = Field(default_factory=utcnow)

    class Settings:
        name = "notifications"
        indexes = [
            IndexModel([("user_id", pymongo.ASCENDING), ("created_at", pymongo.DESCENDING)])
        ]


ALL_DOCUMENTS = [
    User,
    Salon,
    StaffMember,
    Service,
    TimeOff,
    Booking,
    Transaction,
    Advance,
    Expense,
    CashClosure,
    CashMovement,
    Payment,
    Review,
    PortfolioItem,
    RecurringCharge,
    Reel,
    Notification,
]
