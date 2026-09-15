"""Corriger une dépense et joindre la photo du ticket (§3.4).

Une faute de frappe obligeait à supprimer puis ressaisir la dépense ; et rien
n'empêchait de supprimer une dépense déjà comptée dans une clôture.
"""
import pytest
from pydantic import ValidationError

from app.api.v1.cash import expense_edit_refusal
from app.models.documents import Expense
from app.models.enums import PaymentSource
from app.schemas.cash import ExpenseUpdate


# ── Journée clôturée ─────────────────────────────────────────────────────────
def test_une_depense_du_jour_se_corrige():
    assert expense_edit_refusal(day_closed=False) is None


def test_une_depense_d_une_journee_cloturee_est_figee():
    """Le rapport de clôture l'a déjà comptée."""
    refus = expense_edit_refusal(day_closed=True)
    assert refus is not None and "clôturée" in refus


# ── Ce qui se corrige ────────────────────────────────────────────────────────
def test_seuls_les_champs_fournis_changent():
    maj = ExpenseUpdate(amount=54)
    assert maj.model_dump(exclude_none=True) == {"amount": 54}


def test_passer_une_depense_du_tiroir_a_la_banque():
    maj = ExpenseUpdate(paid_from=PaymentSource.BANK)
    assert maj.model_dump(exclude_none=True) == {"paid_from": PaymentSource.BANK}


def test_une_correction_vide_est_refusee():
    with pytest.raises(ValidationError):
        ExpenseUpdate()


def test_un_montant_nul_ou_negatif_est_refuse():
    with pytest.raises(ValidationError):
        ExpenseUpdate(amount=0)
    with pytest.raises(ValidationError):
        ExpenseUpdate(amount=-10)


def test_un_libelle_trop_court_est_refuse():
    with pytest.raises(ValidationError):
        ExpenseUpdate(label="x")


def test_la_date_ne_se_deplace_pas():
    """Déplacer une dépense changerait deux tiroirs, dont un peut-être compté."""
    assert "spent_at" not in ExpenseUpdate.model_fields


# ── Le ticket ────────────────────────────────────────────────────────────────
def test_une_depense_peut_porter_la_photo_de_son_ticket():
    champ = Expense.model_fields["receipt_url"]
    assert champ.default is None, "sans ticket par défaut : rien n'est inventé"
