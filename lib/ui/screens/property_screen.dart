import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../game/batam_game.dart';
import '../../game/systems/economy.dart';
import '../../game/systems/housing.dart';
import '../palette.dart';
import '../widgets/game_button.dart';

/// "Rp 150 jt", "Rp 2,4 M", "Rp 6,2 jt".
String formatShortRupiah(int v) {
  String dec(double x) {
    final s = x.toStringAsFixed(x >= 100 || x == x.roundToDouble() ? 0 : 1);
    return s.replaceAll('.', ',');
  }

  if (v >= 1000000000) return 'Rp ${dec(v / 1e9)} M';
  if (v >= 1000000) return 'Rp ${dec(v / 1e6)} jt';
  return formatRupiah(v, prefix: true);
}

/// Layar "Rumah Dijual" (desain Property).
class PropertyScreen extends StatefulWidget {
  const PropertyScreen({super.key, required this.game, this.initial});

  final BatamGame game;
  final String? initial;

  @override
  State<PropertyScreen> createState() => _PropertyScreenState();
}

class _PropertyScreenState extends State<PropertyScreen> {
  late HouseListing _sel = houseListings.firstWhere((l) => l.id == widget.initial, orElse: () => houseListings.first);

  Housing get housing => widget.game.housing;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: BColors.tanah,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 300, child: _list()),
          Expanded(child: _detail()),
        ],
      ),
    );
  }

  Widget _list() => Container(
    padding: const EdgeInsets.all(14),
    decoration: const BoxDecoration(
      color: BColors.cream,
      border: Border(right: BorderSide(color: BColors.ink, width: 4)),
    ),
    child: ListView(
      children: [
        Row(
          children: [
            Semantics(
              button: true,
              label: 'Kembali',
              child: GestureDetector(
                onTap: widget.game.closeScreen,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFFFF),
                    border: Border.all(color: BColors.ink, width: 3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const CustomPaint(painter: _BackPainter()),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('Rumah Dijual', style: baloo(22).copyWith(height: 1)),
          ],
        ),
        const SizedBox(height: 8),
        for (final l in houseListings) _listItem(l),
      ],
    ),
  );

  Widget _listItem(HouseListing l) {
    final sel = l.id == _sel.id;
    final owned = housing.owned.value.contains(l.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        selected: sel,
        child: GestureDetector(
          onTap: () => setState(() => _sel = l),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: sel ? const Color(0xFFFFFFFF) : BColors.cream,
              border: Border.all(color: sel ? BColors.ink : const Color(0xFFE5D5B8), width: 3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: l.roof, borderRadius: BorderRadius.circular(10)),
                  child: const CustomPaint(painter: _HouseIcon()),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.name, style: nunito(13).copyWith(height: 1.2)),
                      Text(
                        '${l.area} · ${owned ? 'Milikmu' : formatShortRupiah(l.price)}',
                        style: nunito(12, color: owned ? const Color(0xFF2F7A45) : BColors.teksRedup),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detail() {
    final l = _sel;
    final owned = housing.owned.value.contains(l.id);
    final loan = housing.loans[l.id];
    final wallet = widget.game.wallet;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 170,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: BColors.ink, width: 4)),
          ),
          child: Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _FrontPainter(l.roof))),
              Positioned(left: 14, top: 12, child: _tag(owned ? 'MILIKMU' : 'DIJUAL', owned)),
              Positioned(
                right: 14,
                top: 12,
                child: ValueListenableBuilder(
                  valueListenable: wallet.money,
                  builder: (context, m, _) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: BColors.cream,
                      border: Border.all(color: BColors.ink, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Uang kamu: ${formatRupiah(m, prefix: true)}', style: nunito(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.name, style: baloo(22).copyWith(height: 1.05)),
                          Text('${l.area} · ${l.desc}', style: nunito(13, color: BColors.teksRedup)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      formatShortRupiah(l.price),
                      style: baloo(24, color: const Color(0xFFC2452F)).copyWith(height: 1),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in l.tags)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFFFF),
                          border: Border.all(color: const Color(0xFFE5D5B8), width: 2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(t, style: nunito(12)),
                      ),
                  ],
                ),
                const Spacer(),
                if (owned)
                  Text(
                    loan == null
                        ? 'Rumah ini sudah lunas milikmu. Masuk lewat pintunya di peta.'
                        : 'Cicilan ${formatShortRupiah(loan.monthly)}/bln, sisa ${loan.monthsLeft} bulan. '
                              'Ditagih otomatis tiap 30 hari game.',
                    style: nunito(12, color: BColors.teksRedup),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: GameButton(
                          width: double.infinity,
                          height: 48,
                          color: BColors.cream,
                          shadow: 0,
                          enabled: wallet.canPay(l.downPayment),
                          onTap: () => _buy(credit: true),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Cicil ${Housing.loanMonths}× · DP ${formatShortRupiah(l.downPayment)}',
                                style: baloo(14).copyWith(height: 1.1),
                              ),
                              Text('${formatShortRupiah(l.monthly)}/bln', style: nunito(12).copyWith(height: 1.1)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GameButton(
                          width: double.infinity,
                          height: 48,
                          color: BColors.hijauAksi,
                          enabled: wallet.canPay(l.price),
                          onTap: () => _buy(credit: false),
                          child: Text('Beli Tunai', style: baloo(17, color: const Color(0xFFFFFFFF))),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _buy({required bool credit}) {
    final g = widget.game;
    final ok = credit ? housing.buyCredit(_sel, g.clock.day.value) : housing.buyCash(_sel);
    if (!ok) return;
    g.toast.value = credit
        ? '${_sel.name} jadi milikmu! Cicilan dimulai bulan depan.'
        : '${_sel.name} lunas jadi milikmu!';
    g.save();
    setState(() {});
  }

  Widget _tag(String text, bool owned) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: owned ? BColors.hijauAksi : BColors.atapMerah,
      border: Border.all(color: BColors.ink, width: 2),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(text, style: nunito(11, color: const Color(0xFFFFFFFF)).copyWith(letterSpacing: 0.4)),
  );
}

/// Tampak depan rumah yang dipilih (sederhana dari desain Property).
class _FrontPainter extends CustomPainter {
  const _FrontPainter(this.roof);

  final Color roof;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 540, sy = size.height / 170;
    canvas.scale(sx, sy);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 540, 170),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, const Offset(0, 170), const [Color(0xFF9FD7E6), Color(0xFFD8EFF4)]),
    );
    canvas.drawRect(const Rect.fromLTWH(0, 124, 540, 46), Paint()..color = const Color(0xFF8FC27A));
    final tree = Paint()..color = const Color(0xFF5E9E52);
    canvas.drawCircle(const Offset(56, 104), 34, tree);
    canvas.drawCircle(const Offset(496, 100), 30, tree);
    canvas.drawRect(
      const Rect.fromLTWH(122, 70, 210, 64),
      Paint()
        ..shader = ui.Gradient.linear(const Offset(0, 70), const Offset(0, 134), const [
          Color(0xFFFBF1DE),
          Color(0xFFE5D0AC),
        ]),
    );
    final roofPath = Path()
      ..moveTo(110, 74)
      ..lineTo(227, 22)
      ..lineTo(344, 74)
      ..close();
    canvas.drawPath(roofPath, Paint()..color = roof);
    canvas.drawPath(
      roofPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF5E2A1B),
    );
    final glass = Paint()..color = const Color(0xFF86ADC2);
    final white = Paint()..color = const Color(0xFFFFFFFF);
    for (final x in const [138.0, 272.0]) {
      canvas.drawRect(Rect.fromLTWH(x, 88, 44, 32), white);
      canvas.drawRect(Rect.fromLTWH(x + 3, 91, 38, 26), glass);
    }
    canvas.drawRect(const Rect.fromLTWH(208, 86, 38, 48), white);
    canvas.drawRect(const Rect.fromLTWH(211, 89, 32, 45), Paint()..color = const Color(0xFF8E6B4A));
    // Carport.
    canvas.drawRect(const Rect.fromLTWH(332, 78, 120, 6), Paint()..color = const Color(0xFF7D848C));
    canvas.drawRect(const Rect.fromLTWH(446, 84, 5, 52), Paint()..color = const Color(0xFF7D848C));
    canvas.drawRect(const Rect.fromLTWH(332, 134, 120, 8), Paint()..color = const Color(0xFFCFC5B4));
    // Pagar & jalan.
    for (var x = 96.0; x < 340; x += 26) {
      canvas.drawRect(Rect.fromLTWH(x, 124, 5, 24), white);
    }
    canvas.drawRect(const Rect.fromLTWH(96, 128, 240, 5), white);
    canvas.drawRect(const Rect.fromLTWH(0, 148, 540, 8), Paint()..color = BColors.trotoar);
    canvas.drawRect(const Rect.fromLTWH(0, 156, 540, 14), Paint()..color = BColors.aspal);
  }

  @override
  bool shouldRepaint(_FrontPainter old) => old.roof != roof;
}

class _HouseIcon extends CustomPainter {
  const _HouseIcon();

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 40;
    canvas.translate(10 * k, 10 * k);
    canvas.scale(20 * k / 24);
    canvas.drawPath(
      Path()
        ..moveTo(3, 11)
        ..lineTo(12, 4)
        ..lineTo(21, 11)
        ..lineTo(21, 21)
        ..lineTo(3, 21)
        ..close(),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFFFFFFF),
    );
  }

  @override
  bool shouldRepaint(_HouseIcon old) => false;
}

class _BackPainter extends CustomPainter {
  const _BackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    canvas.drawPath(
      Path()
        ..moveTo(14 * k, 7 * k)
        ..lineTo(9 * k, 12 * k)
        ..lineTo(14 * k, 17 * k),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6 * k
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = BColors.ink,
    );
  }

  @override
  bool shouldRepaint(_BackPainter old) => false;
}
