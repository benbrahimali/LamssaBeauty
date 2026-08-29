"""SplitEngine — répartition caisse salon / employé (§3.4, §5.2).

Fonction pure : aucune I/O, entièrement testable unitairement.

Chaque salon encode ici sa propre entente avec son équipe : un taux par
service — une couleur ne se paie pas comme une coupe —, le coût du produit
retenu avant partage, et le sort du pourboire. Rien n'est imposé, parce que
deux salons voisins ne s'organisent presque jamais pareil.
"""
from dataclasses import dataclass

from app.models.enums import CommissionType


@dataclass(frozen=True)
class SplitResult:
    amount: float
    salon_share: float
    staff_share: float
    tip: float = 0.0

    #: Coût du produit retenu par le salon avant partage — affiché pour que
    #: l'employé comprenne pourquoi sa part n'est pas la moitié du prix.
    product_cost: float = 0.0

    #: Part du pourboire revenant au salon (0 dans la quasi-totalité des cas).
    salon_tip: float = 0.0

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
        product_cost: float = 0.0,
        tip_staff_pct: float = 100.0,
    ) -> SplitResult:
        """Calcule la répartition d'une prestation de `amount` dinars.

        - PERCENT            : ex. 50/50 -> 15 DT donnent 7,5 / 7,5
        - FIXED_PLUS_PERCENT : part fixe garantie + % du reste
        - SALON_KEEPS_ALL    : employé salarié, le salon garde tout

        `product_cost` est retenu par le salon **avant** le partage : sur une
        couleur à 50 DT dont 12 de produit, l'employé touche la moitié de 38,
        pas de 50. Partager le prix brut ferait payer au salon la moitié d'un
        produit qu'il a acheté seul.

        `tip_staff_pct` laisse chaque salon décider du pourboire. 100 % —
        le défaut — le donne entièrement à l'employé.
        """
        if amount < 0:
            raise ValueError("Le montant ne peut pas être négatif")
        if not 0 <= commission_pct <= 100:
            raise ValueError("La commission doit être comprise entre 0 et 100 %")
        if product_cost < 0:
            raise ValueError("Le coût produit ne peut pas être négatif")
        if not 0 <= tip_staff_pct <= 100:
            raise ValueError("La part de pourboire doit être comprise entre 0 et 100 %")

        # Un produit plus cher que la prestation ne laisse rien à partager,
        # mais ne doit pas produire une base négative.
        retenue = round(min(product_cost, amount), 2)
        base = amount - retenue

        if commission_type is CommissionType.SALON_KEEPS_ALL:
            staff_share = 0.0
        elif commission_type is CommissionType.FIXED_PLUS_PERCENT:
            fixed = min(commission_fixed, base)
            staff_share = fixed + (base - fixed) * commission_pct / 100
        else:
            staff_share = base * commission_pct / 100

        staff_share = round(min(staff_share, base), 2)
        part_employe = round(tip * tip_staff_pct / 100, 2)
        return SplitResult(
            amount=round(amount, 2),
            # Le salon garde le reste, coût produit compris : c'est lui qui l'a
            # avancé.
            salon_share=round(amount - staff_share, 2),
            staff_share=staff_share,
            tip=part_employe,
            product_cost=retenue,
            salon_tip=round(tip - part_employe, 2),
        )

    @staticmethod
    def rate_for(staff, service=None, salon=None) -> float:
        """Taux applicable, du plus spécifique au plus général.

        Un salon peut fixer une règle générale, l'ajuster pour un employé, puis
        la surcharger pour une prestation particulière — une couleur laisse
        moins de marge qu'une coupe. On lit donc service, puis employé, puis
        salon.
        """
        if service is not None and getattr(service, "commission_pct", None) is not None:
            return service.commission_pct
        if staff is not None:
            return staff.commission_pct
        if salon is not None:
            return salon.default_split_pct
        return 50.0

    @staticmethod
    def for_staff(
        amount: float,
        staff,
        tip: float = 0.0,
        *,
        service=None,
        salon=None,
    ) -> SplitResult:
        """Variante pratique : résout la règle du salon pour cette prestation."""
        return SplitEngine.compute(
            amount,
            commission_type=staff.commission_type,
            commission_pct=SplitEngine.rate_for(staff, service, salon),
            commission_fixed=staff.commission_fixed,
            tip=tip,
            product_cost=getattr(service, "product_cost", 0.0) if service else 0.0,
            tip_staff_pct=getattr(salon, "tip_staff_pct", 100.0) if salon else 100.0,
        )
