import 'package:flutter/material.dart';
import 'package:university_timetable/l10n/app_localizations.dart';
import 'package:university_timetable/l10n/service_message_localizer.dart';
import 'package:university_timetable/providers/timetable_provider.dart';
import 'package:university_timetable/providers/withu_couple_session_provider.dart';
import 'package:university_timetable/screens/couple_timetable_settings_screen.dart';
import 'package:university_timetable/services/withu_couple_config.dart';
import 'package:university_timetable/services/withu_couple_timetable_service.dart';
import 'package:university_timetable/ui/hyperos/hyperos.dart';
import 'package:university_timetable/utils/app_toast.dart';

import 'home_top_menu.dart';

Future<void> showWithuCoupleCenterSheet({
  required BuildContext context,
  required WithuCoupleSessionProvider sessionProvider,
  required TimetableProvider timetableProvider,
}) {
  return showHyperosSheet<void>(
    context: context,
    builder: (_) => WithuCoupleCenterSheet(
      sessionProvider: sessionProvider,
      timetableProvider: timetableProvider,
    ),
  );
}

class WithuCoupleCenterSheet extends StatefulWidget {
  const WithuCoupleCenterSheet({
    super.key,
    required this.sessionProvider,
    required this.timetableProvider,
  });

  final WithuCoupleSessionProvider sessionProvider;
  final TimetableProvider timetableProvider;

  @override
  State<WithuCoupleCenterSheet> createState() => _WithuCoupleCenterSheetState();
}

class _WithuCoupleCenterSheetState extends State<WithuCoupleCenterSheet> {
  late final WithuCoupleTimetableService _timetableService;
  bool _isSyncing = false;
  bool _isDisconnecting = false;
  WithuCoupleConfig _config = const WithuCoupleConfig();

