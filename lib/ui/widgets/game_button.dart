import 'dart:async';

import 'package:flutter/widgets.dart';

import '../palette.dart';

/// Tombol gaya desain: border 3px tinta, bayangan padat ke bawah tanpa blur.
/// Pakai [Listener] (bukan gesture arena) supaya beberapa tombol bisa
/// ditahan bersamaan, mis. GAS + belok.
class GameButton extends StatefulWidget {
  const GameButton({
    super.key,
    required this.width,
    required this.height,
    required this.color,
    required this.child,
    this.radius = 16,
    this.shadow = 4,
    this.onTap,
    this.onHold,
    this.enabled = true,
    this.semanticLabel,
  });

  final double width, height, radius, shadow;
  final Color color;
  final Widget child;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onHold;
  final bool enabled;
  final String? semanticLabel;

  /// Selama ini setelah tombol muncul, [onTap] diabaikan. Mencegah tap ganda
  /// "tembus" ke tombol di layar baru yang posisinya sama
  /// (mis. "Isi Bensin" lalu langsung "Bayar & Isi").
  static const armDelay = Duration(milliseconds: 300);

  @override
  State<GameButton> createState() => _GameButtonState();
}

class _GameButtonState extends State<GameButton> {
  bool _down = false;
  bool _armed = false;
  late final Timer _armTimer;

  @override
  void initState() {
    super.initState();
    _armTimer = Timer(GameButton.armDelay, () => _armed = true);
  }

  @override
  void dispose() {
    _armTimer.cancel();
    super.dispose();
  }

  void _set(bool down, {bool fire = false}) {
    if (!widget.enabled || _down == down) return;
    setState(() => _down = down);
    // Tombol tahan (GAS, REM, belok) tetap langsung responsif.
    widget.onHold?.call(down);
    if (fire && _armed) widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final drop = _down ? 0.0 : widget.shadow;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.semanticLabel,
      child: Opacity(
        opacity: widget.enabled ? 1 : 0.55,
        child: Listener(
          onPointerDown: (_) => _set(true),
          onPointerUp: (_) => _set(false, fire: true),
          onPointerCancel: (_) => _set(false),
          child: SizedBox(
            width: widget.width,
            height: widget.height + widget.shadow,
            child: Padding(
              padding: EdgeInsets.only(top: widget.shadow - drop, bottom: drop),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.color,
                  border: Border.all(color: BColors.ink, width: 3),
                  borderRadius: BorderRadius.circular(widget.radius),
                  boxShadow: [if (drop > 0) BoxShadow(color: BColors.ink, offset: Offset(0, drop))],
                ),
                child: Center(child: widget.child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
