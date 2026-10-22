import 'package:flutter/widgets.dart';

import '../../game/actors/player.dart';
import '../../game/batam_game.dart';
import '../../game/systems/economy.dart';
import '../../game/systems/gps.dart';
import '../../game/systems/orders.dart';
import '../map/map_screen.dart';
import '../screens/business_screen.dart';
import '../screens/fuel_screen.dart';
import '../screens/home_screen.dart';
import '../screens/missions_screen.dart';
import '../screens/phone_screen.dart';
import '../screens/property_screen.dart';
import '../screens/story_screen.dart';
import '../screens/workshop_screen.dart';
import '../map/minimap.dart';
import '../palette.dart';
import '../widgets/game_button.dart';
import '../widgets/joystick.dart';

/// HUD di atas game: berganti antara mode jalan kaki (layar OnFoot)
/// dan mode menyetir (layar Main).
class GameHud extends StatelessWidget {
  const GameHud({super.key, required this.game});

  final BatamGame game;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: game.worldReady,
      builder: (context, ready, _) {
        if (!ready) return const _Loading();
        return ValueListenableBuilder(
          valueListenable: game.screen,
          builder: (context, screen, _) => switch (screen) {
            GameScreen.map => _FullScreen(
              color: BColors.laut,
              child: MapScreen(game: game),
            ),
            GameScreen.fuel => _FullScreen(
              color: BColors.tanah,
              leftColor: BColors.aspal,
              child: FuelScreen(game: game),
            ),
            GameScreen.phone => _FullScreen(
              color: _phoneBg,
              child: PhoneScreen(game: game),
            ),
            GameScreen.missions => _FullScreen(
              color: BColors.tanah,
              leftColor: BColors.ink,
              child: MissionsScreen(game: game),
            ),
            GameScreen.workshop => _FullScreen(
              color: BColors.aspal,
              child: WorkshopScreen(game: game),
            ),
            GameScreen.property => _FullScreen(
              color: BColors.tanah,
              leftColor: BColors.cream,
              child: PropertyScreen(game: game, initial: game.screenTarget),
            ),
            GameScreen.home => _FullScreen(
              color: const Color(0xFFA9D58F),
              child: HomeScreen(game: game, homeId: game.screenTarget!),
            ),
            GameScreen.business => _FullScreen(
              color: BColors.tanah,
              leftColor: BColors.ink,
              child: BusinessScreen(game: game, initial: game.screenTarget),
            ),
            GameScreen.story => StoryScreen(event: game.story.value!, onClose: game.closeStory),
            GameScreen.none => SafeArea(
              child: ValueListenableBuilder(
                valueListenable: game.mode,
                builder: (context, mode, _) => Stack(
                  children: [
                    Positioned(top: 10, left: 0, right: 0, child: Center(child: _AreaLabel(game, mode))),
                    Positioned(
                      left: 10,
                      top: 10,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _MoneyBadge(game.money),
                          const SizedBox(height: 6),
                          _OrderOrGpsCard(game),
                          const SizedBox(height: 6),
                          _MissionTracker(game),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            children: [
                              _PhoneButton(game),
                              const SizedBox(height: 8),
                              GameButton(
                                width: 44,
                                height: 44,
                                radius: 14,
                                shadow: 3,
                                color: BColors.oranye,
                                semanticLabel: 'Buka peta',
                                onTap: game.openMap,
                                child: const CustomPaint(size: Size(22, 22), painter: _MapIcon()),
                              ),
                            ],
                          ),
                          const SizedBox(width: 8),
                          Minimap(game: game),
                        ],
                      ),
                    ),
                    Positioned(top: 62, left: 0, right: 0, child: Center(child: _Toast(game.toast))),
                    if (mode == PlayerMode.walking) ..._walking() else ..._riding(),
                  ],
                ),
              ),
            ),
          },
        );
      },
    );
  }

  List<Widget> _walking() => [
    Positioned(left: 20, bottom: 20, child: Joystick(onChanged: (v) => game.controls.stick.setValues(v.dx, v.dy))),
    Positioned(left: 0, right: 0, bottom: 14, child: Center(child: _HintCard(game))),
    Positioned(
      right: 14,
      bottom: 14,
      child: ValueListenableBuilder(
        valueListenable: game.motorDistanceM,
        builder: (context, _, _) => Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _RefuelButton(game, width: 94, height: 50),
            const SizedBox(width: 10),
            GameButton(
              width: 94,
              height: 50,
              color: game.canBoard ? BColors.hijauAksi : BColors.cream,
              enabled: game.canBoard,
              onTap: game.toggleRide,
              child: Text(
                'Naik Motor',
                textAlign: TextAlign.center,
                style: baloo(15, color: game.canBoard ? BColors.cream : BColors.ink),
              ),
            ),
          ],
        ),
      ),
    ),
  ];

  List<Widget> _riding() {
    final c = game.controls;
    return [
      Positioned(
        left: 20,
        bottom: 20,
        child: Joystick(label: 'Joystick setir', onChanged: (v) => c.stick.setValues(v.dx, v.dy)),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 10,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ValueListenableBuilder(
                valueListenable: game.speedKmh,
                builder: (context, _, _) => _RefuelButton(game, width: 100, height: 46, trailingGap: 10),
              ),
              _Speedometer(game.speedKmh, game.tank),
              const SizedBox(width: 10),
              ValueListenableBuilder(
                valueListenable: game.speedKmh,
                builder: (context, kmh, _) => GameButton(
                  width: 82,
                  height: 46,
                  color: BColors.cream,
                  enabled: kmh <= 5,
                  onTap: game.toggleRide,
                  child: Text('Turun', style: baloo(15)),
                ),
              ),
            ],
          ),
        ),
      ),
      Positioned(
        right: 12,
        bottom: 12,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            GameButton(
              width: 60,
              height: 60,
              radius: 30,
              color: BColors.atapMerah,
              semanticLabel: 'Rem',
              onHold: (v) => c.brakeBtn = v,
              child: Text('REM', style: baloo(15, color: const Color(0xFFFFFFFF))),
            ),
            const SizedBox(width: 10),
            GameButton(
              width: 80,
              height: 80,
              radius: 40,
              color: BColors.hijauAksi,
              semanticLabel: 'Gas',
              onHold: (v) => c.gasBtn = v,
              child: Text('GAS', style: baloo(20, color: const Color(0xFFFFFFFF))),
            ),
          ],
        ),
      ),
    ];
  }
}

