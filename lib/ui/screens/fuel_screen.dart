import 'package:flutter/widgets.dart';

import '../../game/batam_game.dart';
import '../../game/systems/economy.dart';
import '../palette.dart';
import '../widgets/game_button.dart';

/// Layar "Isi Bensin" (desain Fuel): pilih jenis bensin dan jumlah, lalu bayar.
class FuelScreen extends StatefulWidget {
  const FuelScreen({super.key, required this.game});

  final BatamGame game;

  @override
  State<FuelScreen> createState() => _FuelScreenState();
}

enum _Amount {
  rp10('Rp 10rb'),
  rp20('Rp 20rb'),
  half('Setengah'),
  full('Penuh');

  const _Amount(this.label);

  final String label;
}

class _FuelScreenState extends State<FuelScreen> {
  FuelGrade _grade = FuelGrade.biasa;
  _Amount _amount = _Amount.full;

  FuelTank get tank => widget.game.tank;

  double get _liters {
    final space = tank.space;
    return switch (_amount) {
      _Amount.rp10 => (10000 / _grade.pricePerLiter).clamp(0.0, space),
      _Amount.rp20 => (20000 / _grade.pricePerLiter).clamp(0.0, space),
      _Amount.half => (tank.capacity / 2 - tank.liters.value).clamp(0.0, space),
      _Amount.full => space,
    };
  }

  int get _total => FuelTank.price(_liters, _grade);

  String _l(double v, [int digits = 2]) => v.toStringAsFixed(digits).replaceAll('.', ',');

  void _pay() {
    final liters = _liters;
    if (widget.game.buyFuel(liters, _grade)) {
      widget.game.toast.value = 'Tangki terisi +${_l(liters)} L $_gradeLabel';
      widget.game.closeScreen();
    }
  }

  String get _gradeLabel => _grade.label;