  @override
  void initState() {
    super.initState();
    // 复用首页 provider 的认证服务：退出登录必须在同一份状态上发生。
    _timetableService = WithuCoupleTimetableService(
      authService: widget.sessionProvider.authService,
    );
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final config = await _timetableService.loadConfig();
    if (!mounted) {
      return;
    }
    setState(() => _config = config);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasPartnerTimetable = widget.timetableProvider.partnerProfile != null;

    return HyperosSheetFrame(
      maxHeight: MediaQuery.sizeOf(context).height * 0.64,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.withuCoupleCenterTitle,
            style: HyperosTypography.sheetTitle(context),
          ),
          const SizedBox(height: 16),
          _buildAccountHeader(context, hasPartnerTimetable),
          const SizedBox(height: 16),
          _buildStatus(context, hasPartnerTimetable),
          const SizedBox(height: 16),
          _buildActions(context),
        ],
      ),
    );
  }

  Widget _buildAccountHeader(BuildContext context, bool hasPartnerTimetable) {
    final l10n = AppLocalizations.of(context)!;
    final session = widget.sessionProvider;
    // 昵称可能取不到（旧服务端、对方未设置、离线时只有凭证没有缓存资料）：
    // 依次退回账号名、本地化文案，不要把空串直接显示出来。
    final account = session.session?.username.trim() ?? '';
    final userName = session.userNickname.trim().isNotEmpty
        ? session.userNickname.trim()
        : (account.isNotEmpty ? account : l10n.coupleTimetableLegendMine);
    final partnerName = session.partnerNickname.trim().isNotEmpty
        ? session.partnerNickname.trim()
        : l10n.coupleTimetableLegendPartner;

    return Row(
      children: [
        WithuCoupleAvatarGroup(
          userAvatarPath: session.userAvatarPath,
          partnerAvatarPath: session.partnerAvatarPath,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HyperosTypography.listTitle(context),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      Icons.favorite_rounded,
                      size: 14,
                      color: Color(0xFFEA3A5D),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      partnerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HyperosTypography.listTitle(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                l10n.withuCoupleConnectedAs(
                  account.isNotEmpty ? account : userName,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HyperosTypography.listDetail(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatus(BuildContext context, bool hasPartnerTimetable) {
    final l10n = AppLocalizations.of(context)!;
    final lastPulledAt = _config.lastPulledAt;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(HyperosTokens.controlRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasPartnerTimetable
                    ? Icons.check_circle_outline_rounded
                    : Icons.info_outline_rounded,
                size: 16,
                color: hasPartnerTimetable
                    ? const Color(0xFF047857)
                    : Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.56),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasPartnerTimetable
                      ? l10n.withuCouplePartnerImported
                      : l10n.withuCouplePartnerNotImported,
                  style: HyperosTypography.listDetail(context),
                ),
              ),
            ],
          ),
          if (lastPulledAt != null) ...[
            const SizedBox(height: 6),
            Text(
              l10n.withuCoupleLastPulledAt(_formatDateTime(lastPulledAt)),
              style: HyperosTypography.listDetail(context),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        HyperosButton(
          label: l10n.withuCoupleSettings,
          variant: HyperosButtonVariant.secondary,
          onPressed: _openSettings,
        ),
        HyperosButton(
          label: _isSyncing
              ? '${l10n.withuCoupleSyncNow}...'
              : l10n.withuCoupleSyncNow,
          loading: _isSyncing,
          onPressed: _isSyncing ? null : _syncNow,
        ),
        HyperosButton(
          label: _isDisconnecting
              ? '${l10n.withuCoupleDisconnect}...'
              : l10n.withuCoupleDisconnect,
          variant: HyperosButtonVariant.secondary,
          onPressed: _isDisconnecting ? null : _disconnect,
        ),
      ],
    );
  }

  Future<void> _openSettings() async {
    final navigator = Navigator.of(context);
    navigator.pop();
    await navigator.push<void>(
      HyperosPageRoute<void>(
        builder: (_) => const CoupleTimetableSettingsScreen(),
      ),
    );
  }

  Future<void> _syncNow() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _isSyncing = true);
    try {
      final result = await _timetableService.syncAfterLogin(
        provider: widget.timetableProvider,
      );
      await _loadConfig();
      if (!mounted) {
        return;
      }
      switch (result.status) {
        case WithuCouplePullStatus.imported:
          showAppToast(
            context,
            message: l10n.withuCouplePullImported,
            kind: AppToastKind.success,
          );
        case WithuCouplePullStatus.updated:
          showAppToast(
            context,
            message: l10n.withuCouplePullUpdated,
            kind: AppToastKind.success,
          );
        case WithuCouplePullStatus.unchanged:
          showAppToast(context, message: l10n.withuCouplePullUnchanged);
        case WithuCouplePullStatus.failed:
          showAppToast(
            context,
            message: localizeServiceMessage(
              l10n,
              result.errorCode ?? 'withu_request_failed',
            ),
            kind: AppToastKind.error,
          );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _disconnect() async {
    final l10n = AppLocalizations.of(context)!;
    // 弹窗关闭后这里就不能再用本 widget 的 context 找 Overlay 了，先取根 Overlay
    // 备用：服务端注销的提示要在弹窗消失之后才可能弹出来。
    final toastOverlay = Overlay.maybeOf(context, rootOverlay: true);
    setState(() => _isDisconnecting = true);
    try {
      // 1) 本机立即退出：这一步只读本地凭证，返回时首页已经是未登录态，
      //    不等服务端往返。
      await widget.sessionProvider.signOutLocally();
      await _timetableService.forgetPartnerPullMarkers();
      await widget.timetableProvider.syncCoupleTimetableWidgetSnapshot();
      if (!mounted) {
        return;
      }
      // 2) 先把界面收掉，再去做服务端注销。
      Navigator.of(context).pop();

      // 3) 尽力注销服务端会话（吊销 withu_device 可信设备）。拿不到确认时
      //    本地已经退出，只需提醒用户服务端会话可能仍有效。
      final serverConfirmed = await widget.sessionProvider
          .completeServerLogout();
      // 弹窗此时已经关掉，本 widget 的 context 可能已失效，只能用根 Overlay
      // 作为 toast 宿主（它随应用存活）。
      if (!serverConfirmed) {
        showAppToast(
          null,
          overlay: toastOverlay,
          message: l10n.withuCoupleLogoutUnconfirmed,
          kind: AppToastKind.warning,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDisconnecting = false);
      }
    }
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
