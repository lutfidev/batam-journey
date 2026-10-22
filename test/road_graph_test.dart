import 'dart:io';

import 'package:batam_the_journey_begins/game/map/road_graph.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final graph = RoadGraph.parse(File('assets/data/batam_road_graph.json').readAsStringSync());

  test('ukuran dunia mengikuti worldScale', () {
    expect(graph.size.width, closeTo(29606 * worldScale, 0.01));
    expect(graph.edges, hasLength(2020));
    expect(graph.segments.length, greaterThan(graph.edges.length));
  });

  test('titik di tengah jalan terdeteksi on-road, segmen terdekat ketemu', () {
    final s = graph.segments.firstWhere((s) => s.length > 5);
    final mid = (s.a + s.b) / 2;
    expect(graph.isOnRoad(mid), isTrue);
    expect(graph.nearest(mid)!.distance, lessThan(0.01));
  });

  test('titik spawn Nagoya ada dan dekat jalan', () {
    final poi = graph.findPoi((p) => p.name == '21 Cinema Nagoya Hill');
    expect(poi, isNotNull);
    expect(graph.nearest(poi!.position, maxDist: 200), isNotNull);
    expect(graph.nearestPlaceName(poi.position), isNotEmpty);
  });
}
