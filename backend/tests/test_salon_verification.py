"""Salon créé tout de suite, visible après vérification (§2.5).

Le gérant ouvre son salon dès l'inscription et le prépare ; les clients ne le
voient qu'une fois validé par LAMSSA. Ce qui protège le public n'est donc plus
l'accès au formulaire, mais la visibilité du salon — d'où ces règles, testées
sans base de données comme les autres règles du domaine.
"""
from bson import ObjectId

from app.core.deps import without_salons
from app.models.documents import (
    HIDDEN_VERIFICATION,
    PUBLIC_SALON_FILTER,
    may_self_activate_pro,
    salon_is_public,
    salons_hidden_from,
)
from app.models.enums import SalonVerification


# ── Qui peut se déclarer professionnel ───────────────────────────────────────
def test_un_nouveau_gerant_s_active_seul():
    """Le cas d'Ilyes : inscrit via « عندي صالون », il doit pouvoir créer son
    salon sans attendre qu'on lui ouvre l'accès."""
    assert may_self_activate_pro(has_staff_profile=False) is True


def test_un_coiffeur_employe_ne_s_active_pas():
    """Travailler dans un salon ne donne pas le droit d'en ouvrir un depuis ce
    compte — sinon la règle ne protégerait plus rien."""
    assert may_self_activate_pro(has_staff_profile=True) is False


# ── Ce que voit le public ────────────────────────────────────────────────────
def test_un_salon_en_attente_est_cache():
    assert salon_is_public(SalonVerification.PENDING) is False


def test_un_salon_refuse_est_cache():
    assert salon_is_public(SalonVerification.REJECTED) is False


def test_un_salon_verifie_est_visible():
    assert salon_is_public(SalonVerification.VERIFIED) is True


def test_un_salon_anterieur_a_la_regle_reste_visible():
    """Les salons existants n'ont pas le champ : les cacher effacerait de l'app
    des salons qui reçoivent déjà des clients."""
    assert salon_is_public(None) is True


def test_la_valeur_brute_de_la_base_suit_la_meme_regle():
    """Mongo renvoie des chaînes : la règle ne doit pas dépendre du type."""
    assert salon_is_public("pending") is False
    assert salon_is_public("verified") is True


def test_le_filtre_mongo_et_la_regle_python_concordent():
    """Deux écritures de la même règle : la recherche (Mongo) et la fiche
    (Python) ne doivent jamais diverger."""
    exclus = set(PUBLIC_SALON_FILTER["verification_status"]["$nin"])
    for statut in [None, *SalonVerification]:
        valeur = statut.value if statut else None
        assert (valeur not in exclus) == salon_is_public(statut), statut


def test_le_filtre_n_exige_pas_le_champ():
    """`$nin` laisse passer un document sans le champ ; `$eq: verified` le
    rejetterait, et tous les salons existants disparaîtraient."""
    assert "$nin" in PUBLIC_SALON_FILTER["verification_status"]
    assert set(HIDDEN_VERIFICATION) == {"pending", "rejected"}


# ── Qui voit un salon en préparation ─────────────────────────────────────────
SALON, GERANT = ObjectId(), ObjectId()
CACHES = [(SALON, GERANT)]


def test_un_visiteur_anonyme_ne_le_voit_pas():
    assert salons_hidden_from(CACHES, viewer_id=None) == [SALON]


def test_un_client_ne_le_voit_pas():
    assert salons_hidden_from(CACHES, viewer_id=ObjectId()) == [SALON]


def test_son_gerant_le_voit():
    """Sans cela il ne pourrait pas vérifier ce qu'il prépare."""
    assert salons_hidden_from(CACHES, viewer_id=GERANT) == []


def test_son_equipe_le_voit():
    assert salons_hidden_from(CACHES, viewer_id=ObjectId(), member_of={SALON}) == []


def test_le_coiffeur_d_un_autre_salon_ne_le_voit_pas():
    assert salons_hidden_from(CACHES, viewer_id=ObjectId(), member_of={ObjectId()}) == [SALON]


def test_l_administration_le_voit():
    assert salons_hidden_from(CACHES, viewer_id=ObjectId(), is_admin=True) == []


# ── Exclusion dans les fils publics ──────────────────────────────────────────
def test_sans_salon_cache_la_requete_est_intacte():
    requete = {"tags": "fade"}
    assert without_salons(requete, []) == {"tags": "fade"}


def test_les_salons_caches_sont_exclus():
    assert without_salons({}, [SALON]) == {"salon_id": {"$nin": [SALON]}}


def test_le_filtre_d_un_salon_precis_est_conserve():
    """Écraser la clé ferait du fil d'un salon le fil général."""
    autre = ObjectId()
    assert without_salons({"salon_id": autre}, [SALON]) == {
        "salon_id": {"$nin": [SALON], "$eq": autre}
    }


def test_la_requete_d_origine_n_est_pas_modifiee():
    requete = {"staff_id": ObjectId()}
    without_salons(requete, [SALON])
    assert "salon_id" not in requete
