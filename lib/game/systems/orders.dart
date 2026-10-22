import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../map/road_graph.dart';
import 'economy.dart';
import 'gps.dart';

/// Tab di aplikasi OjekKita.
enum OrderTab {
  antar('Antar'),
  makan('Makan'),
  orang('Orang');

  const OrderTab(this.label);

  final String label;
}

class OjekOrder {
  OjekOrder({
    required this.tab,
    required this.kind,
    required this.pickup,
    required this.dropoff,
    required this.tripLength,
    required this.pay,
    this.storyId,
  });

  final OrderTab tab;

  /// Label kecil di kartu: PAKET, MAKANAN, PENUMPANG, …
  final String kind;
  final Destination pickup;
  final Destination dropoff;

  /// Panjang rute jemput → antar (satuan dunia).
  final double tripLength;
  final int pay;

  /// Diisi untuk order cerita dari misi (mis. antar Mak Ijah).
  final String? storyId;

  OjekOrder withPay(int newPay) => OjekOrder(
    tab: tab,
    kind: kind,
    pickup: pickup,
    dropoff: dropoff,
    tripLength: tripLength,
    pay: newPay,
    storyId: storyId,
  );

  String get routeText => '${pickup.title} › ${dropoff.title}';

  /// Kata kerja untuk kartu HUD: "Jemput paket di …", "Antar penumpang ke …".
  String get cargo => switch (kind) {
    'BELANJA' => 'belanjaan',
    'KATERING' => 'pesanan besar',
    _ => _tabCargo,
  };

  String get _tabCargo => switch (tab) {
    OrderTab.antar => kind == 'DOKUMEN' ? 'dokumen' : 'paket',
    OrderTab.makan => kind == 'KOPI' ? 'kopi' : 'makanan',
    OrderTab.orang => 'penumpang',
  };
}

enum OrderStage { toPickup, toDropoff }

class ActiveOrder {
  ActiveOrder(this.order, this.timeLimit) : timeLeft = timeLimit;

  final OjekOrder order;
  final double timeLimit;
  OrderStage stage = OrderStage.toPickup;
  double timeLeft;

  Destination get target => stage == OrderStage.toPickup ? order.pickup : order.dropoff;

  String get headline => stage == OrderStage.toPickup
      ? 'Jemput ${order.cargo} di ${order.pickup.title}'
      : 'Antar ${order.cargo} ke ${order.dropoff.title}';
}

/// Order ojek: penawaran di HP, order aktif, jemput → antar → bayar.
class OrderSystem {
  OrderSystem({required this.graph, required this.gps, required this.wallet, required this.toast, math.Random? random})
    : _rng = random ?? math.Random();

  final RoadGraph graph;
  final Gps gps;
  final Wallet wallet;
  final ValueNotifier<String?> toast;
  final math.Random _rng;

  final offers = ValueNotifier<Map<OrderTab, List<OjekOrder>>>({});
  final active = ValueNotifier<ActiveOrder?>(null);

  /// Detik tersisa order aktif (berubah tiap detik, untuk HUD).
  final secondsLeft = ValueNotifier(0);
  final ordersDone = ValueNotifier(0);

  /// Dipanggil saat progres berubah (untuk simpan).
  VoidCallback? onProgress;

  /// Pengali bayaran per tab (modifikasi box/stiker di bengkel).
  double Function(OrderTab tab) payBonus = (_) => 1;

  /// Dipanggil saat sebuah order selesai dibayar.
  void Function(OjekOrder order)? onCompleted;

  static const reachDistance = 10.0;

  /// Rata-rata kecepatan acuan untuk batas waktu (unit/detik).
  static const _refSpeed = 12.0;

  double _replanCooldown = 0;

  /// Ongkos: Rp 5.000 + Rp 4.000/km, dibulatkan ke Rp 1.000.
  static int payFor(double tripUnits) {
    final km = tripUnits / worldScale / 1000;
    return ((5000 + 4000 * km) / 1000).round() * 1000;
  }

  bool get hasActive => active.value != null;

  // ---- Penawaran ----

