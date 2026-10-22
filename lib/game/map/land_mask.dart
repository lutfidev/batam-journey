import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Offset, Rect, Size;

/// Jenis permukaan satu sel mask.
enum Surface { land, shallow, deep }

/// Mask darat/laut beresolusi rendah, diambil dari `batam_peta.jpg`.
/// Gambar itu menutup persis bbox dunia `0..size.width × 0..size.height`.
class LandMask {
  LandMask._(this.cols, this.rows, this.cell, this._cells);

  /// Ukuran sel dalam satuan dunia.
  static const defaultCell = 5.0;

  final int cols, rows;
  final double cell;
  final Uint8List _cells;

  /// Bangun dari gambar peta yang sudah di-load (mis. `game.mapImage`).
  static Future<LandMask> fromImage(ui.Image image, Size world, {double cell = defaultCell}) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return LandMask.fromRgba(data!.buffer.asUint8List(), image.width, image.height, world, cell: cell);
  }

  /// Tiap sel memilih mayoritas dari 3×3 piksel di sekitar pusatnya,
  /// supaya sungai 1 piksel dan noise JPEG tidak jadi air.
  factory LandMask.fromRgba(Uint8List rgba, int width, int height, Size world, {double cell = defaultCell}) {
    final cols = (world.width / cell).ceil(), rows = (world.height / cell).ceil();
    final cells = Uint8List(cols * rows);
    final sx = width / world.width, sy = height / world.height;
    for (var r = 0; r < rows; r++) {
      final py = ((r + 0.5) * cell * sy).floor();
      for (var c = 0; c < cols; c++) {
        final px = ((c + 0.5) * cell * sx).floor();
        var water = 0, deep = 0;
        for (var dy = -1; dy <= 1; dy++) {
          final y = (py + dy).clamp(0, height - 1);
          for (var dx = -1; dx <= 1; dx++) {
            final x = (px + dx).clamp(0, width - 1);
            final i = (y * width + x) * 4;
            final red = rgba[i], green = rgba[i + 1], blue = rgba[i + 2];
            // Laut #4FB6CC & dangkal #7FCCDA: biru & hijau jauh di atas merah.
            if (blue - red > 50 && green - red > 40) {
              water++;
              if (red < 95) deep++;
            }
          }
        }
        if (water >= 5) cells[r * cols + c] = deep * 2 > water ? 2 : 1;
      }
    }
    return LandMask._(cols, rows, cell, cells);
  }

  /// Nilai sel (kolom, baris); di luar mask dianggap laut dalam.
  Surface at(int c, int r) {
    if (c < 0 || r < 0 || c >= cols || r >= rows) return Surface.deep;
    return Surface.values[_cells[r * cols + c]];
  }

  Surface surfaceAt(Offset p) => at((p.dx / cell).floor(), (p.dy / cell).floor());

  bool isWater(Offset p) => surfaceAt(p) != Surface.land;

  bool isLand(Offset p) => surfaceAt(p) == Surface.land;

  /// Pusat sel (c, r) dalam koordinat dunia.
  Offset centerOf(int c, int r) => Offset((c + 0.5) * cell, (r + 0.5) * cell);

  /// Rentang sel yang menutupi [view], diperluas 1 sel.
  (int, int, int, int) cellRange(Rect view) => (
    (view.left / cell).floor() - 1,
    (view.top / cell).floor() - 1,
    (view.right / cell).floor() + 1,
    (view.bottom / cell).floor() + 1,
  );
}
