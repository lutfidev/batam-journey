import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../ui/palette.dart';
import 'clock.dart';
import 'economy.dart';
import 'needs.dart';
import 'workshop.dart';

/// Titik yang bisa dipakai di dalam rumah (desain HomeLife).
enum HomeSpot {
  kasur('Kasur'),
  dapur('Dapur'),
  mandi('Kamar mandi'),
  lemari('Lemari'),
  meja('Meja kerja'),
  garasi('Garasi');

  const HomeSpot(this.label);

  final String label;
}

/// Rumah dijual (desain Property). Harga mengikuti desain.
class HouseListing {
  const HouseListing({
    required this.id,
    required this.name,
    required this.area,
    required this.desc,
    required this.price,
    required this.roof,
    required this.tags,
    required this.poiName,
  });

  final String id;
  final String name;
  final String area;
  final String desc;
  final int price;
  final Color roof;
  final List<String> tags;

  /// POI di data peta tempat rumah ini berdiri.
  final String poiName;

  int get downPayment => (price * Housing.downPaymentRate).round();

  /// Cicilan per bulan game (30 hari) untuk sisa harga setelah DP, bunga 10%.
  int get monthly => ((price - downPayment) * 1.1 / Housing.loanMonths / 1000).round() * 1000;
}

const houseListings = [
  HouseListing(
    id: 'subsidi',
    name: 'Rumah Subsidi Tipe 36',
    area: 'Sagulung',
    desc: 'rumah pertama, dekat kawasan pabrik',
    price: 150000000,
    roof: BColors.oranye,
    tags: ['2 kamar', 'Garasi motor', 'Hemat listrik'],
    poiName: 'Sagulung Kota',
  ),
  HouseListing(
    id: 'cluster',
    name: 'Rumah Cluster Tipe 45',
    area: 'Tiban',
    desc: 'perumahan cluster, dekat Sekupang',
    price: 320000000,
    roof: BColors.atapMerah,
    tags: ['2 kamar', 'Carport 1 mobil', 'Taman kecil'],
    poiName: 'Tiban Ciptaland',
  ),
  HouseListing(
    id: 'ruko',
    name: 'Ruko 2 Lantai',
    area: 'Batam Centre',
    desc: 'bisa dijadikan warung atau toko',
    price: 850000000,
    roof: Color(0xFFC2452F),
    tags: ['Bisa buka usaha', 'Lantai atas hunian', 'Ramai pembeli'],
    poiName: 'Tranferpoint Batam Centre',
  ),
  HouseListing(
    id: 'villa',
    name: 'Villa Tepi Laut',
    area: 'Nongsa',
    desc: 'pemandangan laut & Singapura',
    price: 2400000000,
    roof: BColors.tosca,
    tags: ['4 kamar', 'Garasi 2 mobil', 'Dermaga kecil'],
    poiName: 'Nongsa Pura',
  ),
];

class Loan {
  Loan({required this.monthly, required this.monthsLeft, required this.nextDueDay, this.missed = 0});

  final int monthly;
  int monthsLeft;
  int nextDueDay;
  int missed;

  Map<String, Object> toJson() => {'monthly': monthly, 'left': monthsLeft, 'due': nextDueDay, 'missed': missed};

  static Loan fromJson(Map<String, dynamic> j) => Loan(
    monthly: (j['monthly'] as num).toInt(),
    monthsLeft: (j['left'] as num).toInt(),
    nextDueDay: (j['due'] as num).toInt(),
    missed: (j['missed'] as num?)?.toInt() ?? 0,
  );
}

/// Tempat tinggal: kos Bu Ros (sewa bulanan) dan rumah yang dibeli tunai
/// atau dicicil. Tagihan jatuh tempo diproses tiap ganti hari game.
class Housing implements JsonState {
  Housing({required this.wallet, required this.toast});

  final Wallet wallet;
  final ValueNotifier<String?> toast;

  static const kosId = 'kos';
  static const kosRent = 600000;
  static const monthDays = 30;
  static const loanMonths = 24;
  static const downPaymentRate = 0.1;

  /// Hari terlambat bayar kos sebelum kamar diambil Bu Ros.
  static const kosGraceDays = 7;

  final kosRented = ValueNotifier(false);
  int kosPaidUntil = 0;

  /// Id rumah milik pemain (tidak termasuk kos).
  final owned = ValueNotifier<Set<String>>({});
  final loans = <String, Loan>{};

  /// Hari terakhir lemari dipakai (mood +5 sekali sehari).
  int _lastWardrobeDay = 0;

  bool get hasHome => kosRented.value || owned.value.isNotEmpty;

  bool isHome(String id) => id == kosId ? kosRented.value : owned.value.contains(id);

  HouseListing? listing(String id) {
    for (final l in houseListings) {
      if (l.id == id) return l;
    }
    return null;
  }

  // ---- Kos ----

  void rentKos(int day) {
    kosRented.value = true;
    kosPaidUntil = day + monthDays;
  }

  /// Bayar sewa sebulan di muka (misi "Bayar kos bulan ini").
  void extendKos() => kosPaidUntil += monthDays;

  // ---- Beli rumah ----

  bool buyCash(HouseListing l) {
    if (owned.value.contains(l.id) || !wallet.pay(l.price)) return false;
    owned.value = {...owned.value, l.id};
    return true;
  }

  bool buyCredit(HouseListing l, int today) {
    if (owned.value.contains(l.id) || !wallet.pay(l.downPayment)) return false;
    owned.value = {...owned.value, l.id};
    loans[l.id] = Loan(monthly: l.monthly, monthsLeft: loanMonths, nextDueDay: today + monthDays);
    return true;
  }