  void refreshOffers(Offset near) {
    final first = ordersDone.value == 0;
    offers.value = {
      OrderTab.antar: _generate(OrderTab.antar, near, 3, firstOrder: first),
      OrderTab.makan: _generate(OrderTab.makan, near, 2),
      OrderTab.orang: _generate(OrderTab.orang, near, 2),
    };
  }

  static const _places = {'place_suburb', 'place_neighbourhood', 'place_quarter'};

  List<OjekOrder> _generate(OrderTab tab, Offset near, int count, {bool firstOrder = false}) {
    final bool Function(Poi) pickupOk;
    final List<String> kinds;
    var radius = 500.0;
    var tripMin = 300.0, tripMax = 2400.0;
    switch (tab) {
      case OrderTab.antar:
        pickupOk = (p) => p.type == 'hotel' || p.type == 'marketplace' || _places.contains(p.type);
        kinds = ['PAKET', 'PAKET', 'DOKUMEN'];
      case OrderTab.makan:
        pickupOk = (p) => p.type == 'marketplace' || p.type == 'hotel';
        kinds = ['MAKANAN', 'KOPI'];
        tripMax = 1200;
      case OrderTab.orang:
        pickupOk = (p) =>
            p.type == 'ferry_terminal' || p.type == 'bus_station' || p.type == 'hotel' || p.type == 'hospital';
        kinds = ['PENUMPANG'];
        radius = 900;
        tripMin = 500;
        tripMax = 3200;
    }
    if (firstOrder) {
      // Order pertama: dekat dan pendek, supaya pemain cepat paham alurnya.
      radius = 350;
      tripMin = 200;
      tripMax = 500;
    }

    final named = graph.pois.where((p) => p.name != null && pickupOk(p)).toList();
    // Titik jemput tidak boleh tepat di posisi pemain (minimal ±200 m).
    bool inRange(Poi p) {
      final d = (p.position - near).distance;
      return d > 40 && d < radius;
    }

    var pool = named.where(inRange).toList();
    if (pool.length < count) {
      pool = named.where((p) => (p.position - near).distance > 40).toList()
        ..sort((a, b) => (a.position - near).distanceSquared.compareTo((b.position - near).distanceSquared));
      pool = pool.take(count * 3).toList();
    }
    pool.shuffle(_rng);
    if (firstOrder) {
      pool.sort((a, b) => (a.position - near).distanceSquared.compareTo((b.position - near).distanceSquared));
    }

    final drops = graph.pois.where((p) => p.name != null && _places.contains(p.type)).toList();
    final out = <OjekOrder>[];
    for (final pick in pool) {
      if (out.length >= count) break;
      final candidates = drops.where((d) {
        final dist = (d.position - pick.position).distance;
        return dist >= tripMin && dist <= tripMax && d.name != pick.name;
      }).toList();
      if (candidates.isEmpty) continue;
      final drop = candidates[_rng.nextInt(candidates.length)];
      final order = _make(tab, kinds[_rng.nextInt(kinds.length)], pick, drop);
      if (order != null) out.add(order);
    }
    return out;
  }

  /// Order cerita dari misi: jemput & antar ke tempat tertentu.
  OjekOrder? makeStory({
    required String storyId,
    required String kind,
    required OrderTab tab,
    required Poi pickup,
    required String pickupTitle,
    required Poi dropoff,
    required String dropoffTitle,
    required int pay,
  }) {
    final o = _make(tab, kind, pickup, dropoff);
    if (o == null) return null;
    return OjekOrder(
      tab: tab,
      kind: kind,
      pickup: Destination(title: pickupTitle, subtitle: o.pickup.subtitle, position: o.pickup.position),
      dropoff: Destination(title: dropoffTitle, subtitle: o.dropoff.subtitle, position: o.dropoff.position),
      tripLength: o.tripLength,
      pay: pay,
      storyId: storyId,
    );
  }

  /// Kalikan bayaran penawaran di satu tab (kejadian "peluang").
  void boostTab(OrderTab tab, double factor) {
    final list = offers.value[tab];
    if (list == null) return;
    offers.value = {
      ...offers.value,
      tab: [for (final o in list) o.withPay((o.pay * factor / 1000).round() * 1000)],
    };
  }

