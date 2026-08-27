"""Configuration centralisée — surchargeable par variables d'env ou fichier .env."""
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # ── Infra ────────────────────────────────────────────────────────────
    ENV: str = "dev"                       # dev | staging | prod
    MONGO_URI: str = "mongodb://localhost:27017"
    MONGO_DB: str = "lamssa"
    REDIS_URI: str = "redis://localhost:6379/0"
    CORS_ORIGINS: list[str] = ["*"]

    # ── Sécurité / JWT (§2.5) ────────────────────────────────────────────
    JWT_SECRET: str = "change-me-in-prod"
    JWT_ALGO: str = "HS256"
    ACCESS_TTL_MIN: int = 30
    REFRESH_TTL_DAYS: int = 30

    # ── OTP (§3.1) ───────────────────────────────────────────────────────
    OTP_TTL_SEC: int = 300
    OTP_MAX_ATTEMPTS: int = 5
    OTP_RESEND_COOLDOWN_SEC: int = 60
    OTP_DEV_CODE: str | None = "000000"    # dev/CI uniquement ; None en prod

    # ── Réservation (§3.3) ───────────────────────────────────────────────
    SLOT_LOCK_TTL_SEC: int = 30
    SLOT_STEP_MIN: int = 15                # granularité de la grille de créneaux
    PENDING_TIMEOUT_MIN: int = 15          # PENDING -> CANCELLED si non payé
    NO_SHOW_GRACE_MIN: int = 20            # CONFIRMED -> NO_SHOW après l'heure
    DEFAULT_CANCEL_WINDOW_H: int = 2       # annulation client jusqu'à H-2
    TIMEZONE: str = "Africa/Tunis"

    # ── Paiement (§3.6) ──────────────────────────────────────────────────
    PSP_PROVIDER: str = "mock"             # mock | konnect | flouci
    PSP_WEBHOOK_SECRET: str = "change-me"
    KONNECT_API_URL: str = "https://api.preprod.konnect.network/api/v2"
    KONNECT_API_KEY: str = ""
    KONNECT_WALLET_ID: str = ""
    FLOUCI_API_URL: str = "https://developers.flouci.com/api"
    FLOUCI_APP_TOKEN: str = ""
    FLOUCI_APP_SECRET: str = ""
    PLATFORM_FEE_PCT: float = 2.5          # commission plateforme sur paiement en ligne
    PAYMENT_SUCCESS_URL: str = "lamssa://payment/success"
    PAYMENT_FAIL_URL: str = "lamssa://payment/fail"
    CURRENCY: str = "TND"

    # ── Partage & liens profonds (§3.2, §8.3) ────────────────────────────
    # Base des liens encodés dans le QR du salon. Tant qu'aucun domaine n'est
    # publié, un client sans l'app tombera sur une page inexistante : c'est le
    # seul maillon du partage qui dépend d'une infra externe.
    PUBLIC_WEB_BASE: str = "https://lamssa.tn"
    APP_SCHEME: str = "lamssa"

    # ── Abonnement salon (§3.6) ──────────────────────────────────────────
    TRIAL_DAYS: int = 30
    SUBSCRIPTION_PRICE: float = 29.0

    # ── Notifications (§3.7) ─────────────────────────────────────────────
    # FCM HTTP v1 : l'API legacy (`Authorization: key=…`) a été fermée par
    # Google le 22/07/2024, il n'existe plus de « server key ». On s'authentifie
    # avec le compte de service du projet Firebase.
    # Sans FCM_CREDENTIALS_FILE, les push sont loggés au lieu d'être envoyés.
    FCM_PROJECT_ID: str = ""
    FCM_CREDENTIALS_FILE: str = ""

    SMS_PROVIDER: str = "console"          # console | twilio | tunsms
    SMS_SENDER: str = "LAMSSA"
    TWILIO_SID: str = ""
    TWILIO_TOKEN: str = ""
    TWILIO_FROM: str = ""

    # ── Stockage médias (§4.1) ───────────────────────────────────────────
    S3_ENDPOINT: str = ""
    S3_BUCKET: str = "lamssa-media"
    S3_KEY: str = ""
    S3_SECRET: str = ""
    S3_PUBLIC_BASE: str = ""
    MAX_UPLOAD_MB: int = 8

    # ── Style DNA — analyse de selfie par modèle vision (§2.4, §8.5) ─────
    # La clé reste côté serveur : une clé embarquée dans l'APK serait extractible.
    ANTHROPIC_API_KEY: str = ""
    STYLE_DNA_MODEL: str = "claude-opus-5"
    #: low | medium | high | xhigh | max — `medium` garde l'analyse sous ~10 s,
    #: ce que l'écran de scan peut absorber. Monter à `high` si la qualité prime.
    STYLE_DNA_EFFORT: str = "medium"
    STYLE_DNA_MAX_IMAGE_MB: int = 5

    # ── Génération d'images (§2.4) ───────────────────────────────────────
    # Second fournisseur : Claude ne génère pas d'images. Sans clé, l'app
    # masque l'illustration et l'essayage, le reste de Style DNA fonctionne.
    GEMINI_API_KEY: str = ""
    GEMINI_IMAGE_MODEL: str = "gemini-3.1-flash-image"

    # ── Rapports ─────────────────────────────────────────────────────────
    REPORTS_DIR: str = "./reports"

    @property
    def is_prod(self) -> bool:
        return self.ENV == "prod"

    def assert_production_ready(self) -> None:
        """Refuse de démarrer en prod avec une configuration de développement.

        Ces valeurs par défaut sont publiques : elles sont dans le dépôt. Un
        `JWT_SECRET` laissé tel quel permet de forger le jeton de n'importe quel
        utilisateur, gérant compris. Mieux vaut un démarrage qui échoue bruyamment
        qu'une API en ligne avec une porte ouverte.
        """
        if not self.is_prod:
            return

        problems: list[str] = []
        if self.JWT_SECRET == "change-me-in-prod":
            problems.append(
                "JWT_SECRET est resté à sa valeur par défaut publique — "
                "générer : python -c \"import secrets;print(secrets.token_urlsafe(48))\""
            )
        if self.PSP_WEBHOOK_SECRET == "change-me":
            problems.append("PSP_WEBHOOK_SECRET est resté à sa valeur par défaut")
        if self.SMS_PROVIDER == "console":
            problems.append(
                "SMS_PROVIDER=console : aucun OTP ne partirait, personne ne "
                "pourrait se connecter"
            )
        if problems:
            raise RuntimeError(
                "Configuration de production incomplète :\n  - "
                + "\n  - ".join(problems)
            )


settings = Settings()
settings.assert_production_ready()
