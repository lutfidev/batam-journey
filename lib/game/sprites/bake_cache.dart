import 'dart:io';
import 'dart:typed_data';

import '../model3d/bake.dart';
import 'sprite_sheet.dart';

/// Cache disk atlas hasil panggang, supaya model Dart hanya dipanggang sekali
/// per versi model (peluncuran berikutnya tinggal membaca file).
/// File: `<dir>/<id>-<sidik>.json` (spesifikasi) + `<id>-<sidik>.rgba.gz` (piksel).
/// Dipanggil di isolate lain; semua operasi sinkron.
class BakeCache {
  const BakeCache(this.dir);

  final String dir;

  File _spec(String id, String fp) => File('$dir/$id-$fp.json');
  File _pixels(String id, String fp) => File('$dir/$id-$fp.rgba.gz');

  /// Atlas [id] dengan sidik jari [fp], atau null bila belum ada atau rusak.
  BakedSheet? read(String id, String fp) {
    try {
      final spec = SpriteSheetSpec.parse(_spec(id, fp).readAsStringSync());
      final rgba = gzip.decode(_pixels(id, fp).readAsBytesSync());
      if (rgba.length != spec.sheetWidth * spec.sheetHeight * 4) return null;
      return BakedSheet(spec, rgba is Uint8List ? rgba : Uint8List.fromList(rgba));
    } on Object {
      return null;
    }
  }

  /// Simpan [sheet] dan hapus versi lama aset [id].
  void write(String id, String fp, BakedSheet sheet) {
    final folder = Directory(dir)..createSync(recursive: true);
    for (final f in folder.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (name.startsWith('$id-') && !name.startsWith('$id-$fp.')) f.deleteSync();
    }
    // Tulis piksel dulu: spesifikasi = penanda bahwa file piksel sudah lengkap.
    _pixels(id, fp).writeAsBytesSync(GZipCodec(level: 1).encode(sheet.rgba), flush: true);
    _spec(id, fp).writeAsStringSync(sheet.spec.encode(), flush: true);
  }
}
