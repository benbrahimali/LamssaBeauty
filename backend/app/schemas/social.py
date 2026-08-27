from beanie import PydanticObjectId
from pydantic import BaseModel, Field

from app.models.enums import ReviewStatus


class ReviewCreate(BaseModel):
    booking_id: PydanticObjectId
    rating: int = Field(ge=1, le=5)
    comment: str = Field(default="", max_length=1000)


class ReviewOut(BaseModel):
    id: str
    rating: int
    comment: str
    client_name: str
    staff_name: str = ""
    created_at: str
    status: ReviewStatus


class PortfolioCreate(BaseModel):
    image_url: str
    before_url: str | None = None
    caption: str = Field(default="", max_length=280)
    tags: list[str] = []


class PortfolioOut(BaseModel):
    id: str
    staff_id: str
    staff_name: str = ""
    salon_id: str
    salon_name: str = ""
    image_url: str
    before_url: str | None = None
    caption: str
    tags: list[str]
    likes: int
    liked_by_me: bool = False
    created_at: str