  // ---- Tagihan harian ----

  void onNewDay(int day) {
    if (kosRented.value && day > kosPaidUntil) {
      if (wallet.pay(kosRent)) {
        kosPaidUntil += monthDays;
        toast.value = 'Sewa kos ${formatRupiah(kosRent, prefix: true)} dibayar otomatis';
      } else if (day > kosPaidUntil + kosGraceDays) {
        kosRented.value = false;
        toast.value = 'Sewa kos telat seminggu, kamar diambil Bu Ros';
      } else {
        toast.value = 'Sewa kos telat! Siapkan ${formatRupiah(kosRent, prefix: true)}';
      }
    }
    for (final id in loans.keys.toList()) {
      final loan = loans[id]!;
      if (day < loan.nextDueDay) continue;
      final name = listing(id)?.name ?? 'rumah';
      if (wallet.pay(loan.monthly)) {
        loan.monthsLeft--;
        loan.missed = 0;
        loan.nextDueDay += monthDays;
        if (loan.monthsLeft <= 0) {
          loans.remove(id);
          toast.value = 'Cicilan $name lunas!';
        } else {
          toast.value = 'Cicilan $name ${formatRupiah(loan.monthly, prefix: true)} dibayar';
        }
      } else {
        loan.missed++;
        loan.nextDueDay += monthDays;
        if (loan.missed >= 2) {
          loans.remove(id);
          owned.value = {...owned.value}..remove(id);
          toast.value = '$name disita bank, cicilan menunggak 2 bulan';
        } else {
          toast.value = 'Cicilan $name menunggak! Bulan depan bisa disita';
        }
      }
    }
  }

  // ---- Di dalam rumah ----

  List<HomeSpot> spots(String homeId) =>
      homeId == kosId ? const [HomeSpot.kasur, HomeSpot.dapur, HomeSpot.mandi] : HomeSpot.values;

  /// Tidur di kos kurang nyenyak dibanding rumah sendiri.
  double sleepQuality(String homeId) => homeId == kosId ? 0.8 : 1.0;

  static const cookCost = 8000;

  int garageServicePrice(Workshop ws) =>
      ((ws.servicePrice(MotorPart.oli) + ws.servicePrice(MotorPart.ban)) / 2 / 500).round() * 500;

  /// Pakai titik [spot]. Mengembalikan teks hasil, atau null bila tidak bisa.
  String? use(
    HomeSpot spot,
    String homeId, {
    required Needs needs,
    required GameClock clock,
    required Workshop workshop,
  }) {
    switch (spot) {
      case HomeSpot.kasur:
        final q = sleepQuality(homeId);
        final hours = clock.sleepUntil(6);
        needs.passNight(hours);
        needs.sleep(quality: q);
        return 'Selamat pagi! ${clock.weekday}, hari ke-${clock.day.value}. Energi ${(q * 100).round()}%.';
      case HomeSpot.dapur:
        if (!wallet.pay(cookCost)) return null;
        needs.eat(60);
        return 'Nasi goreng buatan sendiri. Kenyang dan hemat!';
      case HomeSpot.mandi:
        needs.bathe();
        return 'Badan segar. Pelanggan suka driver yang wangi: tip +5% selama 6 jam.';
      case HomeSpot.lemari:
        if (_lastWardrobeDay == clock.day.value) return null;
        _lastWardrobeDay = clock.day.value;
        needs.cheer(5);
        return 'Ganti jaket ojek yang bersih. Mood +5.';
      case HomeSpot.meja:
        return null;
      case HomeSpot.garasi:
        final price = garageServicePrice(workshop);
        if (price == 0 || !wallet.pay(price)) return null;
        workshop.condition.value = {
          ...workshop.condition.value,
          MotorPart.oli: 100,
          MotorPart.ban: math.max(workshop.level(MotorPart.ban), 100),
        };
        return 'Oli diganti dan angin ban diisi sendiri. Hemat setengah harga bengkel.';
    }
  }

  bool canUse(HomeSpot spot, {required GameClock clock, required Workshop workshop}) => switch (spot) {
    HomeSpot.dapur => wallet.canPay(cookCost),
    HomeSpot.lemari => _lastWardrobeDay != clock.day.value,
    HomeSpot.meja => false,
    HomeSpot.garasi => garageServicePrice(workshop) > 0 && wallet.canPay(garageServicePrice(workshop)),
    _ => true,
  };

  // ---- Simpan ----

  @override
  Map<String, Object> toJson() => {
    'kos': kosRented.value,
    'kosUntil': kosPaidUntil,
    'owned': owned.value.toList(),
    'loans': {for (final e in loans.entries) e.key: e.value.toJson()},
    'wardrobe': _lastWardrobeDay,
  };

  @override
  void loadJson(Map<String, dynamic> j) {
    kosRented.value = j['kos'] == true;
    kosPaidUntil = (j['kosUntil'] as num?)?.toInt() ?? 0;
    final known = houseListings.map((l) => l.id).toSet();
    owned.value = {
      for (final id in (j['owned'] as List? ?? const []))
        if (id is String && known.contains(id)) id,
    };
    loans.clear();
    final l = j['loans'];
    if (l is Map) {
      for (final e in l.entries) {
        if (owned.value.contains(e.key)) {
          loans[e.key as String] = Loan.fromJson(Map<String, dynamic>.from(e.value as Map));
        }
      }
    }
    _lastWardrobeDay = (j['wardrobe'] as num?)?.toInt() ?? 0;
  }
}
