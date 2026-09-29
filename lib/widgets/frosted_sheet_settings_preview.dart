import 'package:flutter/material.dart';
import 'package:university_timetable/l10n/app_localizations.dart';

import '../models/timetable_settings.dart';
import '../providers/timetable_provider.dart';
import '../ui/hyperos/hyperos.dart';
import 'timetable_week_preview.dart';

/// Live + interactive frosted sheet preview for appearance settings.
class FrostedSheetSettingsPreview extends StatelessWidget {
  const FrostedSheetSettingsPreview({
    required this.provider,
    required this.settings,
    required this.week,
    required this.blurSigma,
    required this.tintAlpha,
    required this.barrierAlpha,
    required this.blurEnabled,
    required this.onOpenDemoSheet,
    super.key,
  });

  final TimetableProvider provider;
  final TimetableSettings settings;
  final int week;
  final double blurSigma;
  final double tintAlpha;
  final double barrierAlpha;
  final bool blurEnabled;
  final VoidCallback onOpenDemoSheet;

  static const _previewHeight = 280.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appearance = FrostedAppearance(
      sheetBlurSigma: blurSigma,
      sheetTintAlpha: tintAlpha,
      sheetBarrierAlpha: barrierAlpha,
      blurEnabled: blurEnabled,
    );

    return FrostedAppearanceScope(
      appearance: appearance,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipPath.shape(
            shape: HyperosTheme.cardShape(),
            child: SizedBox(
              height: _previewHeight,
              // The live menu is not rendered inline here. A grouped backdrop
              // inside the scrollable settings ListView captures the whole
              // scrolling viewport (BackdropFilter.grouped's capture is the cull
              // rect — the viewport — and cannot be narrowed by widget-level
              // RepaintBoundary/ClipRect), so it flickers and misaligns on scroll.
              // The home top menu avoids this by being a modal over a static page.
              // So this box previews only the timetable backdrop; the live menu
              // is previewed by the "open demo" button below — a modal that uses
              // the same code path as the home top menu.
              child: TimetableWeekPreview(
                provider: provider,
                settings: settings,
                week: week,
                maxVisibleSections: 2,
                includeAppHeader: true,
                heightBudget: _previewHeight,
              ),
            ),
          ),
          const SizedBox(height: 10),
          HyperosButton(
            label: l10n.frostedSheetPreviewOpenAction,
            variant: HyperosButtonVariant.secondary,
            expand: true,
            onPressed: onOpenDemoSheet,
          ),
        ],
      ),
    );
  }
}

/// Full-size demo sheet opened from the appearance settings preview button.
class FrostedSheetSettingsDemoSheet extends StatelessWidget {
  const FrostedSheetSettingsDemoSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return _buildSheet(context);
  }

  Widget _buildSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final colors = context.theme.colors;
    final typo = context.theme.typography;
    const tileSpacing = 10.0;

    Widget tile(IconData icon, String title) {
      return Expanded(
        child: _DemoMenuTile(
          icon: icon,
          title: title,
          titleStyle: typo.body.xs2.copyWith(
            fontWeight: FontWeight.w400,
            height: 1.15,
            color: colors.foreground,
          ),
          accentColor: colorScheme.primary,
        ),
      );
    }

    return HyperosSheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.frostedSheetPreviewDemoTitle,
            style: HyperosTypography.sheetTitle(context),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.frostedSheetPreviewDemoSubtitle,
            style: HyperosTypography.sectionDescription(context),
          ),
          const SizedBox(height: 14),
          Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  tile(Icons.bar_chart_rounded, l10n.homeMenuStatisticsTitle),
                  const SizedBox(width: tileSpacing),
                  tile(Icons.tune_rounded, l10n.homeMenuSettingsTitle),
                  const SizedBox(width: tileSpacing),
                  tile(Icons.file_upload_outlined, l10n.homeMenuImportTitle),
                  const SizedBox(width: tileSpacing),
                  tile(
                    Icons.add_circle_outline_rounded,
                    l10n.homeMenuAddCourseTitle,
                  ),
                ],
          ),
          const SizedBox(height: 12),
          HyperosButton(
            label: l10n.closeAction,
            variant: HyperosButtonVariant.secondary,
            expand: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

Future<void> showFrostedSheetSettingsDemo(BuildContext context) {
  return showHomeHyperosSheet<void>(
    context: context,
    builder: (_) => const FrostedSheetSettingsDemoSheet(),
  );
}

class _DemoMenuTile extends StatelessWidget {
  const _DemoMenuTile({
    required this.icon,
    required this.title,
    required this.titleStyle,
    required this.accentColor,
  });

  final IconData icon;
  final String title;
  final TextStyle titleStyle;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    const iconWellRadius = BorderRadius.all(Radius.circular(10));
    const iconSize = 24.0;
    const wellSize = 46.0;
    const verticalPadding = 13.0;
    const horizontalPadding = 7.0;

    final content = Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HyperosFrostedSurface(
              borderRadius: iconWellRadius,
              blurEnabled: false,
              tint: HyperosBlurredHeader.accentSurfaceTintColor(accentColor),
              child: SizedBox(
                width: wellSize,
                height: wellSize,
                child: Center(
                  child: Icon(icon, color: accentColor, size: iconSize),
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              title,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: titleStyle,
            ),
          ],
        ),
      ),
    );

    // Nested cards stay a translucent tint over the already-frosted modal.
    return HyperosFrostedSurface(
      borderRadius: HyperosTheme.cardBorderRadius,
      blurEnabled: false,
      tint: HyperosBlurredHeader.nestedSurfaceTintColor(
        context,
        withBlur: HyperosBlurredHeader.backdropBlurEnabled(context),
      ),
      child: content,
    );
  }
}
