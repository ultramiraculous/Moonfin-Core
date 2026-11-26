import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/services/seerr/seerr_download_progress.dart';
import '../../../l10n/app_localizations.dart';
import '../adaptive/adaptive_dialog.dart';
import '../overlay_sheet.dart';
import '../seerr_download_progress_bar.dart';

/// Lists each stuck download behind a Seerr download bar: which episodes it
/// holds, how it is stuck, the arr's reason and the release name.
Future<void> showSeerrStuckDownloadsDialog({
  required BuildContext context,
  required SeerrDownloadSummary summary,
}) async {
  if (summary.stuck.isEmpty) return;
  final l10n = AppLocalizations.of(context);
  await showFocusRestoringDialog(
    context: context,
    builder: (ctx) => AlertDialog.adaptive(
      backgroundColor: const Color(0xFF1A1A2E),
      title: Text(
        l10n.seerrStuckDownloadsTitle,
        style: const TextStyle(color: Colors.white),
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.6,
          maxWidth: 480,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, download) in summary.stuck.indexed) ...[
                if (i > 0) const Divider(color: Colors.white24, height: 24),
                _StuckDownloadTile(download: download),
              ],
            ],
          ),
        ),
      ),
      actions: [
        adaptiveDialogAction(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.close),
        ),
      ],
    ),
  );
}

class _StuckDownloadTile extends StatelessWidget {
  final SeerrStuckDownload download;

  const _StuckDownloadTile({required this.download});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;
    final stateColor = download.state == SeerrDownloadState.failed
        ? AppColorScheme.statusError
        : AppColorScheme.statusPending;
    final stateLabel = switch (download.state) {
      SeerrDownloadState.stalled => l10n.seerrDownloadStalled,
      SeerrDownloadState.failed => l10n.seerrDownloadFailed,
      _ => l10n.seerrImportBlocked,
    };
    final reason = download.reason;
    // Sonarr's import errors usually quote the download's folder, which is
    // the release name already.
    final release = switch (download.release) {
      final r? when reason == null || !reason.contains(r) => r,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            children: [
              if (download.episodes.isNotEmpty)
                TextSpan(
                  text: '${seerrEpisodeRuns(l10n, download.episodes)} · ',
                  style: const TextStyle(color: Colors.white),
                ),
              TextSpan(
                text: stateLabel,
                style: TextStyle(color: stateColor),
              ),
            ],
          ),
          style: theme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          textAlign: TextAlign.start,
        ),
        if (reason != null) ...[
          const SizedBox(height: 4),
          Text(
            reason,
            style: theme.bodySmall?.copyWith(color: Colors.white70),
            textAlign: TextAlign.start,
          ),
        ],
        if (release != null) ...[
          const SizedBox(height: 4),
          Text(
            release,
            style: theme.bodySmall?.copyWith(color: Colors.white54),
            textAlign: TextAlign.start,
          ),
        ],
      ],
    );
  }
}
