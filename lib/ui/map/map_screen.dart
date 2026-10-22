import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../game/batam_game.dart';
import '../../game/map/pathfinder.dart';
import '../../game/map/road_graph.dart';
import '../../game/systems/gps.dart';
import '../palette.dart';
import '../widgets/game_button.dart';
import 'map_draw.dart';

/// Layar "Peta Batam": geser/cubit untuk menjelajah, ketuk pin atau jalan
/// untuk memilih tujuan, lalu "Pasang Rute GPS".
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.game});

  final BatamGame game;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _panelWidth = 250.0;
  static const _minScale = 0.06, _maxScale = 2.0;

  late Offset _center = widget.game.playerOffset;
  double _scale = 0.3;
  double _scaleAtStart = 0.3;

  Destination? _selected;
  RoadRoute? _preview;
  final _filters = PinKind.values.toSet();

  BatamGame get game => widget.game;
  RoadGraph get graph => game.graph;

  @override
  void initState() {
    super.initState();
    final dest = game.gps.destination;
    if (dest != null) {
      _selected = dest;
      _preview = game.gps.route;
    }
  }

  late Size _viewSize;
  Offset get _viewCenter => Offset((_viewSize.width - _panelWidth) / 2, _viewSize.height / 2);

  Offset _toScreen(Offset world) => _viewCenter + (world - _center) * _scale;
  Offset _toWorld(Offset screen) => _center + (screen - _viewCenter) / _scale;

  void _zoomAt(Offset focal, double newScale) {
    newScale = newScale.clamp(_minScale, _maxScale);
    final w = _toWorld(focal);
    _scale = newScale;
    _center = w - (focal - _viewCenter) / _scale;
    _clampCenter();
  }

  void _clampCenter() {
    _center = Offset(_center.dx.clamp(0, graph.size.width), _center.dy.clamp(0, graph.size.height));
  }

  Iterable<Poi> get _visiblePins => [...graph.pois, ...game.housePois, ...game.businessPois].where((p) {
    final k = PinKind.forPoi(p.type);
    return k != null && _filters.contains(k);
  });

  void _onTap(Offset screen) {
    // Pin lebih dulu (area sentuh di badan pin, di atas ujungnya).
    Poi? hitPoi;
    var best = 24.0;
    for (final p in _visiblePins) {
      final d = (_toScreen(p.position) - const Offset(0, 20) - screen).distance;
      if (d < best) {
        best = d;
        hitPoi = p;
      }
    }
    final Destination dest;
    if (hitPoi != null) {
      final kind = PinKind.forPoi(hitPoi.type)!;
      dest = Destination(
        title: hitPoi.name ?? kind.label,
        subtitle: '${kind.label} · ${graph.nearestPlaceName(hitPoi.position)}',
        position: hitPoi.position,
      );
    } else {
      final snap = game.gps.pathfinder.snap(_toWorld(screen), maxDist: math.max(6, 30 / _scale));
      if (snap == null) return;
      dest = Destination(
        title: snap.edge.name ?? 'Titik di jalan',
        subtitle: graph.nearestPlaceName(snap.point),
        position: snap.point,
      );
    }
    setState(() {
      _selected = dest;
      _preview = game.gps.plan(game.playerOffset, dest.position);
    });
  }

  void _startGps() {
    final dest = _selected, route = _preview;
    if (dest == null || route == null) return;
    game.gps.start(dest, route);
    game.closeMap();
  }

  void _clearGps() {
    game.gps.clear();
    setState(() {
      _selected = null;
      _preview = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewSize = constraints.biggest;
        return ColoredBox(
          color: BColors.laut,
          child: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  onPointerSignal: (e) {
                    if (e is PointerScrollEvent) {
                      setState(() => _zoomAt(e.localPosition, _scale * math.pow(0.998, e.scrollDelta.dy)));
                    }
                  },
                  child: GestureDetector(
                    onScaleStart: (_) => _scaleAtStart = _scale,
                    onScaleUpdate: (d) => setState(() {
                      _center -= d.focalPointDelta / _scale;
                      _clampCenter();
                      if (d.pointerCount > 1) _zoomAt(d.localFocalPoint, _scaleAtStart * d.scale);
                    }),
                    onTapUp: (d) => _onTap(d.localPosition),
                    child: CustomPaint(size: Size.infinite, painter: _MapPainter(this)),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                top: 12,
                child: Row(
                  children: [
                    GameButton(
                      width: 44,
                      height: 44,
                      radius: 14,
                      shadow: 3,
                      color: BColors.cream,
                      semanticLabel: 'Kembali ke permainan',
                      onTap: game.closeMap,
                      child: const _BackChevron(),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(color: BColors.ink, borderRadius: BorderRadius.circular(12)),
                      child: Text('Peta Batam', style: baloo(18, color: BColors.cream)),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 12,
                bottom: 12,
                right: _panelWidth + 12,
                child: Wrap(spacing: 6, runSpacing: 6, children: [for (final k in PinKind.values) _filterChip(k)]),
              ),
              Positioned(right: 0, top: 0, bottom: 0, width: _panelWidth, child: _panel()),
            ],
          ),
        );
      },
    );
  }

  Widget _filterChip(PinKind k) {
    final on = _filters.contains(k);
    return Semantics(
      button: true,
      toggled: on,
      child: GestureDetector(
        onTap: () => setState(() => on ? _filters.remove(k) : _filters.add(k)),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: on ? BColors.cream : const Color(0xFFE5D5B8),
            border: Border.all(color: BColors.ink, width: 3),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: k.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFFFFFF), width: 2),
                ),
              ),
              const SizedBox(width: 6),
              Text(k.label, style: nunito(12, color: on ? BColors.ink : const Color(0xFF6B5440))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panel() {
    final dest = _selected;
    final route = _preview;
    final isActive = game.gps.active && game.gps.destination == dest;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: BColors.cream,
        border: Border(left: BorderSide(color: BColors.ink, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('TUJUAN DIPILIH', style: nunito(11, color: const Color(0xFF6B5440)).copyWith(letterSpacing: 0.7)),
          const SizedBox(height: 10),
          if (dest == null)
            Text('Ketuk pin atau jalan di peta untuk memilih tujuan.', style: nunito(13, color: BColors.teksRedup))
          else ...[
            Text(dest.title, style: baloo(22).copyWith(height: 1.05), maxLines: 2, overflow: TextOverflow.ellipsis),
            Text(
              dest.subtitle,
              style: nunito(13, color: BColors.teksRedup),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            if (route == null)
              Text('Rute tidak ditemukan dari posisimu.', style: nunito(12, color: BColors.atapMerah))
            else
              Row(
                children: [
                  Expanded(child: _stat('Jarak', formatDistance(route.length))),
                  const SizedBox(width: 8),
                  Expanded(child: _stat('Estimasi', formatEta(route.length))),
                ],
              ),
          ],
          const Spacer(),
          if (game.gps.active) ...[
            GameButton(
              width: double.infinity,
              height: 40,
              radius: 14,
              shadow: 0,
              color: BColors.cream,
              onTap: _clearGps,
              child: Text('Hapus Rute', style: nunito(13)),
            ),
            const SizedBox(height: 8),
          ],
          GameButton(
            width: double.infinity,
            height: 48,
            color: BColors.biruPemain,
            enabled: route != null && !isActive,
            onTap: _startGps,
            child: Text(
              isActive ? 'Rute Terpasang' : 'Pasang Rute GPS',
              style: baloo(17, color: const Color(0xFFFFFFFF)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '© OpenStreetMap contributors',
            textAlign: TextAlign.center,
            style: nunito(9, color: const Color(0xFF6B5440)),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFFFF),
      border: Border.all(color: const Color(0xFFE5D5B8), width: 2),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: nunito(11, color: const Color(0xFF6B5440))),
        Text(value, style: baloo(18)),
      ],
    ),
  );
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.s);

  final _MapScreenState s;

  @override
  void paint(Canvas canvas, Size size) {
    final game = s.game;
    drawMapImage(canvas, game.mapImage, game.graph.size, s._center, s._scale, s._viewCenter);

    final active = game.gps.route;
    final preview = s._preview;
    final dest = s._selected;
    // Ujung rute ada di jalan utama terdekat; sambung putus-putus ke pin tujuan.
    List<Offset> pts(RoadRoute r) => [
      for (final p in r.points) s._toScreen(p),
      if (dest != null) s._toScreen(dest.position),
    ];
    if (preview != null && preview != active) drawRoute(canvas, pts(preview), dashed: true);
    if (active != null) drawRoute(canvas, pts(active));

    final view = Offset.zero & size;
    for (final p in s._visiblePins) {
      final at = s._toScreen(p.position);
      if (!view.inflate(30).contains(at)) continue;
      final kind = PinKind.forPoi(p.type)!;
      drawPin(canvas, at, kind.color, kind: kind, r: 11);
    }
    if (dest != null) drawPin(canvas, s._toScreen(dest.position), BColors.tosca, r: 16);

    final me = s._toScreen(game.playerOffset);
    drawPlayerArrow(canvas, me, game.heading, size: 26);
    final tag = TextPainter(
      text: TextSpan(
        text: 'Kamu',
        style: nunito(11, color: const Color(0xFFFFFFFF)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final box = Rect.fromCenter(center: me - const Offset(0, 26), width: tag.width + 16, height: tag.height + 2);
    final rr = RRect.fromRectAndRadius(box, const Radius.circular(8));
    canvas.drawRRect(rr, Paint()..color = BColors.biruPemain);
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFFFFFFF),
    );
    tag.paint(canvas, box.topLeft + const Offset(8, 1));
  }

  @override
  bool shouldRepaint(_MapPainter old) => true;
}

class _BackChevron extends StatelessWidget {
  const _BackChevron();

  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(22, 22), painter: _BackPainter());
}

class _BackPainter extends CustomPainter {
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
