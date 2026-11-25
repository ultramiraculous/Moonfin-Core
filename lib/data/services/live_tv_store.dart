import 'dart:async';

import 'package:collection/collection.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../cache/keyed_stream_cache.dart';
import '../models/live_tv_recording_state.dart';
import 'user_data_sync.dart';

/// Identifies one user's channel lineup on one server.
class LiveTvChannelsKey {
  const LiveTvChannelsKey({required this.serverId, required this.userId});

  final String serverId;
  final String userId;

  @override
  bool operator ==(Object other) =>
      other is LiveTvChannelsKey &&
      other.serverId == serverId &&
      other.userId == userId;

  @override
  int get hashCode => Object.hash(serverId, userId);
}

/// A channel lineup and the [UserDataSync.revision] from before it was asked
/// for, so local user data changes made since can win over it.
class LiveTvChannelList {
  const LiveTvChannelList({required this.items, required this.revision});

  final List<Map<String, dynamic>> items;
  final int revision;
}

/// The channel lineup with images and user data, shared by the guide, the
/// player's channel list, search and Home.
///
/// Served lists are shared, so callers must not change them.
class LiveTvChannelStore
    extends KeyedStreamCache<LiveTvChannelsKey, LiveTvChannelList> {
  LiveTvChannelStore({
    super.minRefreshInterval = const Duration(minutes: 5),
    super.maxKeys = 4,
    super.clock,
  }) : super(equals: _sameList);

  static bool _sameList(LiveTvChannelList a, LiveTvChannelList b) =>
      identical(a, b) ||
      const DeepCollectionEquality().equals(a.items, b.items);

  static const fields = 'ImageTags,UserData';

  /// [client]'s lineup, from the registered store when there is one, or
  /// straight from the server.
  static Future<LiveTvChannelList> fetch(
    MediaServerClient client, {
    bool fresh = false,
  }) {
    Future<LiveTvChannelList> load() async {
      final revision = userDataSync.revision;
      final response = await client.liveTvApi.getChannels(
        sortBy: 'SortName',
        sortOrder: 'Ascending',
        fields: fields,
        enableTotalRecordCount: false,
        userId: client.userId,
      );
      final items = ((response['Items'] as List?) ?? const [])
          .whereType<Map>()
          .map((i) => i.cast<String, dynamic>())
          .toList(growable: false);
      return LiveTvChannelList(items: items, revision: revision);
    }

    final getIt = GetIt.instance;
    if (!getIt.isRegistered<LiveTvChannelStore>()) return load();
    final key = LiveTvChannelsKey(
      serverId: client.baseUrl,
      userId: client.userId ?? '',
    );
    return getIt<LiveTvChannelStore>().get(key, load, fresh: fresh);
  }
}

/// Identifies one channel's programs over one guide window, all of them or
/// one category's.
class LiveTvProgramsKey {
  const LiveTvProgramsKey({
    required this.serverId,
    required this.userId,
    required this.channelId,
    required this.from,
    required this.to,
    this.category,
  });

  final String serverId;
  final String userId;
  final String channelId;
  final DateTime from;
  final DateTime to;
  final String? category;

  @override
  bool operator ==(Object other) =>
      other is LiveTvProgramsKey &&
      other.serverId == serverId &&
      other.userId == userId &&
      other.channelId == channelId &&
      other.from == from &&
      other.to == to &&
      other.category == category;

  @override
  int get hashCode =>
      Object.hash(serverId, userId, channelId, from, to, category);
}

/// One channel's guide items and the moment they stop describing what's on.
class LiveTvProgramSlot {
  const LiveTvProgramSlot({required this.items, required this.validUntil});

  final List<Map<String, dynamic>> items;
  final DateTime validUntil;
}

/// Guide programs per channel and window, so the guide and the player's
/// channel carousel share one fetch.
///
/// A channel's programs are served until the half hour after they were
/// fetched, or until the first of them that was airing then ends, whichever
/// comes first. Any recording change drops them all, since they carry each
/// showing's recording state.
class LiveTvProgramStore
    extends KeyedStreamCache<LiveTvProgramsKey, LiveTvProgramSlot> {
  LiveTvProgramStore({super.maxKeys = 1000, super.clock})
    : _clock = clock ?? DateTime.now,
      super(minRefreshInterval: const Duration(minutes: 30)) {
    liveTvRecordingRevision.addListener(clear);
  }

  final DateTime Function() _clock;

  @override
  void dispose() {
    liveTvRecordingRevision.removeListener(clear);
    super.dispose();
  }

  /// The end of the half hour [t] falls in.
  static DateTime nextHalfHour(DateTime t) {
    final start = DateTime(
      t.year,
      t.month,
      t.day,
      t.hour,
      t.minute < 30 ? 0 : 30,
    );
    return start.add(const Duration(minutes: 30));
  }

  /// The guide items for [channelIds] over [from]–[to], as one response.
  ///
  /// Channels held and still valid come from the store; the rest are asked
  /// for in one call to [fetch]. With [fresh], every channel is fetched. With
  /// no registered store, [fetch] gets them all.
  static Future<Map<String, dynamic>> guide(
    MediaServerClient client, {
    required List<String> channelIds,
    required DateTime from,
    required DateTime to,
    String? category,
    bool fresh = false,
    required Future<Map<String, dynamic>> Function(List<String> channelIds)
    fetch,
  }) async {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<LiveTvProgramStore>()) return fetch(channelIds);
    final store = getIt<LiveTvProgramStore>();
    LiveTvProgramsKey keyFor(String channelId) => LiveTvProgramsKey(
      serverId: client.baseUrl,
      userId: client.userId ?? '',
      channelId: channelId,
      from: from,
      to: to,
      category: category,
    );

    final now = store._clock();
    final items = <Map<String, dynamic>>[];
    final missing = <String>[];
    for (final id in channelIds) {
      final slot = fresh ? null : store.peek(keyFor(id));
      if (slot != null && now.isBefore(slot.validUntil)) {
        items.addAll(slot.items);
      } else {
        missing.add(id);
      }
    }
    if (missing.isEmpty) return {'Items': items};

    final response = await fetch(missing);
    final fetchedAt = store._clock();
    final byChannel = <String, List<Map<String, dynamic>>>{
      for (final id in missing) id: [],
    };
    for (final raw in (response['Items'] as List?) ?? const []) {
      if (raw is! Map) continue;
      final item = raw.cast<String, dynamic>();
      byChannel[item['ChannelId']?.toString()]?.add(item);
      items.add(item);
    }
    await Future.wait([
      for (final entry in byChannel.entries)
        store.get(
          keyFor(entry.key),
          () async => LiveTvProgramSlot(
            items: List.unmodifiable(entry.value),
            validUntil: _validUntil(entry.value, fetchedAt),
          ),
          fresh: true,
        ),
    ]);
    return {...response, 'Items': items};
  }

  static DateTime _validUntil(
    List<Map<String, dynamic>> items,
    DateTime fetchedAt,
  ) {
    var until = nextHalfHour(fetchedAt);
    for (final item in items) {
      final end = DateTime.tryParse(item['EndDate']?.toString() ?? '');
      if (end == null) continue;
      final local = end.toLocal();
      if (local.isAfter(fetchedAt) && local.isBefore(until)) until = local;
    }
    return until;
  }
}
