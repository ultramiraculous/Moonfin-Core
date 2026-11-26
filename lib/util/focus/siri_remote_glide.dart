import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_tvos/flutter_tvos.dart'
    show TvRemoteController, TvRemoteTouchEvent, TvRemoteTouchPhase;

import '../../preference/preference_constants.dart'
    show SiriRemoteSwipeSensitivity;
import 'gamepad/gamepad_key_synthesizer.dart';

/// Turns Siri Remote touchpad gestures into focus navigation. Focus steps one
/// item at a time as the finger travels and stops when the finger does, so a
/// drag moves the same number of items however fast it was made. Only a
/// flick, a finger still moving fast as it leaves the pad, carries on for a
/// few more items and slows to a stop. Touching or clicking the pad stops it.
///
/// The engine's own swipe detectors are switched off by config, since one
/// emits a single arrow per gesture and the other latches while the finger
/// rests and runs focus away. Clicks and buttons stay native. Steps go out as
/// real arrow key events through [GamepadKeySynthesizer], so every existing
/// key handler and focus widget behaves exactly as it does for a click.
///
/// While a native view controller covers Flutter the engine stops forwarding
/// touches, so this layer goes quiet on its own.
class SiriRemoteGlide {
  SiriRemoteGlide._();

  static final SiriRemoteGlide instance = SiriRemoteGlide._();

  SiriRemoteSwipeSensitivity sensitivity = SiriRemoteSwipeSensitivity.medium;

  /// Lift-off speed, in pad units per second (the pad is 2 units wide), below
  /// which a gesture is a drag and stops where the finger stopped. A full
  /// swipe across the pad in about 300 ms reaches it.
  static const double flickMinSpeed = 6.0;

  /// Extra pad travel a flick earns per unit of speed above [flickMinSpeed].
  /// It is stepped at the sensitivity's step travel, like a drag.
  static const double _flickTravelPerSpeed = 0.36;
  static const int maxFlickSteps = 8;

  static const Duration _velocityWindow = Duration(milliseconds: 80);
  static const Duration _liftOffGap = Duration(milliseconds: 50);
  static const Duration _glideFirstInterval = Duration(milliseconds: 60);
  static const double _glideDecay = 1.3;

  final GamepadKeySynthesizer _synthesizer = GamepadKeySynthesizer();
  final Stopwatch _clock = Stopwatch()..start();
  final List<_Sample> _samples = <_Sample>[];

  @visibleForTesting
  Duration Function()? debugClock;

  Duration get _now => debugClock?.call() ?? _clock.elapsed;

  bool _attached = false;
  bool _touching = false;
  double _lastX = 0;
  double _lastY = 0;
  double _startX = 0;
  double _startY = 0;
  double _accX = 0;
  double _accY = 0;
  bool _steppedThisGesture = false;
  Timer? _glideTimer;

  void attach() {
    if (_attached) return;
    _attached = true;
    TvRemoteController.instance.addRawListener(_onTouch);
  }

  @visibleForTesting
  void debugReset() {
    _cancelGlide();
    _synthesizer.releaseAll();
    _touching = false;
    _samples.clear();
  }

  @visibleForTesting
  void debugHandleTouch(TvRemoteTouchEvent event) => _onTouch(event);

  void _onTouch(TvRemoteTouchEvent event) {
    switch (event.phase) {
      case TvRemoteTouchPhase.started:
        _cancelGlide();
        _beginGesture(event.x, event.y);
      case TvRemoteTouchPhase.move:
        if (!_touching) {
          _cancelGlide();
          _beginGesture(event.x, event.y);
          return;
        }
        _onMove(event.x, event.y);
      case TvRemoteTouchPhase.ended:
        _onRelease(event.x, event.y);
      case TvRemoteTouchPhase.cancelled:
        _touching = false;
        _samples.clear();
      case TvRemoteTouchPhase.clickStart:
        _cancelGlide();
      case TvRemoteTouchPhase.loc:
      case TvRemoteTouchPhase.clickEnd:
        break;
    }
  }

