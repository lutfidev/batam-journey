import 'dart:math' as math;
import 'dart:ui';

import '../../ui/palette.dart';
import 'economy.dart';
import 'orders.dart';
import 'story.dart';
import 'workshop.dart';

enum RoadEventKind { banBocor, razia, hujan, kecelakaan, peluang }

/// Kejadian acak saat berkendara (desain RoadEvents). Semua efek pilihan
/// memakai sistem yang sudah ada: uang, waktu order, kecepatan motor,
/// bonus order, dan reputasi.
class RoadEventSystem {
  RoadEventSystem({
    required this.wallet,
    required this.stats,
    required this.orders,
    required this.restrictMotor,
    required this.roadName,
    required this.areaName,
    required this.ferryName,
    this.workshop,
    math.Random? random,
  }) : _rng = random ?? math.Random() {
    _nextAt = firstEventAfter;
  }

  final Wallet wallet;
  final PlayerStats stats;
  final OrderSystem orders;

  /// Batasi kecepatan motor: (unit/detik, detik).
  final void Function(double cap, double seconds) restrictMotor;
  final String Function() roadName;
  final String Function() areaName;
  final String Function() ferryName;

  /// Kondisi & modifikasi motor (peluang bocor, mogok, knalpot racing).
  final Workshop? workshop;
  final math.Random _rng;

  /// Detik berkendara (≥ [minSpeedKmh]) sebelum kejadian pertama dan berikutnya.
  static const firstEventAfter = 45.0;
  static const minGap = 70.0, maxGap = 140.0;
  static const minSpeedKmh = 15.0;

  double _ridden = 0;
  late double _nextAt;
  RoadEventKind? _last;

  /// Dipanggil tiap frame. Mengembalikan kejadian bila saatnya muncul.
  StoryEvent? update(double dt, {required bool riding, required double speedKmh}) {
    if (!riding || speedKmh < minSpeedKmh) return null;
    _ridden += dt;
    if (_ridden < _nextAt) return null;
    _ridden = 0;
    _nextAt = minGap + _rng.nextDouble() * (maxGap - minGap);
    final pool = RoadEventKind.values.where((k) => k != _last).toList();
    final kind = _weighted(pool);
    _last = kind;
    return build(kind);
  }

  /// Ban aus → ban bocor lebih sering; ban tubeless → jarang.
  RoadEventKind _weighted(List<RoadEventKind> pool) {
    double w(RoadEventKind k) => k == RoadEventKind.banBocor ? (workshop?.flatTireWeight ?? 1) : 1;
    final total = pool.fold<double>(0, (s, k) => s + w(k));
    var r = _rng.nextDouble() * total;
    for (final k in pool) {
      r -= w(k);
      if (r <= 0) return k;
    }
    return pool.last;
  }

  String _road() {
    final r = roadName();
    return r.isEmpty ? 'jalan ${areaName()}' : r;
  }

  /// Label biaya waktu, hanya bila sedang ada order (waktu tidak berarti tanpa order).
  String _time(int s) => orders.hasActive ? '-$s dtk' : '';

  String _join(List<String> parts) => parts.where((p) => p.isNotEmpty).join(' · ');

  StoryChoice _paid({
    required String label,
    required int price,
    required String extra,
    required String Function() effect,
  }) => StoryChoice(
    label: label,
    cost: _join([formatRupiah(price, prefix: true), extra]),
    enabled: wallet.canPay(price),
    apply: () {
      wallet.pay(price);
      return effect();
    },
  );

  List<(Color, String)> _feed(RoadEventKind except) {
    final all = {
      RoadEventKind.banBocor: (BColors.atapMerah, 'Banyak paku di bahu jalan ${areaName()}'),
      RoadEventKind.razia: (BColors.biruPemain, 'Razia surat kendaraan di sekitar ${areaName()}'),
      RoadEventKind.hujan: (BColors.tosca, 'Hujan lokal bisa bikin jalan tergenang'),
      RoadEventKind.kecelakaan: (BColors.oranye, 'Hati-hati di simpang ramai, banyak yang ngebut'),
      RoadEventKind.peluang: (BColors.hijauAksi, 'Ferry tiba di ${ferryName()}, penumpang butuh ojek'),
    };
    return [
      for (final e in all.entries)
        if (e.key != except) e.value,
    ].take(3).toList();
  }

