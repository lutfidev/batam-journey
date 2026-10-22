import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../ui/palette.dart';
import '../batam_game.dart';
import '../iso.dart';
import '../city/city_gen.dart' show chunkSize;
import 'land_mask.dart';
import 'road_graph.dart';

/// Menggambar laut, tanah, dan jalan. Lantai tiap chunk 1×1 km direkam sekali
/// jadi [Picture] (dicache), lalu diputar ulang tiap frame; hanya rute GPS yang
/// digambar langsung. Urutan lapis di dalam chunk: laut → darat → trotoar semua
/// jalan → aspal → marka & zebra cross, supaya simpang menyatu.
/// Lantai digambar di koordinat tanah lewat [isoMatrix].
class RoadLayer extends Component with HasGameReference<BatamGame> {
  RoadLayer(this.graph, this.mask) : super(priority: -1000000000);

  final RoadGraph graph;

  /// Mask darat/laut. Dipakai juga oleh pemain, motor, dan kota.
  final LandMask mask;

  static const _curb = 1.2;
  static const _dash = 2.2;
  static const _gap = 1.6;

  static const _shallowColor = Color(0xFF7FCCDA);

  /// Chunk yang disimpan paling banyak; yang paling lama tidak terlihat dibuang.
  static const maxChunks = 24;

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
  final _zebra = Paint()..color = const Color(0xFFF4F1EA);

  /// Kunci chunk → gambar lantai; urutan sisip = urutan terakhir dipakai.
  final _chunks = <int, Picture>{};

  late final List<_Crossing> _crossings = _findCrossings(graph);

  @override
  void render(Canvas canvas) {
    final view = groundRectOf(game.camera.visibleWorldRect).inflate(4);
    canvas.save();
    canvas.transform(isoMatrix);
    for (var cy = (view.top / chunkSize).floor(); cy <= (view.bottom / chunkSize).floor(); cy++) {
      for (var cx = (view.left / chunkSize).floor(); cx <= (view.right / chunkSize).floor(); cx++) {
        canvas.drawPicture(_chunk(cx, cy));
      }
    }
    _renderRoute(canvas);
    canvas.restore();
  }

  Picture _chunk(int cx, int cy) {
    final key = cx * 100000 + cy;
    final cached = _chunks.remove(key);
    if (cached != null) return _chunks[key] = cached;
    if (_chunks.length >= maxChunks) _chunks.remove(_chunks.keys.first)!.dispose();
    return _chunks[key] = recordChunk(cx, cy);
  }

  /// Rekam lantai satu chunk, dipotong tepat di batasnya (tanpa antialias,
  /// supaya tidak ada garis sambungan antar-chunk).
  Picture recordChunk(int cx, int cy) {
    final rect = Rect.fromLTWH(cx * chunkSize, cy * chunkSize, chunkSize, chunkSize);
    final rec = PictureRecorder();
    final canvas = Canvas(rec);
    canvas.clipRect(rect, doAntiAlias: false);
    canvas.drawRect(rect, _deep);
    final cells = rect.inflate(mask.cell);
    canvas.drawPath(_coastPath(cells, (s) => s != Surface.deep), _shallow);
    canvas.drawPath(_coastPath(cells, (s) => s == Surface.land), _ground);

    final segs = graph.segmentsIn(rect.inflate(10)).toList();
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
    for (final c in _crossings) {
      if (rect.inflate(10).contains(c.center)) _drawCrossing(canvas, c);
    }
    return rec.endRecording();
  }

  /// Zebra cross: belang putih melintang jalan, sejajar arah jalan.
  void _drawCrossing(Canvas canvas, _Crossing c) {
    canvas.save();
    canvas.translate(c.center.dx, c.center.dy);
    canvas.rotate(math.atan2(c.dir.dy, c.dir.dx));
    // Sumbu x = arah jalan; belang selebar 0,7 berjarak 1,4 di sepanjang lebar jalan.
    const stripe = 0.7, pitch = 1.4, length = 2.6;
    final half = c.width / 2 - 0.5;
    for (var y = -half + stripe / 2; y <= half - stripe / 2 + 1e-6; y += pitch) {
      canvas.drawRect(Rect.fromCenter(center: Offset(0, y), width: length, height: stripe), _zebra);
    }
    canvas.restore();
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

}

/// Satu zebra cross: titik tengah di as jalan, arah jalan, dan lebar aspal.
class _Crossing {
  const _Crossing(this.center, this.dir, this.width);

  final Offset center;
  final Offset dir;
  final double width;
}

/// Zebra cross di tiap kaki simpang (≥ 3 jalan bukan ramp) yang melibatkan
/// jalan besar, sedikit sebelum mulut simpang.
List<_Crossing> _findCrossings(RoadGraph graph) {
  final out = <_Crossing>[];
  for (final MapEntry(key: node, value: edges) in graph.adjacency.entries) {
    final legs = edges.where((e) => !e.type.endsWith('_link') && !e.bridge).toList();
    if (legs.length < 3) continue;
    if (!legs.any((e) => e.type.startsWith('trunk') || e.type.startsWith('primary') || e.type.startsWith('secondary'))) {
      continue;
    }
    final at = graph.nodes[node]!;
    final mouth = legs.map((e) => e.width).reduce(math.max) / 2 + 2.5;
    for (final e in legs) {
      // Arah keluar dari simpang di sepanjang kaki ini.
      final pts = e.from == node ? e.pts : e.pts.reversed.toList();
      if (pts.length < 2) continue;
      final d0 = pts[1] - pts[0];
      if (d0.distance < mouth + 2) continue;
      final dir = d0 / d0.distance;
      out.add(_Crossing(at + dir * mouth, dir, e.width));
    }
  }
  return out;
}

extension SeaBlock on BatamGame {
  /// True bila [p] ada di air (mask) dan bukan di jalan/jembatan.
  bool isWaterBlocked(Offset p) => mask.isWater(p) && !graph.isOnRoad(p);

  /// True bila [p] di air atau di dalam bangunan (tidak bisa dilewati).
  bool isBlocked(Offset p) => isWaterBlocked(p) || city.blocks(p);
}
