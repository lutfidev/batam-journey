import 'package:flutter/foundation.dart';

import 'economy.dart';

/// Jam game sederhana: 1 hari game = 24 menit nyata (1 menit game = 1 detik).
class GameClock implements JsonState {
  GameClock({int day = 1, double minute = 7 * 60}) {
    _minute = minute;
    this.day.value = day;
    _publish();
  }

  static const minutesPerDay = 24 * 60;

  /// Menit game per detik nyata.
  static const speed = 1.0;

  static const _days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];

  /// Hari ke-N (mulai 1, hari Senin).
  final day = ValueNotifier(1);

  /// "07:15" — berubah tiap menit game.
  final text = ValueNotifier('07:00');

  late double _minute;

  /// Dipanggil saat berganti hari (untuk tagihan sewa/cicilan).
  void Function(int day)? onNewDay;

  double get minuteOfDay => _minute;
  double get hour => _minute / 60;
  String get weekday => weekdayOf(day.value);

  /// Nama hari untuk hari ke-[day] (hari ke-1 = Senin).
  static String weekdayOf(int day) => _days[(day - 1) % 7];

  /// Total jam sejak awal (untuk menghitung selisih waktu).
  double get totalHours => (day.value - 1) * 24 + hour;

  void update(double dt) => advanceMinutes(dt * speed);

  void advanceMinutes(double minutes) {
    _minute += minutes;
    while (_minute >= minutesPerDay) {
      _minute -= minutesPerDay;
      day.value++;
      onNewDay?.call(day.value);
    }
    _publish();
  }

  /// Tidur sampai jam [wakeHour] berikutnya. Mengembalikan jam yang dilewati.
  double sleepUntil(int wakeHour) {
    final target = wakeHour * 60.0;
    final skip = _minute < target ? target - _minute : minutesPerDay - _minute + target;
    advanceMinutes(skip);
    return skip / 60;
  }

  void _publish() {
    final m = _minute.floor();
    text.value = '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  }

  @override
  Map<String, Object> toJson() => {'day': day.value, 'minute': _minute};

  @override
  void loadJson(Map<String, dynamic> json) {
    day.value = (json['day'] as num?)?.toInt() ?? 1;
    _minute = ((json['minute'] as num?) ?? 7 * 60).toDouble().clamp(0, minutesPerDay - 1);
    _publish();
  }
}
