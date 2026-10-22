import 'dart:io';
import 'dart:ui' as ui;

import 'package:batam_the_journey_begins/game/city/city_gen.dart';
import 'package:batam_the_journey_begins/game/map/land_mask.dart';
import 'package:batam_the_journey_begins/game/map/road_graph.dart';
import 'package:batam_the_journey_begins/game/model3d/models/buildings.dart';
import 'package:batam_the_journey_begins/game/sprites/sprite_library.dart';
import 'package:flutter/painting.dart' show Offset, Rect;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final graph = RoadGraph.parse(File('assets/data/batam_road_graph.json').readAsStringSync());
  late LandMask mask;
  late List<PropSpec> buildings;

  setUpAll(() async {
    final codec = await ui.instantiateImageCodec(File('assets/images/batam_peta.jpg').readAsBytesSync());
    mask = await LandMask.fromImage((await codec.getNextFrame()).image, graph.size);
    final sw = Stopwatch()..start();
    buildings = generateBuildings(graph, mask, const []);
    // ignore: avoid_print
    print('${buildings.length} bangunan dalam ${sw.elapsedMilliseconds} ms');
  });

  Offset poi(String name) => graph.findPoi((p) => p.name == name)!.position;

  group('geometri', () {
    test('model → tanah: depan bangunan menghadap arah hadap', () {
      for (var f = 0; f < 4; f++) {
        final front = modelToGround(const Offset(1, 0), f, Offset.zero);
        expect(front, facingVector(f));
      }
      // Kanan model (+y) = kanan arah hadap: menghadap timur → kanan = selatan.
      expect(modelToGround(const Offset(0, 1), 0, Offset.zero), const Offset(0, 1));
      expect(modelToGround(const Offset(0, 1), 1, Offset.zero), const Offset(-1, 0));
    });

    test('arah hadap terdekat dari vektor', () {
      expect(facingOf(const Offset(3, 1)), 0);
      expect(facingOf(const Offset(-1, 4)), 1);
      expect(facingOf(const Offset(-5, -1)), 2);
      expect(facingOf(const Offset(0.2, -1)), 3);
    });

    test('jarak ruas–kotak', () {
      const r = Rect.fromLTWH(0, 0, 4, 2);
      expect(segmentRectDistance(const Offset(-1, 1), const Offset(5, 1), r), 0);
      expect(segmentRectDistance(const Offset(6, 0), const Offset(6, 2), r), closeTo(2, 1e-9));
      expect(segmentRectDistance(const Offset(-3, 5), const Offset(5, 5), r), closeTo(3, 1e-9));
      // Ruas miring yang melewati pojok tanpa menyentuh.
      expect(segmentRectDistance(const Offset(3, 4), const Offset(6, 1), r), closeTo(0.7071, 1e-3));
    });
  });

  group('lokasi bangunan penting', () {
    test('SPBU di pinggir jalan, menghadap jalan, tidak menimpa aspal', () {
      final site = siteBeside(graph, poi('21 Cinema Nagoya Hill'), spbuInfo, mask: mask)!;
      expect(roadClearanceOfRect(graph, site.footprint), greaterThan(buildingSetback - 0.7));
      // Titik masuk lebih dekat ke jalan daripada pusat bangunan.
      expect(graph.clearance(site.entrance), lessThan(graph.clearance(site.center)));
    });

    test('lokasi terpakai → bergeser sepanjang jalan', () {
      final taken = RectIndex();
      final first = siteBeside(graph, poi('21 Cinema Nagoya Hill'), rukoInfo, mask: mask, taken: taken)!;
      taken.add(first.footprint);
      final second = siteBeside(graph, poi('21 Cinema Nagoya Hill'), rukoInfo, mask: mask, taken: taken)!;
      expect(second.footprint.overlaps(first.footprint.deflate(0.01)), isFalse);
    });
  });

  group('blok kota', () {
    test('zona: Nagoya & Batam Centre kota, Muka Kuning industri, Nongsa bukan kota', () {
      final zones = ZoneMap(graph);
      expect(zones.at(poi('21 Cinema Nagoya Hill')), Zone.kota);
      expect(zones.at(poi('Batam Centre')), Zone.kota);
      expect(zones.at(poi('Muka Kuning')), Zone.industri);
      expect(zones.at(poi('Nongsa Pura')), isNot(Zone.kota));
    });

    test('tidak ada bangunan yang menimpa jalan, laut, atau bangunan lain', () {
      expect(buildings.length, greaterThan(3000));
      final idx = RectIndex();
      for (final b in buildings) {
        final r = b.footprint!;
        expect(idx.overlaps(r), isFalse, reason: 'tumpang tindih di ${r.center}');
        idx.add(r);
        expect(roadClearanceOfRect(graph, r), greaterThan(1.5), reason: 'menimpa jalan di ${r.center}');
        expect(mask.isLand(r.center), isTrue);
      }
    });

    test('kota lebih padat dari desa; jenis mengikuti zona', () {
      final zones = ZoneMap(graph);
      final byZone = <Zone, Map<String, int>>{};
      for (final b in buildings) {
        final m = byZone[zones.at(b.at)] ??= {};
        m[b.sprite] = (m[b.sprite] ?? 0) + 1;
      }
      // ignore: avoid_print
      print(byZone);
      expect(byZone[Zone.kota]![SpriteIds.ruko], greaterThan(byZone[Zone.kota]![SpriteIds.rumah] ?? 0));
      expect(byZone[Zone.industri]![SpriteIds.pabrik], greaterThan(0));
      expect(byZone[Zone.desa]?[SpriteIds.gedung], isNull);
    });

    test('pohon & lampu: tidak di jalan, tidak di dalam bangunan, deterministik', () {
      final zones = ZoneMap(graph);
      final idx = RectIndex();
      for (final b in buildings) {
        idx.add(b.footprint!);
      }
      bool near(Rect r) => idx.overlaps(r);
      final c = poi('21 Cinema Nagoya Hill');
      final cx = (c.dx / chunkSize).floor(), cy = (c.dy / chunkSize).floor();
      final a = generateChunkDecor(graph, mask, zones, cx, cy, nearBuilding: near);
      final b = generateChunkDecor(graph, mask, zones, cx, cy, nearBuilding: near);
      expect(a.length, b.length);
      expect(a.where((p) => p.sprite == SpriteIds.lampuJalan), isNotEmpty);
      expect(a.where((p) => p.sprite == SpriteIds.pohon), isNotEmpty);
      for (final p in a) {
        expect(graph.isOnRoad(p.at), isFalse);
        expect(idx.contains(p.at), isFalse);
      }
    });
  });
}
