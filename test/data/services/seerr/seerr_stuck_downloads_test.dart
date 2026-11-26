import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/seerr/arr_queue.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';
import 'package:moonfin/data/services/seerr/seerr_download_progress.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/widgets/seerr/seerr_stuck_downloads_dialog.dart';
import 'package:moonfin/ui/widgets/seerr_download_progress_bar.dart';

const _noFiles = 'No files found are eligible for import in /downloads/x';

ArrQueueItem _blocked(int id, int season, int episode, {String? download}) =>
    ArrQueueItem(
      id: id,
      status: 'completed',
      trackedDownloadState: 'importBlocked',
      trackedDownloadStatus: 'warning',
      size: 100,
      sizeLeft: 0,
      downloadId: download ?? 'D$id',
      seasonNumber: season,
      episodeNumber: episode,
      title: 'The.Simpsons.S${season}E$episode.1080p',
      errorMessage: _noFiles,
    );

const _stalled = ArrQueueItem(
  id: 90,
  status: 'warning',
  size: 100,
  sizeLeft: 50,
  downloadId: 'T90',
  seasonNumber: 32,
  episodeNumber: 20,
  title: 'The.Simpsons.S32E20.1080p',
);

Widget _host(SeerrDownloadSummary summary, {VoidCallback? onTap}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: SeerrDownloadProgressBar(summary: summary, onTap: onTap),
          ),
        ),
      ),
    );

void main() {
  group('stuck downloads in the summary', () {
    test('a season pack is one stuck download holding every episode', () {
      final summary = SeerrDownloadSummary.fromArrItems([
        for (var e = 12; e >= 1; e--) _blocked(e, 32, e, download: 'PACK'),
      ])!;
      expect(summary.stuck, hasLength(1));
      expect(summary.stuck.single.state, SeerrDownloadState.importBlocked);
      expect(summary.stuck.single.reason, _noFiles);
      expect(
        summary.stuck.single.episodes.first,
        const SeerrEpisodeNumber(32, 1),
      );
      expect(summary.stuckEpisodes, hasLength(12));
    });

    test('separate downloads are listed in episode order', () {
      final summary = SeerrDownloadSummary.fromArrItems([
        _blocked(2, 33, 1),
        _stalled,
        _blocked(1, 32, 13),
      ])!;
      expect(
        [for (final d in summary.stuck) d.episodes.single],
        const [
          SeerrEpisodeNumber(32, 13),
          SeerrEpisodeNumber(32, 20),
          SeerrEpisodeNumber(33, 1),
        ],
      );
      expect(summary.stuck[1].state, SeerrDownloadState.stalled);
    });

    test('a download that is moving along is not stuck', () {
      final summary = SeerrDownloadSummary.fromArrItems(const [
        ArrQueueItem(
          id: 1,
          status: 'downloading',
          size: 100,
          sizeLeft: 40,
          downloadId: 'A',
          seasonNumber: 1,
          episodeNumber: 1,
        ),
      ])!;
      expect(summary.stuck, isEmpty);
    });

    test("Seerr's own failed items carry their episode", () {
      final summary = SeerrDownloadSummary.fromItems(const [
        SeerrDownloadingItem(
          downloadId: 'A',
          status: 'failed',
          size: 100,
          sizeLeft: 100,
          seasonNumber: 4,
          episodeNumber: 2,
        ),
      ])!;
      expect(summary.stuckEpisodes, const [SeerrEpisodeNumber(4, 2)]);
    });
  });

  group('the bar names what is stuck', () {
    testWidgets('one episode by its code', (tester) async {
      await tester.pumpWidget(
        _host(SeerrDownloadSummary.fromArrItems([_blocked(1, 32, 13)])!),
      );
      expect(find.text('Import blocked · S32E13'), findsOneWidget);
    });

    testWidgets('several in one season by count', (tester) async {
      await tester.pumpWidget(
        _host(
          SeerrDownloadSummary.fromArrItems([
            for (var e = 1; e <= 12; e++) _blocked(e, 32, e),
          ])!,
        ),
      );
      expect(
        find.text('Import blocked · 12 episodes in season 32'),
        findsOneWidget,
      );
    });

    testWidgets('different ways of being stuck read as stuck', (tester) async {
      await tester.pumpWidget(
        _host(
          SeerrDownloadSummary.fromArrItems([
            _blocked(1, 32, 13),
            _stalled,
            _blocked(2, 33, 1),
          ])!,
        ),
      );
      expect(find.text('Stuck · 3 episodes'), findsOneWidget);
    });

    testWidgets('a movie keeps the plain label', (tester) async {
      await tester.pumpWidget(
        _host(
          SeerrDownloadSummary.fromArrItems(const [
            ArrQueueItem(
              id: 7,
              status: 'completed',
              trackedDownloadState: 'importBlocked',
              size: 100,
              sizeLeft: 0,
              downloadId: 'X',
            ),
          ])!,
        ),
      );
      expect(find.text('Import blocked'), findsOneWidget);
    });

    testWidgets('tapping it calls back, and it shows a chevron', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          SeerrDownloadSummary.fromArrItems([_blocked(1, 32, 13)])!,
          onTap: () => taps++,
        ),
      );
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      await tester.tap(find.byType(SeerrDownloadProgressBar));
      expect(taps, 1);
    });
  });

  testWidgets('the dialog lists each download with its episodes', (
    tester,
  ) async {
    final summary = SeerrDownloadSummary.fromArrItems([
      for (var e = 1; e <= 3; e++) _blocked(e, 32, e, download: 'PACK'),
      _blocked(9, 32, 7),
      _stalled,
    ])!;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSeerrStuckDownloadsDialog(
              context: context,
              summary: summary,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Stuck downloads'), findsOneWidget);
    expect(find.text('S32E01–E03 · Import blocked'), findsOneWidget);
    expect(find.text('S32E07 · Import blocked'), findsOneWidget);
    expect(find.text('S32E20 · Stalled'), findsOneWidget);
    expect(find.text(_noFiles), findsNWidgets(2));
    expect(find.text('The.Simpsons.S32E20.1080p'), findsOneWidget);
    expect(find.text('The.Simpsons.S32E7.1080p'), findsOneWidget);
  });

  test('episode runs compact consecutive episodes', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(
      seerrEpisodeRuns(l10n, const [
        SeerrEpisodeNumber(1, 1),
        SeerrEpisodeNumber(1, 2),
        SeerrEpisodeNumber(1, 3),
        SeerrEpisodeNumber(1, 5),
        SeerrEpisodeNumber(2, 1),
      ]),
      'S01E01–E03, S01E05, S02E01',
    );
  });
}
