import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/aggregated_item.dart';
import '../../util/platform_detection.dart';
import '../widgets/merged_copy_picker.dart';
import 'destinations.dart';

/// Item types the Play key starts from a card. The detail screen's auto play
/// picks what: resume, Next Up, first unwatched episode, or play in order.
const _playableTypes = <String>{
  'Movie',
  'Episode',
  'Video',
  'MusicVideo',
  'Trailer',
  'Series',
  'Season',
  'BoxSet',
  'Playlist',
  'MusicAlbum',
  'MusicArtist',
  'Audio',
  'AudioBook',
  'TvChannel',
  'LiveTvChannel',
};

bool canPlayFromCard(AggregatedItem item) =>
    PlatformDetection.isTV &&
    item.serverId != 'seerr' &&
    _playableTypes.contains(item.type) &&
    item.rawData['LocationType'] != 'Virtual';

/// Starts [item] as its detail screen's Play button would; false if it can't.
bool playFromCard(BuildContext context, AggregatedItem item) {
  if (!canPlayFromCard(item)) return false;
  openPickedCopy(
    context,
    item,
    (copy) => context.push(
      Destinations.isLiveTvChannelType(copy.type)
          ? Destinations.liveTvChannel(copy.id)
          : Destinations.item(copy.id, serverId: copy.serverId, autoPlay: true),
    ),
  );
  return true;
}
