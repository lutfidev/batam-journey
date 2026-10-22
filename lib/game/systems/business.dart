import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'economy.dart';

/// Upgrade usaha (desain Business, kartu "UPGRADE").
enum UpgradeKind { kapasitas, promo, staf }

class BizUpgrade {
  const BizUpgrade(this.kind, this.name, this.effect, this.price);

  final UpgradeKind kind;
  final String name;
  final String effect;
  final int price;
}

/// Jenis usaha. Modal & untung mengikuti skala harga desain.
class BizType {
  const BizType({
    required this.id,
    required this.name,
    required this.area,
    required this.poiName,
    required this.desc,
    required this.capital,
    required this.revenue,
    required this.dailyCost,
    required this.stock,
    required this.restockPrice,
    required this.upgrades,
    required this.cateringText,
    this.requiredReputation = 0,
    this.locked = false,
  });

  final String id;
  final String name;
  final String area;

  /// POI tempat usaha berdiri.
  final String poiName;
  final String desc;

  /// Modal buka usaha (sewa tempat + alat).
  final int capital;

  /// Pendapatan kotor per hari bila stok cukup, sebelum upgrade.
  final int revenue;

  /// Biaya operasional per hari (listrik, sewa, gaji dasar).
  final int dailyCost;

  /// Bahan & pemakaian per hari (persen).
  final Map<String, double> stock;

  /// Harga isi ulang semua bahan dari kosong ke penuh lewat supplier.
  final int restockPrice;
  final List<BizUpgrade> upgrades;

  /// Pesanan besar: (judul, tujuan POI).
  final (String, String) cateringText;
  final int requiredReputation;

  /// Belum bisa dibuka sama sekali (butuh sistem yang belum ada).
  final bool locked;

  int get estimatedProfit => revenue - dailyCost;
}

const bizTypes = [
  BizType(
    id: 'kopi',
    name: 'Kedai Kopi',
    area: 'Batam Centre',
    poiName: 'Batam Centre',
    desc: 'Kopi susu gula aren untuk karyawan kantor dan penumpang ferry. Ramai pagi dan sore.',
    capital: 10000000,
    revenue: 320000,
    dailyCost: 60000,
    stock: {'Biji kopi': 15, 'Susu': 25, 'Gula aren': 18},
    restockPrice: 300000,
    upgrades: [
      BizUpgrade(UpgradeKind.kapasitas, 'Tambah 4 meja', 'Pelanggan +30%', 2000000),
      BizUpgrade(UpgradeKind.promo, 'Promosi di medsos', 'Ramai 3 hari (+50%)', 300000),
      BizUpgrade(UpgradeKind.staf, 'Rekrut barista ke-2', 'Buka sampai malam (+40%), gaji Rp 50rb/hari', 500000),
    ],
    cateringText: ('Katering 50 cup kopi ke pabrik Muka Kuning', 'Muka Kuning'),
  ),
  BizType(
    id: 'warung',
    name: 'Warung Makan',
    area: 'Muka Kuning',
    poiName: 'Muka Kuning',
    desc: 'Ribuan karyawan pabrik butuh makan siang murah. Ramai jam 12 dan saat pergantian shift.',
    capital: 15000000,
    revenue: 380000,
    dailyCost: 130000,
    stock: {'Beras': 20, 'Lauk': 30, 'Sayur': 25},
    restockPrice: 400000,
    upgrades: [
      BizUpgrade(UpgradeKind.kapasitas, 'Tambah kompor & meja', 'Pelanggan +30%', 2500000),
      BizUpgrade(UpgradeKind.promo, 'Paket hemat shift', 'Ramai 3 hari (+50%)', 300000),
      BizUpgrade(UpgradeKind.staf, 'Rekrut juru masak', 'Buka sampai malam (+40%), gaji Rp 50rb/hari', 500000),
    ],
    cateringText: ('Katering 40 nasi kotak ke kantor Batam Centre', 'Tranferpoint Batam Centre'),
  ),
  BizType(
    id: 'laundry',
    name: 'Laundry Kiloan',
    area: 'Bengkong',
    poiName: 'Bengkong Laut',
    desc: 'Antar-jemput cucian pelanggan pakai kendaraanmu sendiri. Pelanggan langganan datang tiap minggu.',
    capital: 25000000,
    revenue: 450000,
    dailyCost: 150000,
    stock: {'Deterjen': 15, 'Pewangi': 20, 'Plastik': 18},
    restockPrice: 350000,
    upgrades: [
      BizUpgrade(UpgradeKind.kapasitas, 'Mesin cuci ke-2', 'Pelanggan +30%', 3500000),
      BizUpgrade(UpgradeKind.promo, 'Diskon member', 'Ramai 3 hari (+50%)', 300000),
      BizUpgrade(UpgradeKind.staf, 'Rekrut tukang setrika', 'Buka sampai malam (+40%), gaji Rp 50rb/hari', 500000),
    ],
    cateringText: ('Cucian seprai hotel ke Nagoya', 'Nagoya Plasa'),
  ),
  BizType(
    id: 'kurir',
    name: 'Jasa Kurir',
    area: 'Nagoya',
    poiName: 'Nagoya Plasa',
    desc: 'Rekrut driver lain, kamu jadi bos armada. Order dari seluruh Batam masuk ke usahamu.',
    capital: 0,
    revenue: 0,
    dailyCost: 0,
    stock: {},
    restockPrice: 0,
    upgrades: [],
    cateringText: ('', ''),
    requiredReputation: 30,
    locked: true,
  ),
];

