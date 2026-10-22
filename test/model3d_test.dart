import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:batam_the_journey_begins/game/iso.dart';
import 'package:batam_the_journey_begins/game/model3d/bake.dart';
import 'package:batam_the_journey_begins/game/model3d/mesh.dart';
import 'package:batam_the_journey_begins/game/model3d/models/pin_tujuan.dart';
import 'package:batam_the_journey_begins/game/model3d/models/slime.dart';
import 'package:batam_the_journey_begins/game/model3d/raster.dart';
import 'package:batam_the_journey_begins/game/sprites/bake_cache.dart';
import 'package:batam_the_journey_begins/game/sprites/sprite_library.dart';
import 'package:batam_the_journey_begins/game/sprites/sprite_sheet.dart';
import 'package:flutter/painting.dart' show Color, Offset;
import 'package:flutter_test/flutter_test.dart';

const _ink = Color(0xFF2B1D12);
const _grey = Material(Color(0xFFB0B0B0));

/// Semua normal muka menjauhi titik tengah mesh (mesh tertutup, arah putar benar).
void _expectOutward(Mesh m, V3 center) {
  for (final t in m.tris) {
    expect(t.faceNormal.dot(t.centroid - center), greaterThan(0), reason: 'muka di ${t.centroid}');
  }
}

double _luma(Color c) => 0.3 * c.r + 0.59 * c.g + 0.11 * c.b;

/// Pusat massa piksel berwarna [c] (toleransi kecil) relatif ke titik pijak.
Offset _centroidOf(RasterImage img, bool Function(Color) match) {
  var sx = 0.0, sy = 0.0, n = 0;
  for (var y = 0; y < img.height; y++) {
    for (var x = 0; x < img.width; x++) {
      if (img.alphaAt(x, y) == 255 && match(img.colorAt(x, y))) {
        sx += x + 0.5;
        sy += y + 0.5;
        n++;
      }
    }
  }
  expect(n, greaterThan(0));
  return Offset(sx / n, sy / n) - img.anchor;
}

RasterImage _render(Model m, {double yaw = 0, double ppu = 32}) {
  var bounds = projectedBounds(m, yaw);
  bounds = bounds.expandToInclude(ui.Rect.zero);
  return renderModel(
    m,
    yaw: yaw,
    pixelsPerUnit: ppu,
    frame: PixelFrame.around(bounds, ppu, pad: const RenderStyle().padPx),
  );
}

Future<void> _writePng(ui.Image image, String name) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('build/model3d/$name.png');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes!.buffer.asUint8List());
}

/// Aset kecil untuk tes panggang paralel & cache.
const _cubeAsset = ModelAsset(pixelsPerUnit: 12, animations: [SpriteAnim('idle', frames: 2)], build: _cube);
const _cubeTallAsset = ModelAsset(pixelsPerUnit: 12, animations: [SpriteAnim('idle', frames: 2)], build: _cubeTall);

