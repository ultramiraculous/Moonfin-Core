import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/services/genre_list_store.dart';
import 'package:moonfin/di/modules/app_module.dart';
import 'package:server_core/server_core.dart';

class _Client extends Mock implements MediaServerClient {}

class _ItemsApi extends Mock implements ItemsApi {}

Map<String, dynamic> _page(List<String> names, int total) => {
  'Items': [
    for (final n in names) {'Id': n, 'Name': n},
  ],
  'TotalRecordCount': total,
};

void main() {
  late _Client client;
  late _ItemsApi itemsApi;
  late DateTime now;
  late List<int?> genreStarts;
  late List<List<String>?> genreTypes;

  setUp(() {
    now = DateTime(2026, 11, 25, 12);
    client = _Client();
    itemsApi = _ItemsApi();
    genreStarts = [];
    genreTypes = [];
    when(() => client.itemsApi).thenReturn(itemsApi);
    when(() => client.baseUrl).thenReturn('http://server');
    when(() => client.userId).thenReturn('me');
    when(
      () => itemsApi.getGenres(
        parentId: any(named: 'parentId'),
        userId: any(named: 'userId'),
        sortBy: any(named: 'sortBy'),
        sortOrder: any(named: 'sortOrder'),
        startIndex: any(named: 'startIndex'),
        limit: any(named: 'limit'),
        recursive: any(named: 'recursive'),
        fields: any(named: 'fields'),
        includeItemTypes: any(named: 'includeItemTypes'),
      ),
    ).thenAnswer((invocation) async {
      final start = invocation.namedArguments[#startIndex] as int?;
      genreStarts.add(start);
      genreTypes.add(
        invocation.namedArguments[#includeItemTypes] as List<String>?,
      );
      // Two full pages and a short one.
      final size = GenreListStore.pageSize;
      final count = start == 2 * size ? 3 : size;
      return _page([
        for (var i = 0; i < count; i++) 'g${start! + i}',
      ], 2 * size + 3);
    });
    when(
      () => itemsApi.getStudios(
        parentId: any(named: 'parentId'),
        userId: any(named: 'userId'),
        sortBy: any(named: 'sortBy'),
        sortOrder: any(named: 'sortOrder'),
        startIndex: any(named: 'startIndex'),
        limit: any(named: 'limit'),
        recursive: any(named: 'recursive'),
        fields: any(named: 'fields'),
        includeItemTypes: any(named: 'includeItemTypes'),
      ),
    ).thenAnswer((_) async => _page(['A24'], 1));
  });

  tearDown(GetIt.instance.reset);

  GenreListStore register() {
    final store = GenreListStore(clock: () => now);
    GetIt.instance.registerSingleton(store);
    return store;
  }

  test('loads every page of the list', () async {
    final genres = await GenreListStore.fetch(client, GenreListKind.genres);

    expect(genres, hasLength(2 * GenreListStore.pageSize + 3));
    expect(genreStarts, [
      0,
      GenreListStore.pageSize,
      2 * GenreListStore.pageSize,
    ]);
  });

  test('reads within ten minutes share one load', () async {
    register();
    await GenreListStore.fetch(client, GenreListKind.genres);
    now = now.add(const Duration(minutes: 9));
    await GenreListStore.fetch(client, GenreListKind.genres);
    expect(genreStarts, hasLength(3));

    now = now.add(const Duration(minutes: 2));
    await GenreListStore.fetch(client, GenreListKind.genres);
    expect(genreStarts, hasLength(6));
  });

  test('item types match in any order', () async {
    register();
    await GenreListStore.fetch(
      client,
      GenreListKind.genres,
      includeItemTypes: const ['Movie', 'Series'],
    );
    await GenreListStore.fetch(
      client,
      GenreListKind.genres,
      includeItemTypes: const ['Series', 'Movie'],
    );

    expect(genreStarts, hasLength(3));
    expect(genreTypes.first, ['Movie', 'Series']);
  });

  test(
    'kind, library, item types, user and server are part of the key',
    () async {
      register();
      Future<void> genres({String? parentId, List<String>? types}) =>
          GenreListStore.fetch(
            client,
            GenreListKind.genres,
            parentId: parentId,
            includeItemTypes: types,
          );

      await genres();
      await genres(parentId: 'library');
      await genres(types: const ['Movie']);
      when(() => client.userId).thenReturn('them');
      await genres();
      when(() => client.baseUrl).thenReturn('http://other');
      await genres();
      expect(genreStarts.where((s) => s == 0), hasLength(5));

      final studios = await GenreListStore.fetch(client, GenreListKind.studios);
      expect(studios.single['Name'], 'A24');
    },
  );

  test('fresh reads always load', () async {
    register();
    await GenreListStore.fetch(client, GenreListKind.studios);
    await GenreListStore.fetch(client, GenreListKind.studios, fresh: true);

    verify(
      () => itemsApi.getStudios(
        parentId: any(named: 'parentId'),
        userId: any(named: 'userId'),
        sortBy: any(named: 'sortBy'),
        sortOrder: any(named: 'sortOrder'),
        startIndex: any(named: 'startIndex'),
        limit: any(named: 'limit'),
        recursive: any(named: 'recursive'),
        fields: any(named: 'fields'),
        includeItemTypes: any(named: 'includeItemTypes'),
      ),
    ).called(2);
  });

  test('a session change starts an empty store', () async {
    final before = register();
    await GenreListStore.fetch(client, GenreListKind.genres);

    resetUserScopedSingletons();

    expect(GetIt.instance<GenreListStore>(), isNot(same(before)));
    await GenreListStore.fetch(client, GenreListKind.genres);
    expect(genreStarts, hasLength(6));
  });
}
