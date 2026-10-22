import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle, FontWeight;

import '../../ui/palette.dart';
import '../batam_game.dart';
import '../iso.dart';
import '../map/land_mask.dart';
import '../map/road_graph.dart';
import '../model3d/mesh.dart';
import '../model3d/raster.dart' show IsoCamera;
import 'city_gen.dart';

/// Benda kota yang digambar [CityLayer]: sprite bangunan/pohon/lampu, plus
/// gambar 2D tambahan ([overlay], mis. papan nama) di titik pijaknya.
class CityProp {
  CityProp(this.spec, {this.overlay, this.overlayBounds});

  final PropSpec spec;

  /// Digambar setelah sprite, kanvas sudah digeser ke titik pijak (layar iso).
  final void Function(Canvas canvas)? overlay;

  /// Batas layar overlay (relatif titik pijak) untuk benda tanpa sprite.
  final Rect? overlayBounds;

  /// Batas gambar di layar iso (satuan dunia); dihitung saat sprite siap.
  Rect? screen;

  /// Kejelasan 0..1; turun saat menutupi pemain.
  double alpha = 1;

  bool get hasSprite => spec.sprite.isNotEmpty;

  double get key => spec.depthKey;
}

/// Lapisan kota: bangunan, pohon, dan lampu di chunk yang terlihat, digambar
/// urut kedalaman bersama aktor (anak komponen ini: pemain, motor, pin tujuan).
/// Bangunan yang menutupi pemain dibuat tembus pandang.
class CityLayer extends Component with HasGameReference<BatamGame> {
  CityLayer({required this.graph, required this.mask}) : super(priority: 0);

  final RoadGraph graph;
  final LandMask mask;
  late final zones = ZoneMap(graph);

  final _props = <int, List<CityProp>>{};
  final _decor = <int, List<CityProp>>{};
  /// Kotak penghalang per sel 20×20, bersama sprite pemiliknya.
  final _blockers = <int, List<(Rect, String)>>{};
  final _footprints = RectIndex();

  /// Blok kota sudah dibuat; pohon & lampu baru ditempatkan setelahnya supaya
  /// tidak menimpa bangunan.
  bool buildingsReady = false;

  double _dt = 0;

  static int _chunkKey(int cx, int cy) => cx * 100000 + cy;

  static int _chunkOf(double v) => (v / chunkSize).floor();

  void addProp(CityProp p) {
    final at = p.spec.at;
    (_props[_chunkKey(_chunkOf(at.dx), _chunkOf(at.dy))] ??= []).add(p);
    if (p.spec.footprint case final f?) _footprints.add(f);
    for (final b in p.spec.blockers) {
      for (var cx = (b.left / 20).floor(); cx <= (b.right / 20).floor(); cx++) {
        for (var cy = (b.top / 20).floor(); cy <= (b.bottom / 20).floor(); cy++) {
          (_blockers[_chunkKey(cx, cy)] ??= []).add((b, p.spec.sprite));
        }
      }
    }
  }

  void addProps(Iterable<CityProp> props) => props.forEach(addProp);

  /// Blok kota hasil [generateBuildings]; sesudah ini pohon & lampu mulai dibuat.
  void addBuildings(List<PropSpec> specs) {
    for (final s in specs) {
      addProp(CityProp(s));
    }
    buildingsReady = true;
    _decor.clear();
  }

  /// Titik [p] ada di dalam bangunan yang sudah tampil (sprite-nya siap), jadi
  /// tidak ada dinding tak terlihat selama sprite kota masih dipanggang.
  bool blocks(Offset p) {
    for (final (r, sprite) in _blockers[_chunkKey((p.dx / 20).floor(), (p.dy / 20).floor())] ?? const <(Rect, String)>[]) {
      if (r.contains(p) && game.sprites.loaded(sprite) != null) return true;
    }
    return false;
  }

