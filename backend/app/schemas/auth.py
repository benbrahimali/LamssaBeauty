from pydantic import BaseModel, Field, field_validator

from app.models.enums import Role

TN_PREFIXES = ("+216", "216")


def normalize_phone(value: str) -> str:
    """Normalise au format E.164. Un numéro tunisien nu (8 chiffres) est préfixé +216."""
    raw = "".join(ch for ch in value if ch.isdigit() or ch == "+")
    if raw.startswith("+"):
        digits = raw[1:]
    elif raw.startswith(TN_PREFIXES[1]):
        digits = raw
    elif len(raw) == 8:
        digits = "216" + raw
    else:
        digits = raw
    if not digits.isdigit() or not 8 <= len(digits) <= 15:
        raise ValueError("Numéro de téléphone invalide")
    return "+" + digits


class OTPRequest(BaseModel):
    phone: str

    @field_validator("phone")
    @classmethod
    def _phone(cls, v: str) -> str:
        return normalize_phone(v)


class OTPVerify(OTPRequest):
    code: str = Field(min_length=4, max_length=8)
    name: str = ""
    locale: str = "fr"


class RefreshRequest(BaseModel):
    refresh_token: str


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class UserOut(BaseModel):
    id: str
    phone: str
    name: str
    role: Role
    locale: str
    avatar_url: str | None = None


class AuthOut(TokenPair):
    user: UserOut


class MeUpdate(BaseModel):
    name: str | None = None
    locale: str | None = None
    avatar_url: str | None = None


class DeviceToken(BaseModel):
    fcm_token: str
