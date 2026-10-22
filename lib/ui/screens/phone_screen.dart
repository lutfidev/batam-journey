import 'package:flutter/widgets.dart';

import '../../game/batam_game.dart';
import '../../game/systems/economy.dart';
import '../../game/systems/gps.dart';
import '../../game/systems/orders.dart';
import '../palette.dart';
import '../widgets/game_button.dart';

/// Layar "HP Kamu" dengan aplikasi OjekKita (desain Phone).
/// Game tetap jalan di belakang.
class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key, required this.game});

  final BatamGame game;

  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  OrderTab _tab = OrderTab.antar;

  BatamGame get game => widget.game;

  void _take(OjekOrder o) {
    if (game.orders.take(o, game.playerOffset)) game.closeScreen();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF3A4656),
      child: Stack(
        children: [
          Positioned(
            left: 16,
            top: 14,
            width: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('HP Kamu', style: baloo(22, color: BColors.cream).copyWith(height: 1)),
                const SizedBox(height: 4),
                Text(
                  'Game tetap jalan di belakang, jangan main HP sambil ngebut.',
                  style: nunito(12, color: BColors.trotoar),
                ),
                const SizedBox(height: 10),
                GameButton(
                  width: 100,
                  height: 36,
                  radius: 12,
                  shadow: 0,
                  color: BColors.cream,
                  onTap: game.closeScreen,
                  child: Text('Tutup HP', style: nunito(13)),
                ),
              ],
            ),
          ),
          Center(child: _phone()),
        ],
      ),
    );
  }

  Widget _phone() {
    return Container(
      width: 220,
      height: 360,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: BColors.ink,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [BoxShadow(color: Color(0xFF1A110A), offset: Offset(0, 6))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: ColoredBox(
          color: BColors.cream,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: BColors.hijauAksi,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('OjekKita', style: baloo(18, color: const Color(0xFFFFFFFF)).copyWith(height: 1)),
                        ValueListenableBuilder(
                          valueListenable: game.orders.ordersDone,
                          builder: (context, n, _) =>
                              Text('$n selesai', style: nunito(10, color: const Color(0xFFFFFFFF))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        for (final t in OrderTab.values) ...[
                          if (t != OrderTab.values.first) const SizedBox(width: 4),
                          Expanded(child: _tabButton(t)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ValueListenableBuilder(
                  valueListenable: game.orders.active,
                  builder: (context, active, _) => ValueListenableBuilder(
                    valueListenable: game.orders.offers,
                    builder: (context, offers, _) {
                      final list = offers[_tab] ?? const <OjekOrder>[];
                      return ListView(
                        padding: const EdgeInsets.all(8),
                        children: [
                          if (active != null) _activeCard(active),
                          if (list.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                'Belum ada order di sekitar sini.',
                                style: nunito(11, color: BColors.teksRedup),
                              ),
                            ),
                          for (final o in list) _orderCard(o, takeable: active == null),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabButton(OrderTab t) {
    final on = t == _tab;
    return Semantics(
      button: true,
      selected: on,
      child: GestureDetector(
        onTap: () => setState(() => _tab = t),
        child: Container(
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? const Color(0xFFFFFFFF) : const Color(0x40FFFFFF),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(t.label, style: nunito(11, color: on ? const Color(0xFF2F7A45) : const Color(0xFFFFFFFF))),
        ),
      ),
    );
  }

  Widget _activeCard(ActiveOrder a) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFFDDF0E2),
      border: Border.all(color: BColors.hijauAksi, width: 2),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ORDER AKTIF', style: nunito(10, color: const Color(0xFF2F7A45))),
        Text(a.headline, style: nunito(12).copyWith(height: 1.2)),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(formatRupiah(a.order.pay, prefix: true), style: baloo(14, color: const Color(0xFF2F7A45))),
            _smallButton('Batalkan', BColors.cream, () => game.orders.cancel(reason: 'Order dibatalkan')),
          ],
        ),
      ],
    ),
  );

  Widget _orderCard(OjekOrder o, {required bool takeable}) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFFFF),
      border: Border.all(color: const Color(0xFFE5D5B8), width: 2),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(o.kind, style: nunito(10, color: BColors.teksRedup)),
            Text(formatDistance(o.tripLength), style: nunito(10, color: BColors.teksRedup)),
          ],
        ),
        Text(o.routeText, style: nunito(12).copyWith(height: 1.2), maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(formatRupiah(o.pay, prefix: true), style: baloo(14, color: const Color(0xFF2F7A45))),
            _smallButton(
              takeable ? 'Ambil' : 'Ada order',
              takeable ? BColors.kuning : const Color(0xFFE5D5B8),
              takeable ? () => _take(o) : null,
            ),
          ],
        ),
      ],
    ),
  );

  Widget _smallButton(String label, Color bg, VoidCallback? onTap) => Semantics(
    button: true,
    enabled: onTap != null,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: BColors.ink, width: 2),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(label, style: nunito(11)),
      ),
    ),
  );
}
