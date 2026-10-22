import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/services.dart' show rootBundle;

/// Skala dunia game terhadap meter asli OSM (lihat CLAUDE.md).
const double worldScale = 0.2;

/// Ukuran sel grid spasial (satuan dunia game) untuk culling & query jalan.
const double roadCellSize = 40;

/// Lebar aspal per tipe jalan, dalam satuan dunia game.
/// Sengaja dibesar-besarkan dibanding dunia yang diperkecil 0,2× supaya
/// terbaca dari kamera dekat.
double roadWidthFor(String type) {
  final base = type.replaceAll('_link', '');
  final w = switch (base) {
    'trunk' => 12.0,
    'primary' => 10.0,
    'secondary' => 8.5,
    'tertiary' => 7.0,
    _ => 6.0,
  };
  return type.endsWith('_link') ? w * 0.75 : w;
}

class RoadEdge {
  RoadEdge({
    required this.index,
    required this.from,
    required this.to,
    required this.pts,
    required this.type,
    required this.name,
    required this.oneway,
    required this.bridge,
    required this.width,
  });

  final int index;
  final int from;
  final int to;

  /// Polyline (sudah diskalakan) dari node [from] ke node [to].
  final List<Offset> pts;
  late final double length = _polyLength(pts);

  final String type;
  final String? name;
  final bool oneway;
  final bool bridge;
  final double width;
}

/// Satu potongan lurus dari polyline sebuah edge.
class RoadSegment {
  RoadSegment(this.a, this.b, this.edge, this.index, this.startDist);

  final Offset a;
  final Offset b;
  final RoadEdge edge;

  /// Indeks segmen ini di dalam `edge.pts` (titik a = pts[index]).
  final int index;

  /// Jarak dari awal edge sampai titik [a]; dipakai agar garis putus-putus
  /// tetap menyambung antar segmen.
  final double startDist;

  double get length => (b - a).distance;

