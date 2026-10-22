import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;

import '../model3d/bake.dart';
import '../model3d/models/pin_tujuan.dart';
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
}

/// Sumber sprite per aset. Saat sheet Blender siap, cukup ganti barisnya ke
/// `PngSource('<nama>')`; kamera, fisika, dan animasi game tidak berubah.
final spriteSources = <String, SpriteSource>{
  SpriteIds.pinTujuan: const BakedSource(pinTujuanAsset),
};

/// Memuat dan menyimpan (cache) sprite per id; tiap aset dipanggang/dimuat sekali.
class SpriteLibrary {
  SpriteLibrary({required this.loadImage, required this.loadText, Map<String, SpriteSource>? sources})
    : sources = sources ?? spriteSources;

  /// Memuat gambar/teks berdasarkan nama file di `assets/images/`.
  final Future<ui.Image> Function(String file) loadImage;
  final Future<String> Function(String file) loadText;
  final Map<String, SpriteSource> sources;

  final _cache = <String, Future<DirectionalSprite>>{};
  final _ready = <String, DirectionalSprite>{};

  Future<DirectionalSprite> load(String id) => _cache[id] ??= _load(id).then((s) => _ready[id] = s);

  /// Sprite yang sudah selesai dimuat lewat [load].
  DirectionalSprite operator [](String id) => _ready[id] ?? (throw StateError('sprite "$id" belum dimuat'));

  Future<DirectionalSprite> _load(String id) async {
    final source = sources[id] ?? (throw ArgumentError('sprite "$id" tidak terdaftar'));
    switch (source) {
      case BakedSource(:final asset):
        // Panggang di isolate lain supaya UI tidak tersendat (web tidak punya isolate).
        final sheet = kIsWeb ? bakeModel(asset) : await Isolate.run(() => bakeModel(asset));
        return sheet.toSprite();
      case PngSource(:final name):
        final spec = SpriteSheetSpec.parse(await loadText('$name.json'));
        return DirectionalSprite(await loadImage('$name.png'), spec);
    }
  }
}
