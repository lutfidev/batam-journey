import 'dart:math' as math;
import 'dart:ui';

import 'package:batam_the_journey_begins/game/iso.dart';
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('proyeksi iso 2:1', () {
    test('rumus layar = (x − y, (x + y) / 2)', () {
      expect(isoOf(const Offset(10, 0)), const Offset(10, 5));
      expect(isoOf(const Offset(0, 10)), const Offset(-10, 5));
      expect(isoOf(const Offset(4, 4)), const Offset(0, 4));
    });

    test('groundOf membalik isoOf', () {
      for (final g in const [Offset(0, 0), Offset(123.5, -7), Offset(-40, 900)]) {
        final back = groundOf(isoOf(g));
        expect(back.dx, closeTo(g.dx, 1e-9));
        expect(back.dy, closeTo(g.dy, 1e-9));
      }
    });

    test('isoMatrix sama dengan isoOf', () {
      const g = Offset(17, -3);
      final m = isoMatrix;
      final x = m[0] * g.dx + m[4] * g.dy + m[12];
      final y = m[1] * g.dx + m[5] * g.dy + m[13];
      expect(Offset(x, y), isoOf(g));
    });

    test('groundRectOf memuat semua titik tanah yang terlihat di layar', () {
      const screen = Rect.fromLTWH(-30, -15, 60, 30);
      final ground = groundRectOf(screen);
      for (final s in [screen.topLeft, screen.bottomRight, screen.center, screen.centerLeft]) {
        expect(ground.inflate(1e-9).contains(groundOf(s)), isTrue);
      }
    });

    test('kedalaman: makin ke tenggara makin di depan', () {
      expect(isoDepth(Vector2(10, 10)), greaterThan(isoDepth(Vector2(5, 10))));
      expect(isoDepth(Vector2(10, 10), -12), 8);
    });
  });

  group('joystick layar → arah tanah', () {
    Vector2 onScreen(Vector2 groundDir) => isoOfV(groundDir).normalized();

    test('arah di layar tetap sama setelah dipetakan ke tanah', () {
      for (var deg = 0; deg < 360; deg += 15) {
        final a = deg * math.pi / 180;
        final stick = Vector2(math.cos(a), math.sin(a));
        final s = onScreen(screenDirToGround(stick));
        expect(s.x, closeTo(stick.x, 1e-6), reason: '$deg°');
        expect(s.y, closeTo(stick.y, 1e-6), reason: '$deg°');
      }
    });

    test('panjang dorongan joystick dipertahankan', () {
      expect(screenDirToGround(Vector2(0.4, 0)).length, closeTo(0.4, 1e-6));
      expect(screenDirToGround(Vector2(0, -1)).length, closeTo(1, 1e-6));
      expect(screenDirToGround(Vector2.zero()), Vector2.zero());
    });

    test('kanan layar = timur laut tanah, bawah layar = tenggara tanah', () {
      final right = screenDirToGround(Vector2(1, 0));
      expect(right.x, greaterThan(0));
      expect(right.y, lessThan(0));
      final down = screenDirToGround(Vector2(0, 1));
      expect(down.x, closeTo(down.y, 1e-6));
      expect(down.x, greaterThan(0));
    });
  });

  group('arah motor di layar', () {
    Offset screenOf(double heading) => isoOf(Offset(math.cos(heading), math.sin(heading)));

    test('motor ke timur tanah tampak menyerong ke kanan-bawah layar', () {
      final s = screenOf(0);
      expect(math.atan2(s.dy, s.dx), closeTo(math.atan2(0.5, 1), 1e-9));
    });

    test('motor ke tenggara tanah tampak lurus ke bawah layar', () {
      final s = screenOf(math.pi / 4);
      expect(s.dx, closeTo(0, 1e-9));
      expect(s.dy, greaterThan(0));
    });

    test('setir ke kanan layar membuat motor melaju ke kanan layar', () {
      final g = screenDirToGround(Vector2(1, 0));
      final s = screenOf(math.atan2(g.y, g.x));
      expect(s.dx, greaterThan(0));
      expect(s.dy, closeTo(0, 1e-6));
    });
  });
}
