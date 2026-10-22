import 'dart:io';
import 'dart:math' as math;

import 'package:batam_the_journey_begins/game/map/road_graph.dart';
import 'package:batam_the_journey_begins/game/systems/business.dart';
import 'package:batam_the_journey_begins/game/systems/economy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

BizType t(String id) => bizTypes.firstWhere((b) => b.id == id);

void main() {
  late Wallet wallet;
  late PlayerStats stats;
  late BusinessSystem biz;

  setUp(() {
    wallet = Wallet(30000000);
    stats = PlayerStats();
    biz = BusinessSystem(wallet: wallet, stats: stats, toast: ValueNotifier(null), random: math.Random(2));
  });

  test('semua lokasi usaha & tujuan katering ada di peta', () {
    final graph = RoadGraph.parse(File('assets/data/batam_road_graph.json').readAsStringSync());
    for (final b in bizTypes) {
      expect(graph.findPoi((p) => p.name == b.poiName), isNotNull, reason: b.poiName);
      if (!b.locked) {
        expect(graph.findPoi((p) => p.name == b.cateringText.$2), isNotNull, reason: b.cateringText.$2);
      }
    }
  });

  test('buka usaha memotong modal; jasa kurir terkunci', () {
    expect(biz.open(t('warung')), isTrue);
    expect(wallet.money.value, 30000000 - 15000000);
    expect(biz.open(t('warung')), isFalse, reason: 'sudah dimiliki');
    stats.reputation.value = 100;
    expect(biz.canOpen(t('kurir')), isFalse);
  });

  test('modal kurang → tidak bisa buka', () {
    wallet.money.value = 1000000;
    expect(biz.open(t('kopi')), isFalse);
    expect(biz.owned.value, isEmpty);
  });

  test('untung harian masuk dompet dan tercatat 7 hari', () {
    biz.open(t('kopi'));
    final start = wallet.money.value;
    biz.onNewDay();
    final day1 = biz.get('kopi')!.history.single;
    expect(day1, t('kopi').estimatedProfit);
    expect(wallet.money.value, start + day1);
    for (var i = 0; i < 10; i++) {
      biz.onNewDay();
    }
    expect(biz.get('kopi')!.history, hasLength(7));
  });

  test('stok habis → untung turun, bahkan rugi karena biaya tetap jalan', () {
    biz.open(t('kopi'));
    final b = biz.get('kopi')!;
    for (final k in b.stock.keys) {
      b.stock[k] = 0;
    }
    biz.onNewDay();
    expect(b.history.last, -t('kopi').dailyCost);
  });

  test('isi stok: supplier harga penuh, belanja sendiri −30%', () {
    biz.open(t('kopi'));
    final b = biz.get('kopi')!;
    for (final k in b.stock.keys) {
      b.stock[k] = 0;
    }
    expect(b.restockPrice, t('kopi').restockPrice);
    expect(biz.selfShopPrice('kopi'), (t('kopi').restockPrice * 0.7).round());

    final before = wallet.money.value;
    expect(biz.paySelfShop('kopi'), isTrue);
    expect(wallet.money.value, before - biz.selfShopPrice('kopi'));
    expect(b.coverage, 0, reason: 'bahan belum sampai');
    biz.deliverShopping('kopi');
    expect(b.coverage, 1);
  });

  test('upgrade menaikkan untung; promo 3 hari lalu habis', () {
    biz.open(t('kopi'));
    final b = biz.get('kopi')!;
    final meja = t('kopi').upgrades.firstWhere((u) => u.kind == UpgradeKind.kapasitas);
    final promo = t('kopi').upgrades.firstWhere((u) => u.kind == UpgradeKind.promo);
    expect(biz.buyUpgrade('kopi', meja), isTrue);
    expect(biz.buyUpgrade('kopi', meja), isFalse);
    expect(biz.buyUpgrade('kopi', promo), isTrue);
    expect(biz.buyUpgrade('kopi', promo), isFalse, reason: 'promo masih jalan');
    biz.onNewDay();
    expect(b.history.last, greaterThan(t('kopi').estimatedProfit));
    biz.onNewDay();
    biz.onNewDay();
    expect(b.promoDays, 0);
    expect(biz.buyUpgrade('kopi', promo), isTrue, reason: 'promo bisa diulang');
  });

  test('pesanan besar memakai stok; ditolak bila bahan kurang', () {
    biz.open(t('kopi'));
    final b = biz.get('kopi')!..bigOrder = const BigOrder(title: 'x', targetPoi: 'Muka Kuning', pay: 400000);
    final o = biz.acceptBigOrder('kopi');
    expect(o?.pay, 400000);
    expect(b.stock.values.first, 75);
    expect(b.bigOrder, isNull);

    b
      ..bigOrder = const BigOrder(title: 'x', targetPoi: 'Muka Kuning', pay: 400000)
      ..stock[b.stock.keys.first] = 10;
    expect(biz.acceptBigOrder('kopi'), isNull);
  });

  test('simpan & muat', () {
    biz.open(t('laundry'));
    biz.get('laundry')!
      ..upgrades.add(UpgradeKind.staf)
      ..history.addAll([100, 200])
      ..bigOrder = const BigOrder(title: 'a', targetPoi: 'Nagoya Plasa', pay: 350000);
    final copy = BusinessSystem(wallet: wallet, stats: stats, toast: ValueNotifier(null))
      ..loadJson(Map<String, dynamic>.from(biz.toJson()));
    final b = copy.get('laundry')!;
    expect(b.upgrades, {UpgradeKind.staf});
    expect(b.history, [100, 200]);
    expect(b.bigOrder?.pay, 350000);
  });
}
