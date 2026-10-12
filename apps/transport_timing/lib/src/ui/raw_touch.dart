import 'dart:ui'
    show PointerChange, PointerDataPacket, PointerDataPacketCallback;

import 'package:flutter/widgets.dart';

/// Reports every touch on the screen as early as Dart can know of it.
///
/// Touches are taken from `PlatformDispatcher.onPointerDataPacket`, the
/// first Dart code to run for one: before the framework has turned the
/// packet into pointer events, found what is under them and passed them
/// down the tree. The whole screen is the target, so there is nothing to
/// hit-test, and what the framework does with the touch afterwards is no
/// part of the time measured from it.
///
/// The framework still gets every packet, after [onTouch] has returned.
class RawTouchListener extends StatefulWidget {
  const RawTouchListener({
    super.key,
    required this.clock,
    required this.onTouch,
    required this.child,
  });

  /// Read once per packet, before anything else is done with it.
  final double Function() clock;

  /// Called for a pointer going down, with [clock] when the packet arrived
  /// and the system's own time for the touch.
  final void Function(double heard, Duration timeStamp) onTouch;

  final Widget child;

  @override
  State<RawTouchListener> createState() => _RawTouchListenerState();
}

class _RawTouchListenerState extends State<RawTouchListener> {
  PointerDataPacketCallback? _framework;

  @override
  void initState() {
    super.initState();
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    _framework = dispatcher.onPointerDataPacket;
    dispatcher.onPointerDataPacket = _onPointerData;
  }

  @override
  void dispose() {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    // Unless something else has taken its place since.
    if (dispatcher.onPointerDataPacket == _onPointerData) {
      dispatcher.onPointerDataPacket = _framework;
    }
    super.dispose();
  }

  void _onPointerData(PointerDataPacket packet) {
    // First, before anything else can add to it.
    final heard = widget.clock();
    for (final data in packet.data) {
      // Down, not a tap: a tap is only recognised on release.
      if (data.change == PointerChange.down && !data.synthesized) {
        widget.onTouch(heard, data.timeStamp);
      }
    }
    // The framework after the touch is dealt with: it dispatches as it is
    // called, and would otherwise be in the time being measured.
    _framework?.call(packet);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
