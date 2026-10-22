import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../ui/palette.dart';
import '../batam_game.dart';
import 'land_mask.dart';
import 'road_graph.dart';

/// Menggambar laut, tanah, pohon, dan jalan yang terlihat kamera saja.
/// Urutan lapis: trotoar semua jalan → aspal → marka, supaya simpang menyatu.
class RoadLayer extends Component with HasGameReference<BatamGame> {
  RoadLayer(this.graph) : super(priority: -1000000000);

  final RoadGraph graph;

  static const _curb = 1.2;
  static const _dash = 2.2;
  static const _gap = 1.6;

  /// Mask darat/laut, siap setelah [onLoad]. Dipakai juga oleh pemain & motor.
  late final LandMask mask;

  static const _shallowColor = Color(0xFF7FCCDA);

  final _ground = Paint()..color = BColors.tanah;
  final _deep = Paint()..color = BColors.laut;
  final _shallow = Paint()..color = _shallowColor;
  final _curbPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..color = BColors.trotoar;
  final _railPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..color = BColors.atapMerah;
  final _asphalt = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..color = BColors.aspal;
  final _marking = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.35
    ..color = BColors.kuning;
  final _treeShadow = Paint()..color = const Color(0x33000000);
  final _treeA = Paint()..color = BColors.hutan;
  final _treeB = Paint()..color = BColors.hutanGelap;
  final _treeHi = Paint()..color = const Color(0xFFA9D58F);
  final _treeLine = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.15
    ..color = const Color(0x552B1D12);

  final _trees = <int, List<_Tree>>{};

  @override
  Future<void> onLoad() async {
    mask = await LandMask.fromImage(game.mapImage, graph.size);
  }

  @override
  void render(Canvas canvas) {
    final view = game.camera.visibleWorldRect.inflate(4);
    canvas.drawRect(view, _deep);
    canvas.drawPath(_coastPath(view, (s) => s != Surface.deep), _shallow);
    canvas.drawPath(_coastPath(view, (s) => s == Surface.land), _ground);

    final segs = graph.segmentsIn(view).toList();

    for (final s in segs) {
      final p = s.edge.bridge ? _railPaint : _curbPaint;
      p.strokeWidth = s.edge.width + _curb * 2;
      canvas.drawLine(s.a, s.b, p);
    }
    for (final s in segs) {
      _asphalt.strokeWidth = s.edge.width;
      canvas.drawLine(s.a, s.b, _asphalt);
    }
    final dashes = Path();
    for (final s in segs) {
      if (s.edge.type.endsWith('_link')) continue;
      _addDashes(dashes, s);
    }
    canvas.drawPath(dashes, _marking);

    _renderRoute(canvas);

    _renderTrees(canvas, view);
  }

  /// Wilayah sel yang memenuhi [inside] sebagai Path, dengan marching squares
  /// di antara pusat-pusat sel supaya garis pantai tidak bergerigi kotak.
  Path _coastPath(Rect view, bool Function(Surface) inside) {
    final path = Path();
    final (c0, r0, c1, r1) = mask.cellRange(view);
    final h = mask.cell / 2;
    final ins = List<bool>.filled(4, false);
    final pts = List<Offset>.filled(4, Offset.zero);
    for (var r = r0; r < r1; r++) {
      var runStart = -1;
      for (var c = c0; c < c1; c++) {
        ins[0] = inside(mask.at(c, r));
        ins[1] = inside(mask.at(c + 1, r));
        ins[2] = inside(mask.at(c + 1, r + 1));
        ins[3] = inside(mask.at(c, r + 1));
        final full = ins[0] && ins[1] && ins[2] && ins[3];
        // Kotak penuh digabung per baris jadi satu persegi panjang.
        if (full) {
          if (runStart < 0) runStart = c;
          continue;
        }
        if (runStart >= 0) {
          path.addRect(Rect.fromPoints(mask.centerOf(runStart, r), mask.centerOf(c, r + 1)));
          runStart = -1;
        }
        if (!(ins[0] || ins[1] || ins[2] || ins[3])) continue;
        final o = mask.centerOf(c, r);
        pts[0] = o;
        pts[1] = o + Offset(h * 2, 0);
        pts[2] = o + Offset(h * 2, h * 2);
        pts[3] = o + Offset(0, h * 2);
        final poly = <Offset>[];
        for (var i = 0; i < 4; i++) {
          final j = (i + 1) % 4;
          if (ins[i]) poly.add(pts[i]);
          if (ins[i] != ins[j]) poly.add((pts[i] + pts[j]) / 2);
        }
        path.addPolygon(poly, true);
      }
      if (runStart >= 0) {
        path.addRect(Rect.fromPoints(mask.centerOf(runStart, r), mask.centerOf(c1, r + 1)));
      }
    }
    return path;
  }

