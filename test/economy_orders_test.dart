import 'dart:io';
import 'dart:math' as math;

import 'package:batam_the_journey_begins/game/map/road_graph.dart';
import 'package:batam_the_journey_begins/game/systems/economy.dart';
import 'package:batam_the_journey_begins/game/systems/gps.dart';
import 'package:batam_the_journey_begins/game/systems/orders.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ekonomi', () {
    test('format rupiah', () {
      expect(formatRupiah(1250000), '1.250.000');
      expect(formatRupiah(18000, prefix: true), 'Rp 18.000');
      expect(formatRupiah(500), '500');
    });

    test('dompet tidak bisa minus', () {
      final w = Wallet(10000);
      expect(w.pay(15000), isFalse);
      expect(w.money.value, 10000);
      expect(w.pay(4000), isTrue);
      w.earn(1000);
      expect(w.money.value, 7000);
    });

    test('bensin habis sesuai jarak; turbo lebih awet', () {
      final biasa = FuelTank(liters: 4);
      final turbo = FuelTank(liters: 4, grade: FuelGrade.turbo);
      final sixKm = 6000 * worldScale;
      biasa.consume(sixKm);
      turbo.consume(sixKm);
      expect(biasa.liters.value, closeTo(3.0, 1e-9));
      expect(turbo.liters.value, greaterThan(biasa.liters.value));
      biasa.consume(1e9);
      expect(biasa.isEmpty, isTrue);
      expect(biasa.liters.value, 0);
    });

    test('isi bensin dibatasi kapasitas, harga dibulatkan', () {
      final t = FuelTank(liters: 3.5);
      expect(t.fill(2, FuelGrade.plus), closeTo(0.5, 1e-9));
      expect(t.liters.value, closeTo(4, 1e-9));
      expect(t.grade, FuelGrade.plus);
      expect(FuelTank.price(2.6, FuelGrade.biasa), 26000);
      expect(FuelTank.price(1.234, FuelGrade.plus), 15400);
    });
  });

  group('order ojek', () {
    final graph = RoadGraph.parse(File('assets/data/batam_road_graph.json').readAsStringSync());
    final start = graph.findPoi((p) => p.name == '21 Cinema Nagoya Hill')!.position;

    OrderSystem make() {
      final toast = ValueNotifier<String?>(null);
      final gps = Gps(graph, toast: toast);
      final sys = OrderSystem(graph: graph, gps: gps, wallet: Wallet(0), toast: toast, random: math.Random(7));
      gps.onArrive = sys.handleArrive;
      return sys;
    }

    test('ongkos naik sesuai jarak', () {
      expect(OrderSystem.payFor(0), 5000);
      expect(OrderSystem.payFor(3200 * worldScale), 18000);
    });

    test('penawaran tersedia di semua tab dan order pertama pendek', () {
      final sys = make()..refreshOffers(start);
      for (final tab in OrderTab.values) {
        expect(sys.offers.value[tab], isNotEmpty, reason: tab.label);
      }
      final first = sys.offers.value[OrderTab.antar]!.first;
      expect(first.tripLength, lessThan(1400));
      final d = (first.pickup.position - start).distance;
      expect(d, greaterThan(30));
      expect(d, lessThan(500));
    });

    test('alur jemput → antar → dibayar', () {
      final sys = make()..refreshOffers(start);
      final order = sys.offers.value[OrderTab.antar]!.first;
      expect(sys.take(order, start), isTrue);
      expect(sys.take(order, start), isFalse, reason: 'hanya satu order aktif');
      expect(sys.gps.active, isTrue);
      expect(sys.offers.value[OrderTab.antar], isNot(contains(order)));

      sys.update(1, order.pickup.position);
      expect(sys.active.value!.stage, OrderStage.toDropoff);
      expect(sys.gps.destination!.position, order.dropoff.position);

      sys.update(1, order.dropoff.position);
      expect(sys.active.value, isNull);
      expect(sys.wallet.money.value, order.pay);
      expect(sys.ordersDone.value, 1);
      expect(sys.toast.value, contains('Order selesai'));
    });

    test('waktu habis membatalkan order', () {
      final sys = make()..refreshOffers(start);
      final order = sys.offers.value[OrderTab.orang]!.first;
      sys.take(order, start);
      sys.update(sys.active.value!.timeLimit + 1, start);
      expect(sys.active.value, isNull);
      expect(sys.gps.active, isFalse);
      expect(sys.wallet.money.value, 0);
    });
  });
}
