import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';

import '../auth/store/device_shared_store.dart';

/// Utility for PIN code hashing and verification.
///
/// Uses SHA-256 to store and verify user PINs securely.
/// PIN preferences are scoped per-user via prefixed keys.
class PinCodeUtil {
  final PreferenceStore _store;
  final String _userId;

  /// Which PIN this is. The sign in PIN and the Kids Mode PIN are separate
  /// codes for the same user, so they need separate keys.
  final String _namespace;

  PinCodeUtil(this._store, this._userId) : _namespace = 'user';

  /// The PIN that unlocks Kids Mode, independent of the sign in PIN.
  PinCodeUtil.kidsMode(this._store, this._userId) : _namespace = 'kids';

  String get _pinHashKey => '${_namespace}_pin_hash_$_userId';
  String get _pinEnabledKey => '${_namespace}_pin_enabled_$_userId';
  String get _failedAttemptsKey => '${_namespace}_pin_failed_$_userId';
  String get _lockedUntilKey => '${_namespace}_pin_locked_until_$_userId';
  String get _serverBackedKey => '${_namespace}_pin_server_$_userId';

  /// Wrong guesses allowed before each further one costs a wait.
  static const _freeAttempts = 5;

  /// How far the wait grows per wrong guess past [_freeAttempts], capped at
  /// [_maxLockout]. Four digits is only 10,000 combinations, which is an
  /// evening's work for a determined child if guessing is free.
  static const _lockoutStep = Duration(seconds: 30);
  static const _maxLockout = Duration(minutes: 15);

  /// Whether the user has a PIN enabled, here or on the server.
  bool get isPinEnabled =>
      (_getBool(_pinEnabledKey) ?? false) || isServerBacked;

  /// Whether the server holds a PIN for the user, as last heard. The hash kept
  /// here is then only a copy of what the user last typed, for when the server
  /// cannot be asked.
  bool get isServerBacked => _getBool(_serverBackedKey) ?? false;

  Future<void> setServerBacked(bool value) async {
    if (value) {
      await _set(_serverBackedKey, true);
    } else {
      await _remove(_serverBackedKey);
    }
  }

  /// Whether there is a PIN on the device to check a guess against.
  bool get hasLocalVerifier => (_getString(_pinHashKey) ?? '').isNotEmpty;

  /// Hash a PIN string using SHA-256.
  static String hashPin(String pin) {
    final bytes = utf8.encode(pin);
    return sha256.convert(bytes).toString();
  }

  /// How long until another guess is accepted, or zero when one is accepted
  /// now.
  Duration get lockoutRemaining {
    final until = _getInt(_lockedUntilKey) ?? 0;
    if (until == 0) return Duration.zero;
    final remaining = until - DateTime.now().toUtc().millisecondsSinceEpoch;
    return remaining <= 0 ? Duration.zero : Duration(milliseconds: remaining);
  }

  bool get isLockedOut => lockoutRemaining > Duration.zero;

  /// Verify a PIN against the stored hash.
  ///
  /// Refuses while locked out without looking at [pin], so waiting is the only
  /// way through.
  bool verifyPin(String pin) {
    if (isLockedOut) return false;
    final storedHash = _getString(_pinHashKey);
    if (storedHash == null || storedHash.isEmpty) return false;
    return hashPin(pin) == storedHash;
  }

  /// Records a wrong guess and returns how long the next one has to wait.
  Future<Duration> registerFailedAttempt() async {
    final failed = (_getInt(_failedAttemptsKey) ?? 0) + 1;
    await _set(_failedAttemptsKey, failed);
    if (failed <= _freeAttempts) return Duration.zero;

    final steps = failed - _freeAttempts;
    var lockout = _lockoutStep * steps;
    if (lockout > _maxLockout) lockout = _maxLockout;
    await _set(
      _lockedUntilKey,
      DateTime.now().toUtc().add(lockout).millisecondsSinceEpoch,
    );
    return lockout;
  }

  Future<void> clearFailedAttempts() async {
    await _remove(_failedAttemptsKey);
    await _remove(_lockedUntilKey);
  }

  /// Set a new PIN (hashes and stores it).
  Future<void> setPin(String pin) async {
    await _set(_pinHashKey, hashPin(pin));
    await _set(_pinEnabledKey, true);
    await clearFailedAttempts();
  }

  /// Remove the PIN and disable it.
  Future<void> removePin() async {
    await _remove(_pinHashKey);
    await _set(_pinEnabledKey, false);
    await _remove(_serverBackedKey);
    await clearFailedAttempts();
  }

  /// Enable or disable PIN without changing the hash.
  Future<void> setPinEnabled(bool enabled) async {
    await _set(_pinEnabledKey, enabled);
  }

  // The accounts are shared by every Apple TV user, so their PINs must be too.
  DeviceSharedStore? get _shared => DeviceSharedStore.active;

  bool? _getBool(String key) {
    final shared = _shared;
    return shared != null ? shared.getBool(key) : _store.getBool(key);
  }

  String? _getString(String key) {
    final shared = _shared;
    return shared != null ? shared.getString(key) : _store.getString(key);
  }

  int? _getInt(String key) {
    final shared = _shared;
    return shared != null ? shared.getInt(key) : _store.getInt(key);
  }

  Future<void> _set(String key, Object value) async {
    final shared = _shared;
    if (shared != null) return shared.set(key, value);
    switch (value) {
      case bool v:
        await _store.setBool(key, v);
      case int v:
        await _store.setInt(key, v);
      case String v:
        await _store.setString(key, v);
    }
  }

  Future<void> _remove(String key) async {
    final shared = _shared;
    if (shared != null) return shared.remove(key);
    await _store.remove(key);
  }
}