  final _routeHalo = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = 2.6
    ..color = const Color(0xCCFFFFFF);
  final _routeLine = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = 1.6
    ..color = BColors.biruPemain;

  void _renderRoute(Canvas canvas) {
    final route = game.gps.route;
    final dest = game.gps.destination;
    if (route == null || dest == null) return;
    final path = Path()..addPolygon(route.points, false);
    canvas.drawPath(path, _routeHalo);
    canvas.drawPath(path, _routeLine);
    final end = route.points.last;
    canvas.drawCircle(end, 2.4, _routeHalo..style = PaintingStyle.fill);
    canvas.drawCircle(end, 1.8, _routeLine..style = PaintingStyle.fill);
    _routeHalo.style = PaintingStyle.stroke;
    _routeLine.style = PaintingStyle.stroke;
  }

  void _addDashes(Path path, RoadSegment s) {
    const period = _dash + _gap;
    final len = s.length;
    if (len == 0) return;
    final dir = (s.b - s.a) / len;
    var k = (s.startDist / period).floor();
    while (k * period < s.startDist + len) {
      final from = math.max(k * period, s.startDist) - s.startDist;
      final to = math.min(k * period + _dash, s.startDist + len) - s.startDist;
      if (to > from) {
        final a = s.a + dir * from, b = s.a + dir * to;
        path
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy);
      }
      k++;
    }
  }

  // Pohon ditempatkan deterministik per sel 20×20 dan hanya di luar jalan,
  // tidak di laut, supaya ada patokan gerak saat berjalan/berkendara.
  static const _treeCell = 20.0;

  void _renderTrees(Canvas canvas, Rect view) {
    final x0 = (view.left / _treeCell).floor(), x1 = (view.right / _treeCell).floor();
    final y0 = (view.top / _treeCell).floor(), y1 = (view.bottom / _treeCell).floor();
    for (var cy = y0; cy <= y1; cy++) {
      for (var cx = x0; cx <= x1; cx++) {
        for (final t in _treesFor(cx, cy)) {
          canvas.drawOval(
            Rect.fromCenter(center: t.pos + Offset(t.r * 0.3, t.r * 0.5), width: t.r * 2.2, height: t.r * 1.4),
            _treeShadow,
          );
          final paint = t.dark ? _treeB : _treeA;
          canvas.drawCircle(t.pos, t.r, paint);
          canvas.drawCircle(t.pos, t.r, _treeLine);
          canvas.drawCircle(t.pos - Offset(t.r * 0.3, t.r * 0.35), t.r * 0.45, t.dark ? _treeA : _treeHi);
        }
      }
    }
  }

  List<_Tree> _treesFor(int cx, int cy) {
    final key = cx * 100000 + cy;
    return _trees[key] ??= () {
      final rnd = math.Random(key * 2654435761 & 0x7fffffff);
      final out = <_Tree>[];
      final n = rnd.nextInt(4);
      for (var i = 0; i < n; i++) {
        final pos = Offset((cx + rnd.nextDouble()) * _treeCell, (cy + rnd.nextDouble()) * _treeCell);
        final r = 1.6 + rnd.nextDouble() * 1.6;
        if (mask.isLand(pos) &&
            mask.isLand(pos + Offset(r, r)) &&
            mask.isLand(pos - Offset(r, r)) &&
            graph.clearance(pos, maxDist: 12) > r + 2.5 &&
            !game.isNearBuilding(pos, r)) {
          out.add(_Tree(pos, r, rnd.nextBool()));
        }
      }
      return out;
    }();
  }
}

class _Tree {
  _Tree(this.pos, this.r, this.dark);

  final Offset pos;
  final double r;
  final bool dark;
}

extension SeaBlock on BatamGame {
  /// True bila [p] ada di air (mask) dan bukan di jalan/jembatan.
  /// Sebelum mask siap, tidak ada yang diblokir.
  bool isWaterBlocked(Offset p) {
    final layer = world.firstChild<RoadLayer>();
    if (layer == null || !layer.isLoaded) return false;
    return layer.mask.isWater(p) && !graph.isOnRoad(p);
  }
}
