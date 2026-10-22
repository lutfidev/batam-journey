import 'dart:io';

import 'package:batam_the_journey_begins/game/map/pathfinder.dart';
import 'package:batam_the_journey_begins/game/map/road_graph.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final graph = RoadGraph.parse(File('assets/data/batam_road_graph.json').readAsStringSync());
  final pf = Pathfinder(graph);

  Offset poi(String name) => graph.findPoi((p) => p.name == name)!.position;

  void expectFollowsRoads(RoadRoute r) {
    for (var i = 0; i < r.points.length - 1; i++) {
      final mid = (r.points[i] + r.points[i + 1]) / 2;
      expect(graph.isOnRoad(mid), isTrue, reason: 'segmen rute $i keluar jalan');
    }
  }

  test('rute Nagoya → Tembesi mengikuti jalan dan masuk akal panjangnya', () {
    final a = poi('21 Cinema Nagoya Hill');
    final b = graph.findPoi((p) => p.name == 'Tembesi')!.position;
    final r = pf.route(a, b)!;
    final straight = (a - b).distance;
    expect(r.length, greaterThan(straight * 0.9));
    expect(r.length, lessThan(straight * 2.5));
    expect(r.isNode.where((n) => n), isNotEmpty);
    expectFollowsRoads(r);
  });

  test('A* tanpa satu arah tidak lebih panjang dari dengan satu arah', () {
    final a = poi('21 Cinema Nagoya Hill');
    final b = graph.findPoi((p) => p.name == 'Muka Kuning')!.position;
    final strict = pf.route(a, b)!;
    final free = pf.route(a, b, respectOneway: false)!;
    expect(free.length, lessThanOrEqualTo(strict.length + 0.01));
  });

  test('banyak pasangan acak semua menghasilkan rute', () {
    final places = graph.pois.where((p) => p.type == 'fuel').take(12).toList();
    var found = 0;
    for (var i = 0; i < places.length - 1; i++) {
      final r = pf.route(places[i].position, places[i + 1].position);
      if (r != null) {
        found++;
        expectFollowsRoads(r);
      }
    }
    expect(found, places.length - 1);
  });

  test('tujuan di edge yang sama: rute langsung', () {
    final s = graph.segments.firstWhere((s) => s.length > 20 && !s.edge.oneway);
    final p1 = s.a + (s.b - s.a) * 0.2, p2 = s.a + (s.b - s.a) * 0.8;
    final r = pf.route(p1, p2)!;
    expect(r.length, closeTo((p2 - p1).distance, 0.01));
  });

  test('semua POI pin peta bisa dirutekan dari Nagoya', () {
    final start = poi('21 Cinema Nagoya Hill');
    final types = {'fuel', 'ferry_terminal', 'hospital', 'marketplace'};
    final missing = [
      for (final p in graph.pois.where((p) => types.contains(p.type)))
        if (pf.route(start, p.position) == null) '${p.type}:${p.name}',
    ];
    expect(missing, isEmpty);
  });
}
