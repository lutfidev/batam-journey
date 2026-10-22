import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../map/road_graph.dart';
import 'economy.dart';

/// Bagian motor yang aus dan bisa diservis (desain Workshop, panel kiri).
enum MotorPart {
  mesin('Mesin', 120000),
  ban('Ban', 90000),
  rem('Rem', 60000),
  oli('Oli', 45000);

  const MotorPart(this.label, this.fullServicePrice);

  final String label;

  /// Biaya servis dari 0% ke 100%; servis sebagian dibayar proporsional.
  final int fullServicePrice;
}

/// Statistik motor 0–10 (desain Workshop, panel kanan).
enum MotorStat {
  kecepatan('Kecepatan'),
  akselerasi('Akselerasi'),
  irit('Irit bensin'),
  muatan('Muatan'),
  dayaTahan('Daya tahan');

  const MotorStat(this.label);

  final String label;
}

enum ModCategory {
  mesin('Mesin'),
  ban('Ban'),
  knalpot('Knalpot'),
  box('Box'),
  gaya('Gaya');

  const ModCategory(this.label);

  final String label;
}

/// Satu barang modifikasi. Satu kategori hanya bisa satu barang terpasang.
class MotorMod {
  const MotorMod({
    required this.id,
    required this.category,
    required this.name,
    required this.desc,
    required this.price,
    this.delta = const {},
  });

  final String id;
  final ModCategory category;
  final String name;
  final String desc;
  final int price;
  final Map<MotorStat, int> delta;
}

const motorMods = [
  MotorMod(
    id: 'boreup',
    category: ModCategory.mesin,
    name: 'Bore up ringan',
    desc: 'Lebih kencang, sedikit lebih boros',
    price: 450000,
    delta: {MotorStat.kecepatan: 1, MotorStat.akselerasi: 1, MotorStat.irit: -1},
  ),
  MotorMod(
    id: 'cvt',
    category: ModCategory.mesin,
    name: 'Roller CVT racing',
    desc: 'Tarikan responsif di lampu merah',
    price: 300000,
    delta: {MotorStat.akselerasi: 2, MotorStat.irit: -1},
  ),
  MotorMod(
    id: 'tubeless',
    category: ModCategory.ban,
    name: 'Ban tubeless',
    desc: 'Jarang bocor saat kejadian di jalan',
    price: 280000,
    delta: {MotorStat.dayaTahan: 2},
  ),
  MotorMod(
    id: 'semislick',
    category: ModCategory.ban,
    name: 'Ban semi-slick',
    desc: 'Cengkeram kuat, tapi cepat aus',
    price: 350000,
    delta: {MotorStat.kecepatan: 1, MotorStat.akselerasi: 1, MotorStat.dayaTahan: -1},
  ),
  MotorMod(
    id: 'knalpot_std',
    category: ModCategory.knalpot,
    name: 'Knalpot standar baru',
    desc: 'Lolos razia, sedikit lebih irit',
    price: 180000,
    delta: {MotorStat.irit: 1},
  ),
  MotorMod(
    id: 'knalpot_racing',
    category: ModCategory.knalpot,
    name: 'Knalpot racing',
    desc: 'Kencang tapi rawan ditilang saat razia',
    price: 520000,
    delta: {MotorStat.kecepatan: 1, MotorStat.akselerasi: 1},
  ),
  MotorMod(
    id: 'box45',
    category: ModCategory.box,
    name: 'Box delivery 45 L',
    desc: 'Order antar & makanan dibayar lebih',
    price: 250000,
    delta: {MotorStat.muatan: 3, MotorStat.kecepatan: -1},
  ),
  MotorMod(
    id: 'rak',
    category: ModCategory.box,
    name: 'Rak samping barang',
    desc: 'Muat paket besar, bayaran antar naik',
    price: 200000,
    delta: {MotorStat.muatan: 2},
  ),
  MotorMod(
    id: 'stiker',
    category: ModCategory.gaya,
    name: 'Stiker landmark Batam',
    desc: 'Pelanggan senang, tip semua order +5%',
    price: 50000,
  ),
  MotorMod(
    id: 'led',
    category: ModCategory.gaya,
    name: 'Lampu LED putih',
    desc: 'Lebih awet, jalan malam lebih aman',
    price: 150000,
    delta: {MotorStat.dayaTahan: 1},
  ),
];

/// Kondisi & modifikasi motor. Efeknya dibaca sistem lain lewat getter
/// pengali (kecepatan, akselerasi, rem, bensin, bayaran, peluang bocor).
class Workshop implements JsonState {
  /// Kondisi tiap bagian, 0–100.
  final condition = ValueNotifier<Map<MotorPart, double>>({for (final p in MotorPart.values) p: 100});

  /// Id modifikasi terpasang.
  final installed = ValueNotifier<Set<String>>({});

  static const baseStats = {
    MotorStat.kecepatan: 5,
    MotorStat.akselerasi: 5,
    MotorStat.irit: 7,
    MotorStat.muatan: 3,
    MotorStat.dayaTahan: 6,
  };

  /// Kondisi di bawah ini dianggap rusak (efek negatif & peringatan).
  static const badLevel = 25.0;

