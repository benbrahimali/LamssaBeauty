"""Code public d'un salon (§3.2, §8.3).

Le gérant l'imprime en QR sur sa vitrine et le partage sur WhatsApp. Il est donc
lu par des humains autant que par des caméras : on retire les caractères qui se
confondent (0/O, 1/I/L) pour qu'un client puisse le taper s'il n'arrive pas à
scanner, et on préfixe par un fragment du nom du salon pour qu'il reste
reconnaissable une fois collé dans une conversation.
"""
import re
import secrets
import unicodedata

# Sans 0/O/1/I/L : la confusion visuelle coûte plus cher que les combinaisons perdues.
ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
SUFFIX_LEN = 4
PREFIX_MAX = 6
CODE_RE = re.compile(rf"^[A-Z]{{0,{PREFIX_MAX}}}[{ALPHABET}]{{{SUFFIX_LEN}}}$")


def _slug(name: str) -> str:
    """Fragment alphabétique du nom, sans accent ni espace."""
    ascii_name = (
        unicodedata.normalize("NFKD", name)
        .encode("ascii", "ignore")
        .decode("ascii")
        .upper()
    )
    letters = re.sub(r"[^A-Z]", "", ascii_name)
    return letters[:PREFIX_MAX]


def generate(name: str) -> str:
    """Un code candidat. L'unicité est garantie par l'index, pas par cette fonction."""
    suffix = "".join(secrets.choice(ALPHABET) for _ in range(SUFFIX_LEN))
    return f"{_slug(name)}{suffix}"


def normalize(code: str) -> str:
    """Tolère la saisie manuelle : minuscules, espaces, tirets."""
    return re.sub(r"[\s-]", "", code).upper()


def is_valid(code: str) -> bool:
    return bool(CODE_RE.match(code))


async def assign(salon) -> str:
    """Attribue un code libre au salon et l'enregistre.

    L'unicité vient de l'index Mongo, pas d'un `find_one` préalable : deux
    créations simultanées passeraient toutes deux la vérification et
    produiraient un doublon. On réessaie donc sur collision.
    """
    from pymongo.errors import DuplicateKeyError

    for _ in range(8):
        salon.public_code = generate(salon.name)
        try:
            if salon.id is None:
                await salon.insert()
            else:
                await salon.save()
            return salon.public_code
        except DuplicateKeyError:
            continue

    # 31^4 ≈ 920 000 suffixes par préfixe : huit collisions de suite signalent
    # un vrai problème, pas la malchance.
    raise RuntimeError("Impossible de générer un code public unique")
