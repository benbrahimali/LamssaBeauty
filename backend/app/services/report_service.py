"""Génération du rapport de clôture (§3.4, §5.4) — PDF partageable via WhatsApp."""
import logging
import os

from app.core.config import settings
from app.models.documents import CashClosure, Salon

log = logging.getLogger("lamssa.report")

DT = "DT"


def _rows(closure: CashClosure) -> list[tuple[str, str]]:
    return [
        ("Total encaissé", f"{closure.total:.2f} {DT}"),
        ("Part salon", f"{closure.salon_total:.2f} {DT}"),
        ("Part équipe", f"{closure.staff_total:.2f} {DT}"),
        ("Pourboires", f"{closure.tips_total:.2f} {DT}"),
        ("Dépenses du jour", f"-{closure.expenses_total:.2f} {DT}"),
        ("Tséb9as déduites", f"-{closure.advances_deducted:.2f} {DT}"),
        ("Net salon", f"{closure.net_salon:.2f} {DT}"),
        ("Nombre de prestations", str(closure.transaction_count)),
    ]


def _text_report(salon: Salon, closure: CashClosure) -> str:
    lines = [
        f"LAMSSA — Clôture du {closure.day}",
        salon.name,
        "-" * 44,
    ]
    lines += [f"{label:<26}{value:>18}" for label, value in _rows(closure)]
    lines += ["", "Répartition par mode de paiement", "-" * 44]
    lines += [f"{m:<26}{v:>15.2f} {DT}" for m, v in closure.by_method.items()]
    lines += ["", "Détail par employé", "-" * 44]
    for row in closure.by_staff.values():
        lines.append(
            f"{row.get('name', '—'):<20} {row.get('count', 0):>3} presta. "
            f"| part {row.get('staff_share', 0):>7.2f} "
            f"| pourb. {row.get('tips', 0):>6.2f} "
            f"| avance -{row.get('advance_deducted', 0):>6.2f} "
            f"| net {row.get('net_payout', row.get('staff_share', 0)):>7.2f} {DT}"
        )
    return "\n".join(lines)


def generate_closure_report(salon: Salon, closure: CashClosure) -> str:
    """Écrit le rapport sur disque et retourne son chemin.

    PDF si reportlab est installé, sinon repli sur un .txt lisible : la clôture ne
    doit jamais échouer à cause d'une dépendance de mise en page.
    """
    os.makedirs(settings.REPORTS_DIR, exist_ok=True)
    stem = os.path.join(settings.REPORTS_DIR, f"cloture_{salon.id}_{closure.day}")

    try:
        from reportlab.lib.pagesizes import A4
        from reportlab.lib.units import mm
        from reportlab.pdfgen import canvas
    except ImportError:
        path = f"{stem}.txt"
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(_text_report(salon, closure))
        log.info("reportlab absent — rapport texte généré : %s", path)
        return path

    path = f"{stem}.pdf"
    pdf = canvas.Canvas(path, pagesize=A4)
    width, height = A4
    y = height - 25 * mm

    pdf.setFont("Helvetica-Bold", 18)
    pdf.drawString(20 * mm, y, "LAMSSA")
    pdf.setFont("Helvetica", 11)
    pdf.drawRightString(width - 20 * mm, y, f"Clôture du {closure.day}")
    y -= 8 * mm
    pdf.setFont("Helvetica-Bold", 13)
    pdf.drawString(20 * mm, y, salon.name)
    y -= 4 * mm
    pdf.line(20 * mm, y, width - 20 * mm, y)
    y -= 10 * mm

    pdf.setFont("Helvetica", 11)
    for label, value in _rows(closure):
        pdf.drawString(22 * mm, y, label)
        pdf.drawRightString(width - 22 * mm, y, value)
        y -= 7 * mm

    y -= 4 * mm
    pdf.setFont("Helvetica-Bold", 12)
    pdf.drawString(20 * mm, y, "Modes de paiement")
    y -= 7 * mm
    pdf.setFont("Helvetica", 11)
    for method, value in closure.by_method.items():
        pdf.drawString(22 * mm, y, method)
        pdf.drawRightString(width - 22 * mm, y, f"{value:.2f} {DT}")
        y -= 7 * mm

    y -= 4 * mm
    pdf.setFont("Helvetica-Bold", 12)
    pdf.drawString(20 * mm, y, "Détail par employé")
    y -= 7 * mm
    pdf.setFont("Helvetica", 10)
    for row in closure.by_staff.values():
        if y < 25 * mm:
            pdf.showPage()
            y = height - 25 * mm
            pdf.setFont("Helvetica", 10)
        net = row.get("net_payout", row.get("staff_share", 0))
        pdf.drawString(
            22 * mm,
            y,
            f"{row.get('name', '—')} — {row.get('count', 0)} prestation(s), "
            f"part {row.get('staff_share', 0):.2f}, pourboires {row.get('tips', 0):.2f}, "
            f"avance -{row.get('advance_deducted', 0):.2f}",
        )
        pdf.drawRightString(width - 22 * mm, y, f"{net:.2f} {DT}")
        y -= 6 * mm

    pdf.setFont("Helvetica-Oblique", 8)
    pdf.drawString(20 * mm, 15 * mm, "Généré automatiquement par LAMSSA — document non fiscal.")
    pdf.showPage()
    pdf.save()
    return path
