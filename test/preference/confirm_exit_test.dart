import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<UserPreferences> _prefs([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  final store = PreferenceStore();
  await store.init();
  return UserPreferences(store);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(GetIt.I.reset);
  tearDown(GetIt.I.reset);

  test('the stored default stays on for every platform', () async {
    // The value syncs in the TV profile Apple TV shares with Android TV, so
    // Apple TV's own behaviour must not come from a different default.
    final prefs = await _prefs();
    expect(prefs.get(UserPreferences.confirmExit), isTrue);
  });

  test('shouldConfirmExit follows the setting off Apple TV', () async {
    // MOONFIN_TVOS is a build-time define, so tests run as a non Apple TV
    // build. The Apple TV branch is covered by running the tvOS build.
    expect(PlatformDetection.isAppleTV, isFalse);
    final prefs = await _prefs();
    expect(prefs.shouldConfirmExit, isTrue);
    await prefs.set(UserPreferences.confirmExit, false);
    expect(prefs.shouldConfirmExit, isFalse);
  });
}
