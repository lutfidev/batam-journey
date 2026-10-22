import 'dart:io';
import 'dart:math' as math;

import 'package:batam_the_journey_begins/game/map/road_graph.dart';
import 'package:batam_the_journey_begins/game/systems/economy.dart';
import 'package:batam_the_journey_begins/game/systems/gps.dart';
import 'package:batam_the_journey_begins/game/systems/orders.dart';
import 'package:batam_the_journey_begins/game/systems/road_events.dart';
import 'package:batam_the_journey_begins/game/systems/workshop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

MotorMod mod(String id) => motorMods.firstWhere((m) => m.id == id);

void main() {
  late Workshop ws;
  late Wallet wallet;

  setUp(() {
    ws = Workshop();
    wallet = Wallet(2000000);
  });

  double km(double k) => k * 1000 * worldScale;

  group('keausan', () {
    test('oli paling cepat habis; motor baru tidak punya efek negatif', () {
      expect(ws.speedFactor, 1);
      expect(ws.brakeFactor, 1);
      ws.wear(km(10));
      expect(ws.level(MotorPart.oli), lessThan(ws.level(MotorPart.ban)));
      expect(ws.level(MotorPart.ban), lessThan(ws.level(MotorPart.mesin)));
    });

    test('oli habis membuat mesin aus tiga kali lebih cepat', () {
      final a = Workshop()..wear(km(5));
      final b = Workshop()..damage(MotorPart.oli, 100);
      b.wear(km(5));
      expect(100 - b.level(MotorPart.mesin), closeTo((100 - a.level(MotorPart.mesin)) * 3, 1e-9));
    });

    test('mesin & rem rusak menurunkan kecepatan dan pengereman', () {
      ws.damage(MotorPart.mesin, 90);
      ws.damage(MotorPart.rem, 90);
      expect(ws.speedFactor, lessThan(1));
      expect(ws.brakeFactor, lessThan(1));
    });

    test('kondisi tidak pernah di bawah nol', () {
      ws.wear(km(10000));
      for (final p in MotorPart.values) {
        expect(ws.level(p), 0);
      }
    });
  });

  group('servis', () {
    test('harga sebanding kerusakan; motor sehat gratis dan tidak bisa diservis', () {
      expect(ws.serviceAllPrice, 0);
      expect(ws.serviceAll(wallet), isFalse);
      ws.damage(MotorPart.oli, 50);
      expect(ws.servicePrice(MotorPart.oli), closeTo(MotorPart.oli.fullServicePrice / 2, 500));
    });

    test('servis semua memulihkan kondisi dan memotong uang', () {
      ws.wear(km(20));
      final price = ws.serviceAllPrice;
      expect(ws.serviceAll(wallet), isTrue);
      expect(wallet.money.value, 2000000 - price);
      for (final p in MotorPart.values) {
        expect(ws.level(p), 100);
      }
    });

    test('servis gagal bila uang kurang', () {
      ws.damage(MotorPart.mesin, 100);
      final poor = Wallet(100);
      expect(ws.service(MotorPart.mesin, poor), isFalse);
      expect(ws.level(MotorPart.mesin), 0);
    });
  });

  group('modifikasi', () {
    test('pasang mengganti barang sekategori dan mengubah statistik', () {
      expect(ws.install(mod('boreup'), wallet), isTrue);
      expect(ws.stat(MotorStat.kecepatan), 6);
      expect(ws.speedFactor, greaterThan(1));
      expect(ws.fuelFactor, greaterThan(1), reason: 'bore up lebih boros');

      expect(ws.install(mod('cvt'), wallet), isTrue);
      expect(ws.installed.value, {'cvt'});
      expect(ws.stat(MotorStat.kecepatan), 5);
      expect(ws.install(mod('cvt'), wallet), isFalse, reason: 'sudah terpasang');
    });

    test('pratinjau sebelum → sesudah tidak mengubah yang terpasang', () {
      ws.install(mod('boreup'), wallet);
      expect(ws.stat(MotorStat.kecepatan, preview: mod('cvt')), 5);
      expect(ws.installed.value, {'boreup'});
    });

    test('tubeless menurunkan peluang ban bocor; box menaikkan bayaran antar', () {
      ws.damage(MotorPart.ban, 80);
      final before = ws.flatTireWeight;
      ws.install(mod('tubeless'), wallet);
      expect(ws.flatTireWeight, lessThan(before));
      ws.install(mod('box45'), wallet);
      expect(ws.cargoPayFactor, closeTo(1.15, 1e-9));
    });

    test('simpan & muat kembali', () {
      ws.install(mod('stiker'), wallet);
      ws.damage(MotorPart.ban, 30);
      final copy = Workshop()..loadJson(Map<String, dynamic>.from(ws.toJson()));
      expect(copy.installed.value, {'stiker'});
      expect(copy.level(MotorPart.ban), 70);
      expect(copy.tipFactor, 1.05);
    });
  });

  group('efek ke sistem lain', () {
    final graph = RoadGraph.parse(File('assets/data/batam_road_graph.json').readAsStringSync());
    final start = graph.findPoi((p) => p.name == '21 Cinema Nagoya Hill')!.position;

    test('bensin lebih boros dengan bore up', () {
      final tank = FuelTank(liters: 4);
      tank.modFactor = () => ws.fuelFactor;
      ws.install(mod('boreup'), wallet);
      tank.consume(km(6));
      expect(tank.liters.value, lessThan(3.0));
    });

    test('knalpot racing kena denda saat razia, banjir merusak mesin', () {
      final toast = ValueNotifier<String?>(null);
      final gps = Gps(graph, toast: toast);
      final orders = OrderSystem(graph: graph, gps: gps, wallet: wallet, toast: toast, random: math.Random(1));
      orders.refreshOffers(start);
      ws.install(mod('knalpot_racing'), wallet);
      final money = wallet.money.value;
      final ev = RoadEventSystem(
        wallet: wallet,
        stats: PlayerStats(),
        orders: orders,
        restrictMotor: (_, _) {},
        roadName: () => '',
        areaName: () => 'Nagoya',
        ferryName: () => 'Batam Centre',
        workshop: ws,
        random: math.Random(1),
      );
      ev.build(RoadEventKind.razia).choices.first.apply();
      expect(wallet.money.value, money - 50000);

      ws.damage(MotorPart.mesin, 90); // mesin rusak → peluang mogok naik
      expect(ws.stallChance, greaterThan(0.4));
    });
  });
}
