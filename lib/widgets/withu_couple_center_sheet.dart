import 'package:flutter/material.dart';
import 'package:university_timetable/l10n/app_localizations.dart';
import 'package:university_timetable/l10n/service_message_localizer.dart';
import 'package:university_timetable/providers/timetable_provider.dart';
import 'package:university_timetable/providers/withu_couple_session_provider.dart';
import 'package:university_timetable/screens/couple_timetable_settings_screen.dart';
import 'package:university_timetable/services/withu_couple_auth_service.dart';
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
  final WithuCoupleAuthService _authService = WithuCoupleAuthService();
  late final WithuCoupleTimetableService _timetableService;
  bool _isSyncing = false;
  bool _isDisconnecting = false;
  WithuCoupleConfig _config = const WithuCoupleConfig();

  @override
  void initState() {
    super.initState();
    _timetableService = WithuCoupleTimetableService(authService: _authService);
    _loadConfig();
  }

  @override
  void dispose() {
    _authService.dispose();
    super.dispose();
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
                      session.userNickname,
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
                      session.partnerNickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HyperosTypography.listTitle(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                l10n.withuCoupleConnectedAs(session.userNickname),
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
    setState(() => _isDisconnecting = true);
    try {
      await _timetableService.disconnect();
      await widget.timetableProvider.syncCoupleTimetableWidgetSnapshot();
      if (mounted) {
        Navigator.of(context).pop();
      }
      await widget.sessionProvider.restoreSession();
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