const _phoneBg = Color(0xFF3A4656);

/// Layar penuh: latar diwarnai sampai ke tepi layar (termasuk area potongan
/// kamera), isinya tetap di dalam area aman.
class _FullScreen extends StatelessWidget {
  const _FullScreen({required this.color, required this.child, this.leftColor});

  final Color color;

  /// Warna khusus untuk sisi kiri, bila panel kiri layar berbeda warna.
  final Color? leftColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: color)),
        if (leftColor != null)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: pad.left,
            child: ColoredBox(color: leftColor!),
          ),
        SafeArea(child: child),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: BColors.cream,
      child: Center(child: Text('Memuat peta Batam…', style: baloo(22))),
    );
  }
}

class _MoneyBadge extends StatelessWidget {
  const _MoneyBadge(this.money);

  final ValueNotifier<int> money;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
      decoration: _panel(14, shadow: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: BColors.hijauAksi, shape: BoxShape.circle),
            child: Text('Rp', style: baloo(13, color: const Color(0xFFFFFFFF))),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder(
            valueListenable: money,
            builder: (context, v, _) => Text(formatRupiah(v), style: baloo(18)),
          ),
        ],
      ),
    );
  }
}

class _AreaLabel extends StatelessWidget {
  const _AreaLabel(this.game, this.mode);

  final BatamGame game;
  final PlayerMode mode;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
          decoration: BoxDecoration(color: BColors.ink, borderRadius: BorderRadius.circular(12)),
          child: ValueListenableBuilder(
            valueListenable: game.areaName,
            builder: (context, area, _) =>
                Text(mode == PlayerMode.walking ? '$area · Jalan kaki' : area, style: baloo(15, color: BColors.cream)),
          ),
        ),
        ListenableBuilder(
          listenable: Listenable.merge([game.roadName, game.clock.text]),
          builder: (context, _) {
            final road = mode == PlayerMode.riding ? game.roadName.value : null;
            final line = [road ?? game.clock.weekday, game.clock.text.value].join(' · ');
            return Container(
              margin: const EdgeInsets.only(top: 3),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
              decoration: BoxDecoration(
                color: BColors.cream.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(line, style: nunito(11)),
            );
          },
        ),
      ],
    );
  }
}

class _GpsCard extends StatelessWidget {
  const _GpsCard(this.gps);

