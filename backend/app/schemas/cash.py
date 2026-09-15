from datetime import date, datetime

from beanie import PydanticObjectId
from pydantic import BaseModel, Field, model_validator

from app.models.enums import CashMovementType, ChargePeriod, PaymentSource


class AdvanceCreate(BaseModel):
    """Demande de tséb9a par un membre du staff."""
    salon_id: PydanticObjectId
    amount: float = Field(gt=0, le=10000)
    reason: str = ""


class AdvanceDecision(BaseModel):
    approve: bool
    reason: str = ""
    # Une tséb9a sort du tiroir sauf si le gérant la vire depuis son compte.
    paid_from: PaymentSource = PaymentSource.CASH


class ExpenseCreate(BaseModel):
    label: str = Field(min_length=2, max_length=120)
    amount: float = Field(gt=0)
    category: str = "autre"
    # Par défaut le tiroir : c'est ce qui se passe pour la majorité des achats
    # d'un salon. Le loyer ou l'électricité se déclarent en banque.
    paid_from: PaymentSource = PaymentSource.CASH
    spent_at: datetime | None = None


class ExpenseUpdate(BaseModel):
    """Correction d'une dépense : seuls les champs fournis changent.

    La date n'est pas modifiable : déplacer une dépense d'un jour à l'autre
    changerait deux tiroirs à la fois, dont un peut-être déjà compté.
    """
    label: str | None = Field(default=None, min_length=2, max_length=120)
    amount: float | None = Field(default=None, gt=0)
    category: str | None = None
    paid_from: PaymentSource | None = None

    @model_validator(mode="after")
    def _au_moins_un_champ(self):
        if not self.model_dump(exclude_none=True):
            raise ValueError("Rien à modifier")
        return self


class ClosureCreate(BaseModel):
    salon_id: PydanticObjectId
    day: date | None = None          # défaut : aujourd'hui (heure locale salon)
    # Comptage du tiroir : facultatif, parce qu'on ne force pas un gérant à
    # compter pour pouvoir fermer sa journée.
    counted_cash: float | None = Field(default=None, ge=0)
    withdrawal: float = Field(default=0.0, ge=0)
    variance_reason: str = Field(default="", max_length=200)


class CashMovementCreate(BaseModel):
    """Fond de caisse, apport ou prélèvement — le sens vient du type."""
    salon_id: PydanticObjectId
    type: CashMovementType
    amount: float = Field(ge=0, le=100000)
    label: str = Field(default="", max_length=120)
    day: date | None = None

    @model_validator(mode="after")
    def _montant_selon_le_type(self):
        # Un tiroir peut ouvrir vide : un fond de caisse à zéro est une vraie
        # déclaration. Un apport ou un prélèvement de zéro, lui, ne veut rien dire.
        if self.type is not CashMovementType.OPENING_FLOAT and self.amount <= 0:
            raise ValueError("Le montant d'un apport ou d'un prélèvement doit être positif")
        return self


class StaffCashRow(BaseModel):
    name: str
    chair: int | None = None
    count: int
    gross: float
    staff_share: float
    salon_share: float
    tips: float
    advance_deducted: float = 0.0
    net_payout: float = 0.0


class DayCashOut(BaseModel):
    day: str
    transaction_count: int
    total: float
    salon_total: float
    staff_total: float
    tips_total: float
    expenses_total: float
    net_salon: float
    advances_pending: float
    advances_pending_count: int
    by_method: dict[str, float]
    by_staff: dict[str, StaffCashRow]
    closed: bool
    closure_id: str | None = None


class RecurringChargeCreate(BaseModel):
    """Une charge fixe telle que le gérant la décrit lui-même."""

    label: str = Field(min_length=2, max_length=60)
    amount: float = Field(gt=0)
    category: str = "autre"
    period: ChargePeriod = ChargePeriod.MONTHLY


class RecurringChargeUpdate(BaseModel):
    label: str | None = Field(default=None, min_length=2, max_length=60)
    amount: float | None = Field(default=None, gt=0)
    category: str | None = None
    period: ChargePeriod | None = None
    # Désactiver plutôt que supprimer : l'historique garde son sens.
    active: bool | None = None


class StaffPayoutCreate(BaseModel):
    """Verser la paie de la semaine à un coiffeur.

    Aucun montant n'est fourni : le serveur verse ce qui reste dû. Un chiffre
    tapé à la main pourrait payer deux fois la même semaine.
    """
    salon_id: PydanticObjectId
    staff_id: PydanticObjectId
    week_of: date | None = None
    paid_from: PaymentSource = PaymentSource.CASH
    note: str = Field(default="", max_length=200)
