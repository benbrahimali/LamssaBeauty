from datetime import datetime

from beanie import PydanticObjectId
from pydantic import BaseModel, Field, field_validator

from app.models.documents import DayHours, GeoPoint
from app.models.enums import CommissionType, SalonStatus, SalonType


class SalonCreate(BaseModel):
    name: str = Field(min_length=2, max_length=80)
    type: SalonType
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    address: str = ""
    city: str = ""
    phone: str = ""
    description: str = ""
    hours: dict[str, DayHours] | None = None
    default_split_pct: float = Field(default=50.0, ge=0, le=100)
    cancellation_window_h: int = Field(default=2, ge=0, le=72)

    def to_location(self) -> GeoPoint:
        return GeoPoint(coordinates=[self.lng, self.lat])


class SalonUpdate(BaseModel):
    name: str | None = None
    type: SalonType | None = None
    address: str | None = None
    city: str | None = None
    phone: str | None = None
    description: str | None = None
    photos: list[str] | None = None
    hours: dict[str, DayHours] | None = None
    default_split_pct: float | None = Field(default=None, ge=0, le=100)
    cancellation_window_h: int | None = Field(default=None, ge=0, le=72)
    status: SalonStatus | None = None
    closed_until: datetime | None = None
    lat: float | None = Field(default=None, ge=-90, le=90)
    lng: float | None = Field(default=None, ge=-180, le=180)


class ServiceCreate(BaseModel):
    name: str = Field(min_length=2, max_length=80)
    name_ar: str = ""
    price: float = Field(gt=0)
    duration_min: int = Field(gt=0, le=600)
    buffer_min: int = Field(default=10, ge=0, le=120)
    category: str = ""
    description: str = ""


class ServiceUpdate(BaseModel):
    name: str | None = None
    name_ar: str | None = None
    price: float | None = Field(default=None, gt=0)
    duration_min: int | None = Field(default=None, gt=0, le=600)
    buffer_min: int | None = Field(default=None, ge=0, le=120)
    category: str | None = None
    description: str | None = None
    active: bool | None = None


class StaffCreate(BaseModel):
    """Invitation d'un membre : par numéro de téléphone (le compte est créé au besoin)."""
    phone: str
    display_name: str = ""
    chair_number: int = Field(default=1, ge=1, le=50)
    commission_type: CommissionType = CommissionType.PERCENT
    commission_pct: float = Field(default=50.0, ge=0, le=100)
    commission_fixed: float = Field(default=0.0, ge=0)
    service_ids: list[PydanticObjectId] = []
    bio: str = ""
    specialties: list[str] = []
    is_owner: bool = False

    @field_validator("phone")
    @classmethod
    def _phone(cls, v: str) -> str:
        from app.schemas.auth import normalize_phone

        return normalize_phone(v)


class StaffUpdate(BaseModel):
    display_name: str | None = None
    chair_number: int | None = Field(default=None, ge=1, le=50)
    commission_type: CommissionType | None = None
    commission_pct: float | None = Field(default=None, ge=0, le=100)
    commission_fixed: float | None = Field(default=None, ge=0)
    service_ids: list[PydanticObjectId] | None = None
    bio: str | None = None
    specialties: list[str] | None = None
    available: bool | None = None


class TimeOffCreate(BaseModel):
    staff_id: PydanticObjectId
    start: datetime
    end: datetime
    reason: str = ""


class SalonCard(BaseModel):
    """Résultat de recherche allégé pour la carte / la liste (§3.2)."""
    id: str
    name: str
    type: SalonType
    address: str
    city: str
    lat: float
    lng: float
    photos: list[str]
    rating_avg: float
    rating_count: int
    status: SalonStatus
    is_open_now: bool
    distance_km: float | None = None
    price_from: float | None = None
    staff_count: int = 0
