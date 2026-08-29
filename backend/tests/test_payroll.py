"""Paie hebdomadaire par coiffeur (§3.4).

Le gérant s'en sert pour payer son équipe en fin de semaine. Une erreur ici ne
se voit pas à l'écran : elle se voit dans la main de l'employé.
"""
from dataclasses import dataclass, field

import pytest

from app.services import cash_service


@dataclass
class FakeTx:
    staff_id: str
    amount: float
    staff_share: float
    tip: float = 0.0


@dataclass
class FakeAdvance:
    staff_id: str
    amount: float


@dataclass
class FauxResultat:
    """Remplace les requêtes Mongo : la règle testée est l'agrégation."""

    txs: list = field(default_factory=list)
    advances: list = field(default_factory=list)


@pytest.fixture
def collecte(monkeypatch):
    """Branche `payroll` sur des données en mémoire."""
    donnees = FauxResultat()

    class FausseRequete:
        def __init__(self, resultat):
            self._resultat = resultat

        async def to_list(self):
            return self._resultat

    def find_tx(*args, **kwargs):
        return FausseRequete(donnees.txs)

    def find_advance(*args, **kwargs):
        return FausseRequete(donnees.advances)

    monkeypatch.setattr(cash_service.Transaction, "find", find_tx)
    monkeypatch.setattr(cash_service.Advance, "find", find_advance)
    return donnees


async def _payroll(ids, names=None):
    from datetime import datetime, timezone

    return await cash_service.payroll(
        staff_ids=ids,
        start=datetime(2026, 8, 24, tzinfo=timezone.utc),
        end=datetime(2026, 8, 31, tzinfo=timezone.utc),
        names=names,
    )


@pytest.mark.asyncio
async def test_sans_equipe_il_n_y_a_rien_a_payer():
    assert await _payroll([]) == []


@pytest.mark.asyncio
async def test_un_coiffeur_sans_activite_apparait_quand_meme(collecte):
    """Une ligne à zéro est une information : il n'a rien fait cette semaine."""
    lignes = await _payroll(["a"], {"a": "Ahmed"})
    assert len(lignes) == 1
    assert lignes[0]["name"] == "Ahmed"
    assert lignes[0]["balance"] == 0.0


@pytest.mark.asyncio
async def test_la_paie_est_la_part_plus_les_pourboires(collecte):
    collecte.txs = [
        FakeTx("a", amount=40, staff_share=20, tip=5),
        FakeTx("a", amount=30, staff_share=15, tip=0),
    ]
    ligne = (await _payroll(["a"]))[0]

    assert ligne["services"] == 2
    assert ligne["gross"] == 70.0
    assert ligne["earned"] == 35.0
    assert ligne["tips"] == 5.0
    # Le pourboire est intégralement à l'employé : il ne rentre pas au split.
    assert ligne["balance"] == 40.0


@pytest.mark.asyncio
async def test_la_tseb9a_est_deduite_de_ce_qui_reste_a_payer(collecte):
    collecte.txs = [FakeTx("a", amount=100, staff_share=50, tip=10)]
    collecte.advances = [FakeAdvance("a", amount=20)]

    ligne = (await _payroll(["a"]))[0]
    assert ligne["advances"] == 20.0
    assert ligne["balance"] == 40.0, "50 + 10 - 20"


@pytest.mark.asyncio
async def test_une_avance_superieure_aux_gains_donne_un_solde_negatif(collecte):
    """C'est précisément ce que la tséb9a permet — et le gérant doit le voir.

    Masquer le négatif ferait croire que le compte est soldé alors que
    l'employé doit encore de l'argent au salon.
    """
    collecte.txs = [FakeTx("a", amount=40, staff_share=20)]
    collecte.advances = [FakeAdvance("a", amount=50)]

    assert (await _payroll(["a"]))[0]["balance"] == -30.0


@pytest.mark.asyncio
async def test_chaque_coiffeur_a_sa_propre_ligne(collecte):
    collecte.txs = [
        FakeTx("a", amount=100, staff_share=50),
        FakeTx("b", amount=60, staff_share=30),
    ]
    collecte.advances = [FakeAdvance("b", amount=10)]

    lignes = {l["staff_id"]: l for l in await _payroll(["a", "b"])}
    assert lignes["a"]["balance"] == 50.0
    assert lignes["b"]["balance"] == 20.0, "l'avance de b ne touche pas a"


@pytest.mark.asyncio
async def test_les_plus_gros_gains_arrivent_en_tete(collecte):
    """Le gérant paie de haut en bas : l'ordre lui évite de chercher."""
    collecte.txs = [
        FakeTx("petit", amount=20, staff_share=10),
        FakeTx("gros", amount=200, staff_share=100),
    ]
    lignes = await _payroll(["petit", "gros"])
    assert [l["staff_id"] for l in lignes] == ["gros", "petit"]


@pytest.mark.asyncio
async def test_les_lignes_affichees_s_additionnent_au_total(collecte):
    """Le total est calculé sur les montants déjà arrondis, volontairement.

    3,3333… arrondi donne 3,33 pour la part et 3,33 pour le pourboire. Sommer
    les valeurs exactes donnerait 6,67, et la fiche de paie afficherait alors
    « 3,33 + 3,33 = 6,67 » — impossible à justifier devant un employé qui
    compte, et impossible à rapprocher de l'espèce sortie du tiroir.
    """
    collecte.txs = [FakeTx("a", amount=10, staff_share=10 / 3, tip=10 / 3)]
    ligne = (await _payroll(["a"]))[0]

    assert ligne["earned"] == 3.33
    assert ligne["tips"] == 3.33
    assert ligne["balance"] == 6.66
    assert ligne["balance"] == ligne["earned"] + ligne["tips"]
