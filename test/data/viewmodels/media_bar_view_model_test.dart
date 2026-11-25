import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/models/media_bar_slide_item.dart';
import 'package:moonfin/data/models/media_bar_state.dart';
import 'package:moonfin/data/repositories/mdblist_repository.dart';
import 'package:moonfin/data/repositories/media_bar_repository.dart';
import 'package:moonfin/data/services/media_bar_cache_store.dart';
import 'package:moonfin/data/services/plugin_sync_service.dart';
import 'package:moonfin/data/viewmodels/media_bar_view_model.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Repository extends Mock implements MediaBarRepository {}

class _MdbList extends Mock implements MdbListRepository {}

class _Client extends Mock implements MediaServerClient {}

class _Sync extends ChangeNotifier implements PluginSyncService {
  bool available = false;

  @override
  bool get pluginAvailable => available;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CacheStore implements MediaBarCacheStore {
  final saved = <String, List<MediaBarSlideItem>>{};
  final reads = <String>[];

  @override
  Future<List<MediaBarSlideItem>?> read(
    String cacheKey, {
    String? token,
  }) async {
    reads.add(cacheKey);
    return saved[cacheKey];
  }

  @override
  Future<void> write(
    String cacheKey,
    List<MediaBarSlideItem> items, {
    String? token,
  }) async {
    if (items.isEmpty) {
      saved.remove(cacheKey);
    } else {
      saved[cacheKey] = items;
    }
  }
}

void main() {
  late UserPreferences prefs;
  late _Repository repository;
  late _Sync sync;
  late List<Completer<MediaBarState>> loads;

  setUpAll(() => registerFallbackValue(<MediaBarSlideItem>[]));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);
    sync = _Sync();
    GetIt.instance.registerSingleton<PluginSyncService>(sync);
    loads = [];
    repository = _Repository();
    when(() => repository.loadItems()).thenAnswer((_) {
      final load = Completer<MediaBarState>();
      loads.add(load);
      return load.future;
    });
    when(() => repository.loadNewReleases(any()))
        .thenAnswer((_) async => const {});
  });

  tearDown(() => GetIt.instance.reset());

  MediaBarViewModel create() =>
      MediaBarViewModel(repository, _MdbList(), prefs, _Client());

  test('a source change made during a load runs once that load ends', () async {
    final viewModel = create();
    unawaited(viewModel.load());
    await prefs.set(UserPreferences.mediaBarLibraryIds, 'lib');
    expect(loads, hasLength(1));

    loads.first.complete(const MediaBarDisabled());
    await pumpEventQueue();

    expect(loads, hasLength(2));
  });

  test('the bar shows before its new release labels, which follow', () async {
    const series = MediaBarSlideItem(
      itemId: 'series',
      serverId: 'server',
      title: 'Show',
      itemType: 'Series',
    );
    const movie = MediaBarSlideItem(
      itemId: 'movie',
      serverId: 'server',
      title: 'Film',
    );
    final labels = Completer<Map<String, MediaBarNewReleaseInfo>>();
    when(() => repository.loadNewReleases(any()))
        .thenAnswer((_) => labels.future);
    final viewModel = create();
    unawaited(viewModel.load());
    loads.first.complete(const MediaBarReady([series, movie]));
    await pumpEventQueue();

    expect(viewModel.state, isA<MediaBarReady>());
    expect(viewModel.items.map((item) => item.newRelease), [null, null]);

    labels.complete({
      'series': const MediaBarNewReleaseInfo(
        kind: MediaBarNewRelease.newSeason,
        season: 2,
      ),
    });
    await pumpEventQueue();

    expect(
      viewModel.items.first.newRelease?.kind,
      MediaBarNewRelease.newSeason,
    );
    expect(viewModel.items.last.newRelease, isNull);
    viewModel.dispose();
  });

  test('picked lists load again once Moonbase answers', () async {
    await prefs.set(
      UserPreferences.mediaBarExternalLists,
      'imdb_top_250_movies',
    );
    final viewModel = create();
    unawaited(viewModel.load());
    loads.first.complete(const MediaBarDisabled());
    await pumpEventQueue();

    sync
      ..available = true
      ..notifyListeners();
    await pumpEventQueue();

    expect(loads, hasLength(2));
    viewModel.dispose();
  });

  test(
    'seeding hideWatchedInRecentRows reloads the media bar when changed',
    () async {
      final viewModel = create();
      unawaited(viewModel.load());
      loads.first.complete(const MediaBarReady([]));
      await pumpEventQueue();
      expect(loads, hasLength(1));

      prefs.seedHideWatchedFromServer(
        const UserConfiguration(hidePlayedInLatest: true),
      );
      await pumpEventQueue();

      expect(loads, hasLength(2));
      viewModel.dispose();
    },
  );

  test('changing the recently released sort reloads the media bar', () async {
    final viewModel = create();
    unawaited(viewModel.load());
    loads.first.complete(const MediaBarReady([]));
    await pumpEventQueue();

    await prefs.set(
      UserPreferences.recentlyReleasedSeriesType,
      RecentlyReleasedSeriesType.episode,
    );
    await pumpEventQueue();

    expect(loads, hasLength(2));
    viewModel.dispose();
  });

  group('cold start cache', () {
    const cachedSlide = MediaBarSlideItem(
      itemId: 'cached',
      serverId: 'server',
      title: 'Cached',
    );
    const freshSlide = MediaBarSlideItem(
      itemId: 'fresh',
      serverId: 'server',
      title: 'Fresh',
    );
    late _CacheStore cache;
    late _Client client;

    setUp(() {
      cache = _CacheStore();
      client = _Client();
      when(() => client.baseUrl).thenReturn('http://server');
      when(() => client.userId).thenReturn('user');
      when(() => client.accessToken).thenReturn('token');
    });

    MediaBarViewModel createCached() => MediaBarViewModel(
      repository,
      _MdbList(),
      prefs,
      client,
      cacheStore: cache,
    );

    Future<String> seedKey() async {
      final viewModel = createCached();
      unawaited(viewModel.load());
      await pumpEventQueue();
      final key = cache.reads.single;
      loads.single.complete(const MediaBarReady([cachedSlide]));
      await pumpEventQueue();
      viewModel.dispose();
      loads.clear();
      cache.reads.clear();
      return key;
    }

    test(
      'shows the saved slides, then the fresh ones, and saves those',
      () async {
        final key = await seedKey();
        expect(cache.saved[key]?.single.itemId, 'cached');

        final viewModel = createCached();
        unawaited(viewModel.load());
        await pumpEventQueue();

        expect(viewModel.items.map((i) => i.itemId), ['cached']);
        expect(loads, hasLength(1));

        loads.single.complete(const MediaBarReady([freshSlide]));
        await pumpEventQueue();

        expect(viewModel.items.map((i) => i.itemId), ['fresh']);
        expect(cache.saved[key]?.single.itemId, 'fresh');
        viewModel.dispose();
      },
    );

    test('keeps the saved slides when the refresh fails', () async {
      await seedKey();
      final viewModel = createCached();
      unawaited(viewModel.load());
      await pumpEventQueue();

      loads.single.complete(MediaBarError(Exception('offline')));
      await pumpEventQueue();

      expect(viewModel.items.map((i) => i.itemId), ['cached']);
      viewModel.dispose();
    });

    test('new release banners attach to the fresh slides', () async {
      await seedKey();
      when(() => repository.loadNewReleases(any())).thenAnswer(
        (_) async => {
          'fresh': const MediaBarNewReleaseInfo(
            kind: MediaBarNewRelease.newMovie,
          ),
        },
      );
      final viewModel = createCached();
      unawaited(viewModel.load());
      await pumpEventQueue();
      loads.single.complete(const MediaBarReady([freshSlide]));
      await pumpEventQueue();

      expect(
        viewModel.items.single.newRelease?.kind,
        MediaBarNewRelease.newMovie,
      );
      viewModel.dispose();
    });

    test('another user or changed settings miss the saved slides', () async {
      final key = await seedKey();

      when(() => client.userId).thenReturn('other');
      var viewModel = createCached();
      unawaited(viewModel.load());
      await pumpEventQueue();
      expect(cache.reads.single, isNot(key));
      expect(viewModel.state, isA<MediaBarLoading>());
      viewModel.dispose();

      when(() => client.userId).thenReturn('user');
      await prefs.set(UserPreferences.mediaBarItemCount, '5');
      cache.reads.clear();
      viewModel = createCached();
      unawaited(viewModel.load());
      await pumpEventQueue();
      expect(cache.reads.single, isNot(key));
      expect(viewModel.state, isA<MediaBarLoading>());
      viewModel.dispose();
    });

    test('turning the bar off drops the saved slides', () async {
      final key = await seedKey();
      final viewModel = createCached();
      unawaited(viewModel.load());
      await pumpEventQueue();
      loads.single.complete(const MediaBarDisabled());
      await pumpEventQueue();

      expect(cache.saved, isNot(contains(key)));
      viewModel.dispose();
    });
  });
}