  List<CityProp> _decorFor(int cx, int cy) => _decor[_chunkKey(cx, cy)] ??= [
    for (final s in generateChunkDecor(graph, mask, zones, cx, cy, nearBuilding: _footprints.overlaps)) CityProp(s),
  ];

  @override
  void update(double dt) {
    super.update(dt);
    _dt = dt;
  }

  final _visible = <CityProp>[];
  final _fadePaint = Paint()..filterQuality = FilterQuality.medium;

  @override
  void renderTree(Canvas canvas) {
    if (!game.worldReady.value) return;
    final view = game.camera.visibleWorldRect;
    // Bangunan tinggi yang titik pijaknya di bawah layar masih bisa terlihat.
    final reach = groundRectOf(Rect.fromLTRB(view.left - 25, view.top - 5, view.right + 25, view.bottom + 45));
    _visible.clear();
    for (var cy = _chunkOf(reach.top); cy <= _chunkOf(reach.bottom); cy++) {
      for (var cx = _chunkOf(reach.left); cx <= _chunkOf(reach.right); cx++) {
        _collect(_props[_chunkKey(cx, cy)], view);
        if (buildingsReady) _collect(_decorFor(cx, cy), view);
      }
    }
    _visible.sort((a, b) => a.key.compareTo(b.key));

    // Aktor: kunci kedalaman dari bangunan yang bertumpuk dengannya di layar.
    final actors = [
      for (final c in children)
        if (c is PositionComponent) (c, _actorKey(c.position)),
    ]..sort((a, b) {
      final k = a.$2.compareTo(b.$2);
      return k != 0 ? k : a.$1.priority.compareTo(b.$1.priority);
    });

    final player = game.player;
    final playerKey = actors.where((a) => identical(a.$1, player)).firstOrNull?.$2;
    final playerBox = _actorBox(player.position);

    var ai = 0;
    for (final p in _visible) {
      while (ai < actors.length && actors[ai].$2 < p.key) {
        actors[ai++].$1.renderTree(canvas);
      }
      final covers = playerKey != null && p.key > playerKey && p.screen!.overlaps(playerBox);
      final target = covers ? 0.38 : 1.0;
      p.alpha += (target - p.alpha) * math.min(1, _dt * 10);
      _draw(canvas, p);
    }
    while (ai < actors.length) {
      actors[ai++].$1.renderTree(canvas);
    }
  }

  void _collect(List<CityProp>? props, Rect view) {
    if (props == null) return;
    for (final p in props) {
      final r = p.screen ??= _screenOf(p);
      if (r != null && r.overlaps(view)) _visible.add(p);
    }
  }

  Rect? _screenOf(CityProp p) {
    final base = isoOf(p.spec.at);
    if (!p.hasSprite) return p.overlayBounds?.shift(base);
    final sprite = game.sprites.loaded(p.spec.sprite);
    if (sprite == null) return null;
    final r = sprite.spec.worldRect;
    return Rect.fromLTRB(r.left * p.spec.scale, r.top * p.spec.scale, r.right * p.spec.scale, r.bottom * p.spec.scale)
        .shift(base);
  }

  static Rect _actorBox(Vector2 g) {
    final s = isoOf(g.toOffset());
    return Rect.fromLTRB(s.dx - 2, s.dy - 4.5, s.dx + 2, s.dy + 0.5);
  }

  /// Kunci kedalaman aktor di [g]: di depan semua benda yang tidak menutupinya
  /// dan di belakang benda yang tapaknya ada di antara aktor dan kamera.
  double _actorKey(Vector2 g) {
    final box = _actorBox(g);
    var lo = double.negativeInfinity, hi = double.infinity;
    for (final p in _visible) {
      if (!p.screen!.overlaps(box)) continue;
      final f = p.spec.footprint ?? Rect.fromCircle(center: p.spec.at, radius: 0.4);
      if (_behind(g, f)) {
        hi = math.min(hi, p.key);
      } else {
        lo = math.max(lo, p.key);
      }
    }
    final k = g.x + g.y;
    if (lo >= hi) return lo + 1e-3;
    return k.clamp(lo + 1e-3, hi - 1e-3);
  }

