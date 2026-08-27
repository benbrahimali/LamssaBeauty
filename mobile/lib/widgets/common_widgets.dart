import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

// ── Gold Primary Button ───────────────────────────────────────────
class GoldButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool enabled;
  final double height;
  final double fontSize;
  final Widget? leading;

  const GoldButton({
    super.key,
    required this.text,
    this.onPressed,
    this.enabled = true,
    this.height = 56,
    this.fontSize = 16,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: enabled ? 1.0 : 0.4,
      duration: const Duration(milliseconds: 200),
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            gradient: enabled
                ? const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [AppColors.gold, Color(0xFF8B6914)],
                  )
                : null,
            color: enabled ? null : AppColors.border,
            borderRadius: BorderRadius.circular(18),
            boxShadow: enabled
                ? [BoxShadow(
                    color: AppColors.gold.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  )]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 8)],
              Text(
                text,
                style: GoogleFonts.dmSans(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w800,
                  color: enabled ? Colors.black : AppColors.sub,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Outlined / Ghost Button ───────────────────────────────────────
class OutlinedGoldButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final double height;

  const OutlinedGoldButton({
    super.key,
    required this.text,
    this.onPressed,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: AppColors.gold.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.4), width: 1.5),
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: GoogleFonts.dmSans(
            fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.gold,
          ),
        ),
      ),
    );
  }
}

// ── Book Together Button ("احجز معا") ─────────────────────────────
class BookTogetherButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final bool enabled;

  const BookTogetherButton({super.key, this.onPressed, this.enabled = true});

  @override
  State<BookTogetherButton> createState() => _BookTogetherButtonState();
}

class _BookTogetherButtonState extends State<BookTogetherButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.enabled ? (_) => _controller.forward() : null,
      onTapUp: widget.enabled ? (_) { _controller.reverse(); widget.onPressed?.call(); } : null,
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedOpacity(
          opacity: widget.enabled ? 1.0 : 0.35,
          duration: const Duration(milliseconds: 200),
          child: Container(
            height: 58,
            decoration: BoxDecoration(
              gradient: widget.enabled
                  ? const LinearGradient(
                      colors: [Color(0xFFC9A84C), Color(0xFF8B6914)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    )
                  : null,
              color: widget.enabled ? null : AppColors.border,
              borderRadius: BorderRadius.circular(18),
              boxShadow: widget.enabled
                  ? [
                      BoxShadow(
                        color: AppColors.gold.withValues(alpha: 0.4),
                        blurRadius: 28,
                        offset: const Offset(0, 8),
                      )
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.group_rounded, size: 18, color: Colors.black),
                ),
                const SizedBox(width: 10),
                Text(
                  'احجز معا 👥',
                  style: GoogleFonts.dmSans(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: widget.enabled ? Colors.black : AppColors.sub,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Disabled Placeholder Button (like screenshots) ────────────────
class DisabledPlaceholderButton extends StatelessWidget {
  final String text;
  final double height;

  const DisabledPlaceholderButton({
    super.key,
    required this.text,
    this.height = 56,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: GoogleFonts.dmSans(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: AppColors.sub,
        ),
      ),
    );
  }
}

// ── Section Header ────────────────────────────────────────────────
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({super.key, required this.title, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: GoogleFonts.playfairDisplay(
          fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text,
        )),
        if (actionLabel != null)
          GestureDetector(
            onTap: onAction,
            child: Row(children: [
              Text(actionLabel!, style: GoogleFonts.dmSans(
                fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.gold,
              )),
              const Icon(Icons.chevron_right, size: 16, color: AppColors.gold),
            ]),
          ),
      ],
    );
  }
}

// ── Gold Avatar ───────────────────────────────────────────────────
class InitialsAvatar extends StatelessWidget {
  final String initials;
  final Color color;
  final double size;
  final bool showBadge;
  final bool available;

  const InitialsAvatar({
    super.key,
    required this.initials,
    required this.color,
    this.size = 50,
    this.showBadge = false,
    this.available = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size, height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color, color.withValues(alpha: 0.6)],
            ),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 12)],
          ),
          alignment: Alignment.center,
          child: Text(
            initials,
            style: GoogleFonts.dmSans(
              fontSize: size * 0.32,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
        ),
        if (showBadge)
          Positioned(
            bottom: 1, right: 1,
            child: Container(
              width: size * 0.26, height: size * 0.26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: available ? AppColors.green : AppColors.red,
                border: Border.all(color: AppColors.bg, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Star Rating ───────────────────────────────────────────────────
class StarRating extends StatelessWidget {
  final double rating;
  final double size;

  const StarRating({super.key, required this.rating, this.size = 14});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: size, color: AppColors.gold),
        const SizedBox(width: 3),
        Text(
          rating.toStringAsFixed(1),
          style: GoogleFonts.dmSans(
            fontSize: size - 1,
            fontWeight: FontWeight.w600,
            color: AppColors.gold,
          ),
        ),
      ],
    );
  }
}

// ── Status Badge ──────────────────────────────────────────────────
class StatusBadge extends StatelessWidget {
  final bool open;

  const StatusBadge({super.key, required this.open});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: (open ? AppColors.green : AppColors.red).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(
          color: (open ? AppColors.green : AppColors.red).withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        open ? '🟢 مفتوح' : '🔴 مغلق',
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: open ? AppColors.green : AppColors.red,
        ),
      ),
    );
  }
}

// ── Filter Pill ───────────────────────────────────────────────────
class FilterPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const FilterPill({super.key, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.gold : AppColors.card,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
            color: active ? AppColors.gold : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? Colors.black : AppColors.sub,
          ),
        ),
      ),
    );
  }
}

// ── KPI Card ──────────────────────────────────────────────────────
class KpiCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final String? change;
  final Color? changeColor;
  final bool gold;

  const KpiCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    this.change,
    this.changeColor,
    this.gold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: gold
            ? LinearGradient(colors: [
                AppColors.gold.withValues(alpha: 0.2),
                const Color(0xFF8B6914).withValues(alpha: 0.1),
              ])
            : null,
        color: gold ? null : AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: gold ? AppColors.gold.withValues(alpha: 0.4) : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(height: 10),
          Text(value, style: GoogleFonts.playfairDisplay(
            fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.text,
          )),
          const SizedBox(height: 4),
          Text(label, style: GoogleFonts.dmSans(
            fontSize: 10, color: AppColors.sub,
            letterSpacing: 1, fontWeight: FontWeight.w500,
          ).copyWith(fontSize: 10)),
          if (change != null) ...[
            const SizedBox(height: 4),
            Text(change!, style: GoogleFonts.dmSans(
              fontSize: 12, color: changeColor ?? AppColors.green,
            )),
          ],
        ],
      ),
    );
  }
}
