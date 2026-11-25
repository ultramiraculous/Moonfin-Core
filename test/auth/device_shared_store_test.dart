import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/auth/store/authentication_store.dart';
import 'package:moonfin/auth/store/device_shared_store.dart';
import 'package:moonfin/util/pin_code_util.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('test/shared_store');

String _auth(Map<String, Object> servers) =>
    jsonEncode({'version': 2, 'servers': servers});

/// Stands in for the user-independent keychain item.
class _Keychain {
  String? value;
  bool fail = false;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (fail) throw PlatformException(code: 'keychain_-34018');
          switch (call.method) {
            case 'read':
              return value ?? '';
            case 'write':
              value = call.arguments as String;
              return null;
          }
          return null;
        });
  }

  Map<String, dynamic> get data =>
      Map<String, dynamic>.from(jsonDecode(value!) as Map);
}

Future<PreferenceStore> _profile(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  final store = PreferenceStore();
  await store.init();
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Keychain keychain;

  setUp(() {
    DeviceSharedStore.resetForTesting();
    keychain = _Keychain()..install();
  });

  test(
    'the first Apple TV user to open the app shares their accounts',
    () async {
      final prefs = await _profile({
        'authentication_store_json': _auth({
          's1': {
            'name': 'Home',
            'users': {
              'u1': {'name': 'Parent'},
            },
          },
        }),
        'device_id': 'abc',
        'user_pin_hash_u1': 'hash',
        'user_pin_enabled_u1': true,
        'pref_last_user_id': 'u1',
      });

      await DeviceSharedStore.init(prefs, channel: _channel, enabled: true);

      expect(keychain.data['device_id'], 'abc');
      expect(keychain.data['user_pin_hash_u1'], 'hash');
      expect(keychain.data['user_pin_enabled_u1'], true);
      expect(keychain.data.containsKey('pref_last_user_id'), isFalse);
      expect(prefs.getBool(DeviceSharedStore.seededKey), isTrue);
    },
  );

  test(
    'a second Apple TV user adds their accounts without replacing any',
    () async {
      keychain.value = jsonEncode({
        'authentication_store_json': _auth({
          's1': {
            'name': 'Home',
            'users': {
              'u1': {'name': 'Parent'},
            },
          },
        }),
        'device_id': 'abc',
      });
      final prefs = await _profile({
        'authentication_store_json': _auth({
          's1': {
            'name': 'Renamed here',
            'users': {
              'u2': {'name': 'Kid'},
            },
          },
          's2': {'name': 'Grandma', 'users': {}},
        }),
        'device_id': 'xyz',
      });

      await DeviceSharedStore.init(prefs, channel: _channel, enabled: true);

      final auth = jsonDecode(
        keychain.data['authentication_store_json'] as String,
      );
      expect(auth['servers']['s1']['name'], 'Home');
      expect((auth['servers']['s1']['users'] as Map).keys, ['u1', 'u2']);
      expect(auth['servers']['s2']['name'], 'Grandma');
      expect(keychain.data['device_id'], 'abc');
    },
  );

  test('copies in only once per Apple TV user', () async {
    keychain.value = jsonEncode({'device_id': 'abc'});
    final prefs = await _profile({
      DeviceSharedStore.seededKey: true,
      'user_pin_hash_u1': 'stale',
    });

    await DeviceSharedStore.init(prefs, channel: _channel, enabled: true);

    expect(keychain.data.containsKey('user_pin_hash_u1'), isFalse);
  });

  test('stays on this user\'s own storage when the keychain refuses', () async {
    keychain.fail = true;
    final prefs = await _profile({});

    await DeviceSharedStore.init(prefs, channel: _channel, enabled: true);

    expect(DeviceSharedStore.active, isNull);
    expect(prefs.getBool(DeviceSharedStore.seededKey), isNull);
  });

  test('does nothing off Apple TV', () async {
    final prefs = await _profile({'device_id': 'abc'});

    await DeviceSharedStore.init(prefs, channel: _channel, enabled: false);

    expect(DeviceSharedStore.active, isNull);
    expect(keychain.value, isNull);
  });

  test(
    'saved accounts and PINs are read from and written to the shared store',
    () async {
      keychain.value = jsonEncode({
        'authentication_store_json': _auth({
          's1': {
            'name': 'Home',
            'users': {
              'u1': {'name': 'Parent'},
            },
          },
        }),
      });
      final prefs = await _profile({
        DeviceSharedStore.seededKey: true,
        'user_pin_hash_u1': 'this-user-only',
        'user_pin_enabled_u1': true,
      });
      await DeviceSharedStore.init(prefs, channel: _channel, enabled: true);

      final auth = AuthenticationStore();
      await auth.init();
      expect(auth.getServers().map((s) => s.id), ['s1']);

      final pin = PinCodeUtil(prefs, 'u1');
      expect(pin.isPinEnabled, isFalse);
      await pin.setPin('1234');
      expect(keychain.data['user_pin_enabled_u1'], true);
      expect(keychain.data['user_pin_hash_u1'], PinCodeUtil.hashPin('1234'));
      expect(prefs.getString('user_pin_hash_u1'), 'this-user-only');

      await pin.removePin();
      await Future<void>.delayed(Duration.zero);
      expect(keychain.data.containsKey('user_pin_hash_u1'), isFalse);
      expect(pin.isPinEnabled, isFalse);
    },
  );
}