  StoryEvent build(RoadEventKind kind) {
    final a = orders.active.value;
    final carrying = a == null
        ? ''
        : ' Kamu sedang ${a.stage == OrderStage.toPickup ? 'menuju jemputan' : 'membawa ${a.order.cargo}'}, '
              'sisa waktu ${a.timeLeft ~/ 60} mnt ${(a.timeLeft % 60).floor()} dtk.';
    switch (kind) {
      case RoadEventKind.banBocor:
        return StoryEvent(
          tag: 'BAN BOCOR',
          color: BColors.atapMerah,
          title: 'Ban belakang bocor di ${_road()}!',
          desc: 'Motor tidak bisa dipakai ngebut.$carrying',
          feed: _feed(kind),
          choices: [
            _paid(
              label: 'Dorong ke tukang tambal ban',
              price: 15000,
              extra: 'pelan 20 dtk',
              effect: () {
                restrictMotor(5, 20);
                return 'Ban beres setelah ditambal. Jalan pelan dulu 20 detik.';
              },
            ),
            _paid(
              label: 'Panggil bengkel keliling',
              price: 50000,
              extra: _time(15),
              effect: () {
                orders.spendTime(15);
                return 'Cepat beres! Dompet sedikit tipis.';
              },
            ),
          ],
        );
      case RoadEventKind.razia:
        return StoryEvent(
          tag: 'RAZIA',
          color: BColors.biruPemain,
          title: 'Razia kelengkapan surat di ${_road()}',
          desc: 'Polisi memeriksa SIM dan STNK pengendara yang lewat.$carrying',
          feed: _feed(kind),
          choices: [
            if (workshop?.racingExhaust ?? false)
              StoryChoice(
                label: 'Berhenti dan tunjukkan surat',
                cost: _join([_time(30), 'Denda knalpot Rp 50rb']),
                apply: () {
                  orders.spendTime(30);
                  final fine = math.min(50000, wallet.money.value);
                  wallet.pay(fine);
                  return 'Surat lengkap, tapi knalpot racing kena tilang ${formatRupiah(fine, prefix: true)}.';
                },
              )
            else
              StoryChoice(
                label: 'Berhenti dan tunjukkan surat',
                cost: _join([_time(30), 'Reputasi +1']),
                apply: () {
                  orders.spendTime(30);
                  stats.reputation.value += 1;
                  return 'Surat lengkap, kamu dipersilakan lanjut. Reputasi +1.';
                },
              ),
            StoryChoice(
              label: 'Nekat putar balik',
              cost: 'Risiko tilang Rp 100rb',
              apply: () {
                stats.reputation.value -= 1;
                if (_rng.nextDouble() < 0.5) {
                  final fine = math.min(100000, wallet.money.value);
                  wallet.pay(fine);
                  return 'Ketahuan! Kena tilang ${formatRupiah(fine, prefix: true)}. Reputasi -1.';
                }
                return 'Lolos, tapi jangan diulang. Reputasi -1.';
              },
            ),
          ],
        );
      case RoadEventKind.hujan:
        return StoryEvent(
          tag: 'BANJIR',
          color: BColors.tosca,
          title: 'Hujan deras, ${_road()} tergenang',
          desc: 'Air setinggi betis. Motor bisa mogok kalau nekat lewat.$carrying',
          feed: _feed(kind),
          choices: [
            StoryChoice(
              label: 'Terobos pelan-pelan',
              cost: 'Risiko mogok ${((workshop?.stallChance ?? 0.4) * 100).round()}%',
              apply: () {
                if (_rng.nextDouble() < (workshop?.stallChance ?? 0.4)) {
                  restrictMotor(0, 12);
                  workshop?.damage(MotorPart.mesin, 15);
                  return 'Mesin mogok kemasukan air! Tunggu 12 detik. Mesin perlu dicek di bengkel.';
                }
                restrictMotor(8, 8);
                return 'Berhasil lewat pelan-pelan.';
              },
            ),
            _paid(
              label: 'Neduh di warung kopi',
              price: 8000,
              extra: _join([_time(60), 'Reputasi +1']),
              effect: () {
                orders.spendTime(60);
                stats.reputation.value += 1;
                return 'Hujan reda. Kamu kenalan dengan pemilik warung. Reputasi +1.';
              },
            ),
          ],
        );
      case RoadEventKind.kecelakaan:
        return StoryEvent(
          tag: 'KECELAKAAN',
          color: BColors.oranye,
          title: 'Ada pengendara jatuh di depanmu',
          desc: 'Tidak parah, tapi motornya rusak dan dia minta diantar ke klinik terdekat.$carrying',
          feed: _feed(kind),
          choices: [
            StoryChoice(
              label: 'Antar ke klinik',
              cost: _join([_time(60), 'Reputasi +3']),
              apply: () {
                orders.spendTime(60);
                stats.reputation.value += 3;
                return 'Reputasi +3! Dia ternyata pemilik ruko di ${areaName()}, kontak baru.';
              },
            ),
            StoryChoice(
              label: 'Telepon bantuan lalu lanjut',
              cost: 'Gratis',
              apply: () => 'Bantuan datang. Kamu lanjut jalan.',
            ),
          ],
        );
      case RoadEventKind.peluang:
        return StoryEvent(
          tag: 'PELUANG',
          color: BColors.hijauAksi,
          title: 'Kapal ferry baru tiba di ${ferryName()}',
          desc: 'Puluhan penumpang butuh ojek. Order penumpang di OjekKita dibayar ×2.',
          feed: _feed(kind),
          choices: [
            StoryChoice(
              label: 'Cek order penumpang',
              cost: 'Bonus ×2',
              apply: () {
                orders.boostTab(OrderTab.orang, 2);
                return 'Order penumpang ×2 sudah muncul di HP › OjekKita › Orang.';
              },
            ),
            StoryChoice(label: 'Lewatkan', cost: 'Aman', apply: () => 'Kamu fokus ke rencana sendiri.'),
          ],
        );
    }
  }
}
