from datetime import date, datetime

from beanie import PydanticObjectId
from pydantic import BaseModel, Field


class AdvanceCreate(BaseModel):
    """Demande de tséb9a par un membre du staff."""
    salon_id: PydanticObjectId
    amount: float = Field(gt=0, le=10000)
    reason: str = ""


class AdvanceDecision(BaseModel):
    approve: bool
    reason: str = ""


class ExpenseCreate(BaseModel):
    label: str = Field(min_length=2, max_length=120)
    amount: float = Field(gt=0)
    category: str = "autre"
    spent_at: datetime | None = None


class ClosureCreate(BaseModel):
    salon_id: PydanticObjectId
    day: date | None = None          # défaut : aujourd'hui (heure locale salon)


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