  /// Sinar dari [g] ke arah kamera (+x, +y di tanah) mengenai tapak [f].
  static bool _behind(Vector2 g, Rect f) {
    final t0 = math.max(0.0, math.max(f.left - g.x, f.top - g.y));
    final t1 = math.min(f.right - g.x, f.bottom - g.y);
    return t0 <= t1;
  }

  void _draw(Canvas canvas, CityProp p) {
    final at = isoOf(p.spec.at);
    canvas.save();
    canvas.translate(at.dx, at.dy);
    if (p.hasSprite) {
      final sprite = game.sprites.loaded(p.spec.sprite)!;
      if (p.spec.scale != 1) canvas.scale(p.spec.scale);
      _fadePaint.color = Color.fromRGBO(0, 0, 0, p.alpha);
      sprite.render(canvas, direction: p.spec.dir, frame: p.spec.frame, paint: p.alpha < 0.99 ? _fadePaint : null);
    }
    if (p.alpha > 0.9) p.overlay?.call(canvas);
    canvas.restore();
  }
}

final _labels = <String, TextPainter>{};

TextPainter _label(String text, double size, Color color) => _labels['$text|$size|${color.toARGB32()}'] ??= TextPainter(
  text: TextSpan(
    text: text,
    style: TextStyle(fontSize: size, fontWeight: FontWeight.w900, color: color, letterSpacing: size * 0.05),
  ),
  textDirection: TextDirection.ltr,
)..layout();

/// Overlay tulisan [text] di papan muka depan bangunan menghadap [facing],
/// titik tengah papan [at] (koordinat model). Hanya muka yang menghadap kamera
/// (timur atau selatan) yang diberi tulisan.
void Function(Canvas)? faceLabel(String text, ({V3 at, double width}) board, int facing, {Color color = const Color(0xFFFFFFFF)}) {
  if (facing != 0 && facing != 1) return null;
  final tp = _label(text, 1.0, color);
  final g = modelToGround(Offset(board.at.x, board.at.y), facing, Offset.zero);
  final center = isoOf(g) - Offset(0, board.at.z * IsoCamera.heightScale);
  // Arah "kanan" saat memandang muka depan dari luar.
  final f = facingVector(facing);
  final u = isoOf(Offset(f.dy, -f.dx));
  final scale = math.min(1.0, board.width * 0.85 / tp.width);
  return (canvas) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.transform(
      Float64List.fromList([u.dx * scale, u.dy * scale, 0, 0, 0, IsoCamera.heightScale * scale, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
    );
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  };
}

final _post = Paint()
  ..color = BColors.ink
  ..strokeWidth = 0.22
  ..strokeCap = StrokeCap.round;
final _signInk = Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = 0.2
  ..color = BColors.ink;

/// Papan status di tiang (mis. DIJUAL / RUMAHMU / BUKA), tegak menghadap layar.
CityProp statusSign(Offset at, (String, Color) Function() status) {
  const h = 2.6;
  return CityProp(
    PropSpec(sprite: '', at: at),
    overlayBounds: const Rect.fromLTRB(-4, -h - 1.2, 4, 0.2),
    overlay: (canvas) {
      final (text, color) = status();
      final tp = _label(text, 0.95, const Color(0xFFFFFFFF));
      canvas.drawLine(Offset.zero, const Offset(0, -h), _post);
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(0, -h), width: tp.width + 1.0, height: tp.height + 0.35),
        const Radius.circular(0.35),
      );
      canvas.drawRRect(r, Paint()..color = color);
      canvas.drawRRect(r, _signInk);
      tp.paint(canvas, Offset(-tp.width / 2, -h - tp.height / 2));
    },
  );
}
