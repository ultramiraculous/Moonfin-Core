import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../util/platform_detection.dart';
import '../models/media_bar_slide_item.dart';

/// Persists the media bar's slides to a single JSON file so a cold start can
/// paint them immediately, then refresh in the background.
///
/// Single-slot like the home row cache: only the last-written key is kept, so
/// a server, account or media bar settings change misses on the next read.
/// The access token is never written; image URLs carry a placeholder that
/// [read] swaps for the current token. All operations are best-effort and
/// never throw to the caller.
class MediaBarCacheStore {
  static const _fileName = 'media_bar_cache.json';

  static const _maxAge = Duration(days: 3);

  static const _tokenPlaceholder = '{moonfin-token}';

  Future<File> _file() async {
    final dir = PlatformDetection.isAppleTV
        ? await getApplicationCacheDirectory()
        : await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Returns the cached slides for [cacheKey], or null on any miss (no file,
  /// key mismatch, too old, corrupt, or empty).
  Future<List<MediaBarSlideItem>?> read(
    String cacheKey, {
    String? token,
  }) async {
    try {
      final file = await _file();
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['key'] != cacheKey) return null;
      final savedAt = decoded['savedAt'];
      if (savedAt is! int) return null;
      final age = DateTime.now().millisecondsSinceEpoch - savedAt;
      if (age < 0 || age > _maxAge.inMilliseconds) return null;
      final rawItems = decoded['items'];
      if (rawItems is! List) return null;
      final items = <MediaBarSlideItem>[];
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        final item = _itemFromJson(raw.cast<String, dynamic>(), token);
        if (item != null) items.add(item);
      }
      return items.isEmpty ? null : items;
    } catch (_) {
      return null;
    }
  }

  Future<void> _lastWrite = Future.value();

  /// Persists [items] under [cacheKey]. With none to save, the slides already
  /// saved for that key are dropped.
  Future<void> write(
    String cacheKey,
    List<MediaBarSlideItem> items, {
    String? token,
  }) {
    if (items.isEmpty) {
      return _lastWrite = _lastWrite.then((_) => _clear(cacheKey));
    }
    final envelope = {
      'key': cacheKey,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      'items': [for (final item in items) _itemToJson(item, token)],
    };
    return _lastWrite = _lastWrite.then((_) => _writeEnvelope(envelope));
  }

  Future<void> _clear(String cacheKey) async {
    try {
      final file = await _file();
      if (!file.existsSync()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map && decoded['key'] != cacheKey) return;
      await file.delete();
    } catch (_) {}
  }

  Future<void> _writeEnvelope(Map<String, Object> envelope) async {
    try {
      final payload = jsonEncode(envelope);
      final file = await _file();
      await file.writeAsString(payload, flush: true);
    } catch (_) {}
  }

  static String? _hideToken(String? url, String? token) {
    if (url == null || token == null || token.isEmpty) return url;
    return url
        .replaceAll(Uri.encodeQueryComponent(token), _tokenPlaceholder)
        .replaceAll(token, _tokenPlaceholder);
  }

  /// Null when the URL needs a token and there is none to put back.
  static String? _restoreToken(String? url, String? token) {
    if (url == null || !url.contains(_tokenPlaceholder)) return url;
    if (token == null || token.isEmpty) return null;
    return url.replaceAll(_tokenPlaceholder, Uri.encodeQueryComponent(token));
  }

  /// Leaves out the new release banner, which is only true for the days it
  /// describes and is fetched again with the fresh slides.
  Map<String, Object?> _itemToJson(MediaBarSlideItem item, String? token) => {
    'itemId': item.itemId,
    'serverId': item.serverId,
    'title': item.title,
    'overview': item.overview,
    'backdropUrl': _hideToken(item.backdropUrl, token),
    'bannerUrl': _hideToken(item.bannerUrl, token),
    'logoUrl': _hideToken(item.logoUrl, token),
    'posterUrl': _hideToken(item.posterUrl, token),
    'officialRating': item.officialRating,
    'year': item.year,
    'genres': item.genres,
    'runtimeMs': item.runtime?.inMilliseconds,
    'communityRating': item.communityRating,
    'criticRating': item.criticRating,
    'tmdbId': item.tmdbId,
    'imdbId': item.imdbId,
    'itemType': item.itemType,
    'remoteTrailers': item.remoteTrailers,
    'childCount': item.childCount,
    'isFavorite': item.isFavorite,
  };

  MediaBarSlideItem? _itemFromJson(Map<String, dynamic> json, String? token) {
    final itemId = json['itemId'];
    final serverId = json['serverId'];
    final title = json['title'];
    if (itemId is! String || serverId is! String || title is! String) {
      return null;
    }
    final runtimeMs = json['runtimeMs'];
    final genres = json['genres'];
    final trailers = json['remoteTrailers'];
    return MediaBarSlideItem(
      itemId: itemId,
      serverId: serverId,
      title: title,
      overview: json['overview'] as String?,
      backdropUrl: _restoreToken(json['backdropUrl'] as String?, token),
      bannerUrl: _restoreToken(json['bannerUrl'] as String?, token),
      logoUrl: _restoreToken(json['logoUrl'] as String?, token),
      posterUrl: _restoreToken(json['posterUrl'] as String?, token),
      officialRating: json['officialRating'] as String?,
      year: (json['year'] as num?)?.toInt(),
      genres: genres is List ? genres.whereType<String>().toList() : const [],
      runtime: runtimeMs is num
          ? Duration(milliseconds: runtimeMs.toInt())
          : null,
      communityRating: (json['communityRating'] as num?)?.toDouble(),
      criticRating: (json['criticRating'] as num?)?.toInt(),
      tmdbId: json['tmdbId'] as String?,
      imdbId: json['imdbId'] as String?,
      itemType: json['itemType'] as String? ?? 'Movie',
      remoteTrailers: trailers is List
          ? [
              for (final t in trailers)
                if (t is Map) t.cast<String, dynamic>(),
            ]
          : const [],
      childCount: (json['childCount'] as num?)?.toInt(),
      isFavorite: json['isFavorite'] == true,
    );
  }
}
