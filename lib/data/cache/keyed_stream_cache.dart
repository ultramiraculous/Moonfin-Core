import 'dart:async';

import 'package:rxdart/rxdart.dart';

/// Values fetched per key, shown at once from memory and refreshed behind.
///
/// A key is fetched again only once its last fetch is [minRefreshInterval]
/// old, and everyone asking while a fetch is on the way shares it. With
/// [maxKeys], the least recently used keys without watchers make room.
class KeyedStreamCache<K, V> {
  KeyedStreamCache({
    this.minRefreshInterval = Duration.zero,
    this.maxKeys,
    bool Function(V a, V b)? equals,
    DateTime Function()? clock,
  }) : _equals = equals ?? ((a, b) => a == b),
       _clock = clock ?? DateTime.now;

  /// How long a fetched value counts as current.
  final Duration minRefreshInterval;

  /// How many keys are kept at most, or no limit when null.
  final int? maxKeys;

  final bool Function(V a, V b) _equals;
  final DateTime Function() _clock;
  final _entries = <K, _Entry<V>>{};

  /// [key]'s value, or null when there is none.
  V? peek(K key) {
    final entry = _entries[key];
    return entry != null && entry.usable ? entry.subject.valueOrNull : null;
  }

  /// [key]'s value if it is current, or the result of a fetch.
  ///
  /// With [fresh], always fetch.
  Future<V> get(K key, Future<V> Function() fetch, {bool fresh = false}) {
    final entry = _touch(key);
    if (!fresh && entry.usable && !_due(entry)) {
      return Future.value(entry.subject.value);
    }
    return _refresh(key, entry, fetch, joinRunning: !fresh);
  }

  /// Emit [key]'s value at once, then each new value it takes.
  ///
  /// Fetch first when the value is missing or due. A value equal to the one
  /// before is not emitted again. A failed fetch is an error.
  Stream<V> watch(K key, Future<V> Function() fetch) {
    final controller = StreamController<V>(sync: true);
    StreamSubscription<V>? values;
    controller.onListen = () {
      final entry = _touch(key);
      Object? last = _none;
      // Forward each current value once, ignoring late replays of old ones.
      void forward(V value) {
        if (identical(value, last) || !entry.usable) return;
        if (!identical(value, entry.subject.valueOrNull)) return;
        last = value;
        controller.add(value);
      }

      if (entry.usable) forward(entry.subject.value);
      values = entry.subject.stream.listen(forward, onDone: controller.close);
      if (!entry.usable || _due(entry)) {
        _refresh(key, entry, fetch, joinRunning: true).then(
          (_) {},
          onError: (Object error, StackTrace stack) {
            if (!controller.isClosed) controller.addError(error, stack);
          },
        );
      }
    };
    controller.onCancel = () => values?.cancel();
    return controller.stream;
  }

  /// Drop every key, closing all watchers.
  void clear() {
    for (final entry in _entries.values.toList()) {
      _close(entry);
    }
    _entries.clear();
  }

  void dispose() => clear();

  bool _due(_Entry<V> entry) {
    final at = entry.fetchedAt;
    return at == null || _clock().difference(at) >= minRefreshInterval;
  }

  Future<V> _refresh(
    K key,
    _Entry<V> entry,
    Future<V> Function() fetch, {
    required bool joinRunning,
  }) {
    final running = entry.running;
    if (joinRunning && running != null) return running;
    final generation = entry.generation;
    final future = fetch().then((value) {
      if (generation == entry.generation && identical(_entries[key], entry)) {
        _store(entry, value);
      }
      return value;
    });
    entry.running = future;
    void settle() {
      if (identical(entry.running, future)) entry.running = null;
    }

    future.then((_) => settle(), onError: (Object _) => settle());
    return future;
  }

  void _store(_Entry<V> entry, V value) {
    entry.fetchedAt = _clock();
    final current = entry.subject.valueOrNull;
    final same = entry.usable && current is V && _equals(current, value);
    entry.usable = true;
    if (!same) entry.subject.add(value);
  }

  _Entry<V> _touch(K key) {
    final entry = _entries.remove(key) ?? _Entry<V>();
    _entries[key] = entry;
    _evict(keep: key);
    return entry;
  }

  void _evict({required K keep}) {
    final max = maxKeys;
    if (max == null || _entries.length <= max) return;
    for (final key in _entries.keys.toList()) {
      if (_entries.length <= max) break;
      if (key == keep) continue;
      final entry = _entries[key]!;
      if (entry.subject.hasListener || entry.running != null) continue;
      _close(_entries.remove(key)!);
    }
  }

  void _close(_Entry<V> entry) {
    entry.generation++;
    entry.running = null;
    unawaited(entry.subject.close());
  }
}

const _none = Object();

class _Entry<V> {
  final subject = BehaviorSubject<V>();
  bool usable = false;
  DateTime? fetchedAt;
  Future<V>? running;
  int generation = 0;
}
