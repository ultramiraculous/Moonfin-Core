import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/repositories/item_mutation_repository.dart';
import 'package:moonfin/data/repositories/mdblist_repository.dart';
import 'package:moonfin/data/repositories/tmdb_repository.dart';
import 'package:moonfin/data/services/plugin_sync_service.dart';
import 'package:moonfin/data/services/series_episodes_store.dart';
import 'package:moonfin/data/viewmodels/item_detail_view_model.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends Mock implements MediaServerClient {}

class _ItemsApi extends Mock implements ItemsApi {}

class _PluginSyncService extends Mock implements PluginSyncService {}

Map<String, dynamic> _episodes(List<String> ids, {String played = ''}) => {
  'Items': [
    for (final (i, id) in ids.indexed)
      {
        'Id': id,
        'Type': 'Episode',
        'ParentIndexNumber': 1,
        'IndexNumber': i + 1,
        'UserData': {'Played': id == played},
      },
  ],
};

void main() {
  late _Client client;
  late _ItemsApi itemsApi;

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferenceStore();
    await prefs.init();
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(prefs));
    final pluginSync = _PluginSyncService();
    when(() => pluginSync.seerrAvailable).thenReturn(false);
    GetIt.instance.registerSingleton<PluginSyncService>(pluginSync);
    GetIt.instance.registerSingleton<SeriesEpisodesStore>(
      SeriesEpisodesStore(minRefreshInterval: Duration.zero),
    );

    client = _Client();
    itemsApi = _ItemsApi();
    when(() => client.itemsApi).thenReturn(itemsApi);
    when(() => client.baseUrl).thenReturn('http://server');
    when(() => client.userId).thenReturn('user');
    when(
      () => itemsApi.getItem(
        any(that: startsWith('episode-')),
        mediaSourceId: any(named: 'mediaSourceId'),
      ),
    ).thenAnswer(
      (call) async => {
        'Id': call.positionalArguments.first,
        'Type': 'Episode',
        'SeriesId': 'series-1',
        'SeasonId': 'season-1',
      },
    );
  });

  tearDown(() => GetIt.instance.reset());

  Future<ItemDetailViewModel> openEpisode(String id) async {
    final tmdb = TmdbRepository(client);
    final vm = ItemDetailViewModel(
      itemId: id,
      client: client,
      mutations: ItemMutationRepository(client),
      mdbListRepository: MdbListRepository(client, tmdb),
      tmdbRepository: tmdb,
    );
    addTearDown(vm.dispose);
    await vm.load();
    return vm;
  }

  void answerEpisodes(Future<Map<String, dynamic>> Function() answer) {
    when(
      () => itemsApi.getEpisodes('series-1', fields: any(named: 'fields')),
    ).thenAnswer((_) => answer());
  }

  test('nothing is known before the first load', () async {
    answerEpisodes(() async => _episodes(['episode-1']));
    final vm = await openEpisode('episode-1');

    expect(vm.knownSeriesEpisodes, isNull);
    expect(vm.freshSeriesEpisodes, isNull);

    await vm.loadAllSeriesEpisodes();

    expect(vm.knownSeriesEpisodes!.map((e) => e.id), ['episode-1']);
    expect(vm.freshSeriesEpisodes!.map((e) => e.id), ['episode-1']);
  });

  test('a later page of the series starts from the kept list', () async {
    answerEpisodes(() async => _episodes(['episode-1', 'episode-2']));
    await (await openEpisode('episode-1')).loadAllSeriesEpisodes();

    final response = Completer<Map<String, dynamic>>();
    answerEpisodes(() => response.future);
    final vm = await openEpisode('episode-2');
    final load = vm.loadAllSeriesEpisodes();

    expect(vm.seriesEpisodes.map((e) => e.id), ['episode-1', 'episode-2']);
    expect(vm.freshSeriesEpisodes, isNull);

    response.complete(
      _episodes(['episode-1', 'episode-2'], played: 'episode-1'),
    );
    await load;

    expect(vm.freshSeriesEpisodes!.first.isPlayed, isTrue);
    expect(vm.seriesEpisodes.first.isPlayed, isTrue);
  });

  test('the stream carries each list the page shows', () async {
    answerEpisodes(() async => _episodes(['episode-1']));
    await (await openEpisode('episode-1')).loadAllSeriesEpisodes();

    answerEpisodes(() async => _episodes(['episode-1', 'episode-2']));
    final vm = await openEpisode('episode-2');
    final seen = <List<String>>[];
    final sub = vm.seriesEpisodesStream.listen(
      (episodes) => seen.add(episodes.map((e) => e.id).toList()),
    );
    await vm.loadAllSeriesEpisodes();
    await pumpEventQueue();
    await sub.cancel();

    expect(seen, [
      ['episode-1'],
      ['episode-1', 'episode-2'],
    ]);
  });

  test('a recent kept list is current without a fetch', () async {
    await GetIt.instance.unregister<SeriesEpisodesStore>();
    GetIt.instance.registerSingleton<SeriesEpisodesStore>(SeriesEpisodesStore());
    var calls = 0;
    answerEpisodes(() async {
      calls++;
      return _episodes(['episode-1', 'episode-2']);
    });
    await (await openEpisode('episode-1')).loadAllSeriesEpisodes();

    final vm = await openEpisode('episode-2');
    await vm.loadAllSeriesEpisodes();

    expect(vm.freshSeriesEpisodes!.map((e) => e.id), ['episode-1', 'episode-2']);
    expect(calls, 1);
  });

  test('a failed load is tried again on the next call', () async {
    var calls = 0;
    answerEpisodes(() async {
      calls++;
      if (calls == 1) throw StateError('offline');
      return _episodes(['episode-1']);
    });
    final vm = await openEpisode('episode-1');

    await vm.loadAllSeriesEpisodes();
    expect(vm.knownSeriesEpisodes, isNull);

    await vm.loadAllSeriesEpisodes();
    expect(vm.freshSeriesEpisodes!.map((e) => e.id), ['episode-1']);
    expect(calls, 2);
  });
}
