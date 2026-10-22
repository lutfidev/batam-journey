import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../ui/palette.dart';
import '../map/road_graph.dart';
import 'economy.dart';
import 'gps.dart';
import 'orders.dart';
import 'story.dart';

/// Bab "Kisah Hidupmu". Bab 3–5 baru judul (dikunci) sampai sistemnya ada.
class Chapter {
  const Chapter(this.title, this.goal);

  final String title;
  final String goal;
}

const chapters = [
  Chapter('Baru Tiba', 'Kenali Batam, cari kos'),
  Chapter('Cari Nafkah', 'Narik ojek + lamar pabrik'),
  Chapter('Kendaraan Sendiri', 'Lunasi motor & beli matic'),
  Chapter('Rumah Pertama', 'DP rumah di Tiban / Sagulung'),
  Chapter('Juragan Batam', '3 usaha & buka Barelang'),
];

enum MissionGoal { board, buyFuel, orders, visit, pay, storyOrder }

class Mission {
  const Mission({
    required this.id,
    required this.chapter,
    required this.icon,
    required this.color,
    required this.title,
    required this.sub,
    required this.story,
    required this.goal,
    this.rewards = const [],
    this.rewardMoney = 0,
    this.rewardRep = 0,
    this.count = 1,
    this.place,
    this.price = 0,
    this.requires,
    this.storyKind = 'MISI UTAMA',
  });

  final String id;
  final int chapter;
  final String icon;
  final Color color;
  final String title;
  final String sub;
  final String story;
  final MissionGoal goal;
  final List<String> rewards;
  final int rewardMoney;
  final int rewardRep;

  /// Jumlah order untuk [MissionGoal.orders].
  final int count;

  /// Lokasi untuk [MissionGoal.visit] / [MissionGoal.pay].
  final Destination? place;

  /// Biaya untuk [MissionGoal.pay].
  final int price;

  /// Misi yang harus selesai dulu.
  final String? requires;
  final String storyKind;

  String get kindLabel => '$storyKind · BAB $chapter';
}

/// Misi bab 1–2 di atas sistem yang sudah ada (motor, SPBU, OjekKita, GPS).
class MissionSystem {
  MissionSystem({
    required this.graph,
    required this.wallet,
    required this.stats,
    required this.orders,
    required this.gps,
    required this.toast,
  }) {
    missions = _define();
  }

  final RoadGraph graph;
  final Wallet wallet;
  final PlayerStats stats;
  final OrderSystem orders;
  final Gps gps;
  final ValueNotifier<String?> toast;

  late final List<Mission> missions;

  /// Dipanggil saat progres berubah (untuk simpan).
  VoidCallback? onProgress;

  /// Dipanggil saat sebuah misi selesai (mis. kos jadi tempat tinggal).
  void Function(Mission m)? onCompleted;

  static const reachDistance = 12.0;

  /// Misi kunjungan yang dialognya sudah muncul (muncul lagi setelah menjauh).
  final _prompted = <String>{};

  // ---- Definisi ----

  Destination? _place(bool Function(Poi) test, String title, String subtitle) {
    final poi = graph.findPoi(test);
    if (poi == null) return null;
    final snap = gps.pathfinder.snap(poi.position, maxDist: 400);
    if (snap == null) return null;
    return Destination(title: title, subtitle: subtitle, position: snap.point);
  }

