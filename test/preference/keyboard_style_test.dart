import 'package:custom_tv_text_field/custom_tv_text_field.dart'
    show KeyboardStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Apple TV cases run with --dart-define=MOONFIN_TVOS=true.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<UserPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues({
      'pref_last_server_id': 'server1',
      'pref_last_user_id': 'user1',
      for (final MapEntry(:key, :value) in values.entries)
        '${key}_server1_user1': value,
    });
    final store = PreferenceStore();
    await store.init();
    return UserPreferences(store);
  }

  const appleTvDefault = PlatformDetection.isAppleTV
      ? KeyboardStyle.native
      : KeyboardStyle.docked;

  test('a Docked nobody picked opens Native on Apple TV only', () async {
    final prefs = await prefsWith({'pref_keyboard_style': 'docked'});
    expect(prefs.keyboardStyleInUse, appleTvDefault);
    expect(prefs.get(UserPreferences.keyboardStyle), KeyboardStyle.docked);
  });

  test('a Docked picked on this device stays Docked', () async {
    final prefs = await prefsWith({
      'pref_keyboard_style': 'docked',
      'pref_keyboard_style_picked': true,
    });
    expect(prefs.keyboardStyleInUse, KeyboardStyle.docked);
  });

  test('a Moonbase admin default keeps a synced Docked', () async {
    final prefs = await prefsWith({
      'pref_keyboard_style': 'docked',
      'pref_keyboard_style_admin_default': true,
    });
    expect(prefs.keyboardStyleInUse, KeyboardStyle.docked);
  });

  test('other synced styles are used as they are', () async {
    final prefs = await prefsWith({'pref_keyboard_style': 'classic'});
    expect(prefs.keyboardStyleInUse, KeyboardStyle.classic);
  });

  test('picking a style marks it as picked', () async {
    final prefs = await prefsWith({});
    await prefs.pickKeyboardStyle(KeyboardStyle.docked);
    expect(prefs.get(UserPreferences.keyboardStylePicked), isTrue);
    expect(prefs.keyboardStyleInUse, KeyboardStyle.docked);
  });
}
