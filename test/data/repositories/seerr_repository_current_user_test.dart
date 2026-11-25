import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/auth/repositories/session_repository.dart';
import 'package:moonfin/data/repositories/seerr_repository.dart';
import 'package:server_core/server_core.dart';
import 'package:server_silo/server_silo.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockSessionRepository extends Mock implements SessionRepository {}

/// A Silo server whose account endpoint can be held, failed or changed.
class _Silo implements HttpClientAdapter {
  int userId = 7;
  int userFetches = 0;
  bool failUser = false;
  Completer<void>? hold;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    if (path == '/api/v2/account/me') {
      userFetches++;
      await hold?.future;
      if (failUser) return _json(500, {'status': 500});
      return _json(200, {'id': userId, 'username': 'pat'});
    }
    if (path == '/api/v2/requests/status') {
      return _json(200, {'allowed': true, 'requests_enabled': true});
    }
    return _json(403, {
      'type': 'https://siloserver.org/docs/api/v2/problems/permission_denied',
      'status': 403,
    });
  }

  ResponseBody _json(int status, Object body) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Silo silo;
  late _MockSessionRepository session;
  late SeerrRepository repo;
  late DateTime now;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    session = _MockSessionRepository();
    when(() => session.activeUserId).thenReturn('user1');
    silo = _Silo();
    final client =
        SiloMediaServerClient(
            baseUrl: 'https://silo.example',
            deviceInfo: const DeviceInfo(
              id: 'device',
              name: 'Device',
              appName: 'Moonfin',
              appVersion: '1.0.0',
            ),
            httpClientAdapter: silo,
          )
          ..session.setTokens(
            SiloTokens(
              accessToken: 'access',
              refreshToken: 'refresh',
              expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
              lifetime: const Duration(hours: 1),
            ),
          )
          ..profileId = 'p1';
    repo = SeerrRepository(store, session, client);
    now = DateTime(2026, 11, 25, 12);
    // Initialising reads the user once for the status.
    await repo.ensureInitialized();
    silo.userFetches = 0;
  });

  Future<T> atNow<T>(Future<T> Function() body) =>
      withClock(Clock(() => now), body);

  test('concurrent callers share one fetch, and later ones use it', () {
    return atNow(() async {
      final users = await Future.wait([
        repo.getCurrentUser(),
        repo.getCurrentUser(),
        repo.getCurrentUser(),
      ]);
      expect(users.map((u) => u.id), [7, 7, 7]);
      expect(silo.userFetches, 1);

      now = now.add(const Duration(minutes: 9));
      expect((await repo.getCurrentUser()).id, 7);
      expect(silo.userFetches, 1);
    });
  });

  test('a failed fetch is not stored', () {
    return atNow(() async {
      silo.failUser = true;
      await expectLater(repo.getCurrentUser(), throwsA(anything));

      silo.failUser = false;
      expect((await repo.getCurrentUser()).id, 7);
      expect(silo.userFetches, 2);
    });
  });

  test('an old user is returned at once and refreshed once behind it', () {
    return atNow(() async {
      await repo.getCurrentUser();
      now = now.add(const Duration(minutes: 11));
      silo.userId = 8;
      silo.hold = Completer<void>();

      expect((await repo.getCurrentUser()).id, 7);
      expect((await repo.getCurrentUser()).id, 7);
      await pumpEventQueue();
      expect(silo.userFetches, 2);

      silo.hold!.complete();
      await pumpEventQueue();
      expect((await repo.getCurrentUser()).id, 8);
      expect(silo.userFetches, 2);
    });
  });

  test('a failed background refresh keeps the stored user', () {
    return atNow(() async {
      await repo.getCurrentUser();
      now = now.add(const Duration(minutes: 11));
      silo.failUser = true;

      expect((await repo.getCurrentUser()).id, 7);
      await pumpEventQueue();
      expect((await repo.getCurrentUser()).id, 7);
    });
  });

  test('fresh always asks Seerr', () {
    return atNow(() async {
      await repo.getCurrentUser();
      silo.userId = 8;
      expect((await repo.getCurrentUser(fresh: true)).id, 8);
      expect((await repo.getCurrentUser()).id, 8);
      expect(silo.userFetches, 2);
    });
  });

  test('switching Jellyfin user drops the stored Seerr user', () {
    return atNow(() async {
      await repo.getCurrentUser();
      when(() => session.activeUserId).thenReturn('user2');
      silo.userId = 9;
      expect((await repo.getCurrentUser()).id, 9);
    });
  });

  test('a fetch from before a sign-out does not repopulate the cache', () {
    return atNow(() async {
      silo.hold = Completer<void>();
      final stale = repo.getCurrentUser();
      await pumpEventQueue();

      await repo.logoutMoonfin();
      silo.hold!.complete();
      silo.hold = null;
      expect((await stale).id, 7);

      silo.userId = 8;
      expect((await repo.getCurrentUser()).id, 8);
      expect(silo.userFetches, 2);
    });
  });
}