  List<Mission> _define() {
    final kos = _place((p) => p.name == 'Bengkong Indah', 'Kos Bu Ros', 'Bengkong Indah');
    final pabrik = _place((p) => p.name == 'Muka Kuning', 'Pos satpam pabrik', 'Kawasan industri Muka Kuning');
    return [
      const Mission(
        id: 'c1_motor',
        chapter: 1,
        icon: 'M',
        color: BColors.biruPemain,
        title: 'Kenalan dengan motormu',
        sub: 'Naik motor matic pinjaman Bang Rizal',
        story: 'Motor ini pinjaman dulu. Rawat baik-baik, dia modal kerjamu di Batam.',
        goal: MissionGoal.board,
        rewards: ['Bab 1 maju'],
      ),
      const Mission(
        id: 'c1_bensin',
        chapter: 1,
        icon: 'B',
        color: BColors.atapMerah,
        title: 'Isi bensin pertama',
        sub: 'Cari SPBU BensinKu terdekat',
        story: 'Tangki tinggal sedikit. Jangan sampai mogok di tengah jalan, dorong motor itu capek!',
        goal: MissionGoal.buyFuel,
        rewards: ['Reputasi +1'],
        rewardRep: 1,
      ),
      const Mission(
        id: 'c1_order',
        chapter: 1,
        icon: 'O',
        color: BColors.hijauAksi,
        title: 'Order pertama OjekKita',
        sub: 'Ambil order lewat HP',
        story: 'Akun OjekKita-mu sudah aktif. Ambil satu order, jemput, antar, dapat uang!',
        goal: MissionGoal.orders,
        rewards: ['Rp 10.000 bonus', 'Reputasi +1'],
        rewardMoney: 10000,
        rewardRep: 1,
      ),
      Mission(
        id: 'c1_kos',
        chapter: 1,
        icon: 'K',
        color: BColors.oranye,
        title: 'Cari kos di Bengkong',
        sub: 'Lihat kamar Bu Ros · Rp 300.000',
        story:
            'Tidur di pos ronda terus tidak enak. Bu Ros punya kamar kosong dekat Nagoya, '
            'sewa pertama Rp 300.000.',
        goal: MissionGoal.pay,
        place: kos,
        price: 300000,
        rewards: ['Tempat tinggal', 'Bab 2 terbuka'],
      ),
      const Mission(
        id: 'c2_order5',
        chapter: 2,
        icon: '5',
        color: BColors.tosca,
        title: 'Selesaikan 5 order',
        sub: 'Narik OjekKita sampai lancar',
        story: 'Pelanggan tetap datang dari ojek yang bisa diandalkan. Selesaikan lima order.',
        goal: MissionGoal.orders,
        count: 5,
        rewards: ['Rp 25.000 bonus', 'Reputasi +2'],
        rewardMoney: 25000,
        rewardRep: 2,
      ),
      const Mission(
        id: 'c2_ijah',
        chapter: 2,
        icon: 'I',
        color: BColors.biruPemain,
        title: 'Antar Mak Ijah ke kapal',
        sub: 'Tiban → Pelabuhan Sekupang',
        story: 'Tetangga kosmu mau pulang kampung. Kalau terlambat, kapalnya berangkat tanpa dia!',
        goal: MissionGoal.storyOrder,
        storyKind: 'MISI CERITA',
        rewards: ['Rp 40.000', 'Reputasi +3'],
        rewardRep: 3,
      ),
      Mission(
        id: 'c2_pabrik',
        chapter: 2,
        icon: 'P',
        color: const Color(0xFF7B5EA7),
        title: 'Lamar kerja di Muka Kuning',
        sub: 'Antar berkas ke pos satpam pabrik',
        story: 'Shift pabrik gajinya tetap. Bawa berkas lamaran ke pos satpam di kawasan industri.',
        goal: MissionGoal.visit,
        place: pabrik,
        rewards: ['Kerja pabrik (segera)', 'Reputasi +2'],
        rewardRep: 2,
      ),
      Mission(
        id: 'c2_kos',
        chapter: 2,
        icon: '!',
        color: BColors.atapMerah,
        title: 'Bayar kos bulan ini',
        sub: 'Rp 600.000 ke Bu Ros · Bengkong',
        story: 'Bu Ros sudah dua kali mengingatkan. Telat bayar = pindah ke kos yang lebih jauh.',
        goal: MissionGoal.pay,
        place: kos,
        price: 600000,
        requires: 'c1_kos',
        rewards: ['Bab 2 selesai', 'Reputasi +2'],
        rewardRep: 2,
      ),
    ];
  }

  // ---- Status ----

  bool isDone(Mission m) => stats.missionsDone.value.contains(m.id);

  bool _chapterDone(int c) => missions.where((m) => m.chapter == c).every(isDone);

  /// Bab berjalan (1-based). 3 = bab 1–2 selesai.
  int get chapter => !_chapterDone(1) ? 1 : (!_chapterDone(2) ? 2 : 3);

  bool isAvailable(Mission m) =>
      !isDone(m) && m.chapter <= chapter && (m.requires == null || stats.missionsDone.value.contains(m.requires));

  List<Mission> get available => missions.where(isAvailable).toList();

  /// Misi yang ditampilkan di HUD.
  Mission? get tracked {
    final list = available;
    return list.isEmpty ? null : list.first;
  }

