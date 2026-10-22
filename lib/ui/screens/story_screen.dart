import 'package:flutter/widgets.dart';

import '../../game/systems/story.dart';
import '../palette.dart';
import '../widgets/game_button.dart';

/// Kartu kejadian di jalan / dialog misi (desain RoadEvents). Game dijeda,
/// adegan tetap terlihat di belakang lapisan gelap.
class StoryScreen extends StatefulWidget {
  const StoryScreen({super.key, required this.event, required this.onClose});

  final StoryEvent event;
  final VoidCallback onClose;

  @override
  State<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends State<StoryScreen> {
  int? _picked;
  String? _result;

  void _pick(int i) {
    if (_picked != null) return;
    final c = widget.event.choices[i];
    if (!c.enabled) return;
    setState(() {
      _picked = i;
      _result = c.apply();
    });
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    return ColoredBox(
      color: const Color(0x4D2B1D12),
      child: SafeArea(
        child: Stack(
          children: [
            if (e.feed.isNotEmpty) Positioned(left: 12, top: 12, width: 300, child: _feed(e)),
            Positioned(right: 14, top: 14, bottom: 14, width: 400, child: _card(e)),
          ],
        ),
      ),
    );
  }

  Widget _feed(StoryEvent e) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: BColors.cream.withValues(alpha: 0.96),
      border: Border.all(color: BColors.ink, width: 3),
      borderRadius: BorderRadius.circular(14),
      boxShadow: const [BoxShadow(color: BColors.ink, offset: Offset(0, 3))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('KABAR JALAN HARI INI', style: nunito(11, color: const Color(0xFF6B5440)).copyWith(letterSpacing: 0.7)),
        for (final (color, text) in e.feed)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 3, right: 8),
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                Expanded(child: Text(text, style: nunito(12).copyWith(height: 1.25))),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _card(StoryEvent e) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    decoration: BoxDecoration(
      color: BColors.cream,
      border: Border.all(color: BColors.ink, width: 4),
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [BoxShadow(color: BColors.ink, offset: Offset(0, 6))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
          decoration: BoxDecoration(color: e.color, borderRadius: BorderRadius.circular(8)),
          child: Text(e.tag, style: nunito(11, color: const Color(0xFFFFFFFF)).copyWith(letterSpacing: 0.4)),
        ),
        const SizedBox(height: 8),
        Text(e.title, style: baloo(22).copyWith(height: 1.05)),
        const SizedBox(height: 6),
        Text(e.desc, style: nunito(12, color: BColors.teksRedup).copyWith(height: 1.35)),
        const SizedBox(height: 8),
        for (var i = 0; i < e.choices.length; i++) _choice(i, e.choices[i]),
        const Spacer(),
        if (_result != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFE3F2DA),
              border: Border.all(color: BColors.hijauAksi, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(_result!, style: nunito(12, color: const Color(0xFF24572F))),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: GameButton(
              width: 120,
              height: 42,
              radius: 14,
              color: BColors.hijauAksi,
              onTap: widget.onClose,
              child: Text('Lanjut', style: baloo(17, color: const Color(0xFFFFFFFF))),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _choice(int i, StoryChoice c) {
    final picked = _picked == i;
    final usable = _picked == null && c.enabled;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        enabled: usable,
        selected: picked,
        child: GestureDetector(
          onTap: usable ? () => _pick(i) : null,
          child: Opacity(
            opacity: usable || picked ? 1 : 0.5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: picked ? const Color(0xFFFFFFFF) : BColors.cream,
                border: Border.all(color: picked ? BColors.ink : const Color(0xFFE5D5B8), width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(child: Text(c.label, style: nunito(13).copyWith(height: 1.2))),
                  if (c.cost.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(c.cost, style: nunito(11, color: BColors.teksRedup)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