  /// Kurangi sisa waktu order aktif (detik). Mengembalikan true bila ada order.
  bool spendTime(double seconds) {
    final a = active.value;
    if (a == null) return false;
    a.timeLeft = math.max(1, a.timeLeft - seconds);
    secondsLeft.value = a.timeLeft.ceil();
    return true;
  }

  OjekOrder? _make(OrderTab tab, String kind, Poi pick, Poi drop) {
    final pf = gps.pathfinder;
    final a = pf.snap(pick.position, maxDist: 400), b = pf.snap(drop.position, maxDist: 400);
    if (a == null || b == null) return null;
    final route = pf.routeBetween(a, b) ?? pf.routeBetween(a, b, respectOneway: false);
    if (route == null || route.length < 50) return null;
    final dropTitle = drop.name!;
    return OjekOrder(
      tab: tab,
      kind: kind,
      pickup: Destination(title: pick.name!, subtitle: graph.nearestPlaceName(pick.position), position: a.point),
      dropoff: Destination(title: dropTitle, subtitle: 'Rumah pelanggan', position: b.point),
      tripLength: route.length,
      pay: (payFor(route.length) * payBonus(tab) / 1000).round() * 1000,
    );
  }

  // ---- Order aktif ----

  /// Ambil order. Gagal bila sudah ada order aktif.
  bool take(OjekOrder order, Offset playerPos) {
    if (hasActive) return false;
    final toPickup = gps.plan(playerPos, order.pickup.position)?.length ?? (order.pickup.position - playerPos).distance;
    final limit = 90 + (toPickup + order.tripLength) / _refSpeed;
    final a = ActiveOrder(order, limit);
    active.value = a;
    secondsLeft.value = limit.ceil();
    final list = offers.value[order.tab];
    if (list != null) {
      offers.value = {
        ...offers.value,
        order.tab: [...list]..remove(order),
      };
    }
    _routeTo(a, playerPos);
    toast.value = 'Order diambil! ${a.headline}';
    return true;
  }

  void cancel({String? reason}) {
    final a = active.value;
    if (a == null) return;
    if (gps.destination?.tag == a) gps.clear();
    active.value = null;
    if (reason != null) toast.value = reason;
  }

  void _routeTo(ActiveOrder a, Offset from) {
    final dest = Destination(title: a.target.title, subtitle: a.target.subtitle, position: a.target.position, tag: a);
    final route = gps.plan(from, dest.position);
    if (route != null) gps.start(dest, route);
  }

  /// Dipasang ke [Gps.onArrive]: sembunyikan pesan "Sampai di …" untuk order.
  bool handleArrive(Destination dest) => dest.tag is ActiveOrder;

  void update(double dt, Offset pos) {
    final a = active.value;
    if (a == null) return;
    a.timeLeft -= dt;
    secondsLeft.value = math.max(0, a.timeLeft.ceil());
    if (a.timeLeft <= 0) {
      cancel(reason: 'Waktu habis, order dibatalkan pelanggan');
      return;
    }

    if ((pos - a.target.position).distance <= reachDistance) {
      if (a.stage == OrderStage.toPickup) {
        a.stage = OrderStage.toDropoff;
        toast.value = a.order.tab == OrderTab.orang ? 'Penumpang naik!' : '${_cap(a.order.cargo)} diambil!';
        if (gps.destination?.tag == a) gps.clear();
        _routeTo(a, pos);
        active.value = null;
        active.value = a; // beri tahu HUD
      } else {
        wallet.earn(a.order.pay);
        ordersDone.value++;
        if (gps.destination?.tag == a) gps.clear();
        active.value = null;
        toast.value = '+${formatRupiah(a.order.pay, prefix: true)} · Order selesai!';
        refreshOffers(pos);
        onCompleted?.call(a.order);
        onProgress?.call();
      }
      return;
    }

    // Rute order hilang (mis. dihapus di peta): pasang lagi.
    _replanCooldown -= dt;
    if (!gps.active && _replanCooldown <= 0) {
      _replanCooldown = 2;
      _routeTo(a, pos);
    }
  }

  static String _cap(String s) => s[0].toUpperCase() + s.substring(1);
}
