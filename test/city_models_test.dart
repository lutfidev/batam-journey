import 'dart:io';
import 'dart:ui' as ui;

import 'package:batam_the_journey_begins/game/model3d/bake.dart';
import 'package:batam_the_journey_begins/game/model3d/models/buildings.dart';
import 'package:batam_the_journey_begins/game/model3d/models/props.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _writePng(ui.Image image, String name) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('build/model3d/$name.png');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  final assets = <String, ModelAsset>{
    'spbu': spbuAsset,
    'bengkel': bengkelAsset,
    'rumah': rumahAsset,
    'kos': kosAsset,
    'villa': villaAsset,
    'ruko': rukoAsset,
    'gedung': gedungAsset,
    'pabrik': pabrikAsset,
    'pohon': pohonAsset,
    'lampu_jalan': lampuJalanAsset,
  };

  group('model kota', () {
    for (final MapEntry(key: name, value: asset) in assets.entries) {
      test('$name: dipanggang ${asset.directions} arah, atlas muat di tekstur 4096', () async {
        final sw = Stopwatch()..start();
        final sheet = await bakeModelParallel(asset);
        final spec = sheet.spec;
        // ignore: avoid_print
        print('$name: ${spec.frameWidth}×${spec.frameHeight} px/sel, atlas ${spec.sheetWidth}×${spec.sheetHeight}, '
            '${(spec.sheetWidth * spec.sheetHeight * 4 / 1e6).toStringAsFixed(1)} MB, ${sw.elapsedMilliseconds} ms');
        expect(spec.directions, asset.directions);
        expect(spec.sheetWidth, lessThanOrEqualTo(4096));
        expect(spec.sheetHeight, lessThanOrEqualTo(4096));
        // Tiap sel berisi gambar (tidak kosong).
        for (var c = 0; c < spec.directions * spec.rows; c++) {
          final x0 = (c % spec.directions) * spec.frameWidth, y0 = (c ~/ spec.directions) * spec.frameHeight;
          var opaque = 0;
          for (var y = y0; y < y0 + spec.frameHeight; y += 3) {
            for (var x = x0; x < x0 + spec.frameWidth; x += 3) {
              if (sheet.rgba[(y * spec.sheetWidth + x) * 4 + 3] > 0) opaque++;
            }
          }
          expect(opaque, greaterThan(20), reason: 'sel $c kosong');
        }
        await _writePng(await sheet.toImage(), 'kota_$name');
      });
    }
  });
}
