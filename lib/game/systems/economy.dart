import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../map/road_graph.dart';

/// "Rp 18.000" / "18.000".
String formatRupiah(int v, {bool prefix = false}) {
  final s = v.abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  if (prefix) b.write('Rp ');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// Dompet pemain.
class Wallet {
  Wallet([int start = 1250000]) : money = ValueNotifier(start);

  final ValueNotifier<int> money;

  bool canPay(int amount) => money.value >= amount;

  bool pay(int amount) {
    if (!canPay(amount)) return false;
    money.value -= amount;
    return true;
  }

  void earn(int amount) => money.value += amount;
}

/// Statistik pemain di luar uang.
class PlayerStats {
  /// Reputasi di mata warga & pelanggan (naik dari menolong, misi).
  final reputation = ValueNotifier(0);

  /// Berapa kali isi bensin (untuk misi bab 1).
  final fuelPurchases = ValueNotifier(0);

  /// Id misi yang sudah selesai.
  final missionsDone = ValueNotifier<Set<String>>({});
}

/// Jenis bensin di layar SPBU.
enum FuelGrade {
  biasa('Biasa', 10000, 'Hemat', 1.0, 1.0),
  plus('Super', 12500, '+5% kecepatan', 1.05, 1.0),
  turbo('Turbo', 14000, '+10% & awet', 1.10, 0.85);

  const FuelGrade(this.label, this.pricePerLiter, this.note, this.speedBonus, this.consumption);

  final String label;
  final int pricePerLiter;
  final String note;
  final double speedBonus;

  /// Pengali pemakaian (Turbo lebih awet).
  final double consumption;
}

/// Tangki motor matic.
class FuelTank {
  FuelTank({this.capacity = 4.0, double liters = 1.4, this.grade = FuelGrade.biasa}) : liters = ValueNotifier(liters);

  final double capacity;
  final ValueNotifier<double> liters;
  FuelGrade grade;

  /// Pengali pemakaian dari modifikasi motor (bengkel).
  double Function() modFactor = () => 1;

  /// Liter per km asli (± 6 km per liter — dunia game dipadatkan).
  static const litersPerKm = 1 / 6;

  /// Di bawah ini muncul peringatan bensin tipis.
  static const lowFraction = 0.15;

  double get fraction => liters.value / capacity;
  bool get isEmpty => liters.value <= 0;
  bool get isLow => fraction < lowFraction;
  double get space => capacity - liters.value;

  /// Kurangi bensin sesuai jarak tempuh (satuan dunia).
  void consume(double units) {
    if (units <= 0 || isEmpty) return;
    final km = units / worldScale / 1000;
    liters.value = math.max(0, liters.value - km * litersPerKm * grade.consumption * modFactor());
  }

  /// Isi [amount] liter (dibatasi kapasitas). Mengembalikan liter yang masuk.
  double fill(double amount, FuelGrade g) {
    final add = amount.clamp(0.0, space);
    if (add > 0) {
      grade = g;
      liters.value += add;
    }
    return add;
  }

  /// Harga untuk [amount] liter, dibulatkan ke Rp 100.
  static int price(double amount, FuelGrade g) => (amount * g.pricePerLiter / 100).round() * 100;
}

/// Sistem yang bisa disimpan sebagai JSON (bengkel, jam, kebutuhan, rumah).
abstract interface class JsonState {
  Map<String, Object> toJson();
  void loadJson(Map<String, dynamic> json);
}

/// Simpanan progres lokal.
class SaveData {
  static const _money = 'money', _fuel = 'fuel', _grade = 'fuelGrade', _orders = 'ordersDone';
  static const _rep = 'reputation', _fuelBuys = 'fuelPurchases', _missions = 'missionsDone';

  static Future<void> load(
    Wallet wallet,
    FuelTank tank,
    ValueNotifier<int> ordersDone,
    PlayerStats stats, {
    Map<String, JsonState> parts = const {},
  }) async {
    final p = await SharedPreferences.getInstance();
    wallet.money.value = p.getInt(_money) ?? wallet.money.value;
    tank.liters.value = p.getDouble(_fuel) ?? tank.liters.value;
    final g = p.getInt(_grade);
    if (g != null && g >= 0 && g < FuelGrade.values.length) tank.grade = FuelGrade.values[g];
    ordersDone.value = p.getInt(_orders) ?? 0;
    stats.reputation.value = p.getInt(_rep) ?? 0;
    stats.fuelPurchases.value = p.getInt(_fuelBuys) ?? 0;
    stats.missionsDone.value = (p.getStringList(_missions) ?? const []).toSet();
    for (final e in parts.entries) {
      final raw = p.getString(e.key);
      if (raw != null) e.value.loadJson(jsonDecode(raw) as Map<String, dynamic>);
    }
  }

  static Future<void> save(
    Wallet wallet,
    FuelTank tank,
    int ordersDone,
    PlayerStats stats, {
    Map<String, JsonState> parts = const {},
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_money, wallet.money.value);
    await p.setDouble(_fuel, tank.liters.value);
    await p.setInt(_grade, tank.grade.index);
    await p.setInt(_orders, ordersDone);
    await p.setInt(_rep, stats.reputation.value);
    await p.setInt(_fuelBuys, stats.fuelPurchases.value);
    await p.setStringList(_missions, stats.missionsDone.value.toList());
    for (final e in parts.entries) {
      await p.setString(e.key, jsonEncode(e.value.toJson()));
    }
  }
}
