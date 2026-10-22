import 'dart:io';
import 'dart:math' as math;

import 'package:batam_the_journey_begins/game/map/road_graph.dart';
import 'package:batam_the_journey_begins/game/systems/economy.dart';
import 'package:batam_the_journey_begins/game/systems/gps.dart';
import 'package:batam_the_journey_begins/game/systems/missions.dart';
import 'package:batam_the_journey_begins/game/systems/orders.dart';
import 'package:batam_the_journey_begins/game/systems/road_events.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final graph = RoadGraph.parse(File('assets/data/batam_road_graph.json').readAsStringSync());
  final start = graph.findPoi((p) => p.name == '21 Cinema Nagoya Hill')!.position;

  late Wallet wallet;
  late PlayerStats stats;
  late OrderSystem orders;
  late Gps gps;
  late ValueNotifier<String?> toast;
  late List<(double, double)> restricts;

  setUp(() {
    toast = ValueNotifier(null);
    wallet = Wallet(1000000);
    stats = PlayerStats();
    gps = Gps(graph, toast: toast);
    orders = OrderSystem(graph: graph, gps: gps, wallet: wallet, toast: toast, random: math.Random(3));
    gps.onArrive = orders.handleArrive;
    orders.refreshOffers(start);
    restricts = [];
  });

  RoadEventSystem events([int seed = 1]) => RoadEventSystem(
        wallet: wallet,
        stats: stats,
        orders: orders,
        restrictMotor: (cap, s) => restricts.add((cap, s)),
        roadName: () => 'Jalan Raja Ali Haji',
        areaName: () => 'Nagoya',
        ferryName: () => 'Batam Centre',
        random: math.Random(seed),
      );

  group('kejadian di jalan', () {
    test('hanya muncul saat berkendara cukup lama dan cukup cepat', () {
      final ev = events();
      expect(ev.update(100, riding: false, speedKmh: 60), isNull);
      expect(ev.update(100, riding: true, speedKmh: 5), isNull);
      expect(ev.update(RoadEventSystem.firstEventAfter - 1, riding: true, speedKmh: 40), isNull);
      expect(ev.update(2, riding: true, speedKmh: 40), isNotNull);
      // Jeda berikutnya minimal minGap.
      expect(ev.update(RoadEventSystem.minGap - 1, riding: true, speedKmh: 40), isNull);
    });

    test('kejadian yang sama tidak muncul dua kali berturut-turut', () {
      final ev = events(9);
      String? last;
      for (var i = 0; i < 20; i++) {
        final e = ev.update(1000, riding: true, speedKmh: 40)!;
        expect(e.tag, isNot(last));
        last = e.tag;
      }
    });

    test('ban bocor: tambal bayar Rp 15rb dan motor dibatasi', () {
      final e = events().build(RoadEventKind.banBocor);
      expect(e.title, contains('Jalan Raja Ali Haji'));
      e.choices.first.apply();
      expect(wallet.money.value, 1000000 - 15000);
      expect(restricts, [(5.0, 20.0)]);
    });

    test('pilihan berbayar mati bila uang kurang', () {
      wallet.money.value = 1000;
      final e = events().build(RoadEventKind.banBocor);
      expect(e.choices.every((c) => !c.enabled), isTrue);
    });

    test('kecelakaan: antar ke klinik memakan waktu order dan menaikkan reputasi', () {
      final order = orders.offers.value[OrderTab.antar]!.first;
      orders.take(order, start);
      final before = orders.active.value!.timeLeft;
      final e = events().build(RoadEventKind.kecelakaan);
      expect(e.choices.first.cost, contains('-60 dtk'));
      e.choices.first.apply();
      expect(orders.active.value!.timeLeft, closeTo(before - 60, 1e-9));
      expect(stats.reputation.value, 3);
    });

    test('tanpa order, biaya waktu tidak ditampilkan', () {
      final e = events().build(RoadEventKind.kecelakaan);
      expect(e.choices.first.cost, isNot(contains('dtk')));
    });

    test('peluang: order penumpang dibayar dua kali lipat', () {
      final before = orders.offers.value[OrderTab.orang]!.map((o) => o.pay).toList();
      events().build(RoadEventKind.peluang).choices.first.apply();
      final after = orders.offers.value[OrderTab.orang]!.map((o) => o.pay).toList();
      for (var i = 0; i < before.length; i++) {
        expect(after[i], closeTo(before[i] * 2, 500));
      }
    });
  });

  group('misi bab 1–2', () {
    MissionSystem missions() {
      final m = MissionSystem(graph: graph, wallet: wallet, stats: stats, orders: orders, gps: gps, toast: toast);
      orders.onCompleted = m.onOrderCompleted;
      return m;
    }

    test('semua lokasi misi ditemukan di peta', () {
      final m = missions();
      for (final mission in m.missions) {
        if (mission.goal == MissionGoal.visit || mission.goal == MissionGoal.pay) {
          expect(mission.place, isNotNull, reason: mission.id);
        }
      }
    });

    test('bab 1: naik motor, isi bensin, order, sewa kos → bab 2 terbuka', () {
      final m = missions();
      expect(m.chapter, 1);
      expect(m.available.every((x) => x.chapter == 1), isTrue);

      m.update(start, riding: true);
      stats.fuelPurchases.value = 1;
      m.update(start, riding: false);
      orders.ordersDone.value = 1;
      m.update(start, riding: false);
      expect(stats.missionsDone.value, containsAll(['c1_motor', 'c1_bensin', 'c1_order']));
      expect(wallet.money.value, 1000000 + 10000);

      final kos = m.missions.firstWhere((x) => x.id == 'c1_kos');
      final dialog = m.update(kos.place!.position, riding: false)!;
      expect(m.update(kos.place!.position, riding: false), isNull, reason: 'dialog tidak muncul berulang');
      dialog.choices.first.apply();
      expect(wallet.money.value, 1000000 + 10000 - 300000);
      expect(m.chapter, 2);
      expect(toast.value, contains('Bab 2'));
      expect(m.available.map((x) => x.id), contains('c2_kos'));
    });

    test('bayar kos ditolak bila uang kurang', () {
      final m = missions();
      wallet.money.value = 100;
      final kos = m.missions.firstWhere((x) => x.id == 'c1_kos');
      final dialog = m.update(kos.place!.position, riding: false)!;
      expect(dialog.choices.first.enabled, isFalse);
      dialog.choices.last.apply();
      expect(m.isDone(kos), isFalse);
    });

    test('order cerita Mak Ijah selesai → misi selesai', () {
      final m = missions();
      stats.missionsDone.value = {for (final x in m.missions.where((x) => x.chapter == 1)) x.id};
      final ijah = m.missions.firstWhere((x) => x.id == 'c2_ijah');
      expect(m.startStory(ijah, start), isTrue);
      final a = orders.active.value!;
      expect(a.order.storyId, 'c2_ijah');
      expect(a.order.dropoff.title, 'Pelabuhan Sekupang');
      orders.update(1, a.order.pickup.position);
      orders.update(1, a.order.dropoff.position);
      expect(m.isDone(ijah), isTrue);
      expect(stats.reputation.value, 3);
    });
  });
}
