import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/services/item_store.dart';
import 'package:moonfin/di/modules/app_module.dart';
import 'package:server_core/server_core.dart';

class _Client extends Mock implements MediaServerClient {}

class _ItemsApi extends Mock implements ItemsApi {}

Map<String, dynamic> _item({bool played = false}) => {
  'Id': 'item',
  'Name': 'Item',
  'UserData': {'Played': played},
};

void main() {
  late _Client client;
  late _ItemsApi itemsApi;
  late DateTime now;

  setUp(() {
    now = DateTime(2026, 11, 25, 12);
    client = _Client();
    itemsApi = _ItemsApi();
    when(() => client.itemsApi).thenReturn(itemsApi);
    when(() => client.baseUrl).thenReturn('http://server');
    when(() => client.userId).thenReturn('me');
    when(() => itemsApi.getItem('item')).thenAnswer((_) async => _item());
    when(() => itemsApi.getItem('item', fields: any(named: 'fields')))
        .thenAnswer((_) async => _item());
  });

  tearDown(GetIt.instance.reset);

  ItemStore register() {
    final store = ItemStore(clock: () => now);
    GetIt.instance.registerSingleton(store);
    return store;
  }

  test('items match on their user data', () {
    expect(ItemStore.sameItem(_item(), _item()), isTrue);
    expect(ItemStore.sameItem(_item(), _item(played: true)), isFalse);
  });

  test('without a registered store every read goes to the server', () async {
    await ItemStore.fetch(client, 'item');
    await ItemStore.fetch(client, 'item');

    verify(() => itemsApi.getItem('item')).called(2);
  });

  test('reads within the refresh interval share one fetch', () async {
    register();
    await Future.wait([
      ItemStore.fetch(client, 'item'),
      ItemStore.fetch(client, 'item'),
    ]);
    await ItemStore.fetch(client, 'item');
    verify(() => itemsApi.getItem('item')).called(1);

    now = now.add(const Duration(seconds: 31));
    await ItemStore.fetch(client, 'item');
    verify(() => itemsApi.getItem('item')).called(1);
  });

  test('fresh reads always fetch', () async {
    register();
    await ItemStore.fetch(client, 'item');
    await ItemStore.fetch(client, 'item', fresh: true);

    verify(() => itemsApi.getItem('item')).called(2);
  });

  test(
    'the fields asked for, the user and the server are part of the key',
    () async {
      final store = register();
      await ItemStore.fetch(client, 'item');
      await ItemStore.fetch(client, 'item', fields: 'ProviderIds');
      verify(() => itemsApi.getItem('item')).called(1);
      verify(() => itemsApi.getItem('item', fields: 'ProviderIds')).called(1);

      when(() => client.userId).thenReturn('them');
      await ItemStore.fetch(client, 'item');
      when(() => client.baseUrl).thenReturn('http://other');
      await ItemStore.fetch(client, 'item');
      verify(() => itemsApi.getItem('item')).called(2);

      expect(
        store.peek(
          const ItemKey(
            serverId: 'http://server',
            userId: 'me',
            itemId: 'item',
          ),
        ),
        isNotNull,
      );
    },
  );

  test('watchers see a change in user data', () async {
    final store = register();
    const key = ItemKey(
      serverId: 'http://server',
      userId: 'me',
      itemId: 'item',
    );
    var played = false;
    final seen = <Object?>[];
    final sub = store
        .watch(key, () async => _item(played: played))
        .listen((item) => seen.add((item['UserData'] as Map)['Played']));
    addTearDown(sub.cancel);
    await pumpEventQueue();

    await store.get(key, () async => _item(played: played), fresh: true);
    await pumpEventQueue();
    expect(seen, [false]);

    played = true;
    await store.get(key, () async => _item(played: played), fresh: true);
    await pumpEventQueue();
    expect(seen, [false, true]);
  });

  test('a session change starts an empty store', () async {
    final before = register();
    await ItemStore.fetch(client, 'item');

    resetUserScopedSingletons();

    expect(GetIt.instance<ItemStore>(), isNot(same(before)));
    await ItemStore.fetch(client, 'item');
    verify(() => itemsApi.getItem('item')).called(2);
  });
}
