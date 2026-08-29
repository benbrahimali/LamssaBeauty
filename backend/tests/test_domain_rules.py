"""Règles de gestion transverses : téléphone, machine à états, bornes de journée."""
from datetime import date, datetime, timezone

import pytest
from fastapi import HTTPException

from app.core.timeutils import TZ, day_key, local_day_bounds, local_month_bounds
from app.models.enums import BOOKING_TRANSITIONS, BookingStatus
from app.schemas.auth import normalize_phone
from app.services.booking_service import assert_transition


# ── Téléphone ────────────────────────────────────────────────────────────────
@pytest.mark.parametrize(
    "saisie",
    ["98123456", "+216 98 123 456", "21698123456", "+21698123456", "98 12 34 56"],
)
def test_les_formats_tunisiens_courants_convergent(saisie):
    assert normalize_phone(saisie) == "+21698123456"


def test_numero_international_conserve():
    assert normalize_phone("+33612345678") == "+33612345678"


@pytest.mark.parametrize("saisie", ["12", "abcdefgh", "+", "0123456789012345678"])
def test_numero_invalide_refuse(saisie):
    with pytest.raises(ValueError):
        normalize_phone(saisie)


# ── Machine à états du RDV (§5.5) ────────────────────────────────────────────
def test_chemin_nominal_autorise():
    assert_transition(BookingStatus.PENDING, BookingStatus.CONFIRMED)
    assert_transition(BookingStatus.CONFIRMED, BookingStatus.IN_PROGRESS)
    assert_transition(BookingStatus.IN_PROGRESS, BookingStatus.DONE)


@pytest.mark.parametrize(
    "depart,arrivee",
    [
        (BookingStatus.PENDING, BookingStatus.DONE),          # pas de raccourci
        (BookingStatus.PENDING, BookingStatus.NO_SHOW),
        (BookingStatus.DONE, BookingStatus.CANCELLED),        # une caisse ne se défait pas
        (BookingStatus.CANCELLED, BookingStatus.CONFIRMED),
        (BookingStatus.NO_SHOW, BookingStatus.DONE),
    ],
)
def test_transitions_interdites(depart, arrivee):
    with pytest.raises(HTTPException) as exc:
        assert_transition(depart, arrivee)
    assert exc.value.status_code == 409


def test_les_etats_terminaux_sont_bien_terminaux():
    for etat in (BookingStatus.DONE, BookingStatus.CANCELLED, BookingStatus.NO_SHOW):
        assert BOOKING_TRANSITIONS[etat] == set()


# ── Bornes temporelles ───────────────────────────────────────────────────────
def test_bornes_du_jour_couvrent_24h_en_heure_locale():
    start, end = local_day_bounds(date(2026, 8, 2))
    assert end - start == datetime(2026, 8, 3, tzinfo=timezone.utc) - datetime(
        2026, 8, 2, tzinfo=timezone.utc
    )
    assert start.tzinfo is timezone.utc


def test_bornes_de_mois_passent_l_annee():
    """Décembre 2026 se ferme au 1er janvier 2027 — en heure locale du salon."""
    start, end = local_month_bounds(2026, 12)
    assert start < end
    assert start.astimezone(TZ).strftime("%Y-%m-%d %H:%M") == "2026-12-01 00:00"
    assert end.astimezone(TZ).strftime("%Y-%m-%d %H:%M") == "2027-01-01 00:00"


@pytest.mark.parametrize(
    "jour,cle",
    [
        (date(2026, 9, 14), "mon"),
        (date(2026, 9, 15), "tue"),
        (date(2026, 9, 20), "sun"),
    ],
)
def test_cle_horaire_du_jour(jour, cle):
    assert day_key(jour) == cle


# ── Garde-fous de production ─────────────────────────────────────────────────
def test_en_dev_les_valeurs_par_defaut_sont_acceptees():
    """La configuration de dev doit rester utilisable sans rien renseigner."""
    from app.core.config import Settings

    Settings(ENV="dev").assert_production_ready()  # ne lève pas


