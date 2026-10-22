import 'dart:ui';

/// Satu pilihan di kartu cerita/kejadian.
class StoryChoice {
  const StoryChoice({required this.label, required this.apply, this.cost = '', this.enabled = true});

  final String label;

  /// Keterangan biaya di sisi kanan, mis. "Rp 15rb · pelan 20 dtk".
  final String cost;
  final bool enabled;

  /// Jalankan efek pilihan; kembalikan teks hasil.
  final String Function() apply;
}

/// Kartu cerita: kejadian di jalan atau dialog misi (desain RoadEvents).
class StoryEvent {
  const StoryEvent({
    required this.tag,
    required this.color,
    required this.title,
    required this.desc,
    required this.choices,
    this.feed = const [],
  });

  final String tag;
  final Color color;
  final String title;
  final String desc;
  final List<StoryChoice> choices;

  /// Kabar singkat untuk panel "KABAR JALAN HARI INI" (warna, teks).
  final List<(Color, String)> feed;
}
