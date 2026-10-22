import 'package:batam_the_journey_begins/game/actors/skid_marks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('jejak rem: ruas tersambung, putus saat diangkat, hilang setelah memudar', () {
    final s = SkidMarks();
    s.addPoint(const Offset(0, 0));
    expect(s.count, 0);
    s.addPoint(const Offset(0.1, 0)); // terlalu rapat
    expect(s.count, 0);
    s.addPoint(const Offset(1, 0));
    s.addPoint(const Offset(2, 0));
    expect(s.count, 2);
    s.lift();
    s.addPoint(const Offset(10, 0)); // garis baru, belum ada ruas
    expect(s.count, 2);
    s.update(SkidMarks.life - 0.1);
    expect(s.count, 2);
    s.update(0.2);
    expect(s.count, 0);
  });

  test('jejak rem dibatasi jumlahnya', () {
    final s = SkidMarks();
    for (var i = 0; i <= SkidMarks.maxMarks + 50; i++) {
      s.addPoint(Offset(i.toDouble(), 0));
    }
    expect(s.count, SkidMarks.maxMarks);
  });
}
