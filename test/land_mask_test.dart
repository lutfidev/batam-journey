import 'dart:io';
import 'dart:ui' as ui;

import 'package:batam_the_journey_begins/game/map/land_mask.dart';
import 'package:batam_the_journey_begins/game/map/road_graph.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final graph = RoadGraph.parse(File('assets/data/batam_road_graph.json').readAsStringSync());
  late LandMask mask;

  setUpAll(() async {
    final codec = await ui.instantiateImageCodec(File('assets/images/batam_peta.jpg').readAsBytesSync());
    final image = (await codec.getNextFrame()).image;
    mask = await LandMask.fromImage(image, graph.size);
  });

  test('ukuran mask menutup dunia', () {
    expect(mask.cols * mask.cell, greaterThanOrEqualTo(graph.size.width));
    expect(mask.rows * mask.cell, greaterThanOrEqualTo(graph.size.height));
  });

  test('spawn Nagoya ada di darat', () {
    final poi = graph.findPoi((p) => p.name == '21 Cinema Nagoya Hill')!;
    expect(mask.isLand(poi.position), isTrue);
  });

  test('pojok peta dan Selat Singapura adalah laut dalam', () {
    expect(mask.surfaceAt(const Offset(20, 20)), Surface.deep);
    // Teluk di utara, antara Batu Ampar dan Nongsa (±x 0,63, y 0,12 dunia).
    final bay = Offset(graph.size.width * 0.63, graph.size.height * 0.12);
    expect(mask.isWater(bay), isTrue);
  });

  test('di luar dunia dianggap laut', () {
    expect(mask.surfaceAt(const Offset(-50, 100)), Surface.deep);
    expect(mask.surfaceAt(Offset(graph.size.width + 10, 10)), Surface.deep);
  });

  test('sebagian besar node jalan ada di darat', () {
    final onLand = graph.nodes.values.where(mask.isLand).length;
    expect(onLand / graph.nodes.length, greaterThan(0.95));
  });
}
