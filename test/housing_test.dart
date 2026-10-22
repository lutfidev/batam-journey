import 'package:batam_the_journey_begins/game/systems/clock.dart';
import 'package:batam_the_journey_begins/game/systems/economy.dart';
import 'package:batam_the_journey_begins/game/systems/housing.dart';
import 'package:batam_the_journey_begins/game/systems/needs.dart';
import 'package:batam_the_journey_begins/game/systems/workshop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

HouseListing house(String id) => houseListings.firstWhere((l) => l.id == id);

void main() {
  group('jam game', () {
    test('1 detik nyata = 1 menit game, berganti hari memanggil onNewDay', () {
      final days = <int>[];
      final c = GameClock(minute: 23 * 60 + 59)..onNewDay = days.add;
      expect(c.text.value, '23:59');
      c.update(2);
      expect(c.text.value, '00:01');
      expect(c.day.value, 2);
      expect(days, [2]);
      expect(c.weekday, 'Selasa');
    });

    test('tidur sampai jam 6 pagi berikutnya', () {
      final c = GameClock(minute: 22 * 60);
      expect(c.sleepUntil(6), 8);
      expect(c.text.value, '06:00');
      expect(c.day.value, 2);
      final early = GameClock(minute: 3 * 60);
      expect(early.sleepUntil(6), 3);
      expect(early.day.value, 1);
    });

    test('simpan & muat', () {
      final c = GameClock(day: 5, minute: 615);
      final copy = GameClock()..loadJson(Map<String, dynamic>.from(c.toJson()));
      expect(copy.day.value, 5);
      expect(copy.text.value, '10:15');
    });
  });

  group('kebutuhan', () {
    test('energi turun lebih cepat saat berkendara; lapar naik', () {
      final a = Needs()..tick(5, riding: true);
      final b = Needs()..tick(5, riding: false);
      expect(a.energy.value, lessThan(b.energy.value));
      expect(a.hunger.value, 45);
    });

    test('ngantuk memperlambat motor; mood mempengaruhi tip', () {
      final n = Needs()..energy.value = 10;
      expect(n.speedFactor, lessThan(1));
      n.mood.value = 100;
      expect(n.tipFactor, closeTo(1.1, 1e-9));
      n.mood.value = 0;
      expect(n.tipFactor, closeTo(0.9, 1e-9));
      n.bathe();
      expect(n.tipFactor, greaterThan(0.9));
    });

    test('nilai selalu 0–100', () {
      final n = Needs()..tick(1000, riding: true);
      expect(n.energy.value, 0);
      expect(n.hunger.value, 100);
      expect(n.mood.value, 0);
    });
  });

  group('rumah', () {
    late Wallet wallet;
    late Housing housing;
    late ValueNotifier<String?> toast;

    setUp(() {
      wallet = Wallet(1000000);
      toast = ValueNotifier(null);
      housing = Housing(wallet: wallet, toast: toast);
    });

    test('harga mengikuti desain; DP 10%, cicilan 24× berbunga 10%', () {
      final s = house('subsidi');
      expect(s.price, 150000000);
      expect(s.downPayment, 15000000);
      expect(s.monthly, 6188000);
    });

    test('tidak bisa beli tanpa uang cukup', () {
      expect(housing.buyCash(house('subsidi')), isFalse);
      expect(housing.buyCredit(house('subsidi'), 1), isFalse);
      expect(housing.owned.value, isEmpty);
      expect(wallet.money.value, 1000000);
    });

    test('sewa kos ditagih otomatis tiap 30 hari; telat seminggu → kamar hilang', () {
      housing.rentKos(1);
      housing.onNewDay(31);
      expect(wallet.money.value, 1000000, reason: 'belum jatuh tempo');
      housing.onNewDay(32);
      expect(wallet.money.value, 400000);
      expect(housing.kosPaidUntil, 61);

      wallet.money.value = 0;
      housing.onNewDay(62);
      expect(housing.kosRented.value, isTrue);
      expect(toast.value, contains('telat'));
      housing.onNewDay(69);
      expect(housing.kosRented.value, isFalse);
    });

    test('cicilan dibayar tiap bulan; menunggak 2 bulan → rumah disita', () {
      wallet.money.value = 100000000;
      expect(housing.buyCredit(house('subsidi'), 1), isTrue);
      expect(wallet.money.value, 100000000 - 15000000);
      housing.onNewDay(31);
      expect(housing.loans['subsidi']!.monthsLeft, 23);

      wallet.money.value = 0;
      housing.onNewDay(61);
      expect(housing.owned.value, contains('subsidi'));
      housing.onNewDay(91);
      expect(housing.owned.value, isEmpty);
      expect(housing.loans, isEmpty);
      expect(toast.value, contains('disita'));
    });

    test('di dalam kos: tidur, masak, mandi; lemari & garasi hanya di rumah sendiri', () {
      final needs = Needs()
        ..energy.value = 10
        ..hunger.value = 90;
      final clock = GameClock(minute: 22 * 60);
      final ws = Workshop();
      expect(housing.spots(Housing.kosId), isNot(contains(HomeSpot.garasi)));

      final moodBefore = needs.mood.value;
      housing.use(HomeSpot.kasur, Housing.kosId, needs: needs, clock: clock, workshop: ws);
      expect(needs.energy.value, 80);
      expect(clock.text.value, '06:00');
      expect(needs.mood.value, greaterThanOrEqualTo(moodBefore), reason: 'tidur tidak boleh menurunkan mood');

      housing.use(HomeSpot.dapur, Housing.kosId, needs: needs, clock: clock, workshop: ws);
      expect(wallet.money.value, 1000000 - Housing.cookCost);
      expect(needs.hunger.value, lessThan(50));

      expect(housing.use(HomeSpot.lemari, 'subsidi', needs: needs, clock: clock, workshop: ws), isNotNull);
      expect(housing.use(HomeSpot.lemari, 'subsidi', needs: needs, clock: clock, workshop: ws), isNull,
          reason: 'sekali sehari');
    });

    test('garasi rumah: ganti oli setengah harga bengkel', () {
      final ws = Workshop()..damage(MotorPart.oli, 80);
      final full = ws.servicePrice(MotorPart.oli);
      final price = housing.garageServicePrice(ws);
      expect(price, closeTo(full / 2, 500));
      housing.use(HomeSpot.garasi, 'subsidi', needs: Needs(), clock: GameClock(), workshop: ws);
      expect(ws.level(MotorPart.oli), 100);
      expect(wallet.money.value, 1000000 - price);
    });

    test('simpan & muat termasuk cicilan', () {
      wallet.money.value = 100000000;
      housing.rentKos(3);
      housing.buyCredit(house('subsidi'), 3);
      final copy = Housing(wallet: wallet, toast: toast)..loadJson(Map<String, dynamic>.from(housing.toJson()));
      expect(copy.kosRented.value, isTrue);
      expect(copy.kosPaidUntil, 33);
      expect(copy.loans['subsidi']!.nextDueDay, 33);
    });
  });
}
