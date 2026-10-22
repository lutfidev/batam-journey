import 'package:flutter/widgets.dart';

import '../../game/batam_game.dart';
import '../palette.dart';
import 'map_draw.dart';

/// Minimap bulat 104 px di kanan atas (layar Main). Ketuk untuk buka peta.
class Minimap extends StatelessWidget {
  const Minimap({super.key, required this.game});

  final BatamGame game;

  /// Piksel minimap per satuan dunia (sama dengan desain: gambar 2400 px).
  static const scale = 0.405;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Minimap, ketuk untuk buka peta',
      child: GestureDetector(
        onTap: game.openMap,
        child: Container(
          width: 104,
          height: 104,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: BColors.laut,
            border: Border.fromBorderSide(BorderSide(color: BColors.ink, width: 4)),
            boxShadow: [BoxShadow(color: BColors.ink, offset: Offset(0, 4))],
          ),
          child: ClipOval(child: CustomPaint(painter: _MinimapPainter(game))),
        ),
      ),
    );
  }
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter(this.game) : super(repaint: game.frame);

  final BatamGame game;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.center(Offset.zero);
    final me = game.playerOffset;
    const s = Minimap.scale;
    drawMapImage(canvas, game.mapImage, game.graph.size, me, s, mid);
    final route = game.gps.route;
    if (route != null) {
      drawRoute(canvas, [for (final p in route.points) mid + (p - me) * s], width: 3);
      drawPin(canvas, mid + (route.points.last - me) * s, BColors.biruPemain, r: 7);
    }
    drawPlayerArrow(canvas, mid, game.heading);
  }

  @override
  bool shouldRepaint(_MinimapPainter old) => false;
}
