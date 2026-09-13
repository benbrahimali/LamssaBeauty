"""Qui peut ouvrir un salon (§2.5, §3.1).

La règle ne peut pas reposer sur le rôle. On ne devient gérant qu'en créant un
salon ; exiger d'être gérant pour en créer un rendrait la règle circulaire et
plus aucun salon ne pourrait naître. Elle repose donc sur une capacité portée
par le compte — accordée aujourd'hui par l'administration, demain par un
abonnement payé.
"""
from datetime import timedelta

from app.core.timeutils import utcnow
from app.models.documents import may_open_salon
from app.models.enums import Role


def peut(role=Role.CLIENT, pro=False, jusqu_a=None) -> bool:
    return may_open_salon(role=role, pro_access=pro, pro_access_until=jusqu_a)


# ── Les trois rôles du cahier des charges ────────────────────────────────────
def test_un_client_ordinaire_ne_peut_pas_ouvrir_de_salon():
    assert peut(Role.CLIENT) is False


def test_un_coiffeur_employe_ne_peut_pas_ouvrir_de_salon():
    """Travailler dans un salon n'a jamais donné le droit d'en ouvrir un — et
    surtout, être rattaché à une équipe ne promeut personne gérant."""
    assert peut(Role.STAFF) is False


def test_un_gerant_installe_le_peut():
    """Il possède déjà un salon : le lui refuser l'empêcherait d'en ouvrir un
    second sans rien protéger."""
    assert peut(Role.OWNER) is True


# ── La capacité professionnelle ──────────────────────────────────────────────
def test_un_client_autorise_peut_ouvrir_son_premier_salon():
    """Le cas qui rend le système praticable : sans lui, aucun nouveau gérant
    ne pourrait jamais rejoindre la plateforme."""
    assert peut(Role.CLIENT, pro=True) is True


def test_un_coiffeur_autorise_aussi():
    """Un coiffeur qui quitte son employeur pour s'installer reste le même
    compte : on ne lui demande pas d'en créer un autre."""
    assert peut(Role.STAFF, pro=True) is True


def test_la_capacite_ne_change_pas_le_role():
    """Accorder l'accès n'est pas promouvoir : la promotion vient de la
    création, pas de l'autorisation."""
    # Accorder la capacité ne touche pas au rôle : seule la création promeut.
    assert peut(Role.CLIENT, pro=True) is True


# ── L'échéance, prête pour l'abonnement ──────────────────────────────────────
def test_un_acces_sans_terme_reste_valable():
    assert peut(Role.CLIENT, pro=True, jusqu_a=None) is True


def test_un_acces_encore_valide_ouvre_le_droit():
    demain = utcnow() + timedelta(days=1)
    assert peut(Role.CLIENT, pro=True, jusqu_a=demain) is True


def test_un_acces_expire_ne_vaut_pas_mieux_qu_aucun():
    hier = utcnow() - timedelta(days=1)
    assert peut(Role.CLIENT, pro=True, jusqu_a=hier) is False


def test_un_gerant_garde_son_droit_meme_abonnement_expire():
    """Son salon existe : lui couper l'accès ne le supprimerait pas, cela
    l'empêcherait seulement d'en ouvrir un de plus. Le facturer est un sujet,
    lui retirer son outil de travail en est un autre."""
    hier = utcnow() - timedelta(days=1)
    assert peut(Role.OWNER, pro=True, jusqu_a=hier) is True


def test_l_echeance_ne_sert_a_rien_sans_acces():
    """Une date seule n'accorde rien : c'est le drapeau qui décide."""
    demain = utcnow() + timedelta(days=1)
    assert peut(Role.CLIENT, pro=False, jusqu_a=demain) is False


# ── Défaut sûr ───────────────────────────────────────────────────────────────
def test_un_compte_neuf_n_a_aucun_droit():
    """Le défaut refuse : un oubli de configuration ferme la porte au lieu de
    l'ouvrir."""
    assert peut() is False
