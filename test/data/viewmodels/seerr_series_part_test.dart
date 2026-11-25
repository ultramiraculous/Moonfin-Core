import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/seerr/arr_queue.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';
import 'package:moonfin/data/services/seerr/seerr_download_progress.dart';
import 'package:moonfin/data/viewmodels/seerr_media_detail_view_model.dart';
import 'package:moonfin/ui/widgets/seerr/seerr_item_status.dart';
import 'package:moonfin/ui/widgets/seerr/seerr_status_pill.dart';

const _gb = 1000 * 1000 * 1000;

Map<String, dynamic> _arrItem({
  required int id,
  required int season,
  required int episode,
  required String downloadId,
  String trackedDownloadState = 'downloading',
  String status = 'downloading',
  int sizeLeft = _gb,
}) => {
  'id': id,
  'title': 'Show.S${season}E$episode',
  'status': status,
  'trackedDownloadState': trackedDownloadState,
  'trackedDownloadStatus': 'ok',
  'size': 2 * _gb,
  'sizeleft': sizeLeft,
  'downloadId': downloadId,
  'seasonNumber': season,
  'episodeNumber': episode,
  'statusMessages': <Object>[],
};

SeerrRequest _approved(List<int> seasons) => SeerrRequest(
  id: seasons.first,
  status: SeerrRequest.statusApproved,
  type: 'tv',
  is4k: false,
  seasons: [
    for (final n in seasons)
      SeerrSeasonRequest(id: n, seasonNumber: n, status: 2),
  ],
);

SeerrMediaDetailState _series({
  List<Map<String, dynamic>> arrItems = const [],
  List<SeerrDownloadingItem>? downloadStatus,
  List<SeerrRequest> requests = const [],
  List<Map<String, dynamic>> arrSeasons = const [],
  bool withQueue = true,
}) => SeerrMediaDetailState(
  tv: SeerrTvDetails(
    id: 456,
    name: 'Show',
    mediaInfo: SeerrMediaInfo(
      status: 4,
      downloadStatus: downloadStatus,
      requests: requests,
    ),
  ),
  arrQueue: withQueue
      ? ArrQueue.fromJson({
          'service': 'sonarr',
          'inArr': true,
          'monitored': true,
          'seasons': arrSeasons,
          'items': arrItems,
        })
      : null,
);

AggregatedItem _libraryItem(String type, {int? season, int? index}) =>
    AggregatedItem(
      id: 'x',
      serverId: 's',
      rawData: {
        'Type': type,
        'Name': 'x',
        'IndexNumber': ?index,
        'ParentIndexNumber': ?season,
      },
    );

