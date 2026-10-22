import 'package:flutter/widgets.dart';

import '../../game/batam_game.dart';
import '../../game/systems/gps.dart';
import '../../game/systems/missions.dart';
import '../palette.dart';
import '../widgets/game_button.dart';

/// Layar "Kisah Hidupmu" (desain LifeMissions): bab, daftar misi, detail.
class MissionsScreen extends StatefulWidget {
  const MissionsScreen({super.key, required this.game});

  final BatamGame game;

  @override
  State<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends State<MissionsScreen> {
  late int _chapter = widget.game.missions.chapter.clamp(1, 2);
  late Mission? _selected = _list.isEmpty ? null : _list.first;

  MissionSystem get sys => widget.game.missions;

  List<Mission> get _list {
    final list = sys.missions.where((m) => m.chapter == _chapter).toList();
    // Yang masih bisa dikerjakan di atas, yang selesai di bawah.
    list.sort((a, b) => (sys.isDone(a) ? 1 : 0).compareTo(sys.isDone(b) ? 1 : 0));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: BColors.tanah,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 210, child: _chapters()),
          Expanded(child: _missions()),
          SizedBox(width: 240, child: _detail()),
        ],
      ),
    );
  }

  Widget _chapters() {
    final current = sys.chapter;
    return Container(
      color: BColors.ink,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Semantics(
                button: true,
                label: 'Kembali',
                child: GestureDetector(
                  onTap: widget.game.closeScreen,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      border: Border.all(color: BColors.cream, width: 2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const CustomPaint(painter: _BackPainter()),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('Kisah Hidupmu', style: baloo(20, color: BColors.cream).copyWith(height: 1)),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < chapters.length; i++) _chapterRow(i + 1, chapters[i], current),
          const Spacer(),
          ValueListenableBuilder(
            valueListenable: widget.game.stats.reputation,
            builder: (context, rep, _) => Text('Reputasi: $rep', style: nunito(12, color: const Color(0xFFBFAE93))),
          ),
        ],
      ),
    );
  }

  Widget _chapterRow(int n, Chapter c, int current) {
    final done = n < current;
    final now = n == current;
    final locked = n > current || n > 2;
    final viewing = n == _chapter;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: locked
            ? null
            : () => setState(() {
                _chapter = n;
                _selected = _list.isEmpty ? null : _list.first;
              }),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? BColors.hijauAksi : (now && !locked ? BColors.kuning : null),
                border: Border.all(
                  color: locked ? const Color(0xFF6B5440) : (viewing ? BColors.kuning : BColors.cream),
                  width: 2,
                ),
              ),
              child: done
                  ? const CustomPaint(size: Size(14, 14), painter: _CheckPainter())
                  : Text('$n', style: baloo(13, color: now && !locked ? BColors.ink : const Color(0xFFBFAE93))),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.title,
                    style: nunito(13, color: locked ? const Color(0xFFBFAE93) : BColors.cream).copyWith(height: 1.15),
                  ),
                  Text(c.goal, style: nunito(11, color: const Color(0xFFBFAE93))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _missions() => ListView(
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
    children: [for (final m in _list) Padding(padding: const EdgeInsets.only(bottom: 8), child: _missionCard(m))],
  );

  Widget _missionCard(Mission m) {
    final sel = _selected?.id == m.id;
    final done = sys.isDone(m);
    final locked = !done && !sys.isAvailable(m);
    final right = done ? 'Selesai' : (locked ? 'Terkunci' : sys.progress(m));
    return Semantics(
      button: true,
      selected: sel,
      child: GestureDetector(
        onTap: () => setState(() => _selected = m),
        child: Opacity(
          opacity: done || locked ? 0.6 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? const Color(0xFFFFFFFF) : BColors.cream,
              border: Border.all(color: sel ? BColors.ink : const Color(0xFFE5D5B8), width: 3),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: m.color, borderRadius: BorderRadius.circular(10)),
                  child: Text(m.icon, style: baloo(16, color: const Color(0xFFFFFFFF))),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.title, style: nunito(13).copyWith(height: 1.2)),
                      Text(m.sub, style: nunito(11, color: BColors.teksRedup)),
                    ],
                  ),
                ),
                if (right.isNotEmpty) Text(right, style: nunito(11, color: BColors.teksRedup)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detail() {
    final m = _selected;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: BColors.cream,
        border: Border(left: BorderSide(color: BColors.ink, width: 4)),
      ),
      child: m == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(m.kindLabel, style: nunito(11, color: const Color(0xFF6B5440)).copyWith(letterSpacing: 0.7)),
                const SizedBox(height: 6),
                Text(m.title, style: baloo(19).copyWith(height: 1.1)),
                const SizedBox(height: 6),
                Text(m.story, style: nunito(12, color: BColors.teksRedup).copyWith(height: 1.35)),
                const SizedBox(height: 8),
                if (m.rewards.isNotEmpty) ...[
                  Text('HADIAH', style: nunito(11, color: const Color(0xFF6B5440))),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final r in m.rewards)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFFFF),
                            border: Border.all(color: const Color(0xFFE5D5B8), width: 2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(r, style: nunito(11)),
                        ),
                    ],
                  ),
                ],
                const Spacer(),
                _action(m),
              ],
            ),
    );
  }

  Widget _action(Mission m) {
    final game = widget.game;
    String label;
    VoidCallback? onTap;
    if (sys.isDone(m)) {
      label = 'Selesai';
    } else if (!sys.isAvailable(m)) {
      label = 'Terkunci';
    } else {
      switch (m.goal) {
        case MissionGoal.board:
          label = 'Naik motormu';
        case MissionGoal.buyFuel:
          label = 'Tandai SPBU';
          onTap = () => _mark(game.nearestStationDestination());
        case MissionGoal.orders:
          label = 'Buka OjekKita';
          onTap = () => game.open(GameScreen.phone);
        case MissionGoal.visit:
        case MissionGoal.pay:
          label = 'Tandai di Peta';
          onTap = () => _mark(m.place);
        case MissionGoal.storyOrder:
          final busy = game.orders.hasActive;
          label = busy ? 'Selesaikan order dulu' : 'Mulai Order Cerita';
          if (!busy) {
            onTap = () {
              if (sys.startStory(m, game.playerOffset)) game.closeScreen();
            };
          }
      }
    }
    return GameButton(
      width: double.infinity,
      height: 46,
      radius: 15,
      color: BColors.biruPemain,
      enabled: onTap != null,
      onTap: onTap,
      child: Text(label, style: baloo(16, color: const Color(0xFFFFFFFF))),
    );
  }

  void _mark(Destination? dest) {
    final game = widget.game;
    if (dest == null) return;
    final route = game.gps.plan(game.playerOffset, dest.position);
    if (route == null) {
      game.toast.value = 'Rute tidak ditemukan';
      return;
    }
    game.gps.start(dest, route);
    game.closeScreen();
  }
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

class _CheckPainter extends CustomPainter {
  const _CheckPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.15, size.height * 0.55)
        ..lineTo(size.width * 0.42, size.height * 0.8)
        ..lineTo(size.width * 0.88, size.height * 0.22),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.18
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFFFFFFF),
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => false;
}
