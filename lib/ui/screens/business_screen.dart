import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../game/batam_game.dart';
import '../../game/systems/business.dart';
import '../../game/systems/clock.dart';
import '../../game/systems/economy.dart';
import '../palette.dart';
import '../widgets/game_button.dart';
import 'property_screen.dart' show formatShortRupiah;

/// Layar "Usahaku" (desain Business).
class BusinessScreen extends StatefulWidget {
  const BusinessScreen({super.key, required this.game, this.initial});

  final BatamGame game;
  final String? initial;

  @override
  State<BusinessScreen> createState() => _BusinessScreenState();
}

class _BusinessScreenState extends State<BusinessScreen> {
  late BizType _sel = bizTypes.firstWhere(
    (b) => b.id == widget.initial,
    orElse: () => bizTypes.firstWhere((b) => widget.game.business.owns(b.id), orElse: () => bizTypes.first),
  );

  BatamGame get game => widget.game;
  BusinessSystem get biz => game.business;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: biz.owned,
      builder: (context, _, _) {
        final owned = biz.get(_sel.id);
        return ColoredBox(
          color: BColors.tanah,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 200, child: _list()),
              Expanded(child: owned == null ? _opportunity(_sel) : _dashboard(owned)),
            ],
          ),
        );
      },
    );
  }

  // ---- Kiri ----

  Widget _list() => Container(
    color: BColors.ink,
    padding: const EdgeInsets.all(12),
    child: ListView(
      children: [
        Row(
          children: [
            Semantics(
              button: true,
              label: 'Kembali',
              child: GestureDetector(
                onTap: game.closeScreen,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    border: Border.all(color: BColors.cream, width: 2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const CustomPaint(painter: _BackPainter()),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('Usahaku', style: baloo(19, color: BColors.cream).copyWith(height: 1)),
          ],
        ),
        const SizedBox(height: 8),
        for (final t in bizTypes) _listItem(t),
      ],
    ),
  );

  Widget _listItem(BizType t) {
    final sel = t.id == _sel.id;
    final owned = biz.owns(t.id);
    final (status, color) = owned
        ? ('${t.area} · Buka', const Color(0xFF2F7A45))
        : t.locked
        ? ('Terkunci', const Color(0xFFB23A26))
        : ('${t.area} · Tersedia', const Color(0xFFB5651D));
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Semantics(
        button: true,
        selected: sel,
        child: GestureDetector(
          onTap: () => setState(() => _sel = t),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: sel ? BColors.cream : const Color(0xFFE5D5B8),
              border: Border.all(color: sel ? BColors.kuning : const Color(0xFFE5D5B8), width: 3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.name, style: nunito(13).copyWith(height: 1.15)),
                Text(status, style: nunito(11, color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- Belum dimiliki ----

  Widget _opportunity(BizType t) {
    final canPay = game.wallet.canPay(t.capital);
    final repOk = game.stats.reputation.value >= t.requiredReputation;
    final String cta;
    if (t.locked) {
      cta = 'Terkunci · Reputasi ${t.requiredReputation}';
    } else if (!canPay) {
      cta = 'Modal kurang · ${formatShortRupiah(t.capital)}';
    } else {
      cta = 'Buka usaha · ${formatShortRupiah(t.capital)}';
    }
    final facts = t.locked
        ? ['Butuh reputasi ${t.requiredReputation}', 'Butuh 2 kendaraan', 'Segera hadir']
        : [
            'Modal ${formatShortRupiah(t.capital)}',
            'Untung ±${formatShortRupiah(t.estimatedProfit)}/hari',
            'Belanja bahan rutin',
          ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PELUANG USAHA', style: nunito(11, color: const Color(0xFF6B5440)).copyWith(letterSpacing: 0.7)),
          const SizedBox(height: 6),
          Text(t.name, style: baloo(26).copyWith(height: 1)),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(t.desc, style: nunito(13, color: BColors.teksRedup).copyWith(height: 1.4)),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final f in facts) _chip(f)]),
          const Spacer(),
          GameButton(
            width: 260,
            height: 48,
            color: t.locked ? const Color(0xFF6B5440) : BColors.hijauAksi,
            enabled: !t.locked && canPay && repOk,
            onTap: () {
              if (biz.open(t)) {
                game.toast.value = '${t.name} di ${t.area} resmi buka!';
                game.save();
              }
            },
            child: Text(cta, style: baloo(17, color: const Color(0xFFFFFFFF))),
          ),
        ],
      ),
    );
  }

  // ---- Dimiliki ----

  Widget _dashboard(OwnedBiz b) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _profitCard(b)),
              const SizedBox(width: 10),
              Expanded(child: _stockCard(b)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _bigOrderCard(b)),
              const SizedBox(width: 10),
              Expanded(child: _upgradeCard(b)),
            ],
          ),
        ),
      ],
    ),
  );

  BoxDecoration _card({Color color = BColors.cream}) => BoxDecoration(
    color: color,
    border: Border.all(color: BColors.ink, width: 3),
    borderRadius: BorderRadius.circular(14),
  );

  Text _label(String s) => Text(s, style: nunito(12, color: const Color(0xFF6B5440)));

  Widget _profitCard(OwnedBiz b) {
    final h = b.history;
    final maxV = h.isEmpty ? 1 : math.max(1, h.map((v) => v.abs()).reduce(math.max));
    final today = game.clock.day.value;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              _label('UNTUNG 7 HARI'),
              Text(
                formatShortRupiah(b.weekProfit),
                style: baloo(18, color: b.weekProfit >= 0 ? const Color(0xFF2F7A45) : const Color(0xFFB23A26)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: h.isEmpty
                ? Center(
                    child: Text(
                      'Untung pertama dihitung besok pagi.',
                      style: nunito(11, color: BColors.teksRedup),
                      textAlign: TextAlign.center,
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, c) => Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < h.length; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Container(
                                  height: math.max(3, (c.maxHeight - 16) * h[i].abs() / maxV),
                                  decoration: BoxDecoration(
                                    color: h[i] < 0
                                        ? BColors.atapMerah
                                        : (i == h.length - 1 ? BColors.oranye : BColors.hijauAksi),
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                  ),
                                ),
                                Text(
                                  GameClock.weekdayOf(today - (h.length - i)).substring(0, 3),
                                  style: nunito(10).copyWith(height: 1.2),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  static const _stockColors = [Color(0xFF8B5E3C), BColors.atapMerah, BColors.oranye];

  Widget _stockCard(OwnedBiz b) {
    final supplier = b.restockPrice;
    final self = biz.selfShopPrice(b.type.id);
    final busy = game.orders.hasActive;
    final keys = b.type.stock.keys.toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label('STOK BAHAN'),
          const SizedBox(height: 4),
          for (var i = 0; i < keys.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  SizedBox(width: 70, child: Text(keys[i], style: nunito(12))),
                  Expanded(
                    child: Container(
                      height: 9,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(color: const Color(0xFFE5D5B8), borderRadius: BorderRadius.circular(5)),
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: ((b.stock[keys[i]] ?? 0) / 100).clamp(0.0, 1.0),
                        heightFactor: 1,
                        child: ColoredBox(
                          color: (b.stock[keys[i]] ?? 0) < 25 ? BColors.atapMerah : _stockColors[i % 3],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: _smallButton(
                  supplier == 0 ? 'Stok penuh' : 'Supplier · ${_compact(supplier)}',
                  BColors.cream,
                  supplier > 0 && game.wallet.canPay(supplier)
                      ? () {
                          if (biz.restockSupplier(b.type.id)) {
                            game.toast.value = 'Supplier mengantar bahan ke ${b.type.name}';
                            game.save();
                          }
                        }
                      : null,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _smallButton(
                  busy ? 'Ada order aktif' : 'Belanja −30%',
                  BColors.kuning,
                  self > 0 && !busy && game.wallet.canPay(self)
                      ? () {
                          if (game.startShopping(b.type.id)) game.closeScreen();
                        }
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bigOrderCard(OwnedBiz b) {
    final o = b.bigOrder;
    final hasBox = game.workshop.hasMod('box45') || game.workshop.hasMod('rak');
    final busy = game.orders.hasActive;
    final first = b.type.stock.keys.first;
    final enoughStock = (b.stock[first] ?? 0) >= 25;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: _card(color: const Color(0xFFFFFFFF)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(color: const Color(0xFF7B5EA7), borderRadius: BorderRadius.circular(6)),
            child: Text(
              'PESANAN BESAR',
              style: nunito(10, color: const Color(0xFFFFFFFF)).copyWith(letterSpacing: 0.4),
            ),
          ),
          const SizedBox(height: 4),
          if (o == null)
            Text('Belum ada pesanan besar. Biasanya datang pagi hari.', style: nunito(12, color: BColors.teksRedup))
          else ...[
            Text(o.title, style: baloo(15).copyWith(height: 1.15)),
            Text(
              hasBox ? 'Pakai 25% $first · box delivery terpasang' : 'Butuh box delivery (pasang di bengkel)',
              style: nunito(11, color: hasBox ? BColors.teksRedup : const Color(0xFFB23A26)),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(formatRupiah(o.pay, prefix: true), style: baloo(16, color: const Color(0xFF2F7A45))),
                _smallButton(
                  busy ? 'Ada order' : (enoughStock ? 'Terima' : 'Stok kurang'),
                  BColors.hijauAksi,
                  hasBox && !busy && enoughStock
                      ? () {
                          if (game.startBigOrder(b.type.id)) game.closeScreen();
                        }
                      : null,
                  light: true,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _upgradeCard(OwnedBiz b) => Container(
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
    decoration: _card(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_label('UPGRADE'), const SizedBox(height: 4), for (final u in b.type.upgrades) _upgradeRow(b, u)],
    ),
  );

  Widget _upgradeRow(OwnedBiz b, BizUpgrade u) {
    final done = u.kind == UpgradeKind.promo ? b.promoDays > 0 : b.upgrades.contains(u.kind);
    final label = done
        ? (u.kind == UpgradeKind.promo ? 'Sisa ${b.promoDays} hari' : 'Terpasang')
        : formatShortRupiah(u.price);
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(u.name, style: nunito(12).copyWith(height: 1.15)),
                Text(u.effect, style: nunito(10, color: BColors.teksRedup)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _smallButton(
            label,
            done ? const Color(0xFFE5D5B8) : BColors.kuning,
            !done && game.wallet.canPay(u.price)
                ? () {
                    if (biz.buyUpgrade(b.type.id, u)) {
                      game.toast.value = '${u.name}: ${u.effect}';
                      game.save();
                    }
                  }
                : null,
          ),
        ],
      ),
    );
  }

  /// "232rb" / "Rp 1,5 jt" — muat di tombol kecil.
  String _compact(int v) => v < 1000000 ? '${(v / 1000).round()}rb' : formatShortRupiah(v);

  Widget _chip(String s) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFFFF),
      border: Border.all(color: const Color(0xFFE5D5B8), width: 2),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(s, style: nunito(12)),
  );

  Widget _smallButton(String label, Color bg, VoidCallback? onTap, {bool light = false}) => Semantics(
    button: true,
    enabled: onTap != null,
    child: GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.55 : 1,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: BColors.ink, width: 2),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: nunito(11, color: light ? const Color(0xFFFFFFFF) : BColors.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
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
        ..color = BColors.cream,
    );
  }

  @override
  bool shouldRepaint(_BackPainter old) => false;
}
