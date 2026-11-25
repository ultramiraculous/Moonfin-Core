import 'package:collection/collection.dart';

import '../cache/keyed_stream_cache.dart';
import '../models/aggregated_item.dart';

/// Identifies one user's view of one series on one server.
class SeriesEpisodesKey {
  const SeriesEpisodesKey({
    required this.serverId,
    required this.userId,
    required this.seriesId,
  });

  final String serverId;
  final String userId;
  final String seriesId;

  @override
  bool operator ==(Object other) =>
      other is SeriesEpisodesKey &&
      other.serverId == serverId &&
      other.userId == userId &&
      other.seriesId == seriesId;

  @override
  int get hashCode => Object.hash(serverId, userId, seriesId);
}

/// The episode lists of the last few series a user opened, so each page of a
/// series can draw its episodes at once and refresh them behind.
class SeriesEpisodesStore
    extends KeyedStreamCache<SeriesEpisodesKey, List<AggregatedItem>> {
  SeriesEpisodesStore({
    super.minRefreshInterval = const Duration(seconds: 30),
    super.maxKeys = 8,
    super.clock,
  }) : super(equals: sameEpisodes);

  /// Whether two lists hold the same episodes with the same user data.
  static bool sameEpisodes(List<AggregatedItem> a, List<AggregatedItem> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    const deep = DeepCollectionEquality();
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
      if (!deep.equals(a[i].rawData['UserData'], b[i].rawData['UserData'])) {
        return false;
      }
    }
    return true;
  }
}
