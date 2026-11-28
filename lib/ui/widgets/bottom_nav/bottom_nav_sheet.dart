import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../preference/preference_constants.dart';
import 'bottom_nav_metrics.dart';
import 'bottom_nav_theme.dart';

/// Called with the id of the bar item that opened a sheet and where a tap
/// landed on the bar, after the sheet has started closing.
typedef BottomNavSheetBarTap = void Function(String itemId, Offset position);

/// Opens [builder] as a sheet shaped for the bar it came from: a card
/// floating above Dock and Split, a panel resting on Strip.
///
/// A modal route rather than an overlay inside the layout, so back, focus and
/// screen readers treat it like any other sheet. The bar sits under the scrim
/// and the sheet keeps clear of it; a tap there closes the sheet and is handed
/// to [onBarTap].
Future<void> showBottomNavSheet({
  required BuildContext context,
  required BottomNavTheme theme,
  required BottomNavbarStyle style,
  required double barHeight,
  required WidgetBuilder builder,
  ValueChanged<Offset>? onBarTap,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    isScrollControlled: true,
    barrierColor: AppColorScheme.scrim.withValues(alpha: 0.5),
    builder: (sheetContext) {
      final media = MediaQuery.of(sheetContext);
      final attached = style == BottomNavbarStyle.strip;
      final side = attached
          ? 0.0
          : BottomNavMetrics.floatingInset + media.padding.left;
      final barArea = attached
          ? barHeight
          : barHeight + BottomNavMetrics.capsulePlayerGap;
      final card = ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: BottomNavMetrics.dockMaxWidth,
          maxHeight: media.size.height - media.padding.top - 24 - barArea,
        ),
        child: BottomNavSurface(
          theme: theme,
          radius: BottomNavMetrics.hubRadius,
          topOnly: attached,
          child: builder(sheetContext),
        ),
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: side),
            child: Center(heightFactor: 1, child: card),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTapUp: (details) {
              Navigator.of(sheetContext).pop();
              onBarTap?.call(details.globalPosition);
            },
            child: SizedBox(height: barArea),
          ),
        ],
      );
    },
  );
}

class BottomNavSheetGrabber extends StatelessWidget {
  final Color color;

  const BottomNavSheetGrabber({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 8),
        width: 36,
        height: 5,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.24),
          borderRadius: AppRadius.circular(3),
        ),
      ),
    );
  }
}
