import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../preference/preference_constants.dart';
import 'bottom_nav_controller.dart';
import 'bottom_nav_metrics.dart';
import 'bottom_nav_theme.dart';

/// Opens [builder] as a sheet shaped for the bar it came from: a card
/// floating above Dock and Split, a panel resting on Strip.
///
/// A modal route rather than an overlay inside the layout, so back, focus and
/// screen readers treat it like any other sheet. The sheet, its scrim and its
/// hit area stop at the top of the bar, which stays live; a tap on the bar
/// closes the sheet through [controller].
Future<void> showBottomNavSheet({
  required BuildContext context,
  required BottomNavController controller,
  required String itemId,
  required BottomNavTheme theme,
  required BottomNavbarStyle style,
  required double barHeight,
  required WidgetBuilder builder,
}) async {
  final navigator = Navigator.of(context);
  final localizations = MaterialLocalizations.of(context);
  final attached = style == BottomNavbarStyle.strip;
  final barArea =
      attached ? barHeight : barHeight + BottomNavMetrics.capsulePlayerGap;
  final route = _BottomNavSheetRoute(
    barArea: barArea,
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    barrierLabel: localizations.scrimLabel,
    barrierOnTapHint:
        localizations.scrimOnTapHint(localizations.bottomSheetLabel),
    backgroundColor: Colors.transparent,
    elevation: 0,
    isScrollControlled: true,
    modalBarrierColor: AppColorScheme.scrim.withValues(alpha: 0.5),
    builder: (sheetContext) {
      final media = MediaQuery.of(sheetContext);
      final side = attached
          ? 0.0
          : BottomNavMetrics.floatingInset + media.padding.left;
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
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: side),
        child: Center(heightFactor: 1, child: card),
      );
    },
  );
  controller.sheetOpened(itemId, route);
  try {
    await navigator.push(route);
  } finally {
    controller.sheetClosed(route);
  }
}

class _BottomNavSheetRoute extends ModalBottomSheetRoute<void> {
  final double barArea;

  _BottomNavSheetRoute({
    required this.barArea,
    required super.builder,
    required super.isScrollControlled,
    super.capturedThemes,
    super.barrierLabel,
    super.barrierOnTapHint,
    super.backgroundColor,
    super.elevation,
    super.modalBarrierColor,
  });

  // Clip at the bar's top edge so the sheet slides out from behind it.
  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) =>
      Padding(
        padding: EdgeInsets.only(bottom: barArea),
        child: ClipRect(
          child: super.buildPage(context, animation, secondaryAnimation),
        ),
      );

  @override
  Widget buildModalBarrier() => Padding(
        padding: EdgeInsets.only(bottom: barArea),
        child: super.buildModalBarrier(),
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
