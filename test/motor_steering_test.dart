import 'dart:math' as math;

import 'package:batam_the_journey_begins/game/actors/motorbike.dart';
import 'package:batam_the_journey_begins/game/map/road_graph.dart';
import 'package:batam_the_journey_begins/game/model3d/models/motor.dart';
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

const deg = math.pi / 180;

void main() {
  group('steerToward', () {
    test('langsung sampai kalau selisihnya kecil', () {
      expect(steerToward(0, 10 * deg, 20 * deg), closeTo(10 * deg, 1e-9));
    });

    test('dibatasi maxStep', () {
      expect(steerToward(0, 90 * deg, 20 * deg), closeTo(20 * deg, 1e-9));
      expect(steerToward(0, -90 * deg, 20 * deg), closeTo(-20 * deg, 1e-9));
    });

    test('lewat jalan terpendek melintasi ±180°', () {
      // Dari 170° ke -170°: belok 20° ke kanan, bukan 340° ke kiri.
      final h = steerToward(170 * deg, -170 * deg, 5 * deg);
      expect(wrapAngle(h), closeTo(175 * deg, 1e-9));
    });

    test('joystick ke bawah layar membelokkan motor ke bawah, dari arah mana pun', () {
      for (final start in [0.0, 180 * deg, -90 * deg]) {
        var h = start;
        for (var i = 0; i < 100; i++) {
          h = wrapAngle(steerToward(h, math.pi / 2, 5 * deg));
        }
        expect(h, closeTo(math.pi / 2, 1e-9));
      }
    });
  });

  group('gas & rem bertahap', () {
    test('gas naik ke penuh dalam ±0,4 detik, turun cepat saat dilepas', () {
      var t = 0.0;
      for (var i = 0; i < 6; i++) {
        t = approach(t, 1, Motorbike.throttleRise / 60);
      }
      expect(t, closeTo(0.25, 1e-9)); // 0,1 detik: baru seperempat
      for (var i = 0; i < 24; i++) {
        t = approach(t, 1, Motorbike.throttleRise / 60);
      }
      expect(t, 1);
      for (var i = 0; i < 8; i++) {
        t = approach(t, 0, Motorbike.releaseRate / 60);
      }
      expect(t, 0);
    });

    test('tarikan kuat saat pelan, melemah dekat laju puncak', () {
      expect(driveAccel(0, 0, 28), 0);
      expect(driveAccel(1, 0, 28), closeTo(Motorbike.accel * 1.3, 1e-9));
      expect(driveAccel(1, 27, 28), lessThan(driveAccel(1, 5, 28)));
      expect(driveAccel(0.5, 0, 28), closeTo(driveAccel(1, 0, 28) / 2, 1e-9));
    });
  });

  group('miring saat belok', () {
    test('belok kanan = miring kanan, makin cepat makin miring, dibatasi', () {
      expect(leanFor(1, 10), greaterThan(0));
      expect(leanFor(-1, 10), lessThan(0));
      expect(leanFor(1, 20), greaterThan(leanFor(1, 10)));
      expect(leanFor(1, 0), 0);
      expect(leanFor(10, 28), motorMaxLean);
    });
  });

  group('assist lajur', () {
    RoadSegment road({bool oneway = false}) {
      final e = RoadEdge(
        index: 0,
        from: 0,
        to: 1,
        pts: const [Offset(0, 0), Offset(100, 0)],
        type: 'primary',
        name: null,
        oneway: oneway,
        bridge: false,
        width: 10,
      );
      return RoadSegment(const Offset(0, 0), const Offset(100, 0), e, 0, 0);
    }

    test('ke timur di tengah jalan: ditarik ke lajur kiri (utara)', () {
      final l = laneHeading(const Offset(50, 0), 0.1, road());
      expect(l.road, closeTo(0, 1e-9));
      expect(l.lane, lessThan(0));
      expect(l.lane, greaterThanOrEqualTo(-10 * deg - 1e-9));
    });

    test('sudah di tengah lajur kiri: lurus mengikuti jalan', () {
      final l = laneHeading(const Offset(50, -2.5), 0, road());
      expect(l.lane, closeTo(0, 1e-9));
    });

    test('ke barat: arah jalan dibalik dan lajur kirinya di selatan', () {
      final l = laneHeading(const Offset(50, 0), 3.0, road());
      expect(l.road.abs(), closeTo(math.pi, 1e-9));
      expect(math.sin(l.lane), greaterThan(0)); // condong ke +y (selatan)
    });

    test('jalan satu arah: tetap di tengah', () {
      final l = laneHeading(const Offset(50, 0), 0, road(oneway: true));
      expect(l.lane, closeTo(0, 1e-9));
    });

    test('blendAngle lewat jalan terpendek', () {
      expect(blendAngle(170 * deg, -170 * deg, 0.5).abs(), closeTo(math.pi, 1e-9));
      expect(blendAngle(0, 20 * deg, 0.5), closeTo(10 * deg, 1e-9));
    });
  });

  group('kamera melihat ke depan', () {
    test('searah laju, sebanding kecepatan, tidak saat mundur', () {
      final slow = lookAheadOf(0, 10), fast = lookAheadOf(0, 28);
      expect(slow.y, closeTo(0, 1e-9));
      expect(fast.x, greaterThan(slow.x));
      expect(lookAheadOf(math.pi / 2, 20).y, greaterThan(0));
      expect(lookAheadOf(0, -4), Vector2.zero());
    });
  });
}
