"""Compte de résultat du salon (§3.4).

La caisse du jour dit ce qui est entré ; ce module dit ce qu'il reste. Un
salon peut encaisser 3 000 DT dans le mois et perdre de l'argent une fois le
loyer payé — c'est exactement ce que ces tests protègent.
"""
import pytest

from app.models.enums import ChargePeriod
from app.services.cash_service import DAYS_PER_MONTH, DAYS_PER_YEAR, daily_cost


# ── Ramener toutes les charges au jour ───────────────────────────────────────
def test_un_loyer_mensuel_redonne_son_montant_sur_un_mois():
    """La conversion ne doit rien créer ni rien perdre."""
    assert daily_cost(900, ChargePeriod.MONTHLY) * DAYS_PER_MONTH == pytest.approx(900)


def test_une_taxe_annuelle_redonne_son_montant_sur_une_annee():
    assert daily_cost(1200, ChargePeriod.YEARLY) * DAYS_PER_YEAR == pytest.approx(1200)


def test_un_salaire_hebdomadaire_redonne_son_montant_sur_sept_jours():
    assert daily_cost(200, ChargePeriod.WEEKLY) * 7 == pytest.approx(200)


def test_le_mois_moyen_tient_compte_des_annees_bissextiles():
    """30 jours ronds feraient dériver le prorata de six jours par an.

    Sur un loyer de 900 DT, cela sous-compterait 180 DT de charges annuelles —
    de quoi transformer un salon déficitaire en salon rentable sur le papier.
    """
    assert DAYS_PER_MONTH == pytest.approx(30.4375)
    assert DAYS_PER_YEAR == pytest.approx(365.25)


def test_une_periode_inconnue_est_traitee_comme_mensuelle():
    """Défaut sûr : le mois est le rythme de la quasi-totalité des charges."""
    assert daily_cost(300, "rythme_inattendu") == pytest.approx(daily_cost(300, ChargePeriod.MONTHLY))


def test_une_charge_a_zero_ne_coute_rien():
    for periode in ChargePeriod:
        assert daily_cost(0, periode) == 0


@pytest.mark.parametrize(
    "periode,jours,attendu",
    [
        (ChargePeriod.MONTHLY, 7, 206.98),   # loyer de 900 sur une semaine
        (ChargePeriod.MONTHLY, 1, 29.57),    # la même journée
        (ChargePeriod.WEEKLY, 30.4375, 869.64),
    ],
)
def test_le_prorata_est_stable_entre_les_periodes(periode, jours, attendu):
    """Sans prorata, la semaine du loyer paraîtrait catastrophique et les
    trois autres excellentes — le gérant ne pourrait comparer ses semaines."""
    montant = 900 if periode is ChargePeriod.MONTHLY else 200
    assert daily_cost(montant, periode) * jours == pytest.approx(attendu, abs=0.02)


# ── Le résultat lui-même ─────────────────────────────────────────────────────
from dataclasses import dataclass, field  # noqa: E402
from datetime import datetime, timezone  # noqa: E402

from app.services import cash_service  # noqa: E402


@dataclass
class FakeTx:
    amount: float
    staff_share: float
    salon_share: float = 0.0
    tip: float = 0.0


@dataclass
class FakeExpense:
    amount: float
    category: str = "produits"


@dataclass
class FakeCharge:
    label: str
    amount: float
    period: ChargePeriod = ChargePeriod.MONTHLY
    category: str = "loyer"
    id: str = "c1"


@dataclass
class Donnees:
    txs: list = field(default_factory=list)
    expenses: list = field(default_factory=list)
    charges: list = field(default_factory=list)


@pytest.fixture
def donnees(monkeypatch):
    d = Donnees()

    class Requete:
        def __init__(self, r):
            self._r = r

        async def to_list(self):
            return self._r

    monkeypatch.setattr(cash_service.Transaction, "find", lambda *a, **k: Requete(d.txs))
    monkeypatch.setattr(cash_service.Expense, "find", lambda *a, **k: Requete(d.expenses))
    monkeypatch.setattr(
        cash_service.RecurringCharge, "find", lambda *a, **k: Requete(d.charges)
    )
    return d


