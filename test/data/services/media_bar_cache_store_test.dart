import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/media_bar_slide_item.dart';
import 'package:moonfin/data/services/media_bar_cache_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.supportPath);

  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

const _slide = MediaBarSlideItem(
  itemId: 'movie',
  serverId: 'server',
  title: 'Film',
  overview: 'A film.',
  backdropUrl: 'http://host/Items/movie/Images/Backdrop?tag=b',
  bannerUrl: 'http://host/Moonfin/Tmdb/Thumb?tmdb=1&ApiKey=secret',
  logoUrl: 'http://host/Items/movie/Images/Logo?tag=l',
  posterUrl: 'http://host/Items/movie/Images/Primary?tag=p',
  officialRating: 'PG',
  year: 2024,
  genres: ['Drama'],
  runtime: Duration(minutes: 101),
  communityRating: 7.5,
  criticRating: 88,
  tmdbId: '1',
  imdbId: 'tt1',
  remoteTrailers: [
    {'Url': 'https://example.com/trailer', 'Name': 'Trailer'},
  ],
  newRelease: MediaBarNewReleaseInfo(kind: MediaBarNewRelease.newMovie),
  childCount: 3,
  isFavorite: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory support;
  late MediaBarCacheStore store;

  File cacheFile() => File('${support.path}/media_bar_cache.json');

  setUp(() {
    support = Directory.systemTemp.createTempSync('moonfin_media_bar');
    PathProviderPlatform.instance = _FakePathProvider(support.path);
    store = MediaBarCacheStore();
  });

  tearDown(() {
    if (support.existsSync()) support.deleteSync(recursive: true);
  });

  test('slides round trip without their new release banner', () async {
    await store.write('key', [_slide], token: 'secret');

    final items = await store.read('key', token: 'secret');

    expect(items, hasLength(1));
    final item = items!.single;
    expect(item.itemId, 'movie');
    expect(item.serverId, 'server');
    expect(item.title, 'Film');
    expect(item.overview, 'A film.');
    expect(item.backdropUrl, _slide.backdropUrl);
    expect(item.bannerUrl, _slide.bannerUrl);
    expect(item.logoUrl, _slide.logoUrl);
    expect(item.posterUrl, _slide.posterUrl);
    expect(item.officialRating, 'PG');
    expect(item.year, 2024);
    expect(item.genres, ['Drama']);
    expect(item.runtime, const Duration(minutes: 101));
    expect(item.communityRating, 7.5);
    expect(item.criticRating, 88);
    expect(item.tmdbId, '1');
    expect(item.imdbId, 'tt1');
    expect(item.itemType, 'Movie');
    expect(item.remoteTrailers, _slide.remoteTrailers);
    expect(item.childCount, 3);
    expect(item.isFavorite, isTrue);
    expect(item.newRelease, isNull);
  });

  test('keeps the access token off disk and uses the current one', () async {
    await store.write('key', [_slide], token: 'secret');

    expect(cacheFile().readAsStringSync(), isNot(contains('secret')));

    final items = await store.read('key', token: 'fresh');
    expect(
      items!.single.bannerUrl,
      'http://host/Moonfin/Tmdb/Thumb?tmdb=1&ApiKey=fresh',
    );
    expect(items.single.backdropUrl, _slide.backdropUrl);
  });

  test('drops a URL that needs a token when there is none', () async {
    await store.write('key', [_slide], token: 'secret');

    final items = await store.read('key');

    expect(items!.single.bannerUrl, isNull);
    expect(items.single.posterUrl, _slide.posterUrl);
  });

  test('misses on another key', () async {
    await store.write('key', [_slide]);

    expect(await store.read('other'), isNull);
  });

  test('misses once the slides are too old', () async {
    await store.write('key', [_slide]);
    final json = jsonDecode(cacheFile().readAsStringSync()) as Map;
    json['savedAt'] = DateTime.now()
        .subtract(const Duration(days: 4))
        .millisecondsSinceEpoch;
    cacheFile().writeAsStringSync(jsonEncode(json));

    expect(await store.read('key'), isNull);
  });

  test('misses on a corrupt file', () async {
    cacheFile().writeAsStringSync('{not json');

    expect(await store.read('key'), isNull);
  });

  test('saving no slides drops the ones saved for that key only', () async {
    await store.write('key', [_slide]);
    await store.write('other', const []);
    expect(await store.read('key'), isNotNull);

    await store.write('key', const []);
    expect(await store.read('key'), isNull);
  });
}
