import 'dart:math' as math;

import 'package:batam_the_journey_begins/game/actors/motorbike.dart';
import 'package:batam_the_journey_begins/game/actors/sprites.dart';
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

  group('pose motor 8 arah', () {
    test('octantOf memetakan heading ke penjuru terdekat', () {
      expect(octantOf(0), 0);
      expect(octantOf(44 * deg), 1);
      expect(octantOf(90 * deg), 2);
      expect(octantOf(180 * deg), 4);
      expect(octantOf(-180 * deg), 4);
      expect(octantOf(-90 * deg), 6);
      expect(octantOf(-30 * deg), 7);
    });

    test('poseFor: kanan apa adanya, kiri dicerminkan', () {
      expect(poseFor(0), (facing: Facing.side, flip: false));
      expect(poseFor(1), (facing: Facing.downSide, flip: false));
      expect(poseFor(2), (facing: Facing.down, flip: false));
      expect(poseFor(3), (facing: Facing.downSide, flip: true));
      expect(poseFor(4), (facing: Facing.side, flip: true));
      expect(poseFor(5), (facing: Facing.upSide, flip: true));
      expect(poseFor(6), (facing: Facing.up, flip: false));
      expect(poseFor(7), (facing: Facing.upSide, flip: false));
    });

    test('histeresis: tidak pindah pose tepat di batas, pindah setelah lewat 5°', () {
      expect(octantWithHysteresis(0, 24 * deg), 0);
      expect(octantWithHysteresis(0, 26 * deg), 0);
      expect(octantWithHysteresis(0, 31 * deg), 1);
      expect(octantWithHysteresis(1, 20 * deg), 1);
      expect(octantWithHysteresis(1, 15 * deg), 0);
    });
  });
}
