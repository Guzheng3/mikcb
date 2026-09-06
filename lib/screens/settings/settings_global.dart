part of '../timetable_settings_screen.dart';

/// 全局显示设置页：所有课表默认跟随这里的显示配置；某份课表单独改过的
/// 项目仍以该课表自己的设置为准。学期、节次（时间方案）等课表专属内容
/// 不在这里，仍属于每份课表自身。
class _GlobalTimetableSettingsScreen extends StatelessWidget {
  const _GlobalTimetableSettingsScreen();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.watch<TimetableProvider>();

    void openScoped(String routeName, Widget page) {
      HyperosNavigation.push(
        context,
        settings: RouteSettings(name: routeName),
        builder: (_) => page,
      );
    }

    return HyperosSubpage(
      onBack: () => Navigator.pop(context),
      title: Text(l10n.globalSettingsTitle),
      child: HyperosListView(
        pageStorageKey: const PageStorageKey<String>('settings-global'),
        children: [
          HyperosSettingsBlock(
            title: l10n.globalSettingsDescriptionTitle,
            description: l10n.globalSettingsDescriptionBody,
            child: HyperosListGroup(
              children: [
                _MiuixSettingsPreference(
                  startAction: _settingsIconBadge(
                    MiuixIcons.extended.byName('tune')!,
                    HyperosIconColors.purple,
                  ),
                  title: l10n.generalSettingsTitle,
                  onClick: () => openScoped(
                    '/settings/global-display/general',
                    const _GeneralSettingsScreen(scope: SettingsScope.global),
                  ),
                ),
                _MiuixSettingsPreference(
                  startAction: _settingsIconBadge(
                    MiuixIcons.extended.byName('theme')!,
                    HyperosIconColors.orange,
                  ),
                  title: l10n.appearanceTitle,
                  onClick: () => openScoped(
                    '/settings/global-display/appearance',
                    const _AppearanceSettingsScreen(
                      scope: SettingsScope.global,
                    ),
                  ),
                ),
                _MiuixSettingsPreference(
                  startAction: _settingsIconBadge(
                    MiuixIcons.extended.byName('months')!,
                    HyperosIconColors.blue,
                  ),
                  title: l10n.timetablePageSettingsTitle,
                  onClick: () => openScoped(
                    '/settings/global-display/timetable-page',
                    const _TimetablePageSettingsScreen(
                      scope: SettingsScope.global,
                    ),
                  ),
                ),
                _MiuixSettingsPreference(
                  startAction: _settingsIconBadge(
                    MiuixIcons.extended.byName('gridView')!,
                    HyperosIconColors.teal,
                  ),
                  title: l10n.courseCardSettingsTitle,
                  onClick: () => openScoped(
                    '/settings/global-display/course-card',
                    const _CourseCardSettingsScreen(
                      scope: SettingsScope.global,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (provider.globalSettings != null) ...[
            const HyperosSectionGap(),
            HyperosListGroup(
              children: [
                HyperosListTile(
                  title: l10n.globalSettingsClearTitle,
                  onTap: () => _confirmClear(context, provider),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmClear(
    BuildContext context,
    TimetableProvider provider,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showHyperosConfirmDialog(
      context: context,
      title: l10n.globalSettingsClearTitle,
      message: l10n.globalSettingsClearConfirm,
      cancelLabel: l10n.cancelAction,
      confirmLabel: l10n.globalSettingsClearTitle,
      destructive: true,
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    await provider.clearGlobalTimetableSettings();
    if (context.mounted) {
      showAppToast(
        context,
        message: l10n.globalSettingsCleared,
        kind: AppToastKind.success,
      );
    }
  }
}
