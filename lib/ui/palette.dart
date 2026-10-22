import 'package:flutter/painting.dart';
import 'package:google_fonts/google_fonts.dart';

/// Token warna dari style guide desain (CLAUDE.md › Warna).
abstract final class BColors {
  static const ink = Color(0xFF2B1D12);
  static const cream = Color(0xFFFFF6E5);
  static const tanah = Color(0xFFF4EAD3);
  static const aspal = Color(0xFF4A5566);
  static const laut = Color(0xFF4FB6CC);
  static const hutan = Color(0xFF86BF7A);
  static const atapMerah = Color(0xFFE4573D);
  static const oranye = Color(0xFFF28C38);
  static const kuning = Color(0xFFF5C451);
  static const hijauAksi = Color(0xFF3E9B5B);
  static const biruPemain = Color(0xFF1D4E89);
  static const industri = Color(0xFFD6C3E6);

  // Warna turunan yang dipakai di layar desain.
  static const trotoar = Color(0xFFD9CBB0);
  static const hutanGelap = Color(0xFF6FAE63);
  static const teksRedup = Color(0xFF5B4632);
  static const bensinTrack = Color(0xFF5B4632);
  static const tosca = Color(0xFF2BA3B8);
}

/// Baloo 2 — judul, angka uang, tombol besar.
TextStyle baloo(double size, {Color color = BColors.ink}) =>
    GoogleFonts.baloo2(fontSize: size, fontWeight: FontWeight.w800, color: color, height: 1.1);

/// Nunito — teks UI.
TextStyle nunito(double size, {Color color = BColors.ink}) =>
    GoogleFonts.nunito(fontSize: size, fontWeight: FontWeight.w800, color: color, height: 1.3);
