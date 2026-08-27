from datetime import datetime

from beanie import PydanticObjectId
from pydantic import BaseModel, Field, model_validator

from app.models.enums import BookingSource, BookingStatus, PaymentMethod


class BookingCreate(BaseModel):
    salon_id: PydanticObjectId
    staff_id: PydanticObjectId | None = None   # None => « peu importe » (§3.3)
    service_ids: list[PydanticObjectId] = Field(min_length=1)
    start: datetime
    source: BookingSource = BookingSource.APP
    note: str = ""
    # Walk-in uniquement : identité du client sans compte
    client_name: str = ""
    client_phone: str = ""

    @model_validator(mode="after")
    def _walkin_needs_name(self):
        if self.source is BookingSource.WALKIN and not (self.client_name or self.client_phone):
            raise ValueError("Un walk-in doit porter au moins un nom ou un téléphone")
        return self


class BookingStatusPatch(BaseModel):
    status: BookingStatus
    reason: str = ""


class BookingComplete(BaseModel):
    """Clôture d'une prestation -> génère la Transaction et son split."""
    method: PaymentMethod = PaymentMethod.CASH
    tip: float = Field(default=0.0, ge=0)
    amount_override: float | None = Field(default=None, gt=0)  # remise / supplément
    override_reason: str = ""


class BookingOut(BaseModel):
    id: str
    salon_id: str
    salon_name: str = ""
    staff_id: str
    staff_name: str = ""
    client_id: str | None = None
    client_name: str = ""
    client_phone: str = ""
    service_ids: list[str]
    service_names: list[str]
    start: datetime
    end: datetime
    status: BookingStatus
    source: BookingSource
    price_total: float
    payment_status: str
    note: str = ""


class SlotOut(BaseModel):
    time: str
    start: datetime


class SlotsResponse(BaseModel):
    date: str
    duration_min: int
    slots: list[SlotOut]


class CheckoutCreate(BaseModel):
    booking_id: PydanticObjectId


class CheckoutOut(BaseModel):
    payment_id: str
    checkout_url: str
    provider: str
    amount: float
    platform_fee: float
    currency: str
