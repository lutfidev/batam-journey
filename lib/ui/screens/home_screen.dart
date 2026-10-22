import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../game/actors/sprites.dart';
import '../../game/batam_game.dart';
import '../../game/systems/economy.dart';
import '../../game/systems/housing.dart';
import '../../game/systems/needs.dart';
import '../palette.dart';
import '../widgets/game_button.dart';

/// Di dalam rumah (desain HomeLife): denah 3/4 dengan titik yang bisa
/// dipakai, kebutuhan Energi/Lapar/Mood, dan aksi titik terpilih.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.game, required this.homeId});

  final BatamGame game;
  final String homeId;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _SpotInfo {
  const _SpotInfo(this.x, this.y, this.desc);

  /// Posisi tombol di denah 544×390.
  final double x, y;
  final String desc;
}

const _spotInfo = {
  HomeSpot.kasur: _SpotInfo(60, 206, 'Lewati malam sampai 06:00, game tersimpan otomatis.'),
  HomeSpot.dapur: _SpotInfo(236, 104, 'Masak sendiri jauh lebih hemat daripada beli makan di luar.'),
  HomeSpot.mandi: _SpotInfo(414, 160, 'Badan segar setelah seharian di jalan. Pelanggan suka driver yang wangi.'),
  HomeSpot.lemari: _SpotInfo(142, 124, 'Pakai jaket ojek yang bersih dan rapi.'),
  HomeSpot.meja: _SpotInfo(318, 180, 'Kelola usaha dari rumah: cek untung, stok, upgrade, dan pesanan besar.'),
  HomeSpot.garasi: _SpotInfo(430, 310, 'Perawatan dasar sendiri: ganti oli dan isi angin ban.'),
};

class _HomeScreenState extends State<HomeScreen> {
  late final List<HomeSpot> _spots = widget.game.housing.spots(widget.homeId);
  late HomeSpot _sel = _spots.first;

  BatamGame get game => widget.game;
  Housing get housing => game.housing;
  bool get isKos => widget.homeId == Housing.kosId;

  String get _title {
    if (isKos) return 'Kos Bu Ros · Bengkong';
    final l = housing.listing(widget.homeId);
    return l == null ? 'Rumahmu' : '${l.name} · ${l.area}';
  }

  (String, List<String>) _action(HomeSpot s) => switch (s) {
    HomeSpot.kasur => ('Tidur sampai pagi', [isKos ? 'Energi 80%' : 'Energi penuh', 'Simpan game']),
    HomeSpot.dapur => ('Masak · ${formatRupiah(Housing.cookCost, prefix: true)}', ['Lapar −60', 'Mood +5']),
    HomeSpot.mandi => ('Mandi', ['Mood +15', 'Tip +5% (6 jam)']),
    HomeSpot.lemari => ('Ganti baju', ['Mood +5', 'Sekali sehari']),
    HomeSpot.meja => (game.business.owned.value.isEmpty ? 'Belum punya usaha' : 'Buka laptop', ['Kelola usaha']),
    HomeSpot.garasi => (
      'Servis ringan · ${formatRupiah(housing.garageServicePrice(game.workshop), prefix: true)}',
      ['Ganti oli', 'Isi angin ban', '−50% harga bengkel'],
    ),
  };

