import 'package:flutter/widgets.dart';

import '../../game/batam_game.dart';
import '../../game/systems/economy.dart';
import '../../game/systems/workshop.dart';
import '../palette.dart';
import '../widgets/game_button.dart';

/// Layar "Bengkel" (desain Workshop): kondisi motor + servis, modifikasi,
/// dan perbandingan statistik sebelum → sesudah.
class WorkshopScreen extends StatefulWidget {
  const WorkshopScreen({super.key, required this.game});

  final BatamGame game;

  @override
  State<WorkshopScreen> createState() => _WorkshopScreenState();
}

class _WorkshopScreenState extends State<WorkshopScreen> {
  ModCategory _cat = ModCategory.mesin;
  late MotorMod _selected = _items.first;

  Workshop get ws => widget.game.workshop;
  Wallet get wallet => widget.game.wallet;

  List<MotorMod> get _items => motorMods.where((m) => m.category == _cat).toList();

  static BoxDecoration get _panel => BoxDecoration(
    color: BColors.cream,
    border: Border.all(color: BColors.ink, width: 3),
    borderRadius: BorderRadius.circular(16),
  );

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: BColors.aspal,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 220, child: _condition()),
            const SizedBox(width: 10),
            Expanded(child: _mods()),
            const SizedBox(width: 10),
            SizedBox(width: 230, child: _compare()),
          ],
        ),
      ),
    );
  }

  // ---- Kiri: kondisi & servis ----

  Widget _condition() {
    final station = widget.game.nearWorkshop.value;
    final price = ws.serviceAllPrice;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: _panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Semantics(
                button: true,
                label: 'Kembali',
                child: GestureDetector(
                  onTap: widget.game.closeScreen,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      border: Border.all(color: BColors.ink, width: 2),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const CustomPaint(painter: _BackPainter()),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  station?.name ?? 'Bengkel',
                  style: baloo(17).copyWith(height: 1),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('KONDISI MOTOR MATIC', style: nunito(11, color: const Color(0xFF6B5440)).copyWith(letterSpacing: 0.7)),
          for (final p in MotorPart.values) _partRow(p),
          const Spacer(),
          GameButton(
            width: double.infinity,
            height: 40,
            radius: 13,
            shadow: 3,
            color: BColors.kuning,
            enabled: price > 0 && wallet.canPay(price),
            onTap: () {
              if (ws.serviceAll(wallet)) {
                widget.game.toast.value = 'Motor sudah diservis, seperti baru lagi!';
                widget.game.save();
                setState(() {});
              }
            },
            child: Text(
              price == 0
                  ? 'Motor sehat'
                  : (wallet.canPay(price) ? 'Servis semua · ${formatRupiah(price, prefix: true)}' : 'Uang kurang'),
              style: baloo(14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _partRow(MotorPart p) {
    final v = ws.level(p);
    final (bar, text) = v >= 60
        ? (BColors.hijauAksi, const Color(0xFF2F7A45))
        : v >= Workshop.badLevel
        ? (BColors.oranye, const Color(0xFFB5651D))
        : (BColors.atapMerah, const Color(0xFFB23A26));
    final note = v >= 60
        ? (p == MotorPart.rem ? 'Pakem' : 'Normal')
        : v >= Workshop.badLevel
        ? 'Mulai aus'
        : switch (p) {
            MotorPart.mesin => 'Rusak! Kecepatan turun',
            MotorPart.ban => 'Rawan bocor di jalan',
            MotorPart.rem => 'Rem blong, pengereman jauh',
            MotorPart.oli => 'Segera ganti! Mesin cepat rusak',
          };
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(p.label, style: nunito(12)),
              Text('${v.round()}%', style: nunito(12, color: text)),
            ],
          ),
          const SizedBox(height: 2),
          _bar([(v / 100, bar)]),
          Text(note, style: nunito(10, color: BColors.teksRedup)),
        ],
      ),
    );
  }

  // ---- Tengah: modifikasi ----

  Widget _mods() => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: _panel,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Modifikasi', style: baloo(19).copyWith(height: 1)),
        const SizedBox(height: 8),
        Wrap(spacing: 5, runSpacing: 5, children: [for (final c in ModCategory.values) _catChip(c)]),
        const SizedBox(height: 8),
        for (final m in _items) _itemCard(m),
      ],
    ),
  );

  Widget _catChip(ModCategory c) {
    final on = c == _cat;
    return Semantics(
      button: true,
      selected: on,
      child: GestureDetector(
        onTap: () => setState(() {
          _cat = c;
          _selected = _items.first;
        }),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: on ? BColors.ink : const Color(0xFFFFFFFF),
            border: Border.all(color: BColors.ink, width: 2),
            borderRadius: BorderRadius.circular(10),
          ),
          // Center selebar teks: chip tidak melebar memenuhi panel.
          child: Center(
            widthFactor: 1,
            child: Text(c.label, style: nunito(12, color: on ? BColors.cream : BColors.ink)),
          ),
        ),
      ),
    );
  }

  Widget _itemCard(MotorMod m) {
    final sel = m.id == _selected.id;
    final owned = ws.hasMod(m.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        selected: sel,
        child: GestureDetector(
          onTap: () => setState(() => _selected = m),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: sel ? const Color(0xFFFFFFFF) : BColors.cream,
              border: Border.all(color: sel ? BColors.ink : const Color(0xFFE5D5B8), width: 3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.name, style: nunito(13).copyWith(height: 1.2)),
                      Text(m.desc, style: nunito(11, color: BColors.teksRedup)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  owned ? 'Terpasang' : formatRupiah(m.price, prefix: true),
                  style: nunito(12, color: owned ? const Color(0xFF2F7A45) : BColors.ink),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- Kanan: sebelum → sesudah ----

  Widget _compare() {
    final m = _selected;
    final owned = ws.hasMod(m.id);
    final canPay = wallet.canPay(m.price);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: _panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('SEBELUM › SESUDAH', style: nunito(11, color: const Color(0xFF6B5440)).copyWith(letterSpacing: 0.7)),
          for (final s in MotorStat.values) _statRow(s, m),
          const Spacer(),
          GameButton(
            width: double.infinity,
            height: 44,
            radius: 14,
            color: BColors.hijauAksi,
            enabled: !owned && canPay,
            onTap: () {
              if (ws.install(m, wallet)) {
                widget.game.toast.value = '${m.name} terpasang!';
                widget.game.save();
                setState(() {});
              }
            },
            child: Text(
              owned ? 'Terpasang' : (canPay ? 'Pasang · ${formatRupiah(m.price, prefix: true)}' : 'Uang kurang'),
              style: baloo(16, color: const Color(0xFFFFFFFF)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(MotorStat s, MotorMod preview) {
    final before = ws.stat(s);
    final after = ws.hasMod(preview.id) ? before : ws.stat(s, preview: preview);
    final d = after - before;
    final color = d > 0 ? const Color(0xFF2F7A45) : (d < 0 ? const Color(0xFFB23A26) : BColors.ink);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(s.label, style: nunito(12)),
              Text(d == 0 ? '$before' : '$before › $after', style: nunito(12, color: color)),
            ],
          ),
          const SizedBox(height: 2),
          _bar([((d < 0 ? after : before) / 10, const Color(0xFF6B5440)), if (d > 0) (d / 10, BColors.hijauAksi)]),
        ],
      ),
    );
  }

  /// Bar 9 px dengan beberapa ruas berurutan (pecahan 0–1).
  Widget _bar(List<(double, Color)> parts) => Container(
    height: 9,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(color: const Color(0xFFE5D5B8), borderRadius: BorderRadius.circular(5)),
    child: LayoutBuilder(
      builder: (context, c) => Row(
        children: [
          for (final (f, color) in parts)
            SizedBox(
              width: c.maxWidth * f.clamp(0.0, 1.0),
              height: 9,
              child: ColoredBox(color: color),
            ),
        ],
      ),
    ),
  );
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
