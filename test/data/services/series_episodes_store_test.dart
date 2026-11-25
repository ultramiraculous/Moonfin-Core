import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/series_episodes_store.dart';

AggregatedItem _episode(String id, {bool played = false}) => AggregatedItem(
  id: id,
  serverId: 'server',
  rawData: {
    'Id': id,
    'UserData': {'Played': played},
  },
);

void main() {
  test('lists match on ids and user data', () {
    final same = SeriesEpisodesStore.sameEpisodes;

    expect(same([_episode('a')], [_episode('a')]), isTrue);
    expect(same([_episode('a')], [_episode('b')]), isFalse);
    expect(same([_episode('a')], [_episode('a', played: true)]), isFalse);
    expect(same([_episode('a')], [_episode('a'), _episode('b')]), isFalse);
  });

  test('each user keeps their own list', () async {
    final store = SeriesEpisodesStore();
    addTearDown(store.dispose);
    const mine = SeriesEpisodesKey(
      serverId: 'server',
      userId: 'me',
      seriesId: 'series',
    );
    const theirs = SeriesEpisodesKey(
      serverId: 'server',
      userId: 'them',
      seriesId: 'series',
    );
    await store.get(mine, () async => [_episode('a')]);

    expect(store.peek(mine), hasLength(1));
    expect(store.peek(theirs), isNull);
  });
}