  String progress(Mission m) => switch (m.goal) {
    MissionGoal.orders => '${orders.ordersDone.value.clamp(0, m.count)} / ${m.count}',
    MissionGoal.storyOrder => orders.active.value?.order.storyId == m.id ? 'Berjalan' : '',
    _ => '',
  };

  // ---- Jalannya misi ----

  /// Dipanggil berkala. Mengembalikan dialog bila tiba di lokasi misi.
  StoryEvent? update(Offset pos, {required bool riding}) {
    for (final m in available) {
      switch (m.goal) {
        case MissionGoal.board:
          if (riding) _complete(m);
        case MissionGoal.buyFuel:
          if (stats.fuelPurchases.value >= 1) _complete(m);
        case MissionGoal.orders:
          if (orders.ordersDone.value >= m.count) _complete(m);
        case MissionGoal.visit:
        case MissionGoal.pay:
          final place = m.place;
          if (place == null) continue;
          final d = (pos - place.position).distance;
          if (d > reachDistance * 3) _prompted.remove(m.id);
          if (d <= reachDistance && _prompted.add(m.id)) return _arrivalDialog(m);
        case MissionGoal.storyOrder:
          break;
      }
    }
    return null;
  }

  StoryEvent _arrivalDialog(Mission m) {
    if (m.goal == MissionGoal.visit) {
      return StoryEvent(
        tag: m.kindLabel,
        color: m.color,
        title: m.title,
        desc: m.id == 'c2_pabrik'
            ? 'Satpam menerima berkasmu: "Lamaran masuk. Nanti dihubungi HRD untuk jadwal shift."'
            : m.story,
        choices: [
          StoryChoice(
            label: 'Serahkan berkas',
            cost: 'Selesai',
            apply: () {
              _complete(m);
              return 'Misi selesai: ${m.title}.';
            },
          ),
        ],
      );
    }
    return StoryEvent(
      tag: m.kindLabel,
      color: m.color,
      title: m.title,
      desc: m.story,
      choices: [
        StoryChoice(
          label: 'Bayar ke Bu Ros',
          cost: formatRupiah(m.price, prefix: true),
          enabled: wallet.canPay(m.price),
          apply: () {
            wallet.pay(m.price);
            _complete(m);
            return m.id == 'c1_kos'
                ? 'Kamar kos sudah jadi milikmu. Akhirnya bisa tidur nyenyak!'
                : 'Lunas! Bu Ros tersenyum lebar.';
          },
        ),
        StoryChoice(
          label: 'Nanti dulu',
          cost: wallet.canPay(m.price) ? '' : 'Uang belum cukup',
          apply: () => 'Kembali lagi kalau sudah siap.',
        ),
      ],
    );
  }

  /// Order cerita (antar Mak Ijah) — dipanggil dari tombol "Mulai".
  bool startStory(Mission m, Offset playerPos) {
    if (m.goal != MissionGoal.storyOrder || orders.hasActive) return false;
    final order = orders.makeStory(
      storyId: m.id,
      kind: 'PENUMPANG',
      tab: OrderTab.orang,
      pickup: graph.findPoi((p) => p.name == 'Tiban Indah')!,
      pickupTitle: 'Kos Mak Ijah',
      dropoff: graph.findPoi((p) => p.name == 'Sekupang Ferry Terminal')!,
      dropoffTitle: 'Pelabuhan Sekupang',
      pay: 40000,
    );
    return order != null && orders.take(order, playerPos);
  }

  /// Dipasang ke [OrderSystem.onCompleted].
  void onOrderCompleted(OjekOrder order) {
    for (final m in available) {
      if (m.goal == MissionGoal.storyOrder && order.storyId == m.id) _complete(m);
    }
  }

  void _complete(Mission m) {
    if (isDone(m)) return;
    final before = chapter;
    stats.missionsDone.value = {...stats.missionsDone.value, m.id};
    if (m.rewardMoney > 0) wallet.earn(m.rewardMoney);
    stats.reputation.value += m.rewardRep;
    final after = chapter;
    if (after > before) {
      toast.value = after <= 2
          ? 'Bab $before selesai! Bab $after: ${chapters[after - 1].title}'
          : 'Bab 2 selesai! Bab 3 segera hadir';
    } else {
      toast.value = 'Misi selesai: ${m.title}';
    }
    onCompleted?.call(m);
    onProgress?.call();
  }
}
