import 'package:flutter/widgets.dart';

import '../palette.dart';

/// Joystick jalan kaki sesuai layar OnFoot: lingkaran 106 px krem
/// transparan dengan kenop 44 px. [onChanged] menerima vektor -1..1.
class Joystick extends StatefulWidget {
  const Joystick({super.key, required this.onChanged});

  final ValueChanged<Offset> onChanged;

  @override
  State<Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<Joystick> {
  static const _size = 106.0;
  static const _knob = 44.0;
  static const _travel = 34.0;

  int? _pointer;
  Offset _knobOffset = Offset.zero;

  void _track(Offset local) {
    var d = local - const Offset(_size / 2, _size / 2);
    if (d.distance > _travel) d = d / d.distance * _travel;
    setState(() => _knobOffset = d);
    widget.onChanged(d / _travel);
  }

  void _release() {
    _pointer = null;
    setState(() => _knobOffset = Offset.zero);
    widget.onChanged(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Joystick jalan',
      child: Listener(
        onPointerDown: (e) {
          if (_pointer != null) return;
          _pointer = e.pointer;
          _track(e.localPosition);
        },
        onPointerMove: (e) {
          if (e.pointer == _pointer) _track(e.localPosition);
        },
        onPointerUp: (e) {
          if (e.pointer == _pointer) _release();
        },
        onPointerCancel: (e) {
          if (e.pointer == _pointer) _release();
        },
        child: Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: BColors.cream.withValues(alpha: 0.55),
            border: Border.all(color: BColors.ink, width: 3),
          ),
          alignment: Alignment.center,
          child: Transform.translate(
            offset: _knobOffset,
            child: Container(
              width: _knob,
              height: _knob,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: BColors.cream,
                border: Border.fromBorderSide(BorderSide(color: BColors.ink, width: 3)),
                boxShadow: [BoxShadow(color: BColors.ink, offset: Offset(0, 3))],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
