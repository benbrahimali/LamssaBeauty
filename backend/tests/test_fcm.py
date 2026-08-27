"""Push FCM HTTP v1 (§3.7) : chargement du compte de service et tri des erreurs.

L'API legacy ayant été fermée par Google le 22/07/2024, tout passe désormais par
un compte de service. Ces tests vérifient qu'une configuration absente ou
invalide dégrade proprement — l'API doit tourner sans Firebase — et que seuls
les vrais tokens morts sont purgés.
"""
import json

import pytest

from app.core.config import settings
from app.services import fcm


@pytest.fixture(autouse=True)
def _isolate_cache():
    """Le compte de service est mis en cache : chaque test repart à zéro."""
    fcm.reset_cache()
    original = settings.FCM_CREDENTIALS_FILE
    yield
    settings.FCM_CREDENTIALS_FILE = original
    fcm.reset_cache()


def _service_account(**overrides) -> dict:
    data = {
        "type": "service_account",
        "project_id": "lamssa-test",
        "private_key": "-----BEGIN PRIVATE KEY-----\nfake\n-----END PRIVATE KEY-----\n",
        "client_email": "sa@lamssa-test.iam.gserviceaccount.com",
        "token_uri": "https://oauth2.googleapis.com/token",
    }
    data.update(overrides)
    return data


# ── Chargement du compte de service ──────────────────────────────────────────
def test_sans_fichier_configure_le_push_est_simplement_inactif():
    settings.FCM_CREDENTIALS_FILE = ""
    assert fcm.credentials() is None


def test_un_fichier_introuvable_ne_fait_pas_planter_le_demarrage(tmp_path):
    settings.FCM_CREDENTIALS_FILE = str(tmp_path / "absent.json")
    assert fcm.credentials() is None


def test_un_json_invalide_desactive_le_push_sans_lever(tmp_path):
    path = tmp_path / "casse.json"
    path.write_text("{ pas du json", encoding="utf-8")
    settings.FCM_CREDENTIALS_FILE = str(path)
    assert fcm.credentials() is None


def test_un_compte_de_service_incomplet_desactive_le_push(tmp_path):
    data = _service_account()
    del data["client_email"]
    path = tmp_path / "incomplet.json"
    path.write_text(json.dumps(data), encoding="utf-8")
    settings.FCM_CREDENTIALS_FILE = str(path)
    assert fcm.credentials() is None


def test_un_compte_de_service_valide_est_charge_et_mis_en_cache(tmp_path):
    path = tmp_path / "sa.json"
    path.write_text(json.dumps(_service_account()), encoding="utf-8")
    settings.FCM_CREDENTIALS_FILE = str(path)

    creds = fcm.credentials()
    assert creds is not None
    assert creds.project_id == "lamssa-test"
    # Le fichier n'est lu qu'une fois : le second appel rend le même objet.
    assert fcm.credentials() is creds


@pytest.mark.asyncio
async def test_sans_compte_de_service_aucun_token_n_est_declare_mort(tmp_path):
    """Une config absente ne doit jamais faire purger les appareils des clients."""
    settings.FCM_CREDENTIALS_FILE = ""
    assert await fcm.send(["token-a", "token-b"], "T", "B", {}) == []


# ── Tri des erreurs FCM ──────────────────────────────────────────────────────
def test_le_code_d_erreur_est_lu_dans_les_details():
    body = {
        "error": {
            "status": "NOT_FOUND",
            "details": [
                {"@type": "type.googleapis.com/google.rpc.BadRequest"},
                {
                    "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
                    "errorCode": "UNREGISTERED",
                },
            ],
        }
    }
    assert fcm._error_code(body) == "UNREGISTERED"


def test_sans_details_on_retombe_sur_le_statut():
    assert fcm._error_code({"error": {"status": "UNAVAILABLE"}}) == "UNAVAILABLE"


def test_une_reponse_sans_erreur_ne_donne_aucun_code():
    assert fcm._error_code({}) == ""


@pytest.mark.parametrize("code", ["UNREGISTERED", "INVALID_ARGUMENT", "SENDER_ID_MISMATCH"])
def test_les_appareils_definitivement_perdus_sont_purgeables(code):
    assert code in fcm.DEAD_TOKEN_CODES


@pytest.mark.parametrize("code", ["UNAVAILABLE", "INTERNAL", "QUOTA_EXCEEDED", ""])
def test_une_panne_passagere_ne_fait_pas_perdre_l_appareil(code):
    """Purger sur UNAVAILABLE rendrait l'utilisateur injoignable après une panne FCM."""
    assert code not in fcm.DEAD_TOKEN_CODES
