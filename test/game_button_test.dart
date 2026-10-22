import 'package:batam_the_journey_begins/ui/widgets/game_button.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: child),
    );

GameButton _button({VoidCallback? onTap, ValueChanged<bool>? onHold}) => GameButton(
      width: 100,
      height: 50,
      color: const Color(0xFFFFFFFF),
      onTap: onTap,
      onHold: onHold,
      child: const SizedBox(),
    );

void main() {
  testWidgets('tap yang terlalu cepat setelah tombol muncul diabaikan', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_wrap(_button(onTap: () => taps++)));
    await tester.tap(find.byType(GameButton));
    expect(taps, 0, reason: 'tap tembus dari layar sebelumnya tidak boleh memicu aksi');

    await tester.pump(GameButton.armDelay);
    await tester.tap(find.byType(GameButton));
    expect(taps, 1);
  });

  testWidgets('tombol tahan (GAS) tetap langsung responsif', (tester) async {
    final holds = <bool>[];
    await tester.pumpWidget(_wrap(_button(onHold: holds.add)));
    await tester.tap(find.byType(GameButton));
    expect(holds, [true, false]);
  });
}