  final Gps gps;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: gps.info,
      builder: (context, info, _) {
        if (info == null) return const SizedBox.shrink();
        return Container(
          width: 200,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: _panel(14, shadow: 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(color: BColors.biruPemain, borderRadius: BorderRadius.circular(6)),
                child: Text('GPS', style: nunito(10, color: const Color(0xFFFFFFFF)).copyWith(letterSpacing: 0.4)),
              ),
              const SizedBox(height: 2),
              Text(info.title, style: baloo(14), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                '${formatDistance(info.remaining)} · ${info.instruction}',
                style: nunito(11, color: BColors.teksRedup),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Pesan singkat (mis. sampai tujuan) yang hilang sendiri.
class _Toast extends StatefulWidget {
  const _Toast(this.message);

  final ValueNotifier<String?> message;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> {
  @override
  void initState() {
    super.initState();
    widget.message.addListener(_onMessage);
  }

  @override
  void dispose() {
    widget.message.removeListener(_onMessage);
    super.dispose();
  }

  void _onMessage() {
    setState(() {});
    if (widget.message.value != null) {
      Future.delayed(const Duration(seconds: 3), () => widget.message.value = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.message.value;
    if (text == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: BColors.hijauAksi,
        border: Border.all(color: BColors.ink, width: 3),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: BColors.ink, offset: Offset(0, 3))],
      ),
      child: Text(text, style: baloo(16, color: const Color(0xFFFFFFFF))),
    );
  }
}

/// Kartu kiri atas: order aktif (desain Main) atau GPS biasa.
class _OrderOrGpsCard extends StatelessWidget {
  const _OrderOrGpsCard(this.game);

  final BatamGame game;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: game.orders.active,
      builder: (context, order, _) => order == null ? _GpsCard(game.gps) : _OrderCard(game, order),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard(this.game, this.order);

  final BatamGame game;
  final ActiveOrder order;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: _panel(14, shadow: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(color: BColors.tosca, borderRadius: BorderRadius.circular(6)),
                child: Text(
                  'ORDER AKTIF',
                  style: nunito(10, color: const Color(0xFFFFFFFF)).copyWith(letterSpacing: 0.4),
                ),
              ),
              if (order.order.pay > 0)
                Text(
                  '+${formatRupiah(order.order.pay, prefix: true)}',
                  style: nunito(12, color: const Color(0xFF2F7A45)),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(order.headline, style: baloo(14).copyWith(height: 1.15), maxLines: 2, overflow: TextOverflow.ellipsis),
          ValueListenableBuilder(
            valueListenable: game.orders.secondsLeft,
            builder: (context, secs, _) => ValueListenableBuilder(
              valueListenable: game.gps.info,
              builder: (context, info, _) {
                final mmss = '${(secs ~/ 60).toString().padLeft(2, '0')}:${(secs % 60).toString().padLeft(2, '0')}';
                final parts = [
                  if (info != null) formatDistance(info.remaining),
                  'sisa $mmss',
                  if (info != null) info.instruction,
                ];
                return Text(
                  parts.join(' · '),
                  style: nunito(11, color: secs < 30 ? BColors.atapMerah : BColors.teksRedup),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Pil misi aktif di kiri atas; ketuk untuk buka "Kisah Hidupmu".
class _MissionTracker extends StatelessWidget {
  const _MissionTracker(this.game);

  final BatamGame game;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([game.stats.missionsDone, game.orders.ordersDone, game.orders.active]),
      builder: (context, _) {
        final m = game.missions.tracked;
        final progress = m == null ? '' : game.missions.progress(m);
        return Semantics(
          button: true,
          label: 'Buka misi',
          child: GestureDetector(
            onTap: () => game.open(GameScreen.missions),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 200),
              padding: const EdgeInsets.fromLTRB(4, 3, 10, 3),
              decoration: BoxDecoration(
                color: BColors.cream.withValues(alpha: 0.95),
                border: Border.all(color: BColors.ink, width: 2),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: BColors.ink, offset: Offset(0, 2))],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: BColors.kuning, borderRadius: BorderRadius.circular(8)),
                    child: Text('MISI', style: nunito(10)),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      m == null ? 'Bab 3 segera hadir' : [m.title, progress].where((s) => s.isNotEmpty).join(' · '),
                      style: nunito(11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Tombol HP (tosca) dengan titik notifikasi bila ada order baru.
class _PhoneButton extends StatelessWidget {
  const _PhoneButton(this.game);

  final BatamGame game;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: game.orders.active,
      builder: (context, active, _) => Stack(
        clipBehavior: Clip.none,
        children: [
          GameButton(
            width: 44,
            height: 44,
            radius: 14,
            shadow: 3,
            color: BColors.tosca,
            semanticLabel: 'Buka HP',
            onTap: () => game.open(GameScreen.phone),
            child: const CustomPaint(size: Size(22, 22), painter: _PhoneIcon()),
          ),
          if (active == null)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: BColors.atapMerah,
                  shape: BoxShape.circle,
                  border: Border.all(color: BColors.ink, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Isi Bensin" / "Bengkel" — hanya muncul di dekat SPBU atau bengkel.
class _RefuelButton extends StatelessWidget {
  const _RefuelButton(this.game, {required this.width, required this.height, this.trailingGap = 0});

  final BatamGame game;
  final double width, height, trailingGap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        game.nearStation,
        game.nearWorkshop,
        game.nearHouse,
        game.nearBusiness,
        game.housing.owned,
        game.housing.kosRented,
        game.business.owned,
      ]),
      builder: (context, _) {
        final Widget button;
        if (game.nearStation.value != null) {
          button = GameButton(
            width: width,
            height: height,
            color: BColors.kuning,
            enabled: game.canRefuel,
            onTap: () => game.open(GameScreen.fuel),
            child: Text('Isi Bensin', textAlign: TextAlign.center, style: baloo(15)),
          );
        } else if (game.nearWorkshop.value != null) {
          button = GameButton(
            width: width,
            height: height,
            color: BColors.oranye,
            enabled: game.canEnterWorkshop,
            onTap: () => game.open(GameScreen.workshop),
            child: Text('Bengkel', textAlign: TextAlign.center, style: baloo(15)),
          );
        } else if (game.nearHouse.value case final h? when game.housing.isHome(h.homeId)) {
          button = GameButton(
            width: width,
            height: height,
            color: BColors.hijauAksi,
            enabled: game.motor.speedKmh <= 5,
            onTap: () => game.openHome(h.homeId),
            child: Text(
              'Masuk',
              textAlign: TextAlign.center,
              style: baloo(15, color: BColors.cream),
            ),
          );
        } else if (game.nearBusiness.value case final b?) {
          final owned = game.business.owns(b.type.id);
          button = GameButton(
            width: width,
            height: height,
            color: owned ? BColors.hijauAksi : BColors.cream,
            enabled: game.motor.speedKmh <= 5,
            onTap: () => game.openBusiness(b.type.id),
            child: Text(
              owned ? 'Usahaku' : 'Lihat Usaha',
              textAlign: TextAlign.center,
              style: baloo(15, color: owned ? BColors.cream : BColors.ink),
            ),
          );
        } else if (game.nearHouse.value case final h? when !h.isKos) {
          button = GameButton(
            width: width,
            height: height,
            color: BColors.cream,
            enabled: game.motor.speedKmh <= 5,
            onTap: () => game.openProperty(h.homeId),
            child: Text('Lihat Rumah', textAlign: TextAlign.center, style: baloo(15)),
          );
        } else {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: EdgeInsets.only(right: trailingGap),
          child: button,
        );
      },
    );
  }
}

class _PhoneIcon extends CustomPainter {
  const _PhoneIcon();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFFFFFF);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(6, 2, 12, 20), const Radius.circular(3)), p);
    canvas.drawLine(const Offset(11, 18), const Offset(13, 18), p);
  }

  @override
  bool shouldRepaint(_PhoneIcon old) => false;
}

class _HintCard extends StatelessWidget {
  const _HintCard(this.game);

  final BatamGame game;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        game.motorDistanceM,
        game.nearStation,
        game.nearWorkshop,
        game.nearHouse,
        game.nearBusiness,
        game.orders.active,
        game.orders.ordersDone,
      ]),
      builder: (context, _) => Container(
        width: 300,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: _panel(14, shadow: 3),
        child: Text(_hint(game.motorDistanceM.value), textAlign: TextAlign.center, style: nunito(12)),
      ),
    );
  }

  String _hint(int motorM) {
    final station = game.nearStation.value;
    if (station != null) return 'SPBU BensinKu ${station.area}. Isi bensin dulu sebelum narik!';
    final ws = game.nearWorkshop.value;
    if (ws != null) return '${ws.name}. Cek kondisi motor dan pasang modifikasi di sini.';
    final shop = game.nearBusiness.value;
    if (shop != null) {
      if (game.business.owns(shop.type.id)) return '${shop.type.name} milikmu. Cek untung, stok, dan pesanan besar.';
      if (shop.type.locked) return '${shop.type.name}: segera hadir.';
      return '${shop.type.name} disewakan. Modal ${formatRupiah(shop.type.capital, prefix: true)}.';
    }
    final house = game.nearHouse.value;
    if (house != null) {
      if (game.housing.isHome(house.homeId)) return 'Rumahmu. Masuk untuk tidur, masak, dan mandi.';
      if (house.isKos) return 'Kos Bu Ros. Selesaikan misi "Cari kos di Bengkong" untuk menyewa kamar.';
      return '${house.title} dijual. Lihat harga dan pilihan cicilannya.';
    }
    if (!game.orders.hasActive && game.orders.ordersDone.value == 0) {
      return 'Ada order pertama! Buka HP (tombol biru) › OjekKita, lalu ambil ordernya.';
    }
    if (game.canBoard) return 'Motor di sebelahmu. Tekan Naik Motor untuk berangkat!';
    return 'Motor terparkir $motorM m. Hati-hati, parkir liar bisa diderek!';
  }
}

class _Speedometer extends StatelessWidget {
  const _Speedometer(this.kmh, this.tank);

  final ValueNotifier<int> kmh;
  final FuelTank tank;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 108,
      padding: const EdgeInsets.fromLTRB(10, 5, 10, 7),
      decoration: BoxDecoration(
        color: BColors.ink,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0xFF000000), offset: Offset(0, 3))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              ValueListenableBuilder(
                valueListenable: kmh,
                builder: (context, v, _) => Text('$v', style: baloo(28, color: BColors.cream)),
              ),
              const SizedBox(width: 4),
              Text('km/j', style: nunito(11, color: BColors.cream)),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              const CustomPaint(size: Size(14, 14), painter: _FuelIcon()),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  height: 8,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(color: BColors.bensinTrack, borderRadius: BorderRadius.circular(4)),
                  alignment: Alignment.centerLeft,
                  child: ValueListenableBuilder(
                    valueListenable: tank.liters,
                    builder: (context, _, _) => FractionallySizedBox(
                      widthFactor: tank.fraction.clamp(0.0, 1.0),
                      heightFactor: 1,
                      child: ColoredBox(color: tank.isLow ? BColors.atapMerah : BColors.kuning),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MapIcon extends CustomPainter {
  const _MapIcon();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final p = Path()
      ..moveTo(3, 6)
      ..lineTo(9, 3)
      ..lineTo(15, 6)
      ..lineTo(21, 3)
      ..lineTo(21, 18)
      ..lineTo(15, 21)
      ..lineTo(9, 18)
      ..lineTo(3, 21)
      ..close()
      ..moveTo(9, 3)
      ..lineTo(9, 18)
      ..moveTo(15, 6)
      ..lineTo(15, 21);
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFFFFFFF),
    );
  }

  @override
  bool shouldRepaint(_MapIcon old) => false;
}

class _FuelIcon extends CustomPainter {
  const _FuelIcon();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    canvas.scale(s);
    final p = Path()
      ..moveTo(4, 21)
      ..lineTo(4, 5)
      ..arcToPoint(const Offset(6, 3), radius: const Radius.circular(2))
      ..lineTo(12, 3)
      ..arcToPoint(const Offset(14, 5), radius: const Radius.circular(2))
      ..lineTo(14, 21)
      ..moveTo(3, 21)
      ..lineTo(15, 21)
      ..moveTo(14, 9)
      ..lineTo(16, 9)
      ..arcToPoint(const Offset(18, 11), radius: const Radius.circular(2))
      ..lineTo(18, 16)
      ..arcToPoint(const Offset(21, 16), radius: const Radius.circular(1.5), clockwise: false)
      ..lineTo(21, 8)
      ..lineTo(18, 5);
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round
        ..color = BColors.kuning,
    );
  }

  @override
  bool shouldRepaint(_FuelIcon old) => false;
}

BoxDecoration _panel(double radius, {double shadow = 4}) => BoxDecoration(
  color: BColors.cream,
  border: Border.all(color: BColors.ink, width: 3),
  borderRadius: BorderRadius.circular(radius),
  boxShadow: [BoxShadow(color: BColors.ink, offset: Offset(0, shadow))],
);
