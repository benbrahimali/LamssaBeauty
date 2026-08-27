"""SplitEngine — répartition caisse salon / employé (§3.4, §5.2).

Fonction pure : aucune I/O, entièrement testable unitairement.
Le pourboire n'entre jamais dans le split — il revient à 100% à l'employé.
"""
from dataclasses import dataclass

from app.models.enums import CommissionType


@dataclass(frozen=True)
class SplitResult:
    amount: float
    salon_share: float
    staff_share: float
    tip: float = 0.0

    @property
    def staff_payout(self) -> float:
        """Ce que l'employé touche réellement : sa part + son pourboire."""
        return round(self.staff_share + self.tip, 2)


class SplitEngine:
    @staticmethod
    def compute(
        amount: float,
        *,
        commission_type: CommissionType = CommissionType.PERCENT,
        commission_pct: float = 50.0,
        commission_fixed: float = 0.0,
        tip: float = 0.0,
    ) -> SplitResult:
        """Calcule la répartition d'une prestation de `amount` dinars.

        - PERCENT            : ex. 50/50 -> 15 DT donnent 7,5 / 7,5
        - FIXED_PLUS_PERCENT : part fixe garantie + % du reste
        - SALON_KEEPS_ALL    : employé salarié, le salon garde tout
        """
        if amount < 0:
            raise ValueError("Le montant ne peut pas être négatif")
        if not 0 <= commission_pct <= 100:
            raise ValueError("La commission doit être comprise entre 0 et 100 %")

        if commission_type is CommissionType.SALON_KEEPS_ALL:
            staff_share = 0.0
        elif commission_type is CommissionType.FIXED_PLUS_PERCENT:
            fixed = min(commission_fixed, amount)
            staff_share = fixed + (amount - fixed) * commission_pct / 100
        else:
            staff_share = amount * commission_pct / 100

        staff_share = round(min(staff_share, amount), 2)
        return SplitResult(
            amount=round(amount, 2),
            salon_share=round(amount - staff_share, 2),
            staff_share=staff_share,
            tip=round(tip, 2),
        )

    @staticmethod
    def for_staff(amount: float, staff, tip: float = 0.0) -> SplitResult:
        """Variante pratique : lit la configuration de commission du StaffMember."""
        return SplitEngine.compute(
            amount,
            commission_type=staff.commission_type,
            commission_pct=staff.commission_pct,
            commission_fixed=staff.commission_fixed,
            tip=tip,
        )