Model _cube(SpriteAnim a, int f) => Model([Part(Mesh.box(1, 1, 1.0 + f * 0.5), _grey)]);
Model _cubeTall(SpriteAnim a, int f) => Model([Part(Mesh.box(1, 1, 1.2 + f * 0.5), _grey)]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('primitif', () {
    test('kotak, silinder, kerucut, bola: normal menghadap keluar', () {
      _expectOutward(Mesh.box(2, 3, 4), const V3(0, 0, 2));
      expect(Mesh.box(1, 1, 1).tris, hasLength(12));
      _expectOutward(Mesh.cylinder(1, 2), const V3(0, 0, 1));
      _expectOutward(Mesh.cylinder(1, 2, rTop: 0), const V3(0, 0, 0.5));
      _expectOutward(Mesh.sphere(1, ry: 2, rz: 0.5), V3.zero);
    });

    test('bentuk putar: normal halus & muka menghadap keluar, tutup tanpa segitiga kosong', () {
      const profile = [Offset(0, 0), Offset(1, 0), Offset(1.2, 0.5), Offset(0.8, 1.5), Offset(0, 2)];
      final m = Mesh.lathe(profile, segments: 10);
      _expectOutward(m, const V3(0, 0, 0.9));
      // Ujung berjari-jari 0 hanya memberi satu segitiga per segmen.
      expect(m.tris, hasLength(10 * (1 + 2 + 2 + 1)));
      for (final t in m.tris) {
        expect(t.na.length, closeTo(1, 1e-9));
        expect(t.na.dot(t.faceNormal), greaterThan(0));
      }
    });

    test('normal halus bola = arah dari pusat', () {
      for (final t in Mesh.sphere(1).tris) {
        expect(t.na.dot(t.a.normalized()), closeTo(1, 1e-9));
      }
    });

    test('ekstrusi poligon cekung (huruf L) tertutup dan luas tutupnya benar', () {
      const l = [Offset(0, 0), Offset(3, 0), Offset(3, 1), Offset(1, 1), Offset(1, 3), Offset(0, 3)];
      final tris = triangulate(l);
      expect(tris, hasLength(4));
      final area = tris.fold(0.0, (s, t) => s + signedArea([l[t.$1], l[t.$2], l[t.$3]]));
      expect(area, closeTo(5, 1e-9));
      // Arah putar terbalik tetap menghasilkan muka yang menghadap keluar.
      for (final pts in [l, l.reversed.toList()]) {
        final m = Mesh.extrude(pts, 1);
        for (final t in m.tris.where((t) => t.faceNormal.z.abs() > 0.5)) {
          expect(t.faceNormal.z.sign, t.centroid.z > 0.5 ? 1 : -1);
        }
      }
    });

    test('transformasi part: skala tak seragam tetap memberi normal yang benar', () {
      const part = Part(Mesh(<Tri>[]), _grey, scale: V3(2, 1, 1), rotZ: math.pi / 2);
      // Normal permukaan miring (1,1,0) pada skala x2 → condong ke y sebelum diputar.
      final n = part.normal(const V3(1, 1, 0).normalized());
      expect(n.length, closeTo(1, 1e-9));
      expect(n.x.abs(), greaterThan(n.y.abs()));
    });
  });

  group('kamera iso', () {
    test('lantai (z = 0) sama persis dengan isoOf', () {
      for (final g in const [Offset(3, 0), Offset(0, 5), Offset(-2, 7)]) {
        expect(IsoCamera.project(V3(g.dx, g.dy, 0)), isoOf(g));
      }
    });

    test('toCamera satuan dan tegak lurus bidang layar', () {
      expect(IsoCamera.toCamera.length, closeTo(1, 1e-12));
      // Titik yang bergeser searah kamera tidak berpindah di layar.
      final p = IsoCamera.project(IsoCamera.toCamera * 3);
      expect(p.dx, closeTo(0, 1e-12));
      expect(p.dy, closeTo(0, 1e-12));
    });
  });

  group('render', () {
    final box = Model([Part(Mesh.box(2, 2, 2), _grey)]);

    test('cahaya: atas paling terang, sisi kiri layar sedang, sisi kanan paling gelap', () {
      final img = _render(box);
      Color at(V3 p) {
        final s = IsoCamera.project(p) * 32 + img.anchor;
        return img.colorAt(s.dx.floor(), s.dy.floor());
      }

      final top = at(const V3(0, 0, 2)), left = at(const V3(0, 1, 1)), right = at(const V3(1, 0, 1));
      expect(_luma(top), greaterThan(_luma(left)));
      expect(_luma(left), greaterThan(_luma(right)));
    });

    test('outline tinta di siluet, transparan di luar, titik pijak di tanah', () {
      final img = _render(box);
      // Baris tengah: piksel pertama yang tidak transparan dari kiri adalah tinta.
      final y = img.anchor.dy.floor() - 20;
      final x = List.generate(img.width, (i) => i).firstWhere((i) => img.alphaAt(i, y) > 0);
      expect(img.alphaAt(0, y), 0);
      final c = img.colorAt(x, y);
      expect(_luma(c), lessThan(_luma(_ink) + 0.05));
      // Sudut bawah kotak (1,1,0) jatuh di bawah titik pijak, tepat di isoOf.
      final foot = isoOf(const Offset(1, 1)) * 32 + img.anchor;
      expect(img.alphaAt(foot.dx.floor(), foot.dy.floor() - 2), 255);
    });

    test('garis tinta di batas antar-part, di sisi part yang lebih jauh', () {
      final m = Model([
        Part(Mesh.box(2, 2, 1), _grey),
        Part(Mesh.box(0.8, 0.8, 0.2), const Material(Color(0xFFE4573D)), at: const V3(0, 0, 1)),
      ]);
      final img = _render(m);
      // Di sepanjang garis dari pusat tutup merah ke tepi atas kotak ada piksel tinta.
      final c = IsoCamera.project(const V3(0, 0, 1.2)) * 32 + img.anchor;
      final edge = IsoCamera.project(const V3(0, 0.95, 1)) * 32 + img.anchor;
      var sawRed = false, sawInkAfterRed = false;
      for (var t = 0.0; t <= 1; t += 0.02) {
        final p = c + (edge - c) * t;
        final col = img.colorAt(p.dx.floor(), p.dy.floor());
        if (col.r > 0.7 && col.g < 0.5) sawRed = true;
        if (sawRed && _luma(col) < 0.25) sawInkAfterRed = true;
      }
      expect(sawRed, isTrue);
      expect(sawInkAfterRed, isTrue);
    });

    test('16 arah: hidung model mengikuti heading tanah di layar', () {
      const nose = Color(0xFFFF0000);
      final m = Model([
        Part(Mesh.box(1, 1, 1), _grey),
        Part(Mesh.sphere(0.3), const Material(nose), at: const V3(2.5, 0, 0.5)),
      ]);
      for (var d = 0; d < 16; d++) {
        final yaw = 2 * math.pi * d / 16;
        final img = _render(m, yaw: yaw);
        final got = _centroidOf(img, (c) => c.r > 0.6 && c.g < 0.35 && c.b < 0.35);
        final want = IsoCamera.project(V3(2.5 * math.cos(yaw), 2.5 * math.sin(yaw), 0.5)) * 32;
        expect((got - want).distance, lessThan(4), reason: 'arah $d: $got vs $want');
      }
    });
  });

  group('format sprite', () {
    const spec = SpriteSheetSpec(
      frameWidth: 10,
      frameHeight: 20,
      anchor: Offset(5, 18),
      pixelsPerUnit: 4,
      animations: [SpriteAnim('idle', frames: 2, fps: 4), SpriteAnim('jalan', frames: 3, loop: false)],
    );

    test('JSON bolak-balik', () {
      final back = SpriteSheetSpec.parse(spec.encode());
      expect(back.toJson(), spec.toJson());
      expect(back.rows, 5);
      expect(back.sheetWidth, 160);
      expect(back.sheetHeight, 100);
    });

    test('sel atlas: kolom = arah, baris = frame animasi berurutan', () {
      expect(spec.cell(3, 'idle', 1), const ui.Rect.fromLTWH(30, 20, 10, 20));
      expect(spec.cell(15, 'jalan', 2), const ui.Rect.fromLTWH(150, 80, 10, 20));
      expect(spec.worldRect, const ui.Rect.fromLTWH(-1.25, -4.5, 2.5, 5));
    });

    test('frame animasi: loop berputar, non-loop berhenti di frame terakhir', () {
      expect(spec.anim('idle').frameAt(0.6), 0); // 0,6 × 4 = 2 → 2 % 2
      expect(spec.anim('idle').frameAt(0.3), 1);
      expect(spec.anim('jalan').frameAt(10), 2);
    });

    test('arah dari heading tanah, dengan histeresis', () {
      const step = math.pi / 8;
      expect(spec.directionOf(0), 0);
      expect(spec.directionOf(math.pi / 2), 4);
      expect(spec.directionOf(-math.pi / 2), 12);
      expect(spec.directionOf(math.pi), 8);
      // Sedikit lewat batas: tetap; jauh lewat batas: pindah.
      expect(spec.directionWithHysteresis(0, step / 2 + 0.01), 0);
      expect(spec.directionWithHysteresis(0, step / 2 + 0.1), 1);
      expect(spec.directionWithHysteresis(0, -step / 2 - 0.1), 15);
    });
  });

  group('panggang', () {
    test('pin tujuan: atlas 16 arah, titik pijak bulat di dalam sel, PNG tertulis', () async {
      final sheet = bakeModel(pinTujuanAsset);
      final spec = sheet.spec;
      expect(spec.directions, 16);
      expect(spec.rows, 1);
      expect(spec.anchor.dx, spec.anchor.dx.roundToDouble());
      expect(spec.anchor.dx, inInclusiveRange(0, spec.frameWidth));
      expect(spec.anchor.dy, inInclusiveRange(0, spec.frameHeight));
      expect(sheet.rgba.length, spec.sheetWidth * spec.sheetHeight * 4);
      // Tiap sel berisi gambar.
      for (var d = 0; d < 16; d++) {
        var opaque = 0;
        for (var y = 0; y < spec.frameHeight; y++) {
          for (var x = 0; x < spec.frameWidth; x++) {
            if (sheet.rgba[((y * spec.sheetWidth) + d * spec.frameWidth + x) * 4 + 3] == 255) opaque++;
          }
        }
        expect(opaque, greaterThan(200), reason: 'arah $d');
      }
      final image = await sheet.toImage();
      expect(image.width, spec.sheetWidth);
      expect(image.height, spec.sheetHeight);
      await _writePng(image, 'pin_tujuan');
      File('build/model3d/pin_tujuan.json').writeAsStringSync(spec.encode());
    });

    test('slime: semua animasi × 16 arah, mata terlihat dari depan, tidak dari belakang', () async {
      final sheet = bakeModel(slimeAsset);
      final spec = sheet.spec;
      await _writePng(await sheet.toImage(), 'slime');
      File('build/model3d/slime.json').writeAsStringSync(spec.encode());
      expect(spec.rows, 4 + 1 + 6 + 2);
      int count(int dir, String anim, bool Function(int r, int g, int b) match) {
        final cell = spec.cell(dir, anim, 0);
        var n = 0;
        for (var y = cell.top.toInt(); y < cell.bottom; y++) {
          for (var x = cell.left.toInt(); x < cell.right; x++) {
            final i = (y * spec.sheetWidth + x) * 4;
            if (sheet.rgba[i + 3] == 255 && match(sheet.rgba[i], sheet.rgba[i + 1], sheet.rgba[i + 2])) n++;
          }
        }
        return n;
      }

      bool white(int r, int g, int b) => r > 225 && g > 225 && b > 225;
      // Heading 45° (arah 2) menghadap kamera; arah 10 membelakangi. Kilap badan
      // sama di semua arah (badan bulat, cahaya tetap), jadi selisihnya = putih mata.
      final back = count(10, 'idle', white);
      final eyes = count(2, 'idle', white) - back;
      expect(eyes, greaterThan(150));
      // Kedip: putih mata hilang.
      expect(count(2, 'kedip', white) - back, lessThan(eyes ~/ 6));
      // Lelah: kelopak menutup sebagian putih mata.
      expect(count(2, 'lelah', white) - back, lessThan(eyes * 0.8));
    });

    test('slime: lompat mendarat gepeng di tanah, melar saat terbang', () {
      expect(slimeHop(0).lift, 0);
      expect(slimeHop(0).stretch, lessThan(0.9));
      expect(slimeHop(0.5).lift, greaterThan(0.4));
      expect(slimeHop(0.2).stretch, greaterThan(1.05));
      expect(slimeHop(1.0).stretch, closeTo(slimeHop(0).stretch, 1e-9));
    });

    test('contoh semua bentuk dasar (halus & datar) dirender ke PNG', () async {
      final asset = ModelAsset(
        pixelsPerUnit: 32,
        animations: const [SpriteAnim('idle')],
        build: (_, _) => Model([
          Part(Mesh.box(2, 2, 1.2), const Material(Color(0xFFE4573D)), at: const V3(-1.5, 0, 0)),
          Part(Mesh.cylinder(0.7, 1.6, segments: 10), const Material(Color(0xFFF5C451)), at: const V3(1.2, -1, 0)),
          Part(
            Mesh.sphere(0.9, rz: 0.75, segments: 16, rings: 10),
            const Material(Color(0xFF4F95DC), smooth: true, gloss: 0.8),
            at: const V3(1, 1.4, 0.75),
          ),
          Part(
            Mesh.cylinder(0.6, 1.2, rTop: 0, segments: 8),
            const Material(Color(0xFF3E9B5B)),
            at: const V3(-1, 2, 0),
          ),
        ]),
      );
      final sheet = bakeModel(asset);
      await _writePng(await sheet.toImage(), 'bentuk_dasar');
    });
  });

  group('panggang paralel & cache disk', () {
    test('hasil paralel sama persis dengan panggang satu isolate', () async {
      final one = bakeModel(_cubeAsset);
      final many = await bakeModelParallel(_cubeAsset, workers: 3);
      expect(many.spec.toJson(), one.spec.toJson());
      expect(many.rgba, one.rgba);
    });

    test('sidik jari tetap untuk model sama, berubah bila model diubah', () {
      expect(fingerprint(_cubeAsset), fingerprint(_cubeAsset));
      expect(fingerprint(_cubeAsset), isNot(fingerprint(_cubeTallAsset)));
      expect(fingerprint(slimeAsset), isNot(fingerprint(pinTujuanAsset)));
    });

    test('cache disk: tulis lalu baca sama, versi lama dihapus, file rusak = null', () {
      final dir = Directory.systemTemp.createTempSync('bake_cache');
      addTearDown(() => dir.deleteSync(recursive: true));
      final cache = BakeCache(dir.path);
      final sheet = bakeModel(_cubeAsset);
      expect(cache.read('kotak', 'aaaa'), isNull);
      cache.write('kotak', 'aaaa', sheet);
      final back = cache.read('kotak', 'aaaa')!;
      expect(back.spec.toJson(), sheet.spec.toJson());
      expect(back.rgba, sheet.rgba);
      cache.write('kotak', 'bbbb', sheet);
      expect(cache.read('kotak', 'aaaa'), isNull);
      expect(dir.listSync(), hasLength(2));
      File('${dir.path}/kotak-bbbb.rgba.gz').writeAsBytesSync([1, 2, 3]);
      expect(cache.read('kotak', 'bbbb'), isNull);
    });

    test('pustaka memakai cache disk pada pemuatan berikutnya', () async {
      final dir = Directory.systemTemp.createTempSync('bake_lib');
      addTearDown(() => dir.deleteSync(recursive: true));
      SpriteLibrary lib() => SpriteLibrary(
        sources: const {'kotak': BakedSource(_cubeAsset)},
        loadImage: (_) => throw UnimplementedError(),
        loadText: (_) => throw UnimplementedError(),
        cacheDir: () async => dir.path,
      );
      final first = await lib().load('kotak');
      // Tunggu penulisan cache (berjalan di latar).
      final fp = fingerprint(_cubeAsset);
      final spec = File('${dir.path}/kotak-$fp.json');
      for (var i = 0; i < 100 && !spec.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(spec.existsSync(), isTrue);
      final second = await lib().load('kotak');
      expect(second.spec.toJson(), first.spec.toJson());
    });
  });

  group('pustaka sprite', () {
    test('aset dipanggang sekali lalu di-cache', () async {
      final lib = SpriteLibrary(
        loadImage: (_) => throw UnimplementedError(),
        loadText: (_) => throw UnimplementedError(),
      );
      final a = await lib.load(SpriteIds.pinTujuan);
      final b = await lib.load(SpriteIds.pinTujuan);
      expect(identical(a, b), isTrue);
      expect(identical(lib[SpriteIds.pinTujuan], a), isTrue);
      expect(() => lib['tidak_ada'], throwsStateError);
    });

    test('PngSource membaca PNG + JSON dengan format yang sama', () async {
      final baked = bakeModel(pinTujuanAsset);
      final image = await baked.toImage();
      final asked = <String>[];
      final lib = SpriteLibrary(
        sources: const {'pin_blender': PngSource('pin_blender')},
        loadImage: (f) async {
          asked.add(f);
          return image;
        },
        loadText: (f) async {
          asked.add(f);
          return baked.spec.encode();
        },
      );
      final s = await lib.load('pin_blender');
      expect(asked, ['pin_blender.json', 'pin_blender.png']);
      expect(s.spec.toJson(), baked.spec.toJson());
    });
  });
}
