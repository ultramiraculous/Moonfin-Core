import 'package:collection/collection.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../cache/keyed_stream_cache.dart';

enum GenreListKind { genres, studios }

/// Identifies one user's genre or studio list, for one library or all of
/// them, limited to some item types or not.
class GenreListKey {
  GenreListKey({
    required this.serverId,
    required this.userId,
    required this.kind,
    this.parentId,
    List<String>? includeItemTypes,
  }) : includeItemTypes = includeItemTypes == null
           ? null
           : List.unmodifiable([...includeItemTypes]..sort());

  final String serverId;
  final String userId;
  final GenreListKind kind;
  final String? parentId;
  final List<String>? includeItemTypes;

  @override
  bool operator ==(Object other) =>
      other is GenreListKey &&
      other.serverId == serverId &&
      other.userId == userId &&
      other.kind == kind &&
      other.parentId == parentId &&
      const ListEquality<String>().equals(
        other.includeItemTypes,
        includeItemTypes,
      );

  @override
  int get hashCode => Object.hash(
    serverId,
    userId,
    kind,
    parentId,
    includeItemTypes == null ? null : Object.hashAll(includeItemTypes!),
  );
}

/// Whole genre and studio lists, sorted by name, with the fields every
/// screen that shows them asks for.
///
/// Served lists are shared, so callers must not change them.
class GenreListStore
    extends KeyedStreamCache<GenreListKey, List<Map<String, dynamic>>> {
  GenreListStore({
    super.minRefreshInterval = const Duration(minutes: 10),
    super.maxKeys = 24,
    super.clock,
  }) : super(equals: const DeepCollectionEquality().equals);

  static const fields =
      'ItemCounts,ChildCount,PrimaryImageTag,ImageTags,BackdropImageTags,'
      'PrimaryImageAspectRatio';

  static const pageSize = 250;

  /// The [kind] list [client]'s user sees, from the registered store when
  /// there is one, or straight from the server.
  static Future<List<Map<String, dynamic>>> fetch(
    MediaServerClient client,
    GenreListKind kind, {
    String? parentId,
    List<String>? includeItemTypes,
    bool fresh = false,
  }) {
    Future<List<Map<String, dynamic>>> load() => _loadAll(
      client,
      kind,
      parentId: parentId,
      includeItemTypes: includeItemTypes,
    );
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<GenreListStore>()) return load();
    final key = GenreListKey(
      serverId: client.baseUrl,
      userId: client.userId ?? '',
      kind: kind,
      parentId: parentId,
      includeItemTypes: includeItemTypes,
    );
    return getIt<GenreListStore>().get(key, load, fresh: fresh);
  }

  static Future<List<Map<String, dynamic>>> _loadAll(
    MediaServerClient client,
    GenreListKind kind, {
    String? parentId,
    List<String>? includeItemTypes,
  }) async {
    final all = <Map<String, dynamic>>[];
    var startIndex = 0;
    int? total;
    while (true) {
      final page = kind == GenreListKind.genres
          ? client.itemsApi.getGenres(
              parentId: parentId,
              userId: client.userId,
              sortBy: 'SortName',
              sortOrder: 'Ascending',
              recursive: true,
              startIndex: startIndex,
              limit: pageSize,
              fields: fields,
              includeItemTypes: includeItemTypes,
            )
          : client.itemsApi.getStudios(
              parentId: parentId,
              userId: client.userId,
              sortBy: 'SortName',
              sortOrder: 'Ascending',
              recursive: true,
              startIndex: startIndex,
              limit: pageSize,
              fields: fields,
              includeItemTypes: includeItemTypes,
            );
      final response = await page;
      total ??= (response['TotalRecordCount'] as num?)?.toInt();
      final items = (response['Items'] as List?) ?? const [];
      if (items.isEmpty) break;
      all.addAll(items.whereType<Map>().map((i) => i.cast<String, dynamic>()));
      startIndex += items.length;
      if (items.length < pageSize) break;
      if (total != null && startIndex >= total) break;
    }
    return List.unmodifiable(all);
  }
}
