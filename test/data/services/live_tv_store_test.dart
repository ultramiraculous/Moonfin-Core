import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/models/live_tv_recording_state.dart';
import 'package:moonfin/data/services/live_tv_store.dart';
import 'package:moonfin/di/modules/app_module.dart';
import 'package:server_core/server_core.dart';

class _Client extends Mock implements MediaServerClient {}

class _LiveTvApi extends Mock implements LiveTvApi {}

Map<String, dynamic> _program(String channel, DateTime start, DateTime end) => {
  'Id': '$channel-${start.toIso8601String()}',
  'ChannelId': channel,
  'StartDate': start.toUtc().toIso8601String(),
  'EndDate': end.toUtc().toIso8601String(),
};

void main() {
  late _Client client;
  late _LiveTvApi liveTvApi;
  late DateTime now;
  late int channelLoads;

  final from = DateTime(2026, 11, 25, 20);
  final to = DateTime(2026, 11, 25, 23);

  setUp(() {
    now = DateTime(2026, 11, 25, 20, 10);
    client = _Client();
    liveTvApi = _LiveTvApi();
    channelLoads = 0;
    when(() => client.liveTvApi).thenReturn(liveTvApi);
    when(() => client.baseUrl).thenReturn('http://server');
    when(() => client.userId).thenReturn('me');
    when(
      () => liveTvApi.getChannels(
        sortBy: any(named: 'sortBy'),
        sortOrder: any(named: 'sortOrder'),
        fields: any(named: 'fields'),
        enableTotalRecordCount: any(named: 'enableTotalRecordCount'),
        userId: any(named: 'userId'),
      ),
    ).thenAnswer((_) async {
      channelLoads++;
      return {
        'Items': [
          {'Id': 'c1', 'Name': 'One'},
        ],
      };
    });
  });

  tearDown(GetIt.instance.reset);

  group('channels', () {
    test('reads within five minutes share one load', () async {
      GetIt.instance.registerSingleton(LiveTvChannelStore(clock: () => now));

      final first = await LiveTvChannelStore.fetch(client);
      await LiveTvChannelStore.fetch(client);
      expect(channelLoads, 1);
      expect(first.items.single['Id'], 'c1');

      now = now.add(const Duration(minutes: 6));
      await LiveTvChannelStore.fetch(client);
      expect(channelLoads, 2);
    });

    test('each user has their own lineup', () async {
      GetIt.instance.registerSingleton(LiveTvChannelStore(clock: () => now));
      await LiveTvChannelStore.fetch(client);
      when(() => client.userId).thenReturn('them');
      await LiveTvChannelStore.fetch(client);

      expect(channelLoads, 2);
    });

    test('a session change starts empty stores', () async {
      final channels = LiveTvChannelStore(clock: () => now);
      GetIt.instance.registerSingleton(channels);
      GetIt.instance.registerSingleton(LiveTvProgramStore(clock: () => now));
      await LiveTvChannelStore.fetch(client);

      resetUserScopedSingletons();

      expect(GetIt.instance<LiveTvChannelStore>(), isNot(same(channels)));
      await LiveTvChannelStore.fetch(client);
      expect(channelLoads, 2);
    });
  });

  group('programs', () {
    late LiveTvProgramStore store;
    late List<List<String>> asked;

    setUp(() {
      store = LiveTvProgramStore(clock: () => now);
      GetIt.instance.registerSingleton(store);
      asked = [];
    });

    tearDown(() => store.dispose());

    Future<Map<String, dynamic>> guide(
      List<String> ids, {
      bool fresh = false,
      String? category,
      DateTime? end,
    }) => LiveTvProgramStore.guide(
      client,
      channelIds: ids,
      from: from,
      to: to,
      category: category,
      fresh: fresh,
      fetch: (missing) async {
        asked.add(missing);
        return {
          'Items': [
            for (final id in missing)
              _program(id, from, end ?? DateTime(2026, 11, 25, 21)),
          ],
        };
      },
    );

    List<String?> channelsOf(Map<String, dynamic> response) => [
      for (final item in response['Items'] as List)
        (item as Map)['ChannelId'] as String?,
    ];

    test('only channels not held are fetched', () async {
      await guide(['a', 'b']);
      final response = await guide(['a', 'b', 'c']);

      expect(asked, [
        ['a', 'b'],
        ['c'],
      ]);
      expect(channelsOf(response)..sort(), ['a', 'b', 'c']);
    });

    test('held programs expire at the next half hour', () async {
      await guide(['a']);
      now = DateTime(2026, 11, 25, 20, 29);
      await guide(['a']);
      expect(asked, hasLength(1));

      now = DateTime(2026, 11, 25, 20, 30);
      await guide(['a']);
      expect(asked, hasLength(2));
    });

    test('held programs expire when one airing at fetch time ends', () async {
      await guide(['a'], end: DateTime(2026, 11, 25, 20, 15));
      now = DateTime(2026, 11, 25, 20, 14);
      await guide(['a']);
      expect(asked, hasLength(1));

      now = DateTime(2026, 11, 25, 20, 15);
      await guide(['a']);
      expect(asked, hasLength(2));
    });

    test('fresh reads and other categories fetch', () async {
      await guide(['a']);
      await guide(['a'], fresh: true);
      await guide(['a'], category: 'movies');

      expect(asked, hasLength(3));
    });

    test('a recording change drops held programs', () async {
      await guide(['a']);
      liveTvRecordingRevision.value++;
      await guide(['a']);

      expect(asked, hasLength(2));
    });

    test('without a registered store every channel is fetched', () async {
      GetIt.instance.unregister<LiveTvProgramStore>();
      await guide(['a']);
      await guide(['a']);

      expect(asked, hasLength(2));
    });
  });

  test('half hours end on the hour and the half', () {
    expect(
      LiveTvProgramStore.nextHalfHour(DateTime(2026, 1, 1, 9, 0)),
      DateTime(2026, 1, 1, 9, 30),
    );
    expect(
      LiveTvProgramStore.nextHalfHour(DateTime(2026, 1, 1, 9, 45)),
      DateTime(2026, 1, 1, 10),
    );
  });
}