void main() {
  group('an import blocked on one episode', () {
    final state = _series(
      arrItems: [
        _arrItem(
          id: 1,
          season: 32,
          episode: 13,
          downloadId: 'A',
          status: 'completed',
          trackedDownloadState: 'importBlocked',
          sizeLeft: 0,
        ),
      ],
    );

    test('shows on the series', () {
      expect(state.hdDownload?.state, SeerrDownloadState.importBlocked);
    });

    test('shows on its own season and episode', () {
      expect(
        state.forPart(const SeerrSeriesPart(32)).hdDownload?.state,
        SeerrDownloadState.importBlocked,
      );
      expect(
        state.forPart(const SeerrSeriesPart(32, episode: 13)).hdDownload?.state,
        SeerrDownloadState.importBlocked,
      );
    });

    test('stays off another season and another episode', () {
      expect(state.forPart(const SeerrSeriesPart(38)).hdDownload, isNull);
      expect(
        state.forPart(const SeerrSeriesPart(38, episode: 1)).hdDownload,
        isNull,
      );
      expect(
        state.forPart(const SeerrSeriesPart(32, episode: 12)).hdDownload,
        isNull,
      );
    });
  });

  test('a season counts only its own downloads toward the bar', () {
    final state = _series(
      arrItems: [
        _arrItem(id: 1, season: 1, episode: 1, downloadId: 'A', sizeLeft: 0),
        _arrItem(id: 2, season: 2, episode: 1, downloadId: 'B'),
      ],
    );
    final season2 = state.forPart(const SeerrSeriesPart(2)).hdDownload!;
    expect(season2.totalBytes, 2 * _gb);
    expect(season2.percent, 50);
  });

  test('a season pack still counts once on a season page', () {
    final state = _series(
      arrItems: [
        for (var e = 1; e <= 3; e++)
          _arrItem(id: e, season: 3, episode: e, downloadId: 'PACK'),
      ],
    );
    final season = state.forPart(const SeerrSeriesPart(3)).hdDownload!;
    expect(season.totalBytes, 2 * _gb);
    final episode = state
        .forPart(const SeerrSeriesPart(3, episode: 2))
        .hdDownload!;
    expect(episode.totalBytes, 2 * _gb);
  });

  test("Seerr's own download status is narrowed by its episode", () {
    final items = [
      SeerrDownloadingItem.fromJson({
        'size': 2 * _gb,
        'sizeLeft': _gb,
        'downloadId': 'A',
        'status': 'downloading',
        'episode': {'seasonNumber': 5, 'episodeNumber': 2},
      }),
    ];
    expect(items.single.seasonNumber, 5);
    expect(items.single.episodeNumber, 2);
    final state = _series(downloadStatus: items, withQueue: false);
    expect(state.forPart(const SeerrSeriesPart(5)).hdDownload, isNotNull);
    expect(
      state.forPart(const SeerrSeriesPart(5, episode: 2)).hdDownload,
      isNotNull,
    );
    expect(state.forPart(const SeerrSeriesPart(6)).hdDownload, isNull);
  });

  test("a request card counts only its own seasons from Seerr's status", () {
    SeerrDownloadingItem item(int season, String id) =>
        SeerrDownloadingItem.fromJson({
          'size': 2 * _gb,
          'sizeLeft': _gb,
          'downloadId': id,
          'status': 'downloading',
          'episode': {'seasonNumber': season, 'episodeNumber': 1},
        });
    final media = SeerrMedia(
      id: 1,
      status: 3,
      downloadStatus: [item(1, 'A'), item(2, 'B')],
    );
    SeerrRequest request(int season) => SeerrRequest(
      id: season,
      status: SeerrRequest.statusApproved,
      type: 'tv',
      is4k: false,
      media: media,
      seasons: [
        SeerrSeasonRequest(id: season, seasonNumber: season, status: 2),
      ],
    );
    expect(SeerrDownloadSummary.forRequest(request(2))!.totalBytes, 2 * _gb);
    expect(SeerrDownloadSummary.forRequest(request(3)), isNull);
  });

  group('what the arr is waiting on', () {
    final state = _series(
      requests: [
        _approved([4]),
      ],
      arrSeasons: [
        {
          'seasonNumber': 4,
          'monitored': true,
          'episodeCount': 10,
          'episodeFileCount': 6,
        },
      ],
    );

    test('shows on the requested season', () {
      expect(state.hd.arrWait, isA<ArrNotFoundYet>());
      expect(
        state.forPart(const SeerrSeriesPart(4)).hd.arrWait,
        isA<ArrNotFoundYet>(),
      );
    });

    test('stays off other seasons and every episode', () {
      expect(state.forPart(const SeerrSeriesPart(3)).hd.arrWait, isNull);
      expect(
        state.forPart(const SeerrSeriesPart(4, episode: 1)).hd.arrWait,
        isNull,
      );
    });
  });

  group('the status pill', () {
    // Season 1 is in the library, 2 is partly there and also on its way in
    // 4K, and 3 was requested and has no entry from Seerr yet.
    final state = SeerrMediaDetailState(
      tv: SeerrTvDetails(
        id: 456,
        name: 'Show',
        mediaInfo: SeerrMediaInfo(
          status: 4,
          status4k: 3,
          seasons: const [
            SeerrSeasonAvailability(seasonNumber: 1, status: 5, status4k: 1),
            SeerrSeasonAvailability(seasonNumber: 2, status: 4, status4k: 3),
          ],
          requests: [_approved([3])],
          downloadStatus: const [
            SeerrDownloadingItem(
              downloadId: 'upgrade',
              size: 100,
              sizeLeft: 50,
              seasonNumber: 1,
              episodeNumber: 2,
            ),
          ],
        ),
      ),
    );

    test('is unchanged on the series', () {
      expect(state.hd.status, 4);
      expect(state.hd.requests, hasLength(1));
      expect(seerrStatusIsNoteworthy(state.hd), isTrue);
    });

    test("shows a season's own status", () {
      final season2 = state.forPart(const SeerrSeriesPart(2));
      expect(season2.hd.status, 4);
      expect(seerrStatusIsNoteworthy(season2.hd), isTrue);
      expect(season2.uhd.status, 3);
      expect(seerrStatusIsNoteworthy(season2.uhd), isTrue);

      final season3 = state.forPart(const SeerrSeriesPart(3));
      expect(season3.hd.status, 3);
      expect(season3.hd.hasExistingRequest, isTrue);
    });

    test('stays off a season that is in the library', () {
      final season1 = state.forPart(const SeerrSeriesPart(1));
      expect(seerrStatusIsNoteworthy(season1.hd), isFalse);
      expect(seerrStatusIsNoteworthy(season1.uhd), isFalse);
    });

    test("another season's request doesn't count", () {
      final season4 = state.forPart(const SeerrSeriesPart(4));
      expect(season4.hd.status, 0);
      expect(season4.hd.requests, isEmpty);
      expect(seerrStatusIsNoteworthy(season4.hd), isFalse);
    });

    test("an episode shows its season's status", () {
      expect(
        seerrStatusIsNoteworthy(
          state.forPart(const SeerrSeriesPart(1, episode: 2)).hd,
        ),
        isFalse,
      );
      expect(state.forPart(const SeerrSeriesPart(3, episode: 1)).hd.status, 3);
    });

    test('a season in the library still shows its download', () {
      expect(state.forPart(const SeerrSeriesPart(1)).hdDownload, isNotNull);
    });
  });

  test('a movie has no parts', () {
    const movie = SeerrMediaDetailState(
      movie: SeerrMovieDetails(id: 1, title: 'Movie'),
    );
    expect(movie.forPart(const SeerrSeriesPart(1)).part, isNull);
  });

  group('seerrSeriesPartOf', () {
    test('a season is its index number', () {
      expect(
        seerrSeriesPartOf(_libraryItem('Season', index: 2)),
        const SeerrSeriesPart(2),
      );
    });

    test('an episode is its season and index number', () {
      expect(
        seerrSeriesPartOf(_libraryItem('Episode', season: 38, index: 1)),
        const SeerrSeriesPart(38, episode: 1),
      );
    });

    test('nothing for an unnumbered part or any other item', () {
      expect(seerrSeriesPartOf(_libraryItem('Episode', index: 1)), isNull);
      expect(seerrSeriesPartOf(_libraryItem('Season')), isNull);
      expect(seerrSeriesPartOf(_libraryItem('Series', index: 1)), isNull);
    });
  });
}
