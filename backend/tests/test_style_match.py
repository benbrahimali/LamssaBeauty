"""Style DNA → offre réelle (§2.4, §8.5).

L'analyse ne vaut que si elle mène quelque part : ces tests couvrent la logique
de rapprochement entre une coupe conseillée et le catalogue, sans modèle vision
ni base de données.
"""
import pytest

from app.services import style_match


class FakeStaff:
    def __init__(self, specialties, service_ids=(), name="Ahmed"):
        self.specialties = list(specialties)
        self.service_ids = list(service_ids)
        self.display_name = name


class FakeService:
    def __init__(self, name, category="", name_ar=""):
        self.name = name
        self.name_ar = name_ar
        self.category = category


class FakeStyle:
    def __init__(self, name, tags):
        self.name = name
        self.tags = list(tags)


class FakeSalon:
    def __init__(self, lng, lat):
        self.location = type("Loc", (), {"coordinates": [lng, lat]})()


# ── Normalisation ────────────────────────────────────────────────────────────
@pytest.mark.parametrize(
    "saisie,attendu",
    [("Dégradé", "degrade"), ("FADE", "fade"), ("  Barbe  ", "barbe"), ("Coupé", "coupe")],
)
def test_les_accents_et_la_casse_ne_bloquent_pas_la_correspondance(saisie, attendu):
    assert style_match._fold(saisie) == attendu


def test_les_mots_courts_du_nom_sont_ignores():
    """« un », « de » n'identifient aucune coupe et feraient tout correspondre."""
    terms = style_match._terms("Fade de côté", ["taper"])
    assert "de" not in terms
    assert {"fade", "taper"} <= terms


# ── Score ────────────────────────────────────────────────────────────────────
def test_la_specialite_du_coiffeur_pese_plus_que_le_nom_du_service():
    terms = {"fade"}
    specialiste = FakeStaff(["Fade"])
    generaliste = FakeStaff(["Coloration"])

    score_specialiste, _ = style_match._score(terms, specialiste, FakeService("Coupe homme"))
    score_generaliste, _ = style_match._score(terms, generaliste, FakeService("Fade homme"))

    # Un salon peut appeler « coupe homme » ce que seul un coiffeur sait faire
    # en fade : la compétence de la personne prime sur le libellé du catalogue.
    assert score_specialiste > score_generaliste


def test_sans_aucun_recoupement_le_score_est_nul():
    score, hits = style_match._score({"fade"}, FakeStaff(["Coloration"]), FakeService("Brushing"))
    assert score == 0
    assert hits == []


def test_le_motif_ayant_declenche_la_correspondance_est_rapporte():
    """L'app affiche ce libellé : il doit être celui du salon, pas le terme interne."""
    _, hits = style_match._score({"fade"}, FakeStaff(["Fade & dégradé"]), FakeService("Coupe"))
    assert "Fade & dégradé" in hits


def test_un_service_ne_compte_qu_une_fois_meme_avec_plusieurs_termes():
    score, hits = style_match._score(
        {"fade", "coupe"}, FakeStaff([]), FakeService("Fade coupe homme")
    )
    assert score == 1
    assert hits == ["Fade coupe homme"]


def test_barbershop_ne_correspond_pas_a_barbe():
    """Régression : « barbe » est une sous-chaîne de « barbershop ».

    Avec une comparaison par sous-chaîne, toute prestation d'un barbier
    correspondait à une coupe de barbe — y compris « Coupe homme ».
    """
    score, hits = style_match._score(
        {"barbe"}, FakeStaff([]), FakeService("Coupe homme", category="barbershop")
    )
    assert score == 0, hits


def test_le_vrai_service_barbe_correspond_toujours():
    score, _ = style_match._score(
        {"barbe"}, FakeStaff([]), FakeService("Barbe", category="barbershop")
    )
    assert score == 1


@pytest.mark.parametrize(
    "terme,mot,attendu",
    [
        ("degrade", "degrades", True),   # pluriel du catalogue
        ("fade", "fade", True),
        ("barbe", "barbershop", False),  # le piège
        ("coupe", "coupure", False),
        ("fade", "", False),
    ],
)
def test_comparaison_par_mots_entiers(terme, mot, attendu):
    assert style_match._same_word(terme, mot) is attendu


def test_une_specialite_vide_ne_correspond_a_rien():
    """Un coiffeur sans spécialité ne doit pas correspondre à toutes les coupes."""
    score, _ = style_match._score({"fade"}, FakeStaff([""]), FakeService("Brushing"))
    assert score == 0


# ── Distance ─────────────────────────────────────────────────────────────────
def test_la_distance_est_nulle_sur_place():
    salon = FakeSalon(10.1815, 36.8065)
    assert style_match._distance_km(salon, 36.8065, 10.1815) == 0.0


def test_la_distance_tunis_sfax_est_plausible():
    """Repère : ~235 km à vol d'oiseau."""
    sfax = FakeSalon(10.7600, 34.7400)
    distance = style_match._distance_km(sfax, 36.8065, 10.1815)
    assert 220 < distance < 250


# ── Garde-fous ───────────────────────────────────────────────────────────────
@pytest.mark.asyncio
async def test_sans_position_aucune_offre_n_est_proposee():
    """Un coiffeur de Sfax proposé à un client de Tunis serait pire que rien."""
    styles = [FakeStyle("Fade", ["fade"])]
    assert await style_match.find_matches(styles, lat=None, lng=None) == {}
    assert await style_match.find_matches(styles, lat=36.8, lng=None) == {}


@pytest.mark.asyncio
async def test_sans_coupe_conseillee_rien_n_est_cherche():
    assert await style_match.find_matches([], lat=36.8, lng=10.18) == {}


def test_une_specialite_seule_ne_suffit_pas_a_proposer_une_offre():
    """On réserve un service, pas une spécialité.

    Une coiffeuse spécialisée « dégradé » dont le catalogue ne contient que
    « Manucure » ne doit pas être proposée pour un fade : le client cliquerait
    sur une prestation qui n'est pas la coupe conseillée. `find_matches` écarte
    donc les paires dont le service n'apparaît pas dans les correspondances.
    """
    manucure = FakeService("Manucure", category="femme")
    coiffeuse = FakeStaff(["degrade"], name="Rania")

    score, hits = style_match._score({"fade", "degrade"}, coiffeuse, manucure)

    assert score > 0, "la spécialité correspond bien"
    assert manucure.name not in hits, "mais aucun service ne nomme la coupe"


def test_le_rayon_par_defaut_reste_a_l_echelle_d_une_ville():
    assert 5 <= style_match.DEFAULT_RADIUS_KM <= 25


def test_on_ne_propose_pas_plus_de_trois_offres_par_coupe():
    """Au-delà, l'écran devient un annuaire et ne décide plus rien."""
    assert style_match.MAX_MATCHES_PER_STYLE == 3
