import 'dart:io';
import 'dart:ui' as ui;

import 'package:batam_the_journey_begins/game/city/city_gen.dart';
import 'package:batam_the_journey_begins/game/iso.dart';
import 'package:batam_the_journey_begins/game/map/land_mask.dart';
import 'package:batam_the_journey_begins/game/map/road_graph.dart';
import 'package:batam_the_journey_begins/game/map/road_layer.dart';
import 'package:batam_the_journey_begins/game/model3d/bake.dart';
import 'package:batam_the_journey_begins/game/sprites/sprite_library.dart';
import 'package:batam_the_journey_begins/game/sprites/sprite_sheet.dart';
import 'package:flutter/painting.dart' show Rect;
import 'package:flutter_test/flutter_test.dart';

/// Potret kota di sekitar Nagoya (tanah per chunk + bangunan + pohon + lampu)
/// ke `build/model3d/kota_nagoya.png`, untuk cek visual tanpa HP.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('potret kota Nagoya', () async {
    final graph = RoadGraph.parse(File('assets/data/batam_road_graph.json').readAsStringSync());
    final codec = await ui.instantiateImageCodec(File('assets/images/batam_peta.jpg').readAsBytesSync());
    final mask = await LandMask.fromImage((await codec.getNextFrame()).image, graph.size);
    final buildings = generateBuildings(graph, mask, const []);
    final idx = RectIndex();
    for (final b in buildings) {
      idx.add(b.footprint!);
    }
    final zones = ZoneMap(graph);
    final center = graph.findPoi((p) => p.name == '21 Cinema Nagoya Hill')!.position;
    final cx = (center.dx / chunkSize).floor(), cy = (center.dy / chunkSize).floor();
    final decor = generateChunkDecor(graph, mask, zones, cx, cy, nearBuilding: idx.overlaps);

    final sprites = <String, DirectionalSprite>{};
    for (final id in SpriteIds.city) {
      sprites[id] = await bakeModel((spriteSources[id]! as BakedSource).asset).toSprite();
    }

    // Jendela layar iso 120×60 unit di sekitar pusat, 8 px per unit.
    const ppu = 8.0, w = 120.0, h = 60.0;
    final c = isoOf(center);
    final view = Rect.fromCenter(center: c, width: w, height: h);
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    canvas.drawColor(const ui.Color(0xFF4FB6CC), ui.BlendMode.src);
    canvas.scale(ppu);
    canvas.translate(-view.left, -view.top);
    final layer = RoadLayer(graph, mask);
    canvas.save();
    canvas.transform(isoMatrix);
    final ground = groundRectOf(view);
    final chunks = [
      for (var y = (ground.top / chunkSize).floor(); y <= (ground.bottom / chunkSize).floor(); y++)
        for (var x = (ground.left / chunkSize).floor(); x <= (ground.right / chunkSize).floor(); x++)
          layer.buildChunk(x, y),
    ];
    layer.drawChunks(canvas, chunks);
    canvas.restore();
    final reach = groundRectOf(Rect.fromLTRB(view.left - 25, view.top - 5, view.right + 25, view.bottom + 45));
    final props = [...buildings, ...decor].where((p) => reach.contains(p.at)).toList()
      ..sort((a, b) => a.depthKey.compareTo(b.depthKey));
    for (final p in props) {
      final at = isoOf(p.at);
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.scale(p.scale);
      sprites[p.sprite]!.render(canvas, direction: p.dir, frame: p.frame);
      canvas.restore();
    }
    final image = await rec.endRecording().toImage((w * ppu).round(), (h * ppu).round());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('build/model3d/kota_nagoya.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
    expect(props, isNotEmpty);
  });
}
