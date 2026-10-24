import 'package:flutter/material.dart';

/// Colores de la marca MarLes.
class Marles {
  static const rojo = Color(0xFFD03A3B);
  static const turquesa = Color(0xFF5DC5BE);
  static const turquesaProfundo = Color(0xFF1F7A75);
  static const turquesaPalido = Color(0xFFDFF3F1);
  static const crema = Color(0xFFFFFAF4);
  static const tinta = Color(0xFF1C1A1A);
  static const tintaSuave = Color(0xFF5F5A58);
  static const amarillo = Color(0xFFF3E07A);

  static const lema = 'Somos parte de sus mejores momentos';
}

ThemeData temaMarles() {
  final esquema = ColorScheme.fromSeed(
    seedColor: Marles.rojo,
    primary: Marles.rojo,
    secondary: Marles.turquesaProfundo,
    surface: Marles.crema,
  );
  return ThemeData(
    colorScheme: esquema,
    scaffoldBackgroundColor: Marles.crema,
    appBarTheme: const AppBarTheme(
      backgroundColor: Marles.crema,
      foregroundColor: Marles.tinta,
      elevation: 0,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Marles.rojo,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
    cardTheme: const CardThemeData(color: Colors.white, elevation: 0),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      filled: true,
      fillColor: Colors.white,
    ),
  );
}