/// Pesanan besar yang ditawarkan usaha (dikerjakan sebagai order cerita).
class BigOrder {
  const BigOrder({required this.title, required this.targetPoi, required this.pay});

  final String title;
  final String targetPoi;
  final int pay;

  Map<String, Object> toJson() => {'title': title, 'target': targetPoi, 'pay': pay};

  static BigOrder fromJson(Map<String, dynamic> j) =>
      BigOrder(title: j['title'] as String, targetPoi: j['target'] as String, pay: (j['pay'] as num).toInt());
}

/// Satu usaha yang dimiliki.
class OwnedBiz {
  OwnedBiz(this.type) : stock = {for (final k in type.stock.keys) k: 100.0};

  final BizType type;
  final Map<String, double> stock;
  final upgrades = <UpgradeKind>{};
  int promoDays = 0;

  /// Untung bersih 7 hari terakhir (paling baru di akhir).
  final history = <int>[];
  BigOrder? bigOrder;

  /// Pecahan permintaan yang bisa dilayani dengan stok sekarang (0–1).
  double get coverage {
    var c = 1.0;
    for (final e in type.stock.entries) {
      c = math.min(c, (stock[e.key] ?? 0) / e.value);
    }
    return c.clamp(0.0, 1.0);
  }

  double get demandFactor =>
      (upgrades.contains(UpgradeKind.kapasitas) ? 1.3 : 1) *
      (upgrades.contains(UpgradeKind.staf) ? 1.4 : 1) *
      (promoDays > 0 ? 1.5 : 1);

  int get dailyCost => type.dailyCost + (upgrades.contains(UpgradeKind.staf) ? 50000 : 0);

  /// Harga isi ulang bahan yang kurang lewat supplier.
  int get restockPrice {
    final missing = type.stock.keys.fold<double>(0, (s, k) => s + (100 - (stock[k] ?? 0)));
    return (type.restockPrice * missing / (100 * type.stock.length) / 1000).round() * 1000;
  }

  int get weekProfit => history.fold(0, (s, v) => s + v);

  Map<String, Object> toJson() => {
    'stock': stock,
    'upgrades': upgrades.map((u) => u.name).toList(),
    'promo': promoDays,
    'history': history,
    if (bigOrder != null) 'big': bigOrder!.toJson(),
  };

  void loadJson(Map<String, dynamic> j) {
    final s = j['stock'];
    if (s is Map) {
      for (final k in type.stock.keys) {
        stock[k] = ((s[k] as num?) ?? 100).toDouble().clamp(0, 100);
      }
    }
    upgrades
      ..clear()
      ..addAll([
        for (final n in (j['upgrades'] as List? ?? const []))
          for (final u in UpgradeKind.values)
            if (u.name == n) u,
      ]);
    promoDays = (j['promo'] as num?)?.toInt() ?? 0;
    history
      ..clear()
      ..addAll([for (final v in (j['history'] as List? ?? const [])) (v as num).toInt()]);
    final b = j['big'];
    bigOrder = b is Map ? BigOrder.fromJson(Map<String, dynamic>.from(b)) : null;
  }
}

/// Usaha milik pemain: untung harian, stok, upgrade, pesanan besar.
class BusinessSystem implements JsonState {
  BusinessSystem({required this.wallet, required this.stats, required this.toast, math.Random? random})
    : _rng = random ?? math.Random();

  final Wallet wallet;
  final PlayerStats stats;
  final ValueNotifier<String?> toast;
  final math.Random _rng;

  final owned = ValueNotifier<Map<String, OwnedBiz>>({});

  /// Belanja sendiri lebih murah 30% dari harga supplier.
  static const selfShopDiscount = 0.7;

  BizType type(String id) => bizTypes.firstWhere((b) => b.id == id);
  OwnedBiz? get(String id) => owned.value[id];
  bool owns(String id) => owned.value.containsKey(id);

