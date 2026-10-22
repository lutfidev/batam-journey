import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'economy.dart';

/// Kebutuhan pemain (desain HomeLife, panel kanan): Energi, Lapar, Mood.
/// Lapar 0 = kenyang, 100 = kelaparan.
class Needs implements JsonState {
  final energy = ValueNotifier(100.0);
  final hunger = ValueNotifier(20.0);
  final mood = ValueNotifier(60.0);

  /// Jam game tersisa efek "segar habis mandi" (tip +5%).
  double freshHours = 0;

  static const lowEnergy = 25.0;
  static const highHunger = 75.0;

  bool get sleepy => energy.value < lowEnergy;
  bool get starving => hunger.value > highHunger;

  /// Jalankan waktu [hours] jam game. Berkendara lebih melelahkan.
  void tick(double hours, {required bool riding}) {
    if (hours <= 0) return;
    energy.value = _clamp(energy.value - hours * (riding ? 6 : 4));
    hunger.value = _clamp(hunger.value + hours * 5);
    final moodRate = (sleepy || starving) ? -5.0 : -1.5;
    mood.value = _clamp(mood.value + hours * moodRate);
    freshHours = math.max(0, freshHours - hours);
  }

  /// Pengali kecepatan motor: ngantuk → −15%.
  double get speedFactor => sleepy ? 0.85 : 1;

  /// Pengali tip semua order: mood 0..100 → −10%..+10%, plus segar +5%.
  double get tipFactor => (1 + (mood.value - 50) / 500) * (freshHours > 0 ? 1.05 : 1);

  /// Waktu tidur [hours] jam: hanya sedikit lapar, energi & mood tidak terkuras.
  void passNight(double hours) {
    hunger.value = _clamp(hunger.value + hours * 1.5);
    freshHours = math.max(0, freshHours - hours);
  }

  void sleep({required double quality}) {
    energy.value = _clamp(100 * quality);
    mood.value = _clamp(mood.value + 10);
  }

  void eat(double amount) {
    hunger.value = _clamp(hunger.value - amount);
    mood.value = _clamp(mood.value + 5);
  }

  void bathe() {
    mood.value = _clamp(mood.value + 15);
    freshHours = 6;
  }

  void cheer(double amount) => mood.value = _clamp(mood.value + amount);

  static double _clamp(double v) => v.clamp(0, 100).toDouble();

  @override
  Map<String, Object> toJson() => {
    'energy': energy.value,
    'hunger': hunger.value,
    'mood': mood.value,
    'fresh': freshHours,
  };

  @override
  void loadJson(Map<String, dynamic> json) {
    double read(String k, double d) => ((json[k] as num?) ?? d).toDouble();
    energy.value = _clamp(read('energy', 100));
    hunger.value = _clamp(read('hunger', 20));
    mood.value = _clamp(read('mood', 60));
    freshHours = math.max(0, read('fresh', 0));
  }
}
