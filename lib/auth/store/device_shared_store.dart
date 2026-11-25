import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:logger/logger.dart';

import '../../util/platform_detection.dart';

/// Values every Apple TV user on the device shares: the saved servers and
/// accounts, the PINs that guard them and the device id the server knows the
/// TV by. The app runs as the current Apple TV user, so everything else it
/// keeps, including which account each person last used, stays separate.
///
/// [active] is null wherever there is nothing to share, which leaves those
/// values in the ordinary preferences.
class DeviceSharedStore {
  DeviceSharedStore._(this._channel, this._data);

  static const _defaultChannel = MethodChannel('moonfin/appletv_shared_store');

  /// Set once this Apple TV user's values have been copied in, so a person
  /// who signed in before the store existed doesn't lose their accounts.
  static const seededKey = 'device_shared_store_seeded';

  static const authenticationKey = 'authentication_store_json';
  static const deviceIdKey = 'device_id';
  static final _pinKey = RegExp(r'^(user|kids)_pin_');

  static bool isSharedKey(String key) =>
      key == authenticationKey || key == deviceIdKey || _pinKey.hasMatch(key);

  static DeviceSharedStore? _active;
  static DeviceSharedStore? get active => _active;

  static final _logger = Logger();

  final MethodChannel _channel;
  final Map<String, Object?> _data;
  Future<void> _writes = Future.value();

  static Future<void> init(
    PreferenceStore prefs, {
    MethodChannel? channel,
    bool? enabled,
  }) async {
    if (_active != null) return;
    if (!(enabled ?? PlatformDetection.isAppleTV)) return;
    final ch = channel ?? _defaultChannel;

    final Map<String, Object?> data;
    try {
      final raw = await ch.invokeMethod<String>('read') ?? '';
      data = raw.isEmpty
          ? <String, Object?>{}
          : Map<String, Object?>.from(jsonDecode(raw) as Map);
    } catch (e) {
      // Without the shared keychain every Apple TV user keeps their own
      // accounts, which is safe, just less convenient.
      _logger.w('Shared device store unavailable: $e');
      return;
    }

    final store = DeviceSharedStore._(ch, data);
    if (prefs.getBool(seededKey) != true) {
      if (store._seedFrom(prefs)) await store._flush();
      await prefs.setBool(seededKey, true);
    }
    _active = store;
  }

  /// Copies what this Apple TV user had before into the shared values without
  /// overwriting anything another user already put there. Returns whether
  /// anything changed.
  bool _seedFrom(PreferenceStore prefs) {
    var changed = false;
    for (final key in prefs.keys) {
      if (!isSharedKey(key)) continue;
      final local = _raw(prefs, key);
      if (local == null) continue;
      if (key == authenticationKey) {
        final merged = mergeAuthentication(
          _data[key] as String?,
          local as String,
        );
        if (merged != _data[key]) {
          _data[key] = merged;
          changed = true;
        }
      } else if (!_data.containsKey(key)) {
        _data[key] = local;
        changed = true;
      }
    }
    return changed;
  }

  static Object? _raw(PreferenceStore prefs, String key) {
    for (final read in <Object? Function(String)>[
      prefs.getString,
      prefs.getBool,
      prefs.getInt,
    ]) {
      try {
        final value = read(key);
        if (value != null) return value;
      } catch (_) {}
    }
    return null;
  }

  /// Adds the servers, users and accounts in [local] that [shared] lacks.
  /// Where both have an entry, the shared one is kept.
  static String mergeAuthentication(String? shared, String local) {
    if (shared == null || shared.trim().isEmpty) return local;
    try {
      final s = Map<String, dynamic>.from(jsonDecode(shared) as Map);
      final l = Map<String, dynamic>.from(jsonDecode(local) as Map);
      if (s['version'] != l['version']) return shared;
      return jsonEncode(_fillMissing(s, l));
    } catch (_) {
      return shared;
    }
  }

  static Map<String, dynamic> _fillMissing(
    Map<String, dynamic> into,
    Map<String, dynamic> from,
  ) {
    final out = Map<String, dynamic>.from(into);
    from.forEach((key, value) {
      final existing = out[key];
      if (existing == null) {
        out[key] = value;
      } else if (existing is Map && value is Map) {
        out[key] = _fillMissing(
          Map<String, dynamic>.from(existing),
          Map<String, dynamic>.from(value),
        );
      }
    });
    return out;
  }

  String? getString(String key) => _data[key] as String?;
  bool? getBool(String key) => _data[key] as bool?;
  int? getInt(String key) => _data[key] as int?;

  Future<void> set(String key, Object value) {
    _data[key] = value;
    return _flush();
  }

  Future<void> remove(String key) {
    if (_data.remove(key) == null) return _writes;
    return _flush();
  }

  Future<void> _flush() {
    final snapshot = jsonEncode(_data);
    return _writes = _writes.then((_) async {
      try {
        await _channel.invokeMethod<void>('write', snapshot);
      } catch (e) {
        _logger.w('Saving the shared device store failed: $e');
      }
    });
  }

  static void resetForTesting() => _active = null;
}
