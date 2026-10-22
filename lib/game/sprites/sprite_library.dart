import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import '../model3d/bake.dart';
import '../model3d/models/buildings.dart';
import '../model3d/models/motor.dart';
import '../model3d/models/pin_tujuan.dart';
import '../model3d/models/props.dart';
import '../model3d/models/slime.dart';
import 'bake_cache.dart';
import 'sprite_sheet.dart';

/// Dari mana sprite sebuah aset berasal. Kode game tidak peduli: keduanya
/// menghasilkan [DirectionalSprite] berformat sama.
sealed class SpriteSource {
  const SpriteSource();
}

/// Dipanggang dari model low-poly Dart saat load.
class BakedSource extends SpriteSource {
  const BakedSource(this.asset);

  final ModelAsset asset;
}

/// Dimuat dari `assets/images/<name>.png` + `<name>.json` (mis. hasil Blender).
class PngSource extends SpriteSource {
  const PngSource(this.name);

  final String name;
}

/// Id aset sprite.
abstract final class SpriteIds {
  static const pinTujuan = 'pin_tujuan';
  static const slime = 'slime';
  static const motor = 'motor';

  // Kota (langkah 5): bangunan 4 arah, pohon 4 arah, lampu 16 arah.
  static const spbu = 'spbu';
  static const bengkel = 'bengkel';
  static const rumah = 'rumah';
  static const kos = 'kos';
  static const villa = 'villa';
  static const ruko = 'ruko';
  static const gedung = 'gedung';
  static const pabrik = 'pabrik';
  static const pohon = 'pohon';
  static const lampuJalan = 'lampu_jalan';

  /// Aset kota, urut dari yang paling sering terlihat (dipanggang berurutan).
  static const city = [pohon, rumah, ruko, lampuJalan, spbu, bengkel, kos, villa, gedung, pabrik];
}

/// Sumber sprite per aset. Saat sheet Blender siap, cukup ganti barisnya ke
/// `PngSource('<nama>')`; kamera, fisika, dan animasi game tidak berubah.
final spriteSources = <String, SpriteSource>{
  SpriteIds.pinTujuan: const BakedSource(pinTujuanAsset),
  SpriteIds.slime: const BakedSource(slimeAsset),
  SpriteIds.motor: const BakedSource(motorAsset),
  SpriteIds.spbu: BakedSource(spbuAsset),
  SpriteIds.bengkel: BakedSource(bengkelAsset),
  SpriteIds.rumah: BakedSource(rumahAsset),
  SpriteIds.kos: BakedSource(kosAsset),
  SpriteIds.villa: BakedSource(villaAsset),
  SpriteIds.ruko: BakedSource(rukoAsset),
  SpriteIds.gedung: BakedSource(gedungAsset),
  SpriteIds.pabrik: BakedSource(pabrikAsset),
  SpriteIds.pohon: BakedSource(pohonAsset),
  SpriteIds.lampuJalan: BakedSource(lampuJalanAsset),
};

/// Memuat dan menyimpan (cache) sprite per id; tiap aset dipanggang/dimuat sekali.
class SpriteLibrary {
  SpriteLibrary({
    required this.loadImage,
    required this.loadText,
    Map<String, SpriteSource>? sources,
    this.cacheDir,
    int? bakeWorkers,
  }) : sources = sources ?? spriteSources,
       bakeWorkers = bakeWorkers ?? (kIsWeb ? 1 : (Platform.numberOfProcessors - 1).clamp(2, 6));

  /// Memuat gambar/teks berdasarkan nama file di `assets/images/`.
  final Future<ui.Image> Function(String file) loadImage;
  final Future<String> Function(String file) loadText;
  final Map<String, SpriteSource> sources;

  /// Folder cache disk untuk atlas hasil panggang; null = selalu panggang ulang.
  final Future<String?> Function()? cacheDir;

  /// Jumlah isolate yang memanggang bersamaan.
  final int bakeWorkers;

  final _cache = <String, Future<DirectionalSprite>>{};
  final _ready = <String, DirectionalSprite>{};

  Future<DirectionalSprite> load(String id) => _cache[id] ??= _load(id).then((s) => _ready[id] = s);

  /// Sprite yang sudah selesai dimuat lewat [load].
  /// Sprite [id] bila sudah selesai dimuat, tanpa memicu pemuatan.
  DirectionalSprite? loaded(String id) => _ready[id];

  DirectionalSprite operator [](String id) => _ready[id] ?? (throw StateError('sprite "$id" belum dimuat'));

  Future<DirectionalSprite> _load(String id) async {
    final source = sources[id] ?? (throw ArgumentError('sprite "$id" tidak terdaftar'));
    switch (source) {
      case BakedSource(:final asset):
        // Web tidak punya isolate maupun disk: panggang langsung.
        if (kIsWeb) return bakeModel(asset).toSprite();
        final sw = Stopwatch()..start();
        // Di isolate lain supaya UI tidak tersendat; cache disk dipakai bila
        // sidik jari modelnya sama.
        final dir = await cacheDir?.call();
        final cache = dir == null ? null : BakeCache(dir);
        final fp = await Isolate.run(() => fingerprint(asset));
        var sheet = cache == null ? null : await Isolate.run(() => cache.read(id, fp));
        final cached = sheet != null;
        sheet ??= await bakeModelParallel(asset, workers: bakeWorkers);
        if (!cached && cache != null) {
          final baked = sheet;
          unawaited(Isolate.run(() => cache.write(id, fp, baked)).catchError((Object _) {}));
        }
        debugPrint('sprite $id: ${cached ? 'dari cache' : 'dipanggang'} ${sw.elapsedMilliseconds} ms');
        return sheet.toSprite();
      case PngSource(:final name):
        final spec = SpriteSheetSpec.parse(await loadText('$name.json'));
        return DirectionalSprite(await loadImage('$name.png'), spec);
    }
  }
}
