import 'package:collection/collection.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../cache/keyed_stream_cache.dart';

/// Identifies one user's view of one item on one server, fetched with one
/// set of fields.
class ItemKey {
  const ItemKey({
    required this.serverId,
    required this.userId,
    required this.itemId,
    this.fields,
  });

  final String serverId;
  final String userId;
  final String itemId;

  /// The fields asked for, or null for the server's full item.
  final String? fields;

  @override
  bool operator ==(Object other) =>
      other is ItemKey &&
      other.serverId == serverId &&
      other.userId == userId &&
      other.itemId == itemId &&
      other.fields == fields;

  @override
  int get hashCode => Object.hash(serverId, userId, itemId, fields);
}

/// Items fetched by id, shared by the screens that read the same item within
/// a few seconds of each other.
///
/// Only for reading. Playing, resuming or changing an item fetches it fresh.
/// Served maps are shared, so callers must not change them.
class ItemStore extends KeyedStreamCache<ItemKey, Map<String, dynamic>> {
  ItemStore({
    super.minRefreshInterval = const Duration(seconds: 30),
    super.maxKeys = 64,
    super.clock,
  }) : super(equals: sameItem);

  /// Whether two fetches of an item match, user data included.
  static bool sameItem(Map<String, dynamic> a, Map<String, dynamic> b) =>
      identical(a, b) || const DeepCollectionEquality().equals(a, b);

  /// [itemId] as [client] sees it, from the registered store when there is
  /// one, or straight from the server.
  static Future<Map<String, dynamic>> fetch(
    MediaServerClient client,
    String itemId, {
    String? fields,
    bool fresh = false,
  }) {
    Future<Map<String, dynamic>> load() => fields == null
        ? client.itemsApi.getItem(itemId)
        : client.itemsApi.getItem(itemId, fields: fields);
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<ItemStore>()) return load();
    final key = ItemKey(
      serverId: client.baseUrl,
      userId: client.userId ?? '',
      itemId: itemId,
      fields: fields,
    );
    return getIt<ItemStore>().get(key, load, fresh: fresh);
  }
}
