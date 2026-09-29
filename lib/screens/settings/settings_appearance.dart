part of '../timetable_settings_screen.dart';

class _AppearanceSettingsScreen extends StatefulWidget {
  const _AppearanceSettingsScreen({this.scope = SettingsScope.profile});

  /// [SettingsScope.global] 时编辑全局显示设置（所有课表共享）。
  final SettingsScope scope;

  @override
  State<_AppearanceSettingsScreen> createState() =>
      _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState extends State<_AppearanceSettingsScreen> {
  /// Visual groups on this page (not one card per control).
  /// 0 preview · 1 app display · 2 frosted · 3 reset.
  ///
  /// 页面背景、壁纸与背景区域已移到「课表页面」，统一课卡颜色已移到
  /// 「课程卡片」：它们染的不是应用，而是课表页和课卡。导航形态 /
  /// 玻璃坞 / 首页标题等结构性设置已迁到「首页与导航」。主题色选择器与
  /// 主题库已删除，应用主题色固定为 [TimetableSettings.defaultThemeSeedColor]。
  static const _appearanceSectionCount = 4;

  late final TimetableProvider _timetableProvider;
  late TimetableSettings _draft;
  Timer? _autoSaveTimer;
  Future<void> _saveQueue = Future<void>.value();

  bool get _isGlobal => widget.scope == SettingsScope.global;

  @override
  void initState() {
    super.initState();
    _timetableProvider = context.read<TimetableProvider>();
    _draft = _isGlobal
        ? _timetableProvider.globalSettings ?? _timetableProvider.settings
        : _timetableProvider.settings;
  }

  @override
  void dispose() {
    if (_autoSaveTimer?.isActive ?? false) {
      _autoSaveTimer?.cancel();
      _enqueuePersist(_draft);
    } else {
      _autoSaveTimer?.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return FrostedAppearanceScope(
      appearance: _draft.frostedAppearance,
      child: HyperosSubpage(
        onBack: () => Navigator.pop(context),
        title: Text(l10n.appearanceTitle),
        child: HyperosListView(
          itemCount: _appearanceSectionCount,
          itemBuilder: _buildAppearanceSection,
        ),
      ),
    );
  }

  Widget _buildAppearanceSection(BuildContext context, int index) {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.watch<TimetableProvider>();
    final themePreviewColor = _colorFromHex(
      TimetableSettings.defaultThemeSeedColor,
    );
    final isDarkPreview = Theme.of(context).brightness == Brightness.dark;

    final Widget section = switch (index) {
      0 => HyperosCard(
        padding: EdgeInsets.zero,
        child: ColoredBox(
          color: isDarkPreview
              ? HyperosColors.surfaceContainerHighest(context)
              : HyperosColors.surface(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.previewTitle,
                  style: HyperosTypography.title(context),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: HyperosColors.surfaceContainer(
                      context,
                    ).withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 72,
                          decoration: BoxDecoration(
                            color: themePreviewColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                appThemeModeLabel(l10n, _draft.appThemeMode),
                                style: TextStyle(
                                  color: HyperosColors.onPrimary(context),
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              Text(
                                appFontModeLabel(l10n, _draft.appFontMode),
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          height: 72,
                          decoration: BoxDecoration(
                            color: HyperosColors.surface(
                              context,
                            ).withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            l10n.frostedSheetSectionTitle,
                            style: HyperosTypography.listDetail(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      // 主题 / 字体 — 应用级外观（语言与转场已迁到「通用」，导航形态与
      // 首页标题已迁到「首页与导航」）。本组原是页面中段唯一无标题的裸组，
      // 与后续分组样式不一致（IA 规范 §3「不许无名分组」），补齐区块标题。
      1 => HyperosSettingsBlock(
        title: l10n.appearanceThemeDisplaySectionTitle,
        child: HyperosListGroup(
          children: [
            HyperosSelectTile<AppThemeMode>(
              label: l10n.themeModeLabel,
              subtitle: l10n.displayModeSubtitle,
              items: {
                for (final v in AppThemeMode.values)
                  appThemeModeLabel(l10n, v): v,
              },
              value: _draft.appThemeMode,
              onChanged: (value) {
                _updateDraft(_draft.copyWith(appThemeMode: value));
              },
            ),
            HyperosSelectTile<AppFontMode>(
              label: l10n.fontModeLabel,
              useSheetForPopup: true,
              items: {
                for (final v in AppFontMode.values)
                  appFontModeLabel(l10n, v): v,
              },
              value: _draft.appFontMode,
              onChanged: (value) {
                _updateDraft(_draft.copyWith(appFontMode: value));
              },
              itemTitleStyleBuilder: (mode) {
                final spec = mode.fontSpec;
                if (spec.fontFamily == null || spec.fontFamily!.isEmpty) {
                  return null;
                }
                return TextStyle(
                  fontFamily: spec.fontFamily,
                  fontFamilyFallback: spec.fontFamilyFallback,
                );
              },
            ),
          ],
        ),
      ),
      2 => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          HyperosSettingsBlock(
            title: l10n.frostedSheetSectionTitle,
            child: HyperosListGroup(
              children: [
                HyperosSwitchTile(
                  title: l10n.frostedBlurEnabledTitle,
                  value: _draft.frostedBlurEnabled,
                  onChanged: (value) {
                    _updateDraft(_draft.copyWith(frostedBlurEnabled: value));
                  },
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FrostedSheetSettingsPreview(
                    provider: provider,
                    settings: _draft,
                    week: provider.currentWeek,
                    blurSigma: _draft.frostedSheetBlurSigma,
                    tintAlpha: _draft.frostedSheetTintAlpha,
                    barrierAlpha: _draft.frostedSheetBarrierAlpha,
                    blurEnabled: _draft.frostedBlurEnabled,
                    onOpenDemoSheet: () =>
                        showFrostedSheetSettingsDemo(context),
                  ),
                ),
                  HyperosSliderTile(
                    title: l10n.frostedSheetBlurLabel,
                    value: _draft.frostedSheetBlurSigma,
                    max: 24,
                    divisions: 24,
                    valueLabel: _draft.frostedSheetBlurSigma.toStringAsFixed(0),
                    onChanged: (value) {
                      _updateDraft(
                        _draft.copyWith(frostedSheetBlurSigma: value),
                        debounce: true,
                      );
                    },
                  ),
                  HyperosSliderTile(
                    title: l10n.frostedSheetTintLabel,
                    value: _draft.frostedSheetTintAlpha,
                    max: 0.75,
                    divisions: 75,
                    valueLabel:
                        '${(_draft.frostedSheetTintAlpha * 100).round()}%',
                    onChanged: (value) {
                      _updateDraft(
                        _draft.copyWith(frostedSheetTintAlpha: value),
                        debounce: true,
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
      ),
      3 => _SettingsResetTile(
        scope: SettingsResetScope.appearance,
        onReset: _updateDraft,
        resetSource: _draft,
      ),
      _ => const SizedBox.shrink(),
    };

    if (index == 0) {
      return section;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [const HyperosSectionGap(), section],
    );
  }

  void _updateDraft(TimetableSettings next, {bool debounce = false}) {
    setState(() {
      _draft = next;
    });
    _autoSaveTimer?.cancel();
    if (debounce) {
      _autoSaveTimer = Timer(
        const Duration(milliseconds: 250),
        () => _enqueuePersist(next),
      );
      return;
    }
    _enqueuePersist(next);
  }

  void _enqueuePersist(TimetableSettings next) {
    _saveQueue = _saveQueue.catchError((_) {}).then((_) => _persistDraft(next));
  }

  Future<void> _persistDraft(TimetableSettings next) async {
    if (next.liveMiuiIslandExpandedIconMode ==
            MiuiIslandExpandedIconMode.customImage &&
        (next.liveMiuiIslandExpandedIconPath == null ||
            next.liveMiuiIslandExpandedIconPath!.isEmpty)) {
      return;
    }
    // Use the cached provider — dispose may fire after the Element is unmounted.
    final provider = _timetableProvider;
    if (_isGlobal) {
      await provider.updateGlobalTimetableSettings(next);
      return;
    }
    final message = await provider.updateTimetableSettings(next);
    if (!mounted) {
      return;
    }
    if (message != null) {
      showAppToast(context, message: message);
      setState(() {
        _draft = provider.settings;
      });
    }
  }
}

Map<String, String> buildLocaleMenuMap(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  final seen = <String>{''};
  final map = <String, String>{l10n.languageModeSystem: ''};
  for (final locale in AppLocalizations.supportedLocales) {
    final tag = locale.countryCode?.isNotEmpty == true
        ? '${locale.languageCode}_${locale.countryCode}'
        : locale.languageCode;
    if (!seen.add(tag)) {
      continue;
    }
    map[nativeNameFor(locale)] = tag;
  }
  return map;
}

class _HomeTitleStylePreview extends StatelessWidget {
  final HomeTitleStyle style;

  const _HomeTitleStylePreview({required this.style});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Widget child;
    switch (style) {
      case HomeTitleStyle.classic:
        child = Text(
          AppLocalizations.of(context)!.appTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w400,
          ),
        );
      case HomeTitleStyle.brand:
        child = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppLocalizations.of(context)!.appTitle,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w400,
                height: 1,
              ),
            ),
            Text(
              AppLocalizations.of(context)!.defaultTimetablePreviewName,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HyperosColors.surfaceContainer(context).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Align(child: child),
    );
  }
}

/// Public factory for debug deep-link navigation (debug builds only).