  void _use() {
    if (_sel == HomeSpot.meja) {
      game.openBusiness(null);
      return;
    }
    final result = housing.use(_sel, widget.homeId, needs: game.needs, clock: game.clock, workshop: game.workshop);
    if (result == null) return;
    game.toast.value = result;
    game.save();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFA9D58F),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _plan()),
          SizedBox(width: 300, child: _panel()),
        ],
      ),
    );
  }

  Widget _plan() => LayoutBuilder(
    builder: (context, c) {
      // Denah desain 544×390, diskalakan agar muat.
      final k = (c.maxWidth / 544) < (c.maxHeight / 390) ? c.maxWidth / 544 : c.maxHeight / 390;
      return Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _PlanPainter(kos: isKos, scale: k),
            ),
          ),
          for (final s in _spots)
            Positioned(left: _spotInfo[s]!.x * k, top: _spotInfo[s]!.y * k, child: _spotButton(s)),
          Positioned(
            left: 10,
            top: 10,
            child: GameButton(
              width: 40,
              height: 40,
              radius: 12,
              shadow: 3,
              color: BColors.cream,
              semanticLabel: 'Keluar rumah',
              onTap: game.closeScreen,
              child: const CustomPaint(size: Size(18, 18), painter: _BackPainter()),
            ),
          ),
          Positioned(
            left: 30 * k,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: BColors.ink, borderRadius: BorderRadius.circular(8)),
              child: Text(_title, style: nunito(11, color: BColors.cream)),
            ),
          ),
        ],
      );
    },
  );

  Widget _spotButton(HomeSpot s) {
    final on = s == _sel;
    return Semantics(
      button: true,
      selected: on,
      label: s.label,
      child: GestureDetector(
        onTap: () => setState(() => _sel = s),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: on ? BColors.kuning : BColors.cream,
            border: Border.all(color: BColors.ink, width: 3),
            borderRadius: BorderRadius.circular(15),
            boxShadow: const [BoxShadow(color: BColors.ink, offset: Offset(0, 3))],
          ),
          child: Center(widthFactor: 1, child: Text(s.label, style: nunito(12))),
        ),
      ),
    );
  }

  Widget _panel() {
    final (label, effects) = _action(_sel);
    final canUse = _sel == HomeSpot.meja
        ? game.business.owned.value.isNotEmpty
        : housing.canUse(_sel, clock: game.clock, workshop: game.workshop);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: BColors.cream,
        border: Border(left: BorderSide(color: BColors.ink, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _needsBars(game.needs),
          const SizedBox(height: 8),
          Container(height: 2, color: const Color(0xFFE5D5B8)),
          const SizedBox(height: 8),
          ValueListenableBuilder(
            valueListenable: game.clock.text,
            builder: (context, t, _) => Text(
              '${game.clock.weekday}, hari ke-${game.clock.day.value} · $t',
              style: nunito(11, color: BColors.teksRedup),
            ),
          ),
          Text(_sel.label, style: baloo(21).copyWith(height: 1)),
          const SizedBox(height: 4),
          Text(_spotInfo[_sel]!.desc, style: nunito(12, color: BColors.teksRedup).copyWith(height: 1.35)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in effects)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F2DA),
                    border: Border.all(color: BColors.hijauAksi, width: 2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(e, style: nunito(11, color: const Color(0xFF24572F))),
                ),
            ],
          ),
          const Spacer(),
          GameButton(
            width: double.infinity,
            height: 46,
            radius: 15,
            color: BColors.hijauAksi,
            enabled: canUse,
            onTap: _use,
            child: Text(label, style: baloo(16, color: const Color(0xFFFFFFFF))),
          ),
        ],
      ),
    );
  }

  Widget _needsBars(Needs n) => ListenableBuilder(
    listenable: Listenable.merge([n.energy, n.hunger, n.mood]),
    builder: (context, _) => Column(
      children: [
        _needRow('Energi', n.energy.value, BColors.tosca),
        _needRow('Lapar', n.hunger.value, BColors.oranye),
        _needRow('Mood', n.mood.value, BColors.hijauAksi),
      ],
    ),
  );

  Widget _needRow(String label, double v, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(
      children: [
        SizedBox(width: 52, child: Text(label, style: nunito(12))),
        Expanded(
          child: Container(
            height: 10,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: const Color(0xFFE5D5B8), borderRadius: BorderRadius.circular(5)),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: (v / 100).clamp(0.0, 1.0),
              heightFactor: 1,
              child: ColoredBox(color: color),
            ),
          ),
        ),
        SizedBox(
          width: 30,
          child: Text('${v.round()}', textAlign: TextAlign.right, style: nunito(11)),
        ),
      ],
    ),
  );
}

/// Denah rumah tampak potongan 3/4 (desain HomeLife, disederhanakan).
class _PlanPainter extends CustomPainter {
  const _PlanPainter({required this.kos, required this.scale});

  final bool kos;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(scale);
    Paint p(Color c) => Paint()..color = c;
    Paint grad(Color a, Color b, double y0, double y1) =>
        Paint()..shader = ui.Gradient.linear(Offset(0, y0), Offset(0, y1), [a, b]);

    canvas.drawRect(const Rect.fromLTWH(0, 0, 544, 390), p(const Color(0xFF8FC27A)));
    // Dinding belakang.
    canvas.drawRect(
      const Rect.fromLTWH(16, 18, 190, 72),
      grad(const Color(0xFFF3DFC2), const Color(0xFFE2C8A2), 18, 90),
    );
    canvas.drawRect(
      const Rect.fromLTWH(206, 18, 190, 72),
      grad(const Color(0xFFE3EFE8), const Color(0xFFC9DCD1), 18, 90),
    );
    canvas.drawRect(const Rect.fromLTWH(396, 18, 132, 72), p(const Color(0xFFD5E8EF)));
    // Lantai: kamar kayu, ruang tengah keramik, kamar mandi biru, garasi beton.
    canvas.drawRect(
      const Rect.fromLTWH(16, 90, 190, 250),
      grad(const Color(0xFFC08A5C), const Color(0xFFA9744A), 90, 340),
    );
    final plank = Paint()
      ..color = const Color(0xFF9A673F)
      ..strokeWidth = 1;
    for (var y = 120.0; y < 340; y += 30) {
      canvas.drawLine(Offset(16, y), Offset(206, y), plank);
    }
    canvas.drawRect(const Rect.fromLTWH(206, 90, 190, 250), p(const Color(0xFFECE5D7)));
    final tile = Paint()
      ..color = const Color(0xFFD6CDBB)
      ..strokeWidth = 1;
    for (var y = 122.0; y < 340; y += 32) {
      canvas.drawLine(Offset(206, y), Offset(396, y), tile);
    }
    for (var x = 238.0; x < 396; x += 32) {
      canvas.drawLine(Offset(x, 90), Offset(x, 340), tile);
    }
    canvas.drawRect(const Rect.fromLTWH(396, 90, 132, 110), p(const Color(0xFFC4DEE6)));
    canvas.drawRect(
      const Rect.fromLTWH(396, 200, 132, 140),
      p(kos ? const Color(0xFFCFC5B4) : const Color(0xFFB7B1A6)),
    );