  void _notify() => owned.value = {...owned.value};

  bool canOpen(BizType t) =>
      !t.locked && !owns(t.id) && stats.reputation.value >= t.requiredReputation && wallet.canPay(t.capital);

  bool open(BizType t) {
    if (!canOpen(t) || !wallet.pay(t.capital)) return false;
    owned.value = {...owned.value, t.id: OwnedBiz(t)};
    return true;
  }

  // ---- Harian ----

  /// Tutup buku sehari: jual, pakai stok, bayar operasional, setor untung.
  /// Juga kadang menawarkan pesanan besar.
  void onNewDay() {
    if (owned.value.isEmpty) return;
    var total = 0;
    final empty = <String>[];
    for (final b in owned.value.values) {
      final cover = b.coverage;
      for (final e in b.type.stock.entries) {
        b.stock[e.key] = math.max(0, (b.stock[e.key] ?? 0) - e.value * cover * b.demandFactor.clamp(1, 2));
      }
      final profit = (b.type.revenue * b.demandFactor * cover).round() - b.dailyCost;
      b.history.add(profit);
      while (b.history.length > 7) {
        b.history.removeAt(0);
      }
      if (b.promoDays > 0) b.promoDays--;
      total += profit;
      if (b.coverage < 0.3) empty.add(b.type.name);
      if (b.bigOrder == null && _rng.nextDouble() < 0.5) {
        b.bigOrder = BigOrder(
          title: b.type.cateringText.$1,
          targetPoi: b.type.cateringText.$2,
          pay: 300000 + _rng.nextInt(4) * 50000,
        );
      }
    }
    if (total >= 0) {
      wallet.earn(total);
    } else {
      wallet.pay(math.min(-total, wallet.money.value));
    }
    toast.value = empty.isNotEmpty
        ? 'Stok ${empty.join(', ')} hampir habis! Untung kemarin ${formatRupiah(total, prefix: true)}'
        : 'Usahamu untung ${formatRupiah(total, prefix: true)} kemarin';
    _notify();
  }

  // ---- Stok ----

  bool restockSupplier(String id) {
    final b = get(id);
    if (b == null) return false;
    final price = b.restockPrice;
    if (price == 0 || !wallet.pay(price)) return false;
    for (final k in b.type.stock.keys) {
      b.stock[k] = 100;
    }
    _notify();
    return true;
  }

  int selfShopPrice(String id) => ((get(id)?.restockPrice ?? 0) * selfShopDiscount / 1000).round() * 1000;

  /// Bayar belanja sendiri di muka (bahan dibawa lewat order ojek).
  bool paySelfShop(String id) {
    final price = selfShopPrice(id);
    return price > 0 && wallet.pay(price);
  }

  /// Belanjaan sampai di usaha.
  void deliverShopping(String id) {
    final b = get(id);
    if (b == null) return;
    for (final k in b.type.stock.keys) {
      b.stock[k] = 100;
    }
    _notify();
  }

  // ---- Upgrade ----

  bool hasUpgrade(String id, UpgradeKind k) => get(id)?.upgrades.contains(k) ?? false;

  bool buyUpgrade(String id, BizUpgrade u) {
    final b = get(id);
    if (b == null) return false;
    if (u.kind != UpgradeKind.promo && b.upgrades.contains(u.kind)) return false;
    if (u.kind == UpgradeKind.promo && b.promoDays > 0) return false;
    if (!wallet.pay(u.price)) return false;
    if (u.kind == UpgradeKind.promo) {
      b.promoDays = 3;
    } else {
      b.upgrades.add(u.kind);
    }
    _notify();
    return true;
  }

  // ---- Pesanan besar ----

  /// Terima pesanan besar: memakai 25% bahan pertama. Mengembalikan pesanan.
  BigOrder? acceptBigOrder(String id) {
    final b = get(id);
    final o = b?.bigOrder;
    if (b == null || o == null) return null;
    final first = b.type.stock.keys.first;
    if ((b.stock[first] ?? 0) < 25) return null;
    b.stock[first] = b.stock[first]! - 25;
    b.bigOrder = null;
    _notify();
    return o;
  }

  // ---- Simpan ----

  @override
  Map<String, Object> toJson() => {for (final e in owned.value.entries) e.key: e.value.toJson()};

  @override
  void loadJson(Map<String, dynamic> json) {
    owned.value = {
      for (final e in json.entries)
        if (bizTypes.any((t) => t.id == e.key && !t.locked))
          e.key: OwnedBiz(type(e.key))..loadJson(Map<String, dynamic>.from(e.value as Map)),
    };
  }
}
