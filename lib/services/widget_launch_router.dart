import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/timetable_provider.dart';
import 'home_widget_binding_service.dart';
import 'partner_timetable_service.dart';

enum WidgetLaunchOutcome {
  /// 无 pending 点击，或无需切换（左边点击且当前已是我的课表）→ 普通打开。
  none,

  /// 已切到对应课表（卡片绑定档案或情侣卡片右半 → TA 课表）。
  switchedProfile,

  /// 绑定的 TA 课表已解绑/被删 → 回落普通打开。
  bindingMissing,
}

/// 桌面卡片点击 → App 内分流。
///
/// 原生把卡片点击（带 appWidgetId）作为 pending 递给 Flutter（冷启动由
/// 启动流程 drain，热启动经 miui_live 通道 onWidgetLaunchReceived 通知），
/// 这里按点击位置/卡片绑定分流：
/// - 情侣卡片右半 → 切到 TA 的课表（主界面直接展示，TA 课表可切换）
/// - 情侣卡片左半 → 当前停在 TA 课表时切回我的课表，否则普通打开
/// - 普通卡片按绑定档案 `switchProfile` 直达
/// - 未绑定 / 绑定已失效 → 普通打开
class WidgetLaunchRouter {
  const WidgetLaunchRouter._();

  static Future<WidgetLaunchOutcome> handle(BuildContext context) {
    final provider = context.read<TimetableProvider>();
    return handleWith(provider: provider);
  }

  /// 分流核心：与 BuildContext 解耦，便于纯异步测试。
  static Future<WidgetLaunchOutcome> handleWith({
    required TimetableProvider provider,
    HomeWidgetBindingService bindingService = const HomeWidgetBindingService(),
  }) async {
    final launch = await bindingService.consumePendingWidgetLaunch();
    if (launch == null) {
      return WidgetLaunchOutcome.none;
    }
    await provider.initialize();

    if (launch.side == 'right') {
      return _switchToPartnerTimetable(provider);
    }
    if (launch.side == 'left') {
      // 当前停在 TA 课表 → 切回「我的课表」（最近使用的非 TA 课表）；
      // 已经是我的课表则什么都不做，普通打开。
      if (provider.activeProfileId ==
          PartnerTimetableService.partnerProfileId) {
        final myProfile = provider.myTimetableProfile;
        if (myProfile == null) {
          return WidgetLaunchOutcome.none;
        }
        await provider.switchProfile(myProfile.id);
        return WidgetLaunchOutcome.switchedProfile;
      }
      return WidgetLaunchOutcome.none;
    }

    final appWidgetId = launch.appWidgetId;
    final boundProfileId = await bindingService.getWidgetBinding(appWidgetId);
    if (boundProfileId == null) {
      return WidgetLaunchOutcome.none;
    }

    if (boundProfileId == PartnerTimetableService.partnerProfileId) {
      return _switchToPartnerTimetable(provider);
    }

    // switchProfile 自带守卫：课表不存在时静默不动。
    await provider.switchProfile(boundProfileId);
    return WidgetLaunchOutcome.switchedProfile;
  }

  static Future<WidgetLaunchOutcome> _switchToPartnerTimetable(
    TimetableProvider provider,
  ) async {
    if (!provider.hasPartnerBinding || provider.partnerProfile == null) {
      return WidgetLaunchOutcome.bindingMissing;
    }
    // 情侣课表开关未开时自动打开：情侣卡片本身是情侣入口，点击即应
    // 进入情侣视图（对应旧版点击卡片自动开启覆盖层的行为）。
    if (!provider.settings.coupleTimetableOverlayEnabled) {
      await provider.updateSettings(
        provider.settings.copyWith(coupleTimetableOverlayEnabled: true),
      );
    }
    const partnerId = PartnerTimetableService.partnerProfileId;
    if (provider.activeProfileId != partnerId) {
      await provider.switchProfile(partnerId);
    }
    return WidgetLaunchOutcome.switchedProfile;
  }
}
