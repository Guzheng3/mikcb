import 'dart:async';
import 'package:university_timetable/ui/hyperos/hyperos.dart';

import 'package:flutter/material.dart';
import 'package:university_timetable/l10n/app_localizations.dart';

import '../services/miui_live_activities_service.dart';

class UserGuideScreen extends StatefulWidget {
  const UserGuideScreen({super.key});

  @override
  State<UserGuideScreen> createState() => _UserGuideScreenState();
}

class _UserGuideScreenState extends State<UserGuideScreen>
    with WidgetsBindingObserver {
  final MiuiLiveActivitiesService _service = MiuiLiveActivitiesService();

  bool _isLoading = true;
  bool _hasNotificationPermission = false;
  bool _hasPromotedPermission = false;
  bool _canPostPromoted = false;
  bool _isIgnoringBatteryOptimizations = false;
  bool _isAutoStartEnabled = false;
  Timer? _settingsPollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
  }

  @override
  void dispose() {
    _settingsPollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _settingsPollTimer?.cancel();
      unawaited(_refreshStatusAfterExternalReturn());
    }
  }

  String _permissionSnapshotKey() {
    return [
      _hasNotificationPermission,
      _canPostPromoted,
      _isAutoStartEnabled,
      _isIgnoringBatteryOptimizations,
    ].join(',');
  }

  void _startSettingsStatusPoll({required String baselineKey}) {
    _settingsPollTimer?.cancel();
    var ticks = 0;
    var refreshInFlight = false;
    _settingsPollTimer = Timer.periodic(const Duration(milliseconds: 450), (
      timer,
    ) async {
      ticks++;
      if (!mounted || ticks > 30) {
        timer.cancel();
        return;
      }
      // 回调是 async：_refreshStatus 超过 450ms 时跳过本轮，避免轮询
      // 重叠造成状态抖动。
      if (refreshInFlight) {
        return;
      }
      refreshInFlight = true;
      try {
        await _refreshStatus(showLoading: false);
      } finally {
        refreshInFlight = false;
      }
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_permissionSnapshotKey() != baselineKey) {
        timer.cancel();
      }
    });
  }

  Future<void> _refreshStatusAfterExternalReturn() async {
    for (var i = 0; i < 5; i++) {
      if (i > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      if (!mounted) {
        return;
      }
      await _refreshStatus(showLoading: false);
    }
  }

  Future<void> _refreshStatus({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
      });
    }

    final promotedSupport = await _service.checkPromotedSupport();
    final hasNotificationPermission = await _service
        .checkNotificationPermission();
    final isIgnoringBatteryOptimizations = await _service
        .isIgnoringBatteryOptimizations();
    final isAutoStartEnabled = await _service.isAutoStartEnabled();

    if (!mounted) {
      return;
    }
    setState(() {
      _hasNotificationPermission =
          promotedSupport['hasNotificationPermission'] == true ||
          hasNotificationPermission;
      _hasPromotedPermission = promotedSupport['hasPromotedPermission'] == true;
      _canPostPromoted = promotedSupport['canPostPromoted'] == true;
      _isIgnoringBatteryOptimizations = isIgnoringBatteryOptimizations;
      _isAutoStartEnabled = isAutoStartEnabled;
      _isLoading = false;
    });
  }

  Future<void> _runAction(Future<void> Function() action) async {
    final baselineKey = _permissionSnapshotKey();
    await action();
    if (!mounted) {
      return;
    }
    _startSettingsStatusPoll(baselineKey: baselineKey);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return HyperosSubpage(
      onBack: () => Navigator.pop(context),
      suffixes: [
        FHeaderAction(
          icon: const Icon(Icons.refresh),
          semanticsLabel: l10n.refreshStatusTooltip,
          onPress: _refreshStatus,
        ),
      ],
      title: Text(l10n.guideAndPermissionsTitle),
      bottomBar: _buildBottomBar(l10n),
      child: _buildPermissionsPage(l10n),
    );
  }

  /// 标准列表容器：组件库 [HyperosListView] 自带折叠顶栏 inset（与旧手写
  /// 的 headerInset+8 首屏让位完全等价），滚动时行内容仍从磨砂栏下穿过。
  /// 每页传独立 storageId，避免 PageStorage 恢复到路由级
  /// 默认 key 的滚动偏移。
  Widget _buildGuideList({
    required String storageId,
    required List<Widget> children,
  }) {
    return HyperosListView(
      itemCount: children.length,
      itemBuilder: (context, index) => children[index],
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      pageStorageKey: PageStorageKey<String>('user-guide-$storageId'),
    );
  }

  Widget _buildPermissionsPage(AppLocalizations l10n) {
    if (_isLoading) {
      return const Center(child: HyperosCircularProgress());
    }

    final items = _buildPermissionItems(l10n);
    final countableItems = items.where((item) => item.enabled != null).toList();
    final readyCount = countableItems
        .where((item) => item.enabled == true)
        .length;
    final progress = countableItems.isEmpty
        ? 0.0
        : readyCount / countableItems.length;

    return _buildGuideList(
      storageId: 'permissions',
      children: [
        HyperosSectionLabel(text: l10n.guidePermissionsHeader),
        const SizedBox(height: 8),
        // 摘要卡：副标题 + 就绪计数 + 进度条。刷新入口只保留顶栏
        // action——从系统设置返回本页时生命周期与轮询会自动刷新，
        // 卡内不再重复放一颗 secondary 按钮。
        HyperosControlCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.guidePermissionsSubtitle,
                style: HyperosTypography.listDetail(context),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.guidePermissionsProgressLabel(
                  readyCount,
                  countableItems.length,
                ),
                style: HyperosTypography.listTitle(context),
              ),
              const SizedBox(height: 10),
              HyperosLinearProgress(value: progress),
            ],
          ),
        ),
        const HyperosSectionGap(),
        HyperosListGroup(
          children: [for (final item in items) _buildPermissionTile(item)],
        ),
        const HyperosSectionGap(),
        HyperosHintBanner(
          icon: const Icon(Icons.lightbulb_outline_rounded, size: 18),
          title: Text(l10n.guidePermissionsFooterHint),
        ),
      ],
    );
  }

  List<_PermissionItem> _buildPermissionItems(AppLocalizations l10n) {
    return [
      _PermissionItem(
        icon: Icons.notifications_active_outlined,
        accent: HyperosIconColors.blue,
        title: l10n.guideStatusNotificationPermission,
        enabled: _hasNotificationPermission,
        enabledLabel: l10n.guideStatusEnabled,
        disabledLabel: l10n.guideStatusDisabled,
        onTap: () => _runAction(() async {
          await _service.requestNotificationPermission();
        }),
      ),
      _PermissionItem(
        icon: Icons.auto_awesome,
        accent: HyperosIconColors.purple,
        title: l10n.guideStatusIslandSupport,
        enabled: _canPostPromoted,
        enabledLabel: l10n.guideStatusSystemAllowed,
        disabledLabel: _hasPromotedPermission
            ? l10n.guideStatusEnabledPending
            : l10n.guideStatusSuggestedCheck,
        onTap: () => _runAction(_service.openPromotedSettings),
      ),
      _PermissionItem(
        icon: Icons.play_circle_outline_rounded,
        accent: HyperosIconColors.green,
        title: l10n.quickActionAutoStartTitle,
        enabled: _isAutoStartEnabled,
        enabledLabel: l10n.guideStatusEnabled,
        disabledLabel: l10n.guideStatusDisabled,
        onTap: () => _runAction(_service.openAutoStartSettings),
      ),
      _PermissionItem(
        icon: Icons.battery_saver_outlined,
        accent: HyperosIconColors.teal,
        title: l10n.guideStatusBatteryOptimization,
        enabled: _isIgnoringBatteryOptimizations,
        enabledLabel: l10n.guideStatusBatteryUnrestricted,
        disabledLabel: l10n.guideStatusBatteryRestricted,
        onTap: () => _runAction(_service.openBatteryOptimizationSettings),
      ),
    ];
  }

  Widget _buildPermissionTile(_PermissionItem item) {
    // HyperOS 设置行范式：彩底圆角方徽章 + 标题 + 右侧灰色状态字 + 细
    // chevron（同系统权限管理）。状态不再用自绘描边胶囊表达，避免与
    // 尾部勾/箭头形成双重状态指示器。
    return HyperosListTile(
      icon: item.icon,
      iconAccent: item.accent,
      title: item.title,
      details: item.enabled == true ? item.enabledLabel : item.disabledLabel,
      onTap: item.onTap,
    );
  }

  Widget _buildBottomBar(AppLocalizations l10n) {
    // Container outside SafeArea so the gesture-indicator inset is filled
    // with the same color as the page (fixes the white-strip / blue mismatch).
    // No top border — the bar should sit flush against content.
    final barBackground = HyperosColors.scaffoldBackground(context);
    return Container(
      color: barBackground,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Row(
            children: [
              const Spacer(),
              HyperosButton(
                label: l10n.startUsingAction,
                onPressed: _finishGuide,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _finishGuide() {
    Navigator.of(context).pop();
  }
}

class _PermissionItem {
  final IconData icon;

  /// 徽章底色，取自 HyperOS 图标彩板（[HyperosIconColors]）。
  final Color accent;
  final String title;
  final bool? enabled;
  final String enabledLabel;
  final String disabledLabel;
  final VoidCallback? onTap;

  const _PermissionItem({
    required this.icon,
    required this.accent,
    required this.title,
    required this.enabled,
    required this.enabledLabel,
    required this.disabledLabel,
    this.onTap,
  });
}
