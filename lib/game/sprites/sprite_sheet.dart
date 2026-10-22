import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

/// Format sprite bersama. Kode game hanya membaca format ini, entah gambarnya
/// dipanggang dari model Dart (`model3d/`) atau dimuat dari PNG hasil Blender.
///
/// Tata letak atlas: kolom = 16 arah, baris = frame semua animasi berurutan
/// (animasi pertama di baris paling atas). Semua sel berukuran sama.
/// Arah `d` = heading tanah `d × 22,5°`: 0 = timur, 4 = selatan, 8 = barat,
/// 12 = utara (sama dengan `heading` motor/pemain, bukan arah layar).
///
/// PNG sprite sheet ditemani file JSON bernama sama, mis. `slime.png` + `slime.json`:
/// ```json
/// {"directions": 16, "frameWidth": 128, "frameHeight": 128,
///  "anchorX": 64, "anchorY": 110, "pixelsPerUnit": 36,
///  "animations": [{"name": "idle", "frames": 4, "fps": 6, "loop": true}]}
/// ```

/// Satu animasi dalam sheet.
class SpriteAnim {
  const SpriteAnim(this.name, {this.frames = 1, this.fps = 8, this.loop = true});

  factory SpriteAnim.fromJson(Map<String, dynamic> j) => SpriteAnim(
    j['name'] as String,
    frames: j['frames'] as int? ?? 1,
    fps: (j['fps'] as num?)?.toDouble() ?? 8,
    loop: j['loop'] as bool? ?? true,
  );

  final String name;
  final int frames;
  final double fps;
  final bool loop;

  Map<String, dynamic> toJson() => {'name': name, 'frames': frames, 'fps': fps, 'loop': loop};

  /// Frame ke berapa setelah [time] detik.
  int frameAt(double time) {
    final f = (time * fps).floor();
    return loop ? f % frames : f.clamp(0, frames - 1);
  }
}

/// Ukuran sel, titik pijak, skala, dan daftar animasi sebuah sheet.
class SpriteSheetSpec {
  const SpriteSheetSpec({
    this.directions = 16,
    required this.frameWidth,
    required this.frameHeight,
    required this.anchor,
    required this.pixelsPerUnit,
    required this.animations,
  });

  factory SpriteSheetSpec.fromJson(Map<String, dynamic> j) => SpriteSheetSpec(
    directions: j['directions'] as int? ?? 16,
    frameWidth: j['frameWidth'] as int,
    frameHeight: j['frameHeight'] as int,
    anchor: Offset((j['anchorX'] as num).toDouble(), (j['anchorY'] as num).toDouble()),
    pixelsPerUnit: (j['pixelsPerUnit'] as num).toDouble(),
    animations: [for (final a in j['animations'] as List) SpriteAnim.fromJson(a as Map<String, dynamic>)],
  );

  factory SpriteSheetSpec.parse(String json) => SpriteSheetSpec.fromJson(jsonDecode(json) as Map<String, dynamic>);

  final int directions;
  final int frameWidth, frameHeight;

  /// Titik pijak (kaki/tanah) di dalam sel, dalam piksel dari pojok kiri-atas.
  final Offset anchor;

  /// Piksel sheet per satuan dunia; game menggambar sel dengan skala `1 / pixelsPerUnit`.
  final double pixelsPerUnit;
  final List<SpriteAnim> animations;

  int get rows => animations.fold(0, (n, a) => n + a.frames);
  int get sheetWidth => directions * frameWidth;
  int get sheetHeight => rows * frameHeight;

  SpriteAnim anim(String name) =>
      animations.firstWhere((a) => a.name == name, orElse: () => throw ArgumentError('animasi "$name" tidak ada'));

  /// Baris pertama animasi [name] di atlas.
  int rowOf(String name) {
    var row = 0;
    for (final a in animations) {
      if (a.name == name) return row;
      row += a.frames;
    }
    throw ArgumentError('animasi "$name" tidak ada');
  }

  /// Kotak sumber satu sel di atlas.
  Rect cell(int direction, String anim, int frame) => Rect.fromLTWH(
    (direction % directions) * frameWidth.toDouble(),
    (rowOf(anim) + frame) * frameHeight.toDouble(),
    frameWidth.toDouble(),
    frameHeight.toDouble(),
  );

  /// Kotak gambar di dunia (satuan dunia, relatif ke titik pijak).
  Rect get worldRect => Rect.fromLTWH(
    -anchor.dx / pixelsPerUnit,
    -anchor.dy / pixelsPerUnit,
    frameWidth / pixelsPerUnit,
    frameHeight / pixelsPerUnit,
  );

  Map<String, dynamic> toJson() => {
    'directions': directions,
    'frameWidth': frameWidth,
    'frameHeight': frameHeight,
    'anchorX': anchor.dx,
    'anchorY': anchor.dy,
    'pixelsPerUnit': pixelsPerUnit,
    'animations': [for (final a in animations) a.toJson()],
  };

  /// Teks JSON untuk file pendamping PNG.
  String encode() => jsonEncode(toJson());

  /// Arah terdekat untuk heading tanah [heading] (radian).
  int directionOf(double heading) {
    final step = 2 * math.pi / directions;
    return (heading / step).round() % directions;
  }

  /// Seperti [directionOf], tapi tetap di [current] sampai [heading] lewat batas
  /// arah lebih dari [margin] radian, supaya sprite tidak berkedip di batas.
  int directionWithHysteresis(int current, double heading, {double margin = 3 * math.pi / 180}) {
    final step = 2 * math.pi / directions;
    var off = (heading - current * step) % (2 * math.pi);
    if (off > math.pi) off -= 2 * math.pi;
    return off.abs() > step / 2 + margin ? directionOf(heading) : current;
  }
}

/// Sheet yang sudah dimuat: atlas + spesifikasinya.
class DirectionalSprite {
  DirectionalSprite(this.image, this.spec)
    : assert(image.width >= spec.sheetWidth && image.height >= spec.sheetHeight, 'atlas lebih kecil dari spec');

  final Image image;
  final SpriteSheetSpec spec;

  static final _paint = Paint()..filterQuality = FilterQuality.medium;

  /// Gambar sel arah [direction], animasi [anim] pada detik [time], dengan
  /// titik pijak di (0,0) kanvas dan ukuran dalam satuan dunia.
  void render(Canvas canvas, {required int direction, String? anim, double time = 0, Paint? paint}) {
    final a = anim == null ? spec.animations.first : spec.anim(anim);
    canvas.drawImageRect(image, spec.cell(direction, a.name, a.frameAt(time)), spec.worldRect, paint ?? _paint);
  }
}
