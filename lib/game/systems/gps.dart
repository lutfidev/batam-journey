import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../map/pathfinder.dart';
import '../map/road_graph.dart';

class Destination {
  const Destination({required this.title, required this.subtitle, required this.position, this.tag});

  final String title;
  final String subtitle;
  final Offset position;

  /// Pemilik tujuan ini (mis. order ojek aktif), untuk [Gps.onArrive].
  final Object? tag;
}

/// Ringkasan untuk kartu GPS di HUD.
class GpsInfo {
  const GpsInfo({required this.title, required this.remaining, required this.instruction});

  final String title;

  /// Sisa jarak dalam satuan dunia.
  final double remaining;
  final String instruction;
}

/// Teks jarak dari satuan dunia ke meter/km asli: "650 m", "3,2 km".
String formatDistance(double units) {
  final m = units / worldScale;
  if (m < 1000) return '${(m / 10).round() * 10} m';
  return '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
}

/// Perkiraan waktu tempuh naik motor (rata-rata 40 km/j).
String formatEta(double units) {
  final minutes = (units / worldScale / 1000 / 40 * 60).ceil();
  return '${math.max(1, minutes)} mnt';
}

/// GPS: menyimpan rute aktif, melacak posisi pemain di rute,
/// menghitung ulang bila keluar rute, dan menyiapkan instruksi belok.
class Gps {
  Gps(RoadGraph graph, {ValueNotifier<String?>? toast})
    : pathfinder = Pathfinder(graph),
      message = toast ?? ValueNotifier(null);

  final Pathfinder pathfinder;

  static const arriveDistance = 8.0;
  static const offRouteDistance = 20.0;

  RoadRoute? route;
  Destination? destination;
  final info = ValueNotifier<GpsInfo?>(null);

  /// Pesan sekali tampil (mis. "Sampai di tujuan").
  final ValueNotifier<String?> message;

  /// Dipanggil saat sampai; kembalikan true bila sudah ditangani
  /// (pesan bawaan "Sampai di …" tidak ditampilkan).
  bool Function(Destination dest)? onArrive;

  int _cursor = 0;
  double _rerouteCooldown = 0;

  bool get active => route != null;

  RoadRoute? plan(Offset from, Offset to) => pathfinder.route(from, to);

  void start(Destination dest, RoadRoute r) {
    destination = dest;
    route = r;
    _cursor = 0;
  }

  void clear() {
    route = null;
    destination = null;
    info.value = null;
  }

  /// Dipanggil berkala (bukan tiap frame) dengan posisi pemain.
  void update(Offset pos, double dt) {
    _rerouteCooldown -= dt;
    final r = route, dest = destination;
    if (r == null || dest == null) return;

    final (idx, proj, dist) = _project(r, pos);
    if (dist > offRouteDistance && _rerouteCooldown <= 0) {
      _rerouteCooldown = 2;
      final again = plan(pos, dest.position);
      if (again != null) {
        route = again;
        _cursor = 0;
        return update(pos, 0);
      }
    }
    _cursor = idx;

    var remaining = (r.points[idx + 1] - proj).distance;
    for (var i = idx + 1; i < r.points.length - 1; i++) {
      remaining += (r.points[i + 1] - r.points[i]).distance;
    }
    if (remaining < arriveDistance || (pos - dest.position).distance < arriveDistance) {
      clear();
      if (onArrive?.call(dest) != true) message.value = 'Sampai di ${dest.title}!';
      return;
    }
    info.value = GpsInfo(title: dest.title, remaining: remaining, instruction: _instruction(r, idx, proj));
  }

  /// Segmen rute terdekat, dicari di sekitar kursor terakhir.
  (int, Offset, double) _project(RoadRoute r, Offset p) {
    final from = math.max(0, _cursor - 3);
    final to = math.min(r.points.length - 2, _cursor + 60);
    var best = (from, r.points[from], double.infinity);
    for (var i = from; i <= to; i++) {
      final a = r.points[i], b = r.points[i + 1];
      final ab = b - a;
      final len2 = ab.distanceSquared;
      final t = len2 == 0 ? 0.0 : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
      final q = a + ab * t;
      final d = (p - q).distance;
      if (d < best.$3) best = (i, q, d);
    }
    return best;
  }

  String _instruction(RoadRoute r, int idx, Offset proj) {
    var dist = (r.points[idx + 1] - proj).distance;
    for (var j = idx + 1; j < r.points.length - 1 && dist < 600; j++) {
      if (r.isNode[j]) {
        final inDir = r.points[j] - r.points[j - 1];
        final outDir = r.points[j + 1] - r.points[j];
        final angle = math.atan2(
          inDir.dx * outDir.dy - inDir.dy * outDir.dx,
          inDir.dx * outDir.dx + inDir.dy * outDir.dy,
        );
        if (angle.abs() > 0.6) {
          // Sumbu y ke bawah: sudut positif = belok kanan.
          final side = angle > 0 ? 'kanan' : 'kiri';
          return 'belok $side ${formatDistance(dist)}';
        }
      }
      dist += (r.points[j + 1] - r.points[j]).distance;
    }
    return 'lurus terus';
  }
}
