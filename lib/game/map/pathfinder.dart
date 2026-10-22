import 'dart:ui';

import 'package:collection/collection.dart';

import 'road_graph.dart';

/// Rute hasil A*: polyline dari titik awal sampai tujuan, mengikuti jalan.
class RoadRoute {
  RoadRoute(this.points, this.isNode) : length = _len(points);

  final List<Offset> points;

  /// true bila titik tersebut adalah persimpangan (kandidat belokan).
  final List<bool> isNode;
  final double length;

  static double _len(List<Offset> pts) {
    var d = 0.0;
    for (var i = 0; i < pts.length - 1; i++) {
      d += (pts[i + 1] - pts[i]).distance;
    }
    return d;
  }
}

/// Titik di jalan hasil "snap" sebuah posisi bebas.
class RoadSnap {
  RoadSnap(this.segment, this.point) : along = segment.startDist + (point - segment.a).distance;

  final RoadSegment segment;
  final Offset point;

  /// Jarak dari awal edge (pts[0]) ke [point].
  final double along;

  RoadEdge get edge => segment.edge;
}

/// A* di atas graf jalan. [respectOneway] = aturan jalan satu arah untuk kendaraan.
class Pathfinder {
  Pathfinder(this.graph);

  final RoadGraph graph;

  RoadSnap? snap(Offset p, {double maxDist = 80}) {
    final hit = graph.nearest(p, maxDist: maxDist);
    if (hit == null) return null;
    return RoadSnap(hit.segment, hit.segment.closestPoint(p));
  }

  /// Titik awal/tujuan di-snap ke jalan utama terdekat; tujuan boleh jauh
  /// (graf hanya berisi jalan utama, POI sering berada di jalan kecil).
  RoadRoute? route(Offset from, Offset to, {bool respectOneway = true, double maxSnap = 400}) {
    final a = snap(from, maxDist: maxSnap), b = snap(to, maxDist: maxSnap);
    if (a == null || b == null) return null;
    return routeBetween(a, b, respectOneway: respectOneway) ??
        (respectOneway ? routeBetween(a, b, respectOneway: false) : null);
  }

  RoadRoute? routeBetween(RoadSnap a, RoadSnap b, {bool respectOneway = true}) {
    final oneA = respectOneway && a.edge.oneway;
    final oneB = respectOneway && b.edge.oneway;

    // Tujuan di edge yang sama dan searah: langsung.
    if (a.edge == b.edge && (b.along >= a.along || !oneA)) {
      final pts = <Offset>[a.point];
      if (b.along >= a.along) {
        for (var i = a.segment.index + 1; i <= b.segment.index; i++) {
          pts.add(a.edge.pts[i]);
        }
      } else {
        for (var i = a.segment.index; i > b.segment.index; i--) {
          pts.add(a.edge.pts[i]);
        }
      }
      pts.add(b.point);
      return RoadRoute(pts, List.filled(pts.length, false));
    }

    // Node awal virtual: ujung-ujung edge A yang bisa dicapai dari titik snap.
    final startCost = <int, double>{a.edge.to: a.edge.length - a.along};
    if (!oneA) {
      startCost[a.edge.from] = a.along;
    }
    // Node akhir virtual: ujung edge B yang bisa masuk menuju titik snap.
    final goalCost = <int, double>{b.edge.from: b.along};
    if (!oneB) {
      goalCost[b.edge.to] = b.edge.length - b.along;
    }

    final gScore = <int, double>{};
    final prev = <int, (int, RoadEdge)>{};
    final closed = <int>{};
    final open = HeapPriorityQueue<(double, int)>((x, y) => x.$1.compareTo(y.$1));
    double h(int n) => (graph.nodes[n]! - b.point).distance;

    startCost.forEach((n, c) {
      if (c < (gScore[n] ?? double.infinity)) {
        gScore[n] = c;
        open.add((c + h(n), n));
      }
    });

    var best = double.infinity;
    int? bestNode;
    while (open.isNotEmpty) {
      final (f, u) = open.removeFirst();
      if (f >= best) break;
      if (!closed.add(u)) continue;
      final gu = gScore[u]!;
      final gc = goalCost[u];
      if (gc != null && gu + gc < best) {
        best = gu + gc;
        bestNode = u;
      }
      for (final e in graph.adjacency[u] ?? const <RoadEdge>[]) {
        final int v;
        if (e.from == u) {
          v = e.to;
        } else {
          if (respectOneway && e.oneway) continue;
          v = e.from;
        }
        if (closed.contains(v)) continue;
        final g = gu + e.length;
        if (g < (gScore[v] ?? double.infinity)) {
          gScore[v] = g;
          prev[v] = (u, e);
          open.add((g + h(v), v));
        }
      }
    }
    if (bestNode == null) return null;

    // Rangkai titik dari belakang.
    final chain = <(int, RoadEdge)>[];
    var n = bestNode;
    while (prev.containsKey(n) && !(startCost.containsKey(n) && gScore[n] == startCost[n])) {
      final (p, e) = prev[n]!;
      chain.add((n, e));
      n = p;
    }
    final startNode = n;

    final pts = <Offset>[a.point];
    final nodeFlags = <bool>[false];
    void add(Offset p, bool node) {
      if (pts.isNotEmpty && (pts.last - p).distanceSquared < 1e-6) {
        if (node) nodeFlags[nodeFlags.length - 1] = true;
        return;
      }
      pts.add(p);
      nodeFlags.add(node);
    }

    // Dari titik snap A ke node awal.
    if (startNode == a.edge.to) {
      for (var i = a.segment.index + 1; i < a.edge.pts.length; i++) {
        add(a.edge.pts[i], i == a.edge.pts.length - 1);
      }
    } else {
      for (var i = a.segment.index; i >= 0; i--) {
        add(a.edge.pts[i], i == 0);
      }
    }
    // Edge-edge di tengah.
    for (final (to, e) in chain.reversed) {
      final fwd = e.to == to;
      final ep = fwd ? e.pts : e.pts.reversed.toList();
      for (var i = 1; i < ep.length; i++) {
        add(ep[i], i == ep.length - 1);
      }
    }
    // Dari node akhir ke titik snap B.
    if (bestNode == b.edge.from) {
      for (var i = 1; i <= b.segment.index; i++) {
        add(b.edge.pts[i], false);
      }
    } else {
      for (var i = b.edge.pts.length - 2; i > b.segment.index; i--) {
        add(b.edge.pts[i], false);
      }
    }
    add(b.point, false);
    return RoadRoute(pts, nodeFlags);
  }
}