async def _pnl(jours=30.4375):
    debut = datetime(2026, 8, 1, tzinfo=timezone.utc)
    return await cash_service.profit_and_loss(
        "salon", debut, debut + timedelta(days=jours)
    )


from datetime import timedelta  # noqa: E402


@pytest.mark.asyncio
async def test_un_salon_sans_activite_a_un_resultat_nul(donnees):
    p = await _pnl()
    assert p["revenue"] == 0
    assert p["result"] == 0
    assert p["margin_pct"] == 0, "pas de division par zéro"


@pytest.mark.asyncio
async def test_la_marge_brute_est_le_chiffre_moins_la_part_equipe(donnees):
    donnees.txs = [FakeTx(amount=100, staff_share=50), FakeTx(amount=60, staff_share=30)]
    p = await _pnl()

    assert p["revenue"] == 160
    assert p["staff_share"] == 80
    assert p["gross_margin"] == 80


@pytest.mark.asyncio
async def test_les_pourboires_ne_gonflent_pas_le_resultat(donnees):
    """Ils transitent par la caisse mais appartiennent à l'employé.

    Les compter en revenu ferait croire au gérant qu'il gagne plus.
    """
    donnees.txs = [FakeTx(amount=100, staff_share=50, tip=20)]
    p = await _pnl()

    assert p["revenue"] == 100, "le pourboire n'est pas du chiffre d'affaires"
    assert p["tips_collected"] == 20, "mais il reste visible : il est passé en caisse"
    assert p["result"] == 50


@pytest.mark.asyncio
async def test_le_loyer_transforme_un_benefice_en_perte(donnees):
    """Le cas qui justifie tout le module."""
    donnees.txs = [FakeTx(amount=1000, staff_share=500)]
    donnees.charges = [FakeCharge("Loyer", 900)]

    p = await _pnl()
    assert p["gross_margin"] == 500, "la caisse dit 500 de marge"
    assert p["recurring_charges"] == pytest.approx(900, abs=0.1)
    assert p["result"] < 0, "et pourtant le salon perd de l'argent"


@pytest.mark.asyncio
async def test_les_depenses_ponctuelles_et_les_charges_s_additionnent(donnees):
    donnees.txs = [FakeTx(amount=2000, staff_share=1000)]
    donnees.expenses = [FakeExpense(120, "produits"), FakeExpense(80, "entretien")]
    donnees.charges = [FakeCharge("Loyer", 600)]

    p = await _pnl()
    assert p["expenses"] == 200
    assert p["recurring_charges"] == pytest.approx(600, abs=0.1)
    assert p["result"] == pytest.approx(1000 - 200 - 600, abs=0.1)


@pytest.mark.asyncio
async def test_chaque_poste_est_ventile_par_categorie(donnees):
    """Le gérant veut savoir où part l'argent, pas seulement combien."""
    donnees.expenses = [FakeExpense(120, "produits"), FakeExpense(30, "produits")]
    donnees.charges = [FakeCharge("Loyer", 600, category="loyer")]

    p = await _pnl()
    assert p["by_category"]["produits"] == 150
    assert p["by_category"]["loyer"] == pytest.approx(600, abs=0.1)
    # Trié du plus lourd au plus léger : c'est le premier poste qu'on regarde.
    assert list(p["by_category"])[0] == "loyer"


@pytest.mark.asyncio
async def test_le_taux_de_marge_situe_le_resultat(donnees):
    """500 DT sur 10 000 de chiffre n'a rien à voir avec 500 sur 1 500."""
    donnees.txs = [FakeTx(amount=1000, staff_share=500)]
    p = await _pnl()
    assert p["margin_pct"] == pytest.approx(50, abs=0.1)


@pytest.mark.asyncio
async def test_chaque_charge_montre_son_montant_reel_et_son_prorata(donnees):
    """Sur une semaine, un loyer de 900 doit s'afficher 900 — et peser 207."""
    donnees.charges = [FakeCharge("Loyer", 900)]
    p = await _pnl(jours=7)

    ligne = p["charges"][0]
    assert ligne["amount"] == 900, "ce que le gérant paie vraiment"
    assert ligne["prorated"] == pytest.approx(206.98, abs=0.05), "ce que la semaine coûte"
