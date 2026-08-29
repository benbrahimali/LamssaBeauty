"""Énumérations du domaine LAMSSA (cf. cahier des charges §4.4)."""
from enum import Enum


class Role(str, Enum):
    CLIENT = "CLIENT"
    STAFF = "STAFF"
    OWNER = "OWNER"


class SalonType(str, Enum):
    BARBERSHOP = "barbershop"
    FEMME = "femme"
    MIXTE = "mixte"
    MARIEES = "mariees"


class SalonStatus(str, Enum):
    OPEN = "open"
    CLOSED = "closed"          # fermeture temporaire / congés (§2.4 "Should")


class BookingStatus(str, Enum):
    PENDING = "PENDING"
    CONFIRMED = "CONFIRMED"
    IN_PROGRESS = "IN_PROGRESS"
    DONE = "DONE"
    CANCELLED = "CANCELLED"
    NO_SHOW = "NO_SHOW"


#: Machine à états du RDV (§5.5). Toute transition hors de cette table est refusée.
BOOKING_TRANSITIONS: dict[BookingStatus, set[BookingStatus]] = {
    BookingStatus.PENDING: {BookingStatus.CONFIRMED, BookingStatus.CANCELLED},
    BookingStatus.CONFIRMED: {
        BookingStatus.IN_PROGRESS,
        BookingStatus.CANCELLED,
        BookingStatus.NO_SHOW,
    },
    BookingStatus.IN_PROGRESS: {BookingStatus.DONE, BookingStatus.CANCELLED},
    BookingStatus.DONE: set(),
    BookingStatus.CANCELLED: set(),
    BookingStatus.NO_SHOW: set(),
}

#: Statuts qui occupent réellement un créneau dans l'agenda.
ACTIVE_BOOKING_STATUSES = [
    BookingStatus.PENDING,
    BookingStatus.CONFIRMED,
    BookingStatus.IN_PROGRESS,
]


class PaymentMethod(str, Enum):
    CASH = "cash"
    CARD = "card"              # TPE du salon
    ONLINE = "online"          # Konnect / Flouci


class PaymentStatus(str, Enum):
    NONE = "none"
    PENDING = "pending"
    PAID = "paid"
    FAILED = "failed"
    REFUNDED = "refunded"


class AdvanceStatus(str, Enum):
    """Cycle de vie d'une tséb9a (avance sur salaire)."""
    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"
    SETTLED = "settled"        # déduite lors d'une clôture de caisse


class CommissionType(str, Enum):
    """Modes de split configurables par employé (§3.4)."""
    PERCENT = "percent"        # ex. 50/50, 60/40
    FIXED_PLUS_PERCENT = "fixed_plus_percent"   # fixe garanti + % au-delà
    SALON_KEEPS_ALL = "salon_keeps_all"         # employé salarié


class BookingSource(str, Enum):
    APP = "app"
    WALKIN = "walkin"          # client hors app saisi par le gérant (§3.3)


class ReviewStatus(str, Enum):
    PUBLISHED = "published"
    HIDDEN = "hidden"          # modération basique (§3.8)


class NotificationType(str, Enum):
    BOOKING_CONFIRMED = "booking_confirmed"
    BOOKING_CANCELLED = "booking_cancelled"
    REMINDER_J1 = "reminder_j1"
    REMINDER_H2 = "reminder_h2"
    YOUR_TURN = "your_turn"
    ADVANCE_DECIDED = "advance_decided"
    ADVANCE_REQUESTED = "advance_requested"
    CLOSURE_READY = "closure_ready"
    NEW_PORTFOLIO = "new_portfolio"
    NEW_REVIEW = "new_review"


class ChargePeriod(str, Enum):
    """Rythme d'une charge fixe du salon (§3.4)."""
    WEEKLY = "weekly"
    MONTHLY = "monthly"
    YEARLY = "yearly"


class SubscriptionStatus(str, Enum):
    TRIAL = "trial"
    ACTIVE = "active"
    EXPIRED = "expired"
