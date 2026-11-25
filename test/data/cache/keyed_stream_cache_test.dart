import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/cache/keyed_stream_cache.dart';

void main() {
  late DateTime now;
  late KeyedStreamCache<String, String> cache;
  late int fetches;

  KeyedStreamCache<String, String> make({
    Duration interval = const Duration(seconds: 30),
    int? maxKeys,
  }) => KeyedStreamCache<String, String>(
    minRefreshInterval: interval,
    maxKeys: maxKeys,
    clock: () => now,
  );

  setUp(() {
    now = DateTime(2026, 11, 25, 12);
    cache = make();
    fetches = 0;
  });

  tearDown(() => cache.dispose());

  Future<String> Function() answer(String value) => () async {
    fetches++;
    return value;
  };

  Future<List<String>> collect(Stream<String> stream) async {
    final seen = <String>[];
    final sub = stream.listen(seen.add, onError: (_) {});
    await pumpEventQueue();
    await sub.cancel();
    return seen;
  }

  group('watch', () {
    test('fetches a missing value and emits it', () async {
      expect(await collect(cache.watch('k', answer('a'))), ['a']);
      expect(cache.peek('k'), 'a');
      expect(fetches, 1);
    });

    test('emits the kept value, then the refetched one once due', () async {
      await cache.get('k', answer('a'));
      now = now.add(const Duration(seconds: 31));

      expect(await collect(cache.watch('k', answer('b'))), ['a', 'b']);
      expect(fetches, 2);
    });

    test('a refetched value equal to the kept one is not emitted', () async {
      await cache.get('k', answer('a'));
      now = now.add(const Duration(seconds: 31));

      expect(await collect(cache.watch('k', answer('a'))), ['a']);
      expect(fetches, 2);
    });

    test('later fetches by others reach every watcher', () async {
      final seen = <String>[];
      final sub = cache.watch('k', answer('a')).listen(seen.add);
      await pumpEventQueue();
      await cache.get('k', answer('b'), fresh: true);
      await pumpEventQueue();
      await sub.cancel();

      expect(seen, ['a', 'b']);
    });

    test('a failed fetch is an error on the stream', () async {
      final errors = <Object>[];
      final sub = cache
          .watch('k', () async => throw StateError('offline'))
          .listen((_) {}, onError: errors.add);
      await pumpEventQueue();
      await sub.cancel();

      expect(errors.single, isStateError);
      expect(cache.peek('k'), isNull);
    });
  });

  group('throttle', () {
    test('a value younger than the interval is not refetched', () async {
      await cache.get('k', answer('a'));
      now = now.add(const Duration(seconds: 29));

      expect(await collect(cache.watch('k', answer('b'))), ['a']);
      expect(await cache.get('k', answer('b')), 'a');
      expect(fetches, 1);
      expect(cache.isCurrent('k'), isTrue);
    });

    test('the interval counts from the last fetch, not the last ask', () async {
      await cache.get('k', answer('a'));
      for (var i = 0; i < 3; i++) {
        now = now.add(const Duration(seconds: 10));
        await cache.get('k', answer('b'));
      }

      expect(fetches, 2);
      expect(cache.peek('k'), 'b');
    });

    test('a failed fetch leaves the kept value due', () async {
      await cache.get('k', answer('a'));
      now = now.add(const Duration(seconds: 31));
      await expectLater(
        cache.get('k', () async => throw StateError('offline')),
        throwsStateError,
      );

      expect(cache.peek('k'), 'a');
      expect(cache.isCurrent('k'), isFalse);
    });
  });

  group('fresh', () {
    test('skips the kept value and the interval and emits once', () async {
      await cache.get('k', answer('a'));

      final emitted = await cache
          .watch('k', answer('b'), fresh: true)
          .toList();

      expect(emitted, ['b']);
      expect(cache.peek('k'), 'b');
      expect(fetches, 2);
    });

    test('does not join a fetch already running', () async {
      final slow = Completer<String>();
      final first = cache.get('k', () {
        fetches++;
        return slow.future;
      });
      final second = cache.get('k', answer('b'), fresh: true);
      slow.complete('a');

      expect(await first, 'a');
      expect(await second, 'b');
      expect(fetches, 2);
    });
  });

  test('asks for one key while its fetch runs share it', () async {
    final slow = Completer<String>();
    Future<String> fetch() {
      fetches++;
      return slow.future;
    }

    final watched = collect(cache.watch('k', fetch));
    final got = cache.get('k', fetch);
    slow.complete('a');

    expect(await got, 'a');
    expect(await watched, ['a']);
    expect(fetches, 1);
  });

  test('invalidate makes the next ask fetch', () async {
    await cache.get('k', answer('a'));
    cache.invalidate('k');

    expect(cache.peek('k'), isNull);
    expect(await collect(cache.watch('k', answer('a'))), ['a']);
    expect(fetches, 2);
  });

  test('invalidate drops the answer of a fetch already running', () async {
    final slow = Completer<String>();
    final running = cache.get('k', () => slow.future);
    cache.invalidate('k');
    slow.complete('old');
    await running;

    expect(cache.peek('k'), isNull);
  });

  test('a custom equality decides what counts as a change', () async {
    final loose = KeyedStreamCache<String, String>(
      minRefreshInterval: Duration.zero,
      equals: (a, b) => a.toLowerCase() == b.toLowerCase(),
    );
    addTearDown(loose.dispose);
    await loose.get('k', answer('a'));

    expect(await collect(loose.watch('k', answer('A'))), ['a']);
  });

  group('limits and clearing', () {
    test('keeps only the most recently used keys', () async {
      cache = make(maxKeys: 2);
      await cache.get('one', answer('1'));
      await cache.get('two', answer('2'));
      cache.peek('one');
      await cache.get('one', answer('1'));
      await cache.get('three', answer('3'));

      expect(cache.peek('two'), isNull);
      expect(cache.peek('one'), '1');
      expect(cache.peek('three'), '3');
    });

    test('a watched key is not evicted', () async {
      cache = make(maxKeys: 1);
      final sub = cache.watch('one', answer('1')).listen((_) {});
      await pumpEventQueue();
      await cache.get('two', answer('2'));

      expect(cache.peek('one'), '1');
      await sub.cancel();
    });

    test('clearWhere drops matching keys and closes their watchers', () async {
      await cache.get('user-a:x', answer('a'));
      await cache.get('user-b:x', answer('b'));
      var closed = false;
      final sub = cache
          .watch('user-a:x', answer('a'))
          .listen((_) {}, onDone: () => closed = true);
      await pumpEventQueue();

      cache.clearWhere((key) => key.startsWith('user-a:'));
      await pumpEventQueue();

      expect(cache.peek('user-a:x'), isNull);
      expect(cache.peek('user-b:x'), 'b');
      expect(closed, isTrue);
      await sub.cancel();
    });

    test('clear ignores fetches that were running', () async {
      final slow = Completer<String>();
      final running = cache.get('k', () => slow.future);
      cache.clear();
      slow.complete('a');
      await running;

      expect(cache.peek('k'), isNull);
    });
  });
}
