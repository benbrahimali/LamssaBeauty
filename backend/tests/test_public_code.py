"""Code public de salon (§3.2, §8.3) : lu par une caméra, mais aussi par un humain.

Le code finit imprimé sur une vitrine et collé dans des conversations WhatsApp.
Ces tests protègent ce qui compte à l'usage : pas de caractères ambigus, une
saisie tolérante, et un espace de codes assez large pour que les collisions
restent l'exception.
"""
from app.services import public_code


# ── Génération ───────────────────────────────────────────────────────────────
def test_le_code_reprend_le_nom_du_salon():
    """Collé dans une conversation, le code doit rester reconnaissable."""
    assert public_code.generate("Barbier El Menzah").startswith("BARBIE")


def test_les_accents_et_espaces_disparaissent():
    code = public_code.generate("Rania Beauté Lounge")
    assert code.startswith("RANIAB")
    assert code.isalnum()


def test_un_nom_entierement_non_latin_donne_un_code_utilisable():
    """Un salon nommé en arabe n'a pas de préfixe : le suffixe suffit."""
    code = public_code.generate("صالون الأنس")
    assert len(code) == public_code.SUFFIX_LEN
    assert public_code.is_valid(code)


def test_un_nom_tres_long_est_tronque():
    code = public_code.generate("Studio Mariées Carthage Prestige International")
    assert len(code) == public_code.PREFIX_MAX + public_code.SUFFIX_LEN


def test_aucun_caractere_confondable_dans_le_suffixe():
    """0/O et 1/I/L se lisent pareil sur une vitrine : ils sont exclus."""
    for interdit in "01OIL":
        assert interdit not in public_code.ALPHABET


def test_deux_codes_du_meme_salon_different():
    codes = {public_code.generate("Barbier El Menzah") for _ in range(50)}
    assert len(codes) > 45, "le suffixe doit être réellement aléatoire"


def test_tout_code_genere_est_valide():
    for nom in ("Barbier El Menzah", "صالون", "A", ""):
        assert public_code.is_valid(public_code.generate(nom))


# ── Saisie manuelle ──────────────────────────────────────────────────────────
def test_la_saisie_manuelle_tolere_casse_espaces_et_tirets():
    """Le client qui n'arrive pas à scanner tape le code comme il le voit."""
    for saisie in ("barbie-7k2m", "BARBIE 7K2M", " Barbie7K2M ", "barbie 7k2m"):
        assert public_code.normalize(saisie) == "BARBIE7K2M"


def test_un_code_mal_forme_est_rejete():
    for invalide in ("", "ABC", "BARBIE7K2M0", "barbie7k2m", "BARBIE-7K2M"):
        assert not public_code.is_valid(invalide)


def test_un_code_normalise_reste_valide():
    code = public_code.generate("Barbier")
    assert public_code.is_valid(public_code.normalize(code.lower()))