def test_en_prod_un_secret_jwt_par_defaut_empeche_le_demarrage():
    """Cette valeur est publique : elle est dans le dépôt.

    La laisser permettrait de forger le jeton de n'importe quel utilisateur,
    gérant compris. Un démarrage qui échoue vaut mieux qu'une porte ouverte.
    """
    from app.core.config import Settings

    with pytest.raises(RuntimeError, match="JWT_SECRET"):
        Settings(
            ENV="prod", SMS_PROVIDER="twilio", PSP_WEBHOOK_SECRET="vrai-secret"
        ).assert_production_ready()


def test_en_prod_sans_fournisseur_sms_le_demarrage_est_refuse():
    """Sans SMS, aucun OTP ne part : personne ne peut se connecter."""
    from app.core.config import Settings

    with pytest.raises(RuntimeError, match="SMS_PROVIDER"):
        Settings(
            ENV="prod", JWT_SECRET="x" * 40, PSP_WEBHOOK_SECRET="vrai-secret"
        ).assert_production_ready()


def test_en_prod_une_configuration_complete_demarre():
    from app.core.config import Settings

    Settings(
        ENV="prod",
        JWT_SECRET="x" * 40,
        PSP_WEBHOOK_SECRET="vrai-secret",
        SMS_PROVIDER="twilio",
    ).assert_production_ready()


def test_tous_les_problemes_sont_signales_d_un_coup():
    """Corriger une variable pour redécouvrir la suivante ferait perdre du temps."""
    from app.core.config import Settings

    with pytest.raises(RuntimeError) as exc:
        Settings(ENV="prod").assert_production_ready()
    message = str(exc.value)
    assert "JWT_SECRET" in message
    assert "PSP_WEBHOOK_SECRET" in message
    assert "SMS_PROVIDER" in message


# ── Cohérence du rôle (§2.5, §3.5) ───────────────────────────────────────────
def test_le_role_owner_prime_sur_staff():
    """Un gérant qui coupe aussi les cheveux reste gérant.

    `sync_role` teste la possession d'un salon avant le rattachement à une
    équipe : l'ordre inverse rétrograderait un patron-coiffeur en employé le
    jour où il quitte l'équipe d'un confrère.
    """
    import inspect

    from app.api.v1.salons import sync_role

    source = inspect.getsource(sync_role)
    assert source.index("Salon.owner_id") < source.index("StaffMember.user_id")


def test_les_trois_roles_couvrent_les_cas_possibles():
    """Le rôle dérive de ce que le compte possède, il n'est jamais déclaratif."""
    from app.models.enums import Role

    assert {r.value for r in Role} == {"CLIENT", "STAFF", "OWNER"}


def test_aucune_route_ne_s_appuie_sur_le_role_staff():
    """Les accès employé passent par l'existence d'un StaffMember.

    Si ce test tombe, c'est qu'une route s'est mise à gater sur `Role.STAFF` :
    il faut alors s'assurer que `sync_role` est appelé partout où un employé
    peut perdre son rattachement, sinon un renvoyé garderait la porte ouverte.
    """
    import pathlib

    api = pathlib.Path(__file__).resolve().parents[1] / "app" / "api"
    # `Depends(...)` cible l'usage réel : chercher le nom seul attraperait
    # aussi les commentaires qui en parlent, celui-ci compris.
    for fichier in api.rglob("*.py"):
        source = fichier.read_text(encoding="utf-8")
        assert "Depends(require_role(Role.STAFF" not in source, fichier.name


def test_une_reservation_previent_le_coiffeur_et_le_gerant():
    """Le salon doit savoir, pas seulement la personne qui coupera.

    Le gérant tient l'agenda et la caisse : ne prévenir que le coiffeur le
    laissait découvrir ses journées après coup.
    """
    import inspect

    from app.api.v1 import bookings

    source = inspect.getsource(bookings.create_booking_route) \
        if hasattr(bookings, "create_booking_route") else inspect.getsource(bookings)
    debut = source.index("Nouveau rendez-vous")
    extrait = source[max(0, debut - 400):debut]
    assert "staff.user_id" in extrait
    assert "salon.owner_id" in extrait


def test_le_patron_qui_coupe_ne_recoit_pas_deux_fois():
    """`notify_many` déduplique : sinon un patron-coiffeur aurait deux alertes."""
    import inspect

    from app.services.notification_service import notify_many

    # La déduplication passe par un `set` sur les identifiants.
    assert "{u for u in user_ids" in inspect.getsource(notify_many)