  double distanceTo(Offset p) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    var t = len2 == 0 ? 0.0 : ((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2;
    t = t.clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  Offset closestPoint(Offset p) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    var t = len2 == 0 ? 0.0 : ((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2;
    t = t.clamp(0.0, 1.0);
    return a + ab * t;
  }
}

class Poi {
  Poi(this.type, this.name, this.position);

  final String type;
  final String? name;
  final Offset position;
}

class RoadHit {
  RoadHit(this.segment, this.distance);

  final RoadSegment segment;
  final double distance;
}

/// Graf jalan Batam dari `batam_road_graph.json`, sudah dikali [worldScale],
/// plus grid spasial untuk mencari segmen di sekitar sebuah titik.
class RoadGraph {
  RoadGraph._(this.size, this.nodes, this.edges, this.segments, this.pois, this._grid)
    : adjacency = _buildAdjacency(edges);

  final Size size;

  /// Posisi node persimpangan berdasarkan id.
  final Map<int, Offset> nodes;

  /// Node → edge yang bersentuhan dengannya.
  final Map<int, List<RoadEdge>> adjacency;
  final List<RoadEdge> edges;
  final List<RoadSegment> segments;
  final List<Poi> pois;
  final Map<int, List<int>> _grid;

  static Future<RoadGraph> load([String path = 'assets/data/batam_road_graph.json']) async {
    return parse(await rootBundle.loadString(path));
  }

  static RoadGraph parse(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    final meta = json['meta'] as Map<String, dynamic>;
    final size = Size((meta['width_m'] as num) * worldScale, (meta['height_m'] as num) * worldScale);

    final nodes = <int, Offset>{
      for (final n in json['nodes'] as List)
        n['id'] as int: Offset((n['x'] as num) * worldScale, (n['y'] as num) * worldScale),
    };

    final edges = <RoadEdge>[];
    final segments = <RoadSegment>[];
    for (final e in json['edges'] as List) {
      final type = e['type'] as String;
      final pts = (e['pts'] as List)
          .map((p) => Offset((p[0] as num) * worldScale, (p[1] as num) * worldScale))
          .toList();
      final edge = RoadEdge(
        index: edges.length,
        from: e['from'] as int,
        to: e['to'] as int,
        pts: pts,
        type: type,
        name: e['name'] as String?,
        oneway: e['oneway'] == true,
        bridge: e['bridge'] == true,
        width: roadWidthFor(type),
      );
      edges.add(edge);
      var dist = 0.0;
      for (var i = 0; i < pts.length - 1; i++) {
        final s = RoadSegment(pts[i], pts[i + 1], edge, i, dist);
        segments.add(s);
        dist += s.length;
      }
    }

    final pois = [
      for (final p in json['pois'] as List)
        Poi(
          p['type'] as String,
          p['name'] as String?,
          Offset((p['x'] as num) * worldScale, (p['y'] as num) * worldScale),
        ),
    ];

    final grid = <int, List<int>>{};
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      final pad = s.edge.width / 2 + 2;
      final x0 = (math.min(s.a.dx, s.b.dx) - pad) ~/ roadCellSize;
      final x1 = (math.max(s.a.dx, s.b.dx) + pad) ~/ roadCellSize;
      final y0 = (math.min(s.a.dy, s.b.dy) - pad) ~/ roadCellSize;
      final y1 = (math.max(s.a.dy, s.b.dy) + pad) ~/ roadCellSize;
      for (var cx = x0; cx <= x1; cx++) {
        for (var cy = y0; cy <= y1; cy++) {
          (grid[_key(cx, cy)] ??= []).add(i);
        }
      }
    }

    return RoadGraph._(size, nodes, edges, segments, pois, grid);
  }

  static Map<int, List<RoadEdge>> _buildAdjacency(List<RoadEdge> edges) {
    final adj = <int, List<RoadEdge>>{};
    for (final e in edges) {
      (adj[e.from] ??= []).add(e);
      if (e.to != e.from) (adj[e.to] ??= []).add(e);
    }
    return adj;
  }

  static int _key(int cx, int cy) => cx * 100000 + cy;

  /// Indeks segmen (unik) yang selnya beririsan dengan [rect].
  Iterable<RoadSegment> segmentsIn(Rect rect) sync* {
    final seen = <int>{};
    final x0 = rect.left ~/ roadCellSize, x1 = rect.right ~/ roadCellSize;
    final y0 = rect.top ~/ roadCellSize, y1 = rect.bottom ~/ roadCellSize;
    for (var cx = x0; cx <= x1; cx++) {
      for (var cy = y0; cy <= y1; cy++) {
        final cell = _grid[_key(cx, cy)];
        if (cell == null) continue;
        for (final i in cell) {
          if (seen.add(i)) yield segments[i];
        }
      }
    }
  }

  /// Segmen terdekat dalam radius [maxDist], atau null.
  RoadHit? nearest(Offset p, {double maxDist = 30}) {
    RoadHit? best;
    for (final s in segmentsIn(Rect.fromCircle(center: p, radius: maxDist))) {
      final d = s.distanceTo(p);
      if (d <= maxDist && (best == null || d < best.distance)) {
        best = RoadHit(s, d);
      }
    }
    return best;
  }

  /// Jarak dari [p] ke tepi aspal terdekat (negatif = di atas aspal).
  double clearance(Offset p, {double maxDist = 20}) {
    var best = maxDist;
    for (final s in segmentsIn(Rect.fromCircle(center: p, radius: maxDist))) {
      final d = s.distanceTo(p) - s.edge.width / 2;
      if (d < best) best = d;
    }
    return best;
  }

  bool isOnRoad(Offset p) => clearance(p, maxDist: 10) <= 0;

  /// Nama kelurahan/kawasan terdekat untuk label HUD.
  String nearestPlaceName(Offset p) {
    Poi? best;
    var bestD = double.infinity;
    for (final poi in pois) {
      if (poi.name == null || !poi.type.startsWith('place_')) continue;
      if (poi.type == 'place_city') continue;
      final d = (poi.position - p).distanceSquared;
      if (d < bestD) {
        bestD = d;
        best = poi;
      }
    }
    return best?.name ?? 'Batam';
  }

  Poi? findPoi(bool Function(Poi) test) {
    for (final p in pois) {
      if (test(p)) return p;
    }
    return null;
  }
}

double _polyLength(List<Offset> pts) {
  var d = 0.0;
  for (var i = 0; i < pts.length - 1; i++) {
    d += (pts[i + 1] - pts[i]).distance;
  }
  return d;
}