  void _beginGesture(double x, double y) {
    _touching = true;
    _startX = x;
    _startY = y;
    _lastX = x;
    _lastY = y;
    _accX = 0;
    _accY = 0;
    _steppedThisGesture = false;
    _samples
      ..clear()
      ..add(_Sample(_now, x, y));
  }

  void _onMove(double x, double y) {
    final dx = x - _lastX;
    final dy = y - _lastY;
    _lastX = x;
    _lastY = y;

    final now = _now;
    _samples.add(_Sample(now, x, y));
    _samples.removeWhere((s) => now - s.time > _velocityWindow);

    // A reversal replaces the accumulator instead of unwinding it, so
    // changing direction mid drag responds immediately.
    _accX = dx.sign != 0 && dx.sign != _accX.sign ? dx : _accX + dx;
    _accY = dy.sign != 0 && dy.sign != _accY.sign ? dy : _accY + dy;

    while (true) {
      final threshold = _steppedThisGesture
          ? sensitivity.stepTravel
          : sensitivity.firstStepTravel;
      final horizontal = _accX.abs() >= _accY.abs();
      final travel = horizontal ? _accX : _accY;
      if (travel.abs() < threshold) return;
      _step(_directionOf(horizontal, travel));
      _steppedThisGesture = true;
      if (horizontal) {
        _accX -= travel.sign * threshold;
        _accY = 0;
      } else {
        _accY -= travel.sign * threshold;
        _accX = 0;
      }
    }
  }

  /// Glides only when the finger was still moving fast just before it lifted,
  /// in the same direction as the gesture as a whole.
  void _onRelease(double x, double y) {
    if (!_touching) return;
    _touching = false;
    final now = _now;
    final samples = List.of(_samples);
    _samples.clear();
    if (samples.isEmpty || now - samples.last.time > _liftOffGap) return;
    final last = samples.last;
    final window = samples
        .where((s) => last.time - s.time <= _velocityWindow)
        .toList();
    if (window.length < 2) return;
    final first = window.first;
    final seconds = (last.time - first.time).inMicroseconds / 1e6;
    if (seconds <= 0) return;
    final vx = (last.x - first.x) / seconds;
    final vy = (last.y - first.y) / seconds;
    final horizontal = vx.abs() >= vy.abs();
    final speed = horizontal ? vx.abs() : vy.abs();
    if (speed < flickMinSpeed) return;
    final dx = x - _startX;
    final dy = y - _startY;
    final travel = horizontal ? dx : dy;
    if ((dx.abs() >= dy.abs()) != horizontal ||
        travel.sign != (horizontal ? vx : vy).sign) {
      return;
    }
    final extra = (speed - flickMinSpeed) * _flickTravelPerSpeed;
    final steps = (extra / sensitivity.stepTravel).round() + 1;
    _glide(
      _directionOf(horizontal, travel),
      steps.clamp(1, maxFlickSteps),
      _glideFirstInterval,
    );
  }

  void _glide(GamepadNavKey direction, int stepsLeft, Duration interval) {
    _glideTimer = Timer(interval, () {
      _step(direction);
      if (stepsLeft > 1) {
        _glide(
          direction,
          stepsLeft - 1,
          Duration(
            microseconds: (interval.inMicroseconds * _glideDecay).round(),
          ),
        );
      } else {
        _glideTimer = null;
      }
    });
  }

  void _cancelGlide() {
    _glideTimer?.cancel();
    _glideTimer = null;
  }

  // The pad reports up as negative y, so travelling positive is a finger
  // moving down the surface.
  GamepadNavKey _directionOf(bool horizontal, double travel) => horizontal
      ? (travel > 0 ? GamepadNavKey.right : GamepadNavKey.left)
      : (travel > 0 ? GamepadNavKey.down : GamepadNavKey.up);

  void _step(GamepadNavKey direction) {
    _synthesizer.press(direction);
    _synthesizer.release(direction);
  }
}

class _Sample {
  const _Sample(this.time, this.x, this.y);

  final Duration time;
  final double x;
  final double y;
}