  /// Persen aus per km asli untuk tiap bagian (sebelum pengali daya tahan).
  static const wearPerKm = {MotorPart.mesin: 0.6, MotorPart.ban: 1.4, MotorPart.rem: 0.5, MotorPart.oli: 2.5};

  double level(MotorPart p) => condition.value[p] ?? 100;

  List<MotorMod> get mods => [
    for (final m in motorMods)
      if (installed.value.contains(m.id)) m,
  ];

  bool hasMod(String id) => installed.value.contains(id);

  int stat(MotorStat s, {MotorMod? preview}) {
    var v = baseStats[s]!;
    for (final m in mods) {
      if (preview != null && m.category == preview.category) continue;
      v += m.delta[s] ?? 0;
    }
    if (preview != null) v += preview.delta[s] ?? 0;
    return v.clamp(0, 10);
  }

  // ---- Efek ke gameplay ----

  /// Kecepatan maksimal: ±6% per poin, mesin rusak −20%.
  double get speedFactor =>
      (1 + 0.06 * (stat(MotorStat.kecepatan) - 5)) * (level(MotorPart.mesin) < badLevel ? 0.8 : 1);

  double get accelFactor => 1 + 0.1 * (stat(MotorStat.akselerasi) - 5);

  /// Rem aus → jarak pengereman lebih panjang.
  double get brakeFactor => level(MotorPart.rem) < badLevel ? 0.55 : 1;

  /// Pemakaian bensin: −7% per poin irit di atas 7.
  double get fuelFactor => 1 - 0.07 * (stat(MotorStat.irit) - 7);

  /// Bayaran order antar/makanan: +5% per poin muatan di atas 3.
  double get cargoPayFactor => 1 + 0.05 * (stat(MotorStat.muatan) - 3);

  /// Tip semua order (stiker).
  double get tipFactor => hasMod('stiker') ? 1.05 : 1;

  /// Bobot kejadian ban bocor (1 = normal).
  double get flatTireWeight {
    var w = 1.0 + (1 - level(MotorPart.ban) / 100) * 2;
    if (hasMod('tubeless')) w *= 0.3;
    return w;
  }

  /// Peluang mogok saat menerobos banjir.
  double get stallChance => (0.4 + (level(MotorPart.mesin) < badLevel ? 0.3 : 0)).clamp(0, 0.9);

  bool get racingExhaust => hasMod('knalpot_racing');

  // ---- Keausan ----

  /// Aus karena jarak tempuh (satuan dunia). Oli habis → mesin aus 3×.
  void wear(double units, {bool braking = false}) {
    if (units <= 0) return;
    final km = units / worldScale / 1000;
    final dur = 1 - 0.1 * (stat(MotorStat.dayaTahan) - 6);
    final next = Map.of(condition.value);
    for (final p in MotorPart.values) {
      var w = wearPerKm[p]! * km * dur;
      if (p == MotorPart.mesin && level(MotorPart.oli) < badLevel) w *= 3;
      if (p == MotorPart.rem && braking) w *= 4;
      next[p] = math.max(0, next[p]! - w);
    }
    condition.value = next;
  }

  /// Kerusakan langsung (mis. mesin kemasukan air).
  void damage(MotorPart p, double amount) {
    condition.value = {...condition.value, p: math.max(0, level(p) - amount)};
  }

  // ---- Servis & pasang ----

  int servicePrice(MotorPart p) => ((100 - level(p)) / 100 * p.fullServicePrice / 500).round() * 500;

  int get serviceAllPrice => MotorPart.values.fold(0, (s, p) => s + servicePrice(p));

  bool service(MotorPart p, Wallet wallet) {
    final price = servicePrice(p);
    if (price == 0 || !wallet.pay(price)) return false;
    condition.value = {...condition.value, p: 100};
    return true;
  }

  bool serviceAll(Wallet wallet) {
    final price = serviceAllPrice;
    if (price == 0 || !wallet.pay(price)) return false;
    condition.value = {for (final p in MotorPart.values) p: 100};
    return true;
  }

  /// Pasang modifikasi (mengganti barang sekategori).
  bool install(MotorMod m, Wallet wallet) {
    if (hasMod(m.id) || !wallet.pay(m.price)) return false;
    installed.value = {
      for (final id in installed.value)
        if (motorMods.firstWhere((x) => x.id == id).category != m.category) id,
      m.id,
    };
    return true;
  }

  // ---- Simpan ----

  @override
  Map<String, Object> toJson() => {
    'condition': {for (final e in condition.value.entries) e.key.name: e.value},
    'installed': installed.value.toList(),
  };

  @override
  void loadJson(Map<String, dynamic> json) {
    final c = json['condition'];
    if (c is Map) {
      condition.value = {for (final p in MotorPart.values) p: ((c[p.name] as num?) ?? 100).toDouble().clamp(0, 100)};
    }
    final i = json['installed'];
    if (i is List) {
      final known = motorMods.map((m) => m.id).toSet();
      installed.value = {
        for (final id in i)
          if (id is String && known.contains(id)) id,
      };
    }
  }
}
