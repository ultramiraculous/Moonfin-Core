import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tvos/flutter_tvos.dart'
    show TvRemoteTouchEvent, TvRemoteTouchPhase;
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/util/focus/siri_remote_glide.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final glide = SiriRemoteGlide.instance;
  final pressed = <LogicalKeyboardKey>[];
  bool capture(KeyEvent event) {
    if (event is KeyDownEvent) pressed.add(event.logicalKey);
    return true;
  }

  // Each move arrives this long after the last. Tests that hand-place
  // samples move slowly enough that lifting off never counts as a flick.
  var now = Duration.zero;
  var sampleGap = const Duration(milliseconds: 50);

  void touch(TvRemoteTouchPhase phase, double x, double y) {
    if (phase == TvRemoteTouchPhase.move) now += sampleGap;
    glide.debugHandleTouch(TvRemoteTouchEvent(phase: phase, x: x, y: y));
  }

  /// Swipes along x from [from] to [to] in samples spread over [ms], and
  /// returns how many steps came out before the finger lifted.
  int swipe(double from, double to, int ms) {
    final samples = (ms / 16.667).round();
    final previousGap = sampleGap;
    sampleGap = Duration(microseconds: ms * 1000 ~/ samples);
    touch(TvRemoteTouchPhase.started, from, 0);
    for (var i = 1; i <= samples; i++) {
      touch(TvRemoteTouchPhase.move, from + (to - from) * i / samples, 0);
    }
    final duringDrag = pressed.length;
    touch(TvRemoteTouchPhase.ended, to, 0);
    sampleGap = previousGap;
    return duringDrag;
  }

  setUp(() {
    pressed.clear();
    now = Duration.zero;
    sampleGap = const Duration(milliseconds: 50);
    glide.debugClock = () => now;
    // The step counts below are written against the high thresholds.
    glide.sensitivity = SiriRemoteSwipeSensitivity.high;
    HardwareKeyboard.instance.addHandler(capture);
  });

  tearDown(() {
    glide.debugReset();
    HardwareKeyboard.instance.removeHandler(capture);
  });

  test('medium is the default and lower sensitivity steps less per drag', () {
    expect(
      UserPreferences.siriRemoteSwipeSensitivity.defaultValue,
      SiriRemoteSwipeSensitivity.medium,
    );

    int stepsFor(SiriRemoteSwipeSensitivity sensitivity) {
      glide.sensitivity = sensitivity;
      pressed.clear();
      var x = -0.9;
      touch(TvRemoteTouchPhase.started, x, 0);
      // A full edge-to-edge slow drag.
      for (var i = 0; i < 18; i++) {
        x += 0.1;
        touch(TvRemoteTouchPhase.move, x, 0);
      }
      touch(TvRemoteTouchPhase.ended, x, 0);
      return pressed.length;
    }

    final high = stepsFor(SiriRemoteSwipeSensitivity.high);
    final medium = stepsFor(SiriRemoteSwipeSensitivity.medium);
    final low = stepsFor(SiriRemoteSwipeSensitivity.low);
    expect(high, 5);
    expect(medium, 3);
    expect(low, 2);
  });

  testWidgets('slow drag steps focus per distance and stops on release', (
    tester,
  ) async {
    touch(TvRemoteTouchPhase.started, -0.8, 0);
    var x = -0.8;
    // 16 moves of 0.1 each, crossing 1.6 units of travel: one step at 0.28
    // then one every 0.36, so four steps in total.
    for (var i = 0; i < 16; i++) {
      x += 0.1;
      touch(TvRemoteTouchPhase.move, x, 0);
    }
    expect(pressed, List.filled(4, LogicalKeyboardKey.arrowRight));

    touch(TvRemoteTouchPhase.ended, x, 0);
    await tester.pump(const Duration(seconds: 3));
    expect(pressed.length, 4, reason: 'a drag must not keep moving');
  });

  testWidgets('dragging toward positive y steps down', (tester) async {
    touch(TvRemoteTouchPhase.started, 0, -0.2);
    touch(TvRemoteTouchPhase.move, 0, 0.2);
    expect(pressed, [LogicalKeyboardKey.arrowDown]);
    touch(TvRemoteTouchPhase.ended, 0, 0.2);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('dragging toward negative y steps up', (tester) async {
    touch(TvRemoteTouchPhase.started, 0, 0.2);
    touch(TvRemoteTouchPhase.move, 0, -0.2);
    expect(pressed, [LogicalKeyboardKey.arrowUp]);
    touch(TvRemoteTouchPhase.ended, 0, -0.2);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('slow drags and ordinary swipes never glide', (tester) async {
    for (final sensitivity in SiriRemoteSwipeSensitivity.values) {
      glide.sensitivity = sensitivity;
      for (final ms in [600, 400]) {
        pressed.clear();
        final duringDrag = swipe(-0.9, 0.9, ms);
        await tester.pump(const Duration(seconds: 3));
        expect(pressed.length, duringDrag,
            reason: '${sensitivity.name}, full swipe over $ms ms');
      }
    }
  });

  testWidgets('a nudge moves one item on medium and never glides', (
    tester,
  ) async {
    glide.sensitivity = SiriRemoteSwipeSensitivity.medium;
    swipe(-0.15, 0.15, 80);
    await tester.pump(const Duration(seconds: 3));
    expect(pressed, [LogicalKeyboardKey.arrowRight]);
  });

  testWidgets('a finger that slows before lifting does not glide', (
    tester,
  ) async {
    glide.sensitivity = SiriRemoteSwipeSensitivity.medium;
    sampleGap = const Duration(microseconds: 16667);
    touch(TvRemoteTouchPhase.started, -0.7, 0);
    var x = -0.7;
    for (var i = 0; i < 9; i++) {
      x += 1.2 / 9;
      touch(TvRemoteTouchPhase.move, x, 0);
    }
    for (var i = 0; i < 12; i++) {
      x += 0.2 / 12;
      touch(TvRemoteTouchPhase.move, x, 0);
    }
    final duringDrag = pressed.length;
    touch(TvRemoteTouchPhase.ended, x, 0);
    await tester.pump(const Duration(seconds: 3));
    expect(pressed.length, duringDrag);
  });

  testWidgets('a flick still glides when lift-off arrives a frame later', (
    tester,
  ) async {
    glide.sensitivity = SiriRemoteSwipeSensitivity.medium;
    sampleGap = const Duration(microseconds: 16667);
    touch(TvRemoteTouchPhase.started, -0.9, 0);
    var x = -0.9;
    for (var i = 0; i < 12; i++) {
      x += 1.8 / 12;
      touch(TvRemoteTouchPhase.move, x, 0);
    }
    final duringDrag = pressed.length;
    now += const Duration(milliseconds: 18);
    touch(TvRemoteTouchPhase.ended, x, 0);
    await tester.pump(const Duration(seconds: 3));
    expect(pressed.length - duringDrag, 3);
  });

  testWidgets('a flick that rests before lifting does not glide', (
    tester,
  ) async {
    glide.sensitivity = SiriRemoteSwipeSensitivity.medium;
    sampleGap = const Duration(microseconds: 16667);
    touch(TvRemoteTouchPhase.started, -0.9, 0);
    var x = -0.9;
    for (var i = 0; i < 12; i++) {
      x += 1.8 / 12;
      touch(TvRemoteTouchPhase.move, x, 0);
    }
    final duringDrag = pressed.length;
    // The pad reports nothing while the finger rests.
    now += const Duration(milliseconds: 150);
    touch(TvRemoteTouchPhase.ended, x, 0);
    await tester.pump(const Duration(seconds: 3));
    expect(pressed.length, duringDrag);
  });

  testWidgets('a flick that rests on the same point before lifting does not glide', (
    tester,
  ) async {
    glide.sensitivity = SiriRemoteSwipeSensitivity.medium;
    sampleGap = const Duration(microseconds: 16667);
    touch(TvRemoteTouchPhase.started, -0.9, 0);
    var x = -0.9;
    for (var i = 0; i < 12; i++) {
      x += 1.8 / 12;
      touch(TvRemoteTouchPhase.move, x, 0);
    }
    for (var i = 0; i < 9; i++) {
      touch(TvRemoteTouchPhase.move, x, 0);
    }
    final duringDrag = pressed.length;
    touch(TvRemoteTouchPhase.ended, x, 0);
    await tester.pump(const Duration(seconds: 3));
    expect(pressed.length, duringDrag);
  });

  testWidgets('a flick that hooks back as it lifts does not glide', (
    tester,
  ) async {
    glide.sensitivity = SiriRemoteSwipeSensitivity.medium;
    sampleGap = const Duration(microseconds: 16667);
    touch(TvRemoteTouchPhase.started, -0.6, 0);
    var x = -0.6;
    for (var i = 0; i < 24; i++) {
      x += 1.2 / 24;
      touch(TvRemoteTouchPhase.move, x, 0);
    }
    for (var i = 0; i < 5; i++) {
      x -= 0.12;
      touch(TvRemoteTouchPhase.move, x, 0);
    }
    final duringDrag = pressed.length;
    touch(TvRemoteTouchPhase.ended, x, 0);
    await tester.pump(const Duration(seconds: 3));
    expect(pressed.length, duringDrag);
  });

  testWidgets('a flick glides a few more steps, slowing, then stops', (
    tester,
  ) async {
    glide.sensitivity = SiriRemoteSwipeSensitivity.medium;
    final duringDrag = swipe(-0.9, 0.9, 200);
    expect(duringDrag, 3);

    // 9 units/s: 0.6 steps per unit above 6, plus one.
    final times = <Duration>[];
    var elapsed = Duration.zero;
    const tick = Duration(milliseconds: 10);
    while (elapsed < const Duration(seconds: 3)) {
      final before = pressed.length;
      await tester.pump(tick);
      elapsed += tick;
      if (pressed.length > before) times.add(elapsed);
    }
    expect(pressed.length - duringDrag, 3);
    expect(pressed.skip(duringDrag), everyElement(LogicalKeyboardKey.arrowRight));
    final gaps = [
      for (var i = 1; i < times.length; i++) times[i] - times[i - 1],
    ];
    expect(gaps.first < gaps.last, isTrue, reason: 'the glide slows down');
  });

  testWidgets('a faster flick glides further, up to a cap', (tester) async {
    glide.sensitivity = SiriRemoteSwipeSensitivity.medium;
    final brisk = swipe(-0.9, 0.9, 200);
    await tester.pump(const Duration(seconds: 3));
    final briskGlide = pressed.length - brisk;

    pressed.clear();
    final fast = swipe(-0.9, 0.9, 100);
    await tester.pump(const Duration(seconds: 3));
    final fastGlide = pressed.length - fast;

    expect(fastGlide, greaterThan(briskGlide));
    expect(fastGlide, lessThanOrEqualTo(SiriRemoteGlide.maxFlickSteps));
  });

  testWidgets('lower sensitivity glides fewer steps', (tester) async {
    int glideFor(SiriRemoteSwipeSensitivity sensitivity) {
      glide.sensitivity = sensitivity;
      pressed.clear();
      return swipe(-0.9, 0.9, 120);
    }

    final lowDrag = glideFor(SiriRemoteSwipeSensitivity.low);
    await tester.pump(const Duration(seconds: 3));
    final low = pressed.length - lowDrag;
    final highDrag = glideFor(SiriRemoteSwipeSensitivity.high);
    await tester.pump(const Duration(seconds: 3));
    final high = pressed.length - highDrag;
    expect(low, lessThan(high));
  });

  testWidgets('a vertical flick glides the way the finger went', (
    tester,
  ) async {
    glide.sensitivity = SiriRemoteSwipeSensitivity.medium;
    sampleGap = const Duration(microseconds: 16667);
    touch(TvRemoteTouchPhase.started, 0, -0.9);
    for (var i = 1; i <= 12; i++) {
      touch(TvRemoteTouchPhase.move, 0, -0.9 + 1.8 * i / 12);
    }
    touch(TvRemoteTouchPhase.ended, 0, 0.9);
    await tester.pump(const Duration(seconds: 3));
    expect(pressed, isNotEmpty);
    expect(pressed, everyElement(LogicalKeyboardKey.arrowDown));
  });

  testWidgets('touching or clicking the pad stops a glide', (tester) async {
    glide.sensitivity = SiriRemoteSwipeSensitivity.medium;
    for (final stop in [
      TvRemoteTouchPhase.started,
      TvRemoteTouchPhase.clickStart,
    ]) {
      pressed.clear();
      final duringDrag = swipe(-0.9, 0.9, 120);
      await tester.pump(const Duration(milliseconds: 70));
      final atStop = pressed.length;
      expect(atStop, greaterThan(duringDrag));
      touch(stop, 0, 0);
      if (stop == TvRemoteTouchPhase.started) {
        touch(TvRemoteTouchPhase.ended, 0, 0);
      }
      await tester.pump(const Duration(seconds: 3));
      expect(pressed.length, atStop, reason: stop.name);
    }
  });

  testWidgets('holding still after a swipe emits nothing more', (tester) async {
    touch(TvRemoteTouchPhase.started, -0.6, 0);
    var x = -0.6;
    for (var i = 0; i < 5; i++) {
      x += 0.15;
      touch(TvRemoteTouchPhase.move, x, 0);
    }
    final afterSwipe = pressed.length;

    // Finger resting on the pad: repeated moves that report the same point.
    for (var i = 0; i < 20; i++) {
      touch(TvRemoteTouchPhase.move, x, 0);
    }
    await tester.pump(const Duration(seconds: 3));
    expect(pressed.length, afterSwipe,
        reason: 'a held finger must not step focus');

    touch(TvRemoteTouchPhase.ended, x, 0);
    await tester.pump(const Duration(seconds: 3));
    expect(pressed.length, afterSwipe);
  });

  testWidgets('direction reversal mid drag responds immediately', (
    tester,
  ) async {
    touch(TvRemoteTouchPhase.started, 0.0, 0);
    touch(TvRemoteTouchPhase.move, 0.3, 0);
    expect(pressed, [LogicalKeyboardKey.arrowRight]);

    // Coming back shouldn't have to unwind the forward accumulator.
    touch(TvRemoteTouchPhase.move, 0.0, 0);
    touch(TvRemoteTouchPhase.move, -0.1, 0);
    expect(pressed.last, LogicalKeyboardKey.arrowLeft);
    touch(TvRemoteTouchPhase.ended, -0.1, 0);
    await tester.pump(const Duration(seconds: 3));
  });
}
