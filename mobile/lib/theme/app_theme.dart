import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // ── Core Palette ──────────────────────────────────────────────
  static const Color bg        = Color(0xFF080810);
  static const Color card      = Color(0xFF0F0F1A);
  static const Color card2     = Color(0xFF151525);
  static const Color border    = Color(0xFF1E1E35);
  static const Color text      = Color(0xFFF0EDE8);
  static const Color sub       = Color(0xFF8888AA);

  // ── Accent Colors ─────────────────────────────────────────────
  static const Color gold      = Color(0xFFC9A84C);
  static const Color gold2     = Color(0xFFF4D03F);
  static const Color pink      = Color(0xFFE8A0BF);
  static const Color teal      = Color(0xFF84CFC9);
  static const Color green     = Color(0xFF27AE60);
  static const Color red       = Color(0xFFE74C3C);
  static const Color yellow    = Color(0xFFF4D03F);

  // ── Gradients ─────────────────────────────────────────────────
  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gold, Color(0xFF8B6914)],
  );
  static const LinearGradient bgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bg, Color(0xFF030308)],
  );
}

class AppTheme {
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.gold,
      secondary: AppColors.teal,
      surface: AppColors.card,
      error: AppColors.red,
    ),
    textTheme: GoogleFonts.dmSansTextTheme(ThemeData.dark().textTheme).copyWith(
      displayLarge: GoogleFonts.playfairDisplay(
        fontSize: 48, fontWeight: FontWeight.w900, color: AppColors.text,
      ),
      displayMedium: GoogleFonts.playfairDisplay(
        fontSize: 36, fontWeight: FontWeight.w700, color: AppColors.text,
      ),
      displaySmall: GoogleFonts.playfairDisplay(
        fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.text,
      ),
      headlineLarge: GoogleFonts.playfairDisplay(
        fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.text,
      ),
      headlineMedium: GoogleFonts.playfairDisplay(
        fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text,
      ),
      headlineSmall: GoogleFonts.playfairDisplay(
        fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text,
      ),
      bodyLarge: GoogleFonts.dmSans(
        fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.text,
      ),
      bodyMedium: GoogleFonts.dmSans(
        fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.text,
      ),
      bodySmall: GoogleFonts.dmSans(
        fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.sub,
      ),
      labelLarge: GoogleFonts.dmSans(
        fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.playfairDisplay(
        fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text,
      ),
      iconTheme: const IconThemeData(color: AppColors.text),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      hintStyle: GoogleFonts.dmSans(color: AppColors.sub, fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    dividerColor: AppColors.border,
    cardColor: AppColors.card,
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.transparent,
      selectedItemColor: AppColors.gold,
      unselectedItemColor: AppColors.sub,
    ),
  );
}

// ── Reusable text styles ──────────────────────────────────────────
class AppTextStyle {
  static TextStyle playfair({double size = 20, FontWeight weight = FontWeight.w700, Color color = AppColors.text}) =>
      GoogleFonts.playfairDisplay(fontSize: size, fontWeight: weight, color: color);

  static TextStyle dmSans({double size = 14, FontWeight weight = FontWeight.w400, Color color = AppColors.text}) =>
      GoogleFonts.dmSans(fontSize: size, fontWeight: weight, color: color);
}