    // Jendela & tirai kamar.
    canvas.drawRect(const Rect.fromLTWH(40, 26, 64, 40), p(const Color(0xFFFFFFFF)));
    canvas.drawRect(const Rect.fromLTWH(44, 30, 56, 32), p(const Color(0xFF86ADC2)));
    // Kasur.
    canvas.drawRect(const Rect.fromLTWH(34, 72, 116, 30), p(const Color(0xFF7A5134)));
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(34, 98, 116, 84), const Radius.circular(6)),
      p(const Color(0xFFF7F4EE)),
    );
    canvas.drawRect(const Rect.fromLTWH(34, 132, 116, 50), p(BColors.atapMerah));
    canvas.drawRect(const Rect.fromLTWH(34, 182, 116, 14), p(const Color(0xFF5E3F25)));
    if (!kos) {
      // Lemari.
      canvas.drawRect(const Rect.fromLTWH(160, 38, 40, 80), p(const Color(0xFF9C6B44)));
      canvas.drawLine(const Offset(180, 40), const Offset(180, 116), Paint()..color = const Color(0xFF5E3F25));
    }
    // Dapur: kompor, wastafel, kulkas.
    canvas.drawRect(const Rect.fromLTWH(216, 56, 120, 10), p(const Color(0xFF7D848C)));
    canvas.drawRect(const Rect.fromLTWH(216, 66, 120, 34), p(const Color(0xFFFFFFFF)));
    canvas.drawRect(const Rect.fromLTWH(344, 30, 42, 72), p(const Color(0xFFE3E9EE)));
    // Sofa & karpet.
    canvas.drawOval(const Rect.fromLTWH(48, 238, 124, 48), p(BColors.kuning.withValues(alpha: 0.55)));
    if (!kos) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(222, 248, 120, 40), const Radius.circular(6)),
        p(const Color(0xFF4CC0D3)),
      );
      // Meja kerja & laptop.
      canvas.drawRect(const Rect.fromLTWH(342, 140, 48, 26), p(const Color(0xFF8B5E3C)));
      canvas.drawRect(const Rect.fromLTWH(354, 120, 24, 16), p(BColors.ink));
      canvas.drawRect(const Rect.fromLTWH(356, 122, 20, 12), p(const Color(0xFF5BB6D9)));
    }
    // Kamar mandi.
    canvas.drawOval(const Rect.fromLTWH(410, 98, 26, 20), p(const Color(0xFFFFFFFF)));
    canvas.drawRect(const Rect.fromLTWH(476, 96, 46, 60), p(const Color(0xFFE8F3F6)));

    // Sekat dinding.
    final wall = p(const Color(0xFFEFE6D8));
    for (final r in const [
      Rect.fromLTWH(16, 18, 10, 334),
      Rect.fromLTWH(518, 18, 10, 334),
      Rect.fromLTWH(201, 18, 10, 226),
      Rect.fromLTWH(201, 296, 10, 56),
      Rect.fromLTWH(391, 18, 10, 122),
      Rect.fromLTWH(391, 178, 10, 174),
      Rect.fromLTWH(396, 196, 132, 8),
      Rect.fromLTWH(16, 14, 512, 6),
    ]) {
      canvas.drawRect(r, wall);
    }
    canvas.drawRect(const Rect.fromLTWH(16, 340, 512, 14), p(const Color(0xFF8A6A4C)));

    // Motor di garasi & pemain di ruang tengah.
    if (!kos) {
      canvas.save();
      canvas.translate(466, 308);
      canvas.scale(0.55);
      drawMotor(canvas, Facing.side, rider: false);
      canvas.restore();
    }
    canvas.save();
    canvas.translate(300, 192);
    canvas.scale(0.42);
    drawWalker(canvas, Facing.down, 0, 0, false);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PlanPainter old) => old.kos != kos || old.scale != scale;
}

class _BackPainter extends CustomPainter {
  const _BackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    canvas.drawPath(
      Path()
        ..moveTo(15 * k, 5 * k)
        ..lineTo(8 * k, 12 * k)
        ..lineTo(15 * k, 19 * k),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * k
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = BColors.ink,
    );
  }

  @override
  bool shouldRepaint(_BackPainter old) => false;
}
