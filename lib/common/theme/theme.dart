import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/colors.dart';

class AppTheme {
  static ThemeData getTheme({required bool isPink}) {
    final primaryColor = isPink ? const Color(0xFFEC4899) : const Color(0xFF6366F1);

    return ThemeData(
      brightness: Brightness.light, // Change globally to Light Theme
      scaffoldBackgroundColor: Colors.white,
      fontFamily: GoogleFonts.poppins().fontFamily,
      colorScheme: ColorScheme.light(
        primary: primaryColor,
        secondary: AppColors.secondary,
        surface: Colors.white,
        error: AppColors.error,
      ),
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.blue.shade900,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.blue.shade900),
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.blue.shade900, fontFamily: GoogleFonts.poppins().fontFamily),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue.shade900, fontFamily: GoogleFonts.poppins().fontFamily),
        bodyLarge: TextStyle(fontSize: 16, color: Colors.black87, fontFamily: GoogleFonts.poppins().fontFamily),
        bodyMedium: TextStyle(fontSize: 14, color: Colors.black54, fontFamily: GoogleFonts.poppins().fontFamily),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF1F5F9),
        labelStyle: TextStyle(color: Colors.blueGrey.shade600),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: GoogleFonts.poppins().fontFamily),
        ),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFFF8FAFC),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.black12),
        ),
      ),
    );
  }
}
