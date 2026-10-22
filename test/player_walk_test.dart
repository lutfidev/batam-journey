import 'package:batam_the_journey_begins/game/actors/player.dart';
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

/// Jalankan percepatan jalan kaki selama [seconds] detik dengan langkah 1/60.
Vector2 _run(Vector2 v, Vector2 target, double rate, double seconds) {
  for (var t = 0.0; t < seconds - 1e-9; t += 1 / 60) {
    approachVelocity(v, target, rate / 60);
  }
  return v;
}

void main() {
  final full = Vector2(Player.walkSpeed, 0);

  test('jalan kaki: mulai bertahap, lalu laju penuh dan tidak lebih', () {
    final v = _run(Vector2.zero(), full, Player.walkAccel, 0.1);
    expect(v.x, closeTo(Player.walkAccel * 0.1, 0.01));
    expect(v.x, lessThan(Player.walkSpeed));
    _run(v, full, Player.walkAccel, 0.5);
    expect(v.x, Player.walkSpeed);
  });

  test('jalan kaki: lepas joystick berhenti cepat, tidak meluncur', () {
    final v = _run(full.clone(), Vector2.zero(), Player.walkDecel, 0.1);
    expect(v.x, greaterThan(0)); // masih ada perlambatan, bukan berhenti seketika
    _run(v, Vector2.zero(), Player.walkDecel, 0.15);
    expect(v.length, 0);
  });

  test('jalan kaki: belok arah tetap lewat jalur halus, panjang tidak melebihi laju', () {
    final v = full.clone();
    final up = Vector2(0, -Player.walkSpeed);
    approachVelocity(v, up, Player.walkAccel / 60);
    expect(v.y, lessThan(0));
    expect(v.x, lessThan(Player.walkSpeed));
    _run(v, up, Player.walkAccel, 1);
    expect(v, up);
  });
}
