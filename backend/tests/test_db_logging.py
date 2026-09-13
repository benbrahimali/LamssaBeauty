"""Ce que le démarrage écrit dans les logs.

Le log de démarrage publiait l'URI MongoDB complète, mot de passe compris, dans
les logs de l'hébergeur — conservés et lisibles depuis le tableau de bord. Sur
ce cluster, le même mot de passe protège une autre application en production.
"""
from app.core.db import uri_sans_identifiants

ATLAS = (
    "mongodb+srv://benbrahimali_db_user:Motdepasse%407@cluster0.tdvydhm.mongodb.net"
    "/lamssa?retryWrites=true&w=majority&appName=Cluster0"
)


def test_le_mot_de_passe_disparait():
    assert "Motdepasse" not in uri_sans_identifiants(ATLAS)


def test_l_utilisateur_disparait_aussi():
    """Un nom d'utilisateur réel est la moitié d'un identifiant."""
    assert "benbrahimali_db_user" not in uri_sans_identifiants(ATLAS)


def test_l_hote_et_la_base_restent_lisibles():
    """Le log doit toujours dire à quoi on s'est connecté, sinon il ne sert à rien."""
    resultat = uri_sans_identifiants(ATLAS)
    assert "cluster0.tdvydhm.mongodb.net" in resultat
    assert "/lamssa" in resultat


def test_le_resultat_exact():
    assert uri_sans_identifiants(ATLAS) == (
        "mongodb+srv://cluster0.tdvydhm.mongodb.net"
        "/lamssa?retryWrites=true&w=majority&appName=Cluster0"
    )


def test_une_uri_sans_identifiants_est_rendue_telle_quelle():
    assert uri_sans_identifiants("mongodb://localhost:27017") == "mongodb://localhost:27017"


def test_un_utilisateur_sans_mot_de_passe_est_retire():
    assert uri_sans_identifiants("mongodb://admin@localhost:27017/x") == (
        "mongodb://localhost:27017/x"
    )


def test_un_arobase_encode_dans_le_mot_de_passe_ne_laisse_rien_passer():
    """`%40` est un @ encodé : il ne doit pas couper le mot de passe en deux."""
    uri = "mongodb://u:a%40b%40c@db.example.com:27017/lamssa"
    resultat = uri_sans_identifiants(uri)
    assert "a%40b" not in resultat
    assert resultat == "mongodb://db.example.com:27017/lamssa"