  @override
  Widget build(BuildContext context) {
    final station = widget.game.nearStation.value;
    final liters = _liters;
    final total = _total;
    final canPay = liters > 0.005 && widget.game.wallet.canPay(total);
    final payLabel = liters <= 0.005
        ? 'Tangki Penuh'
        : widget.game.wallet.canPay(total)
        ? 'Bayar & Isi'
        : 'Uang Kurang';

    return ColoredBox(
      color: BColors.tanah,
      child: Row(
        children: [
          SizedBox(
            width: 330,
            child: _PumpPanel(
              liters: _l(liters),
              total: formatRupiah(total, prefix: true),
              location: '${station?.area ?? 'Batam'} · pompa ${station?.pumpNo ?? 1}',
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Isi Bensin', style: baloo(24)),
                      GameButton(
                        width: 40,
                        height: 40,
                        radius: 12,
                        shadow: 0,
                        color: BColors.cream,
                        semanticLabel: 'Tutup',
                        onTap: widget.game.closeScreen,
                        child: const CustomPaint(size: Size(18, 18), painter: _CloseIcon()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final g in FuelGrade.values) ...[
                        if (g != FuelGrade.values.first) const SizedBox(width: 8),
                        Expanded(child: _gradeCard(g)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Tangki motor', style: nunito(12)),
                      Text('${_l(tank.liters.value + liters, 1)} / ${_l(tank.capacity, 1)} L', style: nunito(12)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 16,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5D5B8),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: BColors.ink, width: 2),
                    ),
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final cur = c.maxWidth * tank.fraction.clamp(0.0, 1.0);
                        final add = c.maxWidth * (liters / tank.capacity).clamp(0.0, 1.0);
                        return Stack(
                          children: [
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              width: cur,
                              child: const ColoredBox(color: BColors.kuning),
                            ),
                            Positioned(
                              left: cur,
                              top: 0,
                              bottom: 0,
                              width: add,
                              child: const ColoredBox(color: BColors.hijauAksi),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final a in _Amount.values) ...[
                        if (a != _Amount.values.first) const SizedBox(width: 8),
                        Expanded(child: _amountButton(a)),
                      ],
                    ],
                  ),
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Total bayar', style: nunito(12, color: BColors.teksRedup)),
                            Text(formatRupiah(total, prefix: true), style: baloo(26).copyWith(height: 1)),
                          ],
                        ),
                      ),
                      GameButton(
                        width: 150,
                        height: 52,
                        color: BColors.hijauAksi,
                        enabled: canPay,
                        onTap: _pay,
                        child: Text(payLabel, style: baloo(19, color: const Color(0xFFFFFFFF))),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _gradeColors = {
    FuelGrade.biasa: BColors.kuning,
    FuelGrade.plus: BColors.tosca,
    FuelGrade.turbo: BColors.atapMerah,
  };

  Widget _gradeCard(FuelGrade g) {
    final on = g == _grade;
    return Semantics(
      button: true,
      selected: on,
      child: GestureDetector(
        onTap: () => setState(() => _grade = g),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: on ? const Color(0xFFFFFFFF) : BColors.cream,
            border: Border.all(color: BColors.ink, width: 3),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [if (on) const BoxShadow(color: BColors.ink, offset: Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 6,
                decoration: BoxDecoration(color: _gradeColors[g], borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(height: 2),
              Text(g.label, style: baloo(17)),
              Text('${formatRupiah(g.pricePerLiter, prefix: true)}/L', style: nunito(12, color: BColors.teksRedup)),
              Text(g.note, style: nunito(11, color: BColors.teksRedup)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _amountButton(_Amount a) {
    final on = a == _amount;
    return Semantics(
      button: true,
      selected: on,
      child: GestureDetector(
        onTap: () => setState(() => _amount = a),
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? BColors.ink : BColors.cream,
            border: Border.all(color: BColors.ink, width: 3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(a.label, style: nunito(13, color: on ? BColors.cream : BColors.ink)),
        ),
      ),
    );
  }
}

/// Panel kiri: ilustrasi pompa dengan layar liter & total.
class _PumpPanel extends StatelessWidget {
  const _PumpPanel({required this.liters, required this.total, required this.location});

  final String liters, total, location;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: BColors.aspal,
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _PumpPainter())),
          Positioned(
            left: 0,
            right: 0,
            top: 14,
            child: Text(
              'SPBU BensinKu',
              textAlign: TextAlign.center,
              style: baloo(26, color: const Color(0xFFFFFFFF)).copyWith(height: 1),
            ),
          ),
          Positioned(
            left: 124,
            top: 128,
            width: 82,
            child: Column(
              children: [
                Text(liters, style: baloo(22, color: BColors.kuning)),
                Text('liter', style: baloo(11, color: BColors.cream).copyWith(height: 1)),
                FittedBox(
                  child: Text(total, style: baloo(13, color: const Color(0xFFFFFFFF))),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: BColors.cream.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(location, style: nunito(12)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PumpPainter extends CustomPainter {
  const _PumpPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Koordinat desain 330×390.
    canvas.scale(size.width / 330, size.height / 390);
    RRect r(double x, double y, double w, double h, double rad) =>
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(rad));
    canvas.drawRect(const Rect.fromLTWH(0, 0, 330, 70), Paint()..color = BColors.atapMerah);
    canvas.drawRect(const Rect.fromLTWH(0, 62, 330, 10), Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawRRect(r(110, 110, 110, 200, 12), Paint()..color = BColors.cream);
    canvas.drawRRect(
      r(110, 110, 110, 200, 12),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = BColors.ink,
    );
    canvas.drawRRect(r(124, 126, 82, 64, 6), Paint()..color = BColors.ink);
    canvas.drawRRect(r(124, 204, 82, 22, 5), Paint()..color = BColors.atapMerah);
    canvas.drawRRect(r(124, 234, 38, 56, 5), Paint()..color = BColors.kuning);
    canvas.drawRRect(r(168, 234, 38, 56, 5), Paint()..color = BColors.tosca);
    canvas.drawPath(
      Path()
        ..moveTo(220, 150)
        ..cubicTo(260, 150, 262, 200, 250, 236),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..color = BColors.ink,
    );
    canvas.drawRRect(r(238, 232, 24, 16, 4), Paint()..color = BColors.ink);
    canvas.drawRRect(r(60, 318, 210, 18, 6), Paint()..color = BColors.trotoar);
    canvas.drawRRect(r(228, 270, 80, 34, 10), Paint()..color = BColors.biruPemain);
    canvas.drawCircle(const Offset(292, 287), 7, Paint()..color = BColors.kuning);
    canvas.drawCircle(const Offset(242, 287), 9, Paint()..color = BColors.oranye);
  }

  @override
  bool shouldRepaint(_PumpPainter old) => false;
}

class _CloseIcon extends CustomPainter {
  const _CloseIcon();

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * k
      ..strokeCap = StrokeCap.round
      ..color = BColors.ink;
    canvas.drawLine(Offset(6 * k, 6 * k), Offset(18 * k, 18 * k), p);
    canvas.drawLine(Offset(18 * k, 6 * k), Offset(6 * k, 18 * k), p);
  }

  @override
  bool shouldRepaint(_CloseIcon old) => false;
}
