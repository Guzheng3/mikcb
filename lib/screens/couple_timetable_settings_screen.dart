import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:university_timetable/l10n/app_localizations.dart';
import 'package:university_timetable/l10n/service_message_localizer.dart';
import 'package:provider/provider.dart';

import '../models/partner_timetable_binding.dart';
import '../domain/couple_timetable_logic.dart';
import '../providers/timetable_provider.dart';
import '../services/partner_timetable_service.dart';
import '../services/home_widget_service.dart';
import '../services/withu_couple_auth_service.dart';
import '../services/withu_couple_config.dart';
import '../services/withu_couple_session_store.dart';
import '../services/withu_couple_timetable_service.dart';
import '../ui/hyperos/hyperos.dart';
import '../utils/app_toast.dart';
import '../utils/course_color_palette.dart';
import '../utils/hex_color.dart';
import 'withu_couple_login_screen.dart';

class CoupleTimetableSettingsScreen extends StatefulWidget {
  const CoupleTimetableSettingsScreen({super.key});

  @override
  State<CoupleTimetableSettingsScreen> createState() =>
      _CoupleTimetableSettingsScreenState();
}

class _CoupleTimetableSettingsScreenState
    extends State<CoupleTimetableSettingsScreen> {
  // 双人课程色快选：沿用一族一色的快捷色（选中色不在列表时
  // _paletteIncluding 会自动补到行首）。
  static const _coupleColorChoices = kCourseColorQuickPickHexes;

  bool _isExporting = false;
  bool _isImporting = false;
  bool _isUnlinking = false;
  bool _isPullingWithu = false;
  bool _isUploadingWithu = false;
  bool _isPinningCoupleWidget = false;

  final WithuCoupleAuthService _withuAuthService = WithuCoupleAuthService();
  final HomeWidgetService _homeWidgetService = HomeWidgetService();
  late final WithuCoupleTimetableService _withuTimetableService;
  WithuCoupleConfig _withuCoupleConfig = const WithuCoupleConfig();
  WithuCoupleSession? _withuCoupleSession;

  @override
  void initState() {
    super.initState();
    _withuTimetableService = WithuCoupleTimetableService(
      authService: _withuAuthService,
    );
    _loadWithuCoupleState();
  }

  @override
  void dispose() {
    _withuAuthService.dispose();
    super.dispose();
  }

  bool get _isWithuCoupleConnected =>
      _withuCoupleConfig.baseUrl.trim().isNotEmpty &&
      _withuCoupleSession != null &&
      _withuCoupleSession!.isUsable;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.watch<TimetableProvider>();
    final binding = provider.partnerBinding;
    final partnerProfile = provider.partnerProfile;

    return HyperosSubpage(
      onBack: () => Navigator.pop(context),
      title: Text(l10n.coupleTimetableTitle),
      child: HyperosListView(
        children: [
          HyperosControlCard(
            edgeToEdge: true,
            child: HyperosControlCardRowScope(
              isFirst: true,
              isLast: true,
              child: HyperosSwitchTile(
                icon: Icons.favorite_outline_rounded,
                iconAccent: provider.settings.coupleTimetableOverlayEnabled
                    ? HyperosIconColors.red
                    : HyperosIconColors.blue,
                title: l10n.coupleTimetableTitle,
                subtitle: l10n.coupleTimetableSwitchSubtitle,
                value: provider.settings.coupleTimetableOverlayEnabled,
                onChanged: (value) {
                  provider.updateSettings(
                    provider.settings.copyWith(
                      coupleTimetableOverlayEnabled: value,
                    ),
                  );
                },
              ),
            ),
          ),
          const HyperosSectionGap(),
          HyperosSectionLabel(
            text: binding == null
                ? l10n.coupleTimetableUnboundTitle
                : l10n.coupleTimetableBoundTitle,
          ),
          if (binding != null)
            HyperosControlCard(
              child: HyperosControlCardInset(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow(
                      context,
                      l10n.coupleTimetablePartnerNameLabel,
                      partnerProfile?.name ?? binding.partnerName,
                    ),
                    _buildInfoRow(
                      context,
                      l10n.courseCountBullet(
                        partnerProfile?.courses.length ?? 0,
                      ),
                      binding.lastImportedAt == null
                          ? '-'
                          : _formatDateTime(binding.lastImportedAt!),
                    ),
                  ],
                ),
              ),
            ),
          const HyperosSectionGap(),
          HyperosSectionLabel(text: l10n.withuCoupleTitle),
          HyperosControlCard(
            child: HyperosControlCardInset(
              child: _buildWithuCoupleControl(context, l10n),
            ),
          ),
          if (provider.settings.coupleTimetableOverlayEnabled) ...[
            const HyperosSectionGap(),
            HyperosSectionLabel(text: l10n.coupleTimetableDesktopCardTitle),
            HyperosControlCard(
              title: l10n.coupleTimetableDesktopCardTitle,
              child: HyperosControlCardInset(
                child: HyperosButton(
                  label: _isPinningCoupleWidget
                      ? '${l10n.homeWidgetTargetCoupleTimetable42}...'
                      : l10n.homeWidgetTargetCoupleTimetable42,
                  variant: HyperosButtonVariant.secondary,
                  loading: _isPinningCoupleWidget,
                  onPressed: _isPinningCoupleWidget
                      ? null
                      : _pinCoupleTimetableWidget,
                ),
              ),
            ),
          ],
          const HyperosSectionGap(),
          HyperosSectionLabel(text: l10n.coupleTimetableTitle),
          HyperosControlCard(
            child: HyperosControlCardInset(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  HyperosButton(
                    label: _isExporting
                        ? '${l10n.coupleTimetableExportForPartner}...'
                        : l10n.coupleTimetableExportForPartner,
                    loading: _isExporting,
                    onPressed: _isExporting ? null : _exportForPartner,
                  ),
                  HyperosButton(
                    label: _isImporting
                        ? '${l10n.coupleTimetableImportPartner}...'
                        : l10n.coupleTimetableImportPartner,
                    variant: HyperosButtonVariant.secondary,
                    loading: _isImporting,
                    onPressed: _isImporting ? null : _importPartner,
                  ),
                  if (binding != null)
                    HyperosButton(
                      label: _isUnlinking
                          ? '${l10n.coupleTimetableUnlink}...'
                          : l10n.coupleTimetableUnlink,
                      variant: HyperosButtonVariant.secondary,
                      loading: _isUnlinking,
                      onPressed: _isUnlinking ? null : _confirmUnlink,
                    ),
                ],
              ),
            ),
          ),
          if (binding != null) ...[
            const HyperosSectionGap(),
            HyperosSectionLabel(text: l10n.coupleTimetableWeekOffsetTitle),
            HyperosControlCard(
              child: HyperosControlCardInset(
                child: _buildWeekOffsetControl(
                  context,
                  provider,
                  binding.weekOffset,
                ),
              ),
            ),
            const HyperosSectionGap(),
            HyperosSectionLabel(text: l10n.coupleTimetableColorsTitle),
            HyperosControlCard(
              child: HyperosControlCardInset(
                child: _buildCoupleColorsControl(context, provider, binding),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _loadWithuCoupleState() async {
    final config = await _withuAuthService.loadConfig();
    final session = await _withuAuthService.loadSession();
    if (!mounted) {
      return;
    }
    setState(() {
      _withuCoupleConfig = config;
      _withuCoupleSession = session;
    });
  }

  Widget _buildWithuCoupleControl(BuildContext context, AppLocalizations l10n) {
    final connected = _isWithuCoupleConnected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          connected
              ? l10n.withuCoupleConnectedAs(_withuCoupleSession!.username)
              : l10n.withuCoupleNotConnected,
          style: HyperosTypography.listTitle(context),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.withuCoupleServerHint(_withuCoupleConfig.baseUrl),
          style: HyperosTypography.listDetail(context),
        ),
        if (_withuCoupleConfig.lastPulledAt != null) ...[
          const SizedBox(height: 8),
          Text(
            l10n.withuCoupleLastPulledAt(
              _formatDateTime(_withuCoupleConfig.lastPulledAt!),
            ),
            style: HyperosTypography.listDetail(context),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!connected)
              HyperosButton(
                label: l10n.withuCoupleConnect,
                onPressed: _connectWithuCouple,
              )
            else ...[
              HyperosButton(
                label: _isPullingWithu
                    ? '${l10n.withuCouplePullNow}...'
                    : l10n.withuCouplePullNow,
                loading: _isPullingWithu,
                onPressed: _isPullingWithu ? null : _pullPartnerWithu,
              ),
              HyperosButton(
                label: _isUploadingWithu
                    ? '${l10n.withuCoupleUploadForPartner}...'
                    : l10n.withuCoupleUploadForPartner,
                variant: HyperosButtonVariant.secondary,
                loading: _isUploadingWithu,
                onPressed: _isUploadingWithu
                    ? null
                    : _uploadMyTimetableForWithu,
              ),
              HyperosButton(
                label: l10n.withuCoupleDisconnect,
                variant: HyperosButtonVariant.secondary,
                onPressed: _disconnectWithuCouple,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Future<void> _connectWithuCouple() async {
    final provider = context.read<TimetableProvider>();
    final connected = await showWithuCoupleLoginSheet(
      context: context,
      initialConfig: _withuCoupleConfig,
      onPullPartner: (service) =>
          service.syncAfterLogin(provider: provider),
    );
    if (connected != true || !mounted) {
      return;
    }
    await provider.syncCoupleTimetableWidgetSnapshot();
    await _loadWithuCoupleState();
  }

  Future<void> _disconnectWithuCouple() async {
    final provider = context.read<TimetableProvider>();
    await _withuTimetableService.disconnect();
    await provider.syncCoupleTimetableWidgetSnapshot();
    await _loadWithuCoupleState();
  }

  Future<void> _pinCoupleTimetableWidget() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _isPinningCoupleWidget = true);
    final result = await _homeWidgetService.requestPinWidget(
      HomeWidgetPinTarget.coupleTimetable42,
    );
    if (!mounted) {
      return;
    }
    setState(() => _isPinningCoupleWidget = false);
    final message = switch (result) {
      HomeWidgetPinRequestResult.requested => l10n.homeWidgetPinRequested(
        l10n.homeWidgetTargetCoupleTimetable42,
      ),
      HomeWidgetPinRequestResult.unsupported =>
        l10n.homeWidgetPinUnsupportedManual(
          l10n.homeWidgetTargetCoupleTimetable42,
        ),
      HomeWidgetPinRequestResult.invalidWidgetType =>
        l10n.homeWidgetInvalidType,
      HomeWidgetPinRequestResult.failed => l10n.homeWidgetPinFailedManual(
        l10n.homeWidgetTargetCoupleTimetable42,
      ),
    };
    showAppToast(context, message: message);
  }

  Future<void> _pullPartnerWithu({
    bool force = false,
    bool showProgress = true,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    if (showProgress) {
      setState(() => _isPullingWithu = true);
    }
    try {
      final result = await _withuTimetableService.pullPartnerTimetable(
        provider: context.read<TimetableProvider>(),
        force: force,
      );
      await _loadWithuCoupleState();
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
      if (mounted && showProgress) {
        setState(() => _isPullingWithu = false);
      }
    }
  }

  Future<void> _uploadMyTimetableForWithu() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _isUploadingWithu = true);
    try {
      final errorCode = await _withuTimetableService
          .uploadMyTimetableForPartner(
            provider: context.read<TimetableProvider>(),
          );
      if (!mounted) {
        return;
      }
      if (errorCode != null) {
        showAppToast(
          context,
          message: localizeServiceMessage(l10n, errorCode),
          kind: AppToastKind.error,
        );
        return;
      }
      showAppToast(
        context,
        message: l10n.withuCoupleUploadSuccess,
        kind: AppToastKind.success,
      );
    } finally {
      if (mounted) {
        setState(() => _isUploadingWithu = false);
      }
    }
  }

  Widget _buildCoupleColorsControl(
    BuildContext context,
    TimetableProvider provider,
    PartnerTimetableBinding binding,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCoupleColorRow(
          context,
          label: l10n.coupleTimetableLegendMine,
          selectedHex: binding.mineColorHex,
          onSelected: (color) =>
              provider.updatePartnerCoupleColors(mineColorHex: color),
        ),
        const SizedBox(height: 14),
        _buildCoupleColorRow(
          context,
          label: l10n.coupleTimetableLegendPartner,
          selectedHex: binding.partnerColorHex,
          onSelected: (color) =>
              provider.updatePartnerCoupleColors(partnerColorHex: color),
        ),
        const SizedBox(height: 14),
        _buildCoupleColorRow(
          context,
          label: l10n.coupleTimetableLegendTogether,
          selectedHex: binding.togetherColorHex,
          onSelected: (color) =>
              provider.updatePartnerCoupleColors(togetherColorHex: color),
        ),
      ],
    );
  }

  Widget _buildCoupleColorRow(
    BuildContext context, {
    required String label,
    required String selectedHex,
    required ValueChanged<String> onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: HyperosTypography.listTitle(context)),
        const SizedBox(height: 8),
        HyperosHexColorChipGroup(
          colorHexes: _paletteIncluding(selectedHex),
          selectedHex: selectedHex,
          colorParser: _colorFromHex,
          distributeHorizontally: false,
          onSelectedHex: onSelected,
        ),
      ],
    );
  }

  List<String> _paletteIncluding(String selectedHex) {
    final normalized = selectedHex.toUpperCase();
    if (_coupleColorChoices.any((hex) => hex.toUpperCase() == normalized)) {
      return _coupleColorChoices;
    }
    return [selectedHex, ..._coupleColorChoices];
  }

  Color _colorFromHex(String hex) =>
      parseHexColorOrFallback(hex, fallback: HyperosIconColors.blue);

  Widget _buildWeekOffsetControl(
    BuildContext context,
    TimetableProvider provider,
    int weekOffset,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final previewWeek = provider.currentWeek;
    final partnerWeek = provider.partnerWeekFor(previewWeek);
    final canDecrement = weekOffset > CoupleTimetableLogic.minWeekOffset;
    final canIncrement = weekOffset < CoupleTimetableLogic.maxWeekOffset;
    final offsetLabel = weekOffset == 0
        ? l10n.coupleTimetableWeekOffsetZero
        : l10n.coupleTimetableWeekOffsetSigned(
            weekOffset > 0 ? '+$weekOffset' : '$weekOffset',
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _WeekOffsetStepButton(
              icon: Icons.remove_rounded,
              enabled: canDecrement,
              onPressed: canDecrement
                  ? () => provider.updatePartnerWeekOffset(weekOffset - 1)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                offsetLabel,
                textAlign: TextAlign.center,
                style: HyperosTypography.listTitle(context),
              ),
            ),
            const SizedBox(width: 12),
            _WeekOffsetStepButton(
              icon: Icons.add_rounded,
              enabled: canIncrement,
              onPressed: canIncrement
                  ? () => provider.updatePartnerWeekOffset(weekOffset + 1)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          l10n.coupleTimetableWeekOffsetPreview(previewWeek, partnerWeek),
          style: HyperosTypography.listDetail(context),
        ),
      ],
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: HyperosTypography.listTitle(context)),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: HyperosTypography.listDetail(context),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _exportForPartner() async {
    final provider = context.read<TimetableProvider>();
    final l10n = AppLocalizations.of(context)!;
    setState(() => _isExporting = true);
    try {
      await provider.dataTransferService.exportAndShare(
        profileName: provider.activeProfile?.name,
        courses: provider.courses,
        tasks: provider.tasks,
        scheduleItems: provider.scheduleItems,
        settings: provider.settings,
        currentWeek: provider.currentWeek,
        shareText: l10n.coupleTimetableShareText,
        shareSubject: l10n.coupleTimetableShareSubject,
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _importPartner() async {
    final provider = context.read<TimetableProvider>();
    final l10n = AppLocalizations.of(context)!;
    setState(() => _isImporting = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        withData: true,
        allowedExtensions: const ['json', 'mikcb'],
      );
      final file = result?.files.single;
      if (file == null) {
        return;
      }
      final bytes = file.bytes;
      final content = bytes == null ? '' : utf8.decode(bytes);
      if (!mounted || content.isEmpty) {
        if (mounted && content.isEmpty) {
          throw FormatException(l10n.importFileReadFailed);
        }
        return;
      }
      final importResult = await provider.importPartnerTimetable(content);
      if (!mounted) {
        return;
      }
      showAppToast(
        context,
        message: importResult.kind == PartnerImportResultKind.updated
            ? l10n.coupleTimetableImportUpdated
            : l10n.coupleTimetableImportSuccess,
        kind: AppToastKind.success,
      );
    } on FormatException catch (error) {
      if (!mounted) {
        return;
      }
      showAppToast(
        context,
        message: localizeServiceMessage(l10n, error.message),
        kind: AppToastKind.error,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      showAppToast(
        context,
        message: l10n.importFailedInvalidFile,
        kind: AppToastKind.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _confirmUnlink() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showHyperosDialog<bool>(
      context: context,
      title: l10n.coupleTimetableUnlinkConfirmTitle,
      message: l10n.coupleTimetableUnlinkConfirmMessage,
      actions: [
        HyperosDialogAction(
          label: l10n.cancelAction,
          onPressed: () => Navigator.pop(context, false),
        ),
        HyperosDialogAction(
          label: l10n.coupleTimetableUnlink,
          isPrimary: true,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isUnlinking = true);
    try {
      await context.read<TimetableProvider>().unlinkPartner();
      if (!mounted) {
        return;
      }
      showAppToast(
        context,
        message: l10n.coupleTimetableUnlinkSuccess,
        kind: AppToastKind.success,
      );
    } finally {
      if (mounted) {
        setState(() => _isUnlinking = false);
      }
    }
  }
}

class _WeekOffsetStepButton extends StatelessWidget {
  const _WeekOffsetStepButton({
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return HyperosFrostedSurface(
      borderRadius: BorderRadius.circular(HyperosTokens.controlRadius),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(HyperosTokens.controlRadius),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: 20,
              color: enabled
                  ? colors.primary
                  : colors.onSurface.withValues(alpha: 0.35),
            ),
          ),
        ),
      ),
    );
  }
}
