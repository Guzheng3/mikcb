import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:university_timetable/l10n/app_localizations.dart';
import 'package:university_timetable/providers/withu_couple_session_provider.dart';
import 'package:university_timetable/ui/hyperos/hyperos.dart';

/// 首页菜单条目的分类（列表弹窗的分组依据）。
enum HomeMenuEntryCategory { features, data, preferences, about }

String homeMenuEntryCategoryLabel(
  AppLocalizations l10n,
  HomeMenuEntryCategory category,
) => switch (category) {
  HomeMenuEntryCategory.features => l10n.homeMenuCategoryFeatures,
  HomeMenuEntryCategory.data => l10n.homeMenuCategoryData,
  HomeMenuEntryCategory.preferences => l10n.homeMenuCategoryPreferences,
  HomeMenuEntryCategory.about => l10n.homeMenuCategoryAbout,
};

/// Matches the compact HyperOS-style menu width measured on common phones.
const double _homeTopMenuWidth = 131.4;

/// 131.4 physical px on the common 3x phone; the avatar row stays at 56dp.
const double _homeTopMenuRowHeight = 43.8;

/// 一个可放入首页右上角菜单的入口：应用内任意二级页面或功能。
///
/// [id] 是稳定主键（内置项沿用旧 HomeTopMenuAction.name 以兼容旧数据），
/// 其余来自目录 kHomeMenuCatalog；[open] 负责从当前 context 导航，由
/// 目录统一提供实现。
/// [visible] 是构建模式等环境可见性门控：返回 false 的条目不进菜单、
/// 不进底栏圆钮候选——调试/性能版工具绝不能经目录泄漏给正式版用户。
class HomeMenuEntry {
  const HomeMenuEntry({
    required this.id,
    required this.title,
    required this.icon,
    required this.category,
    required this.open,
    this.visible = _alwaysVisible,
  });

  static bool _alwaysVisible() => true;

  final String id;
  final String Function(AppLocalizations l10n) title;
  final IconData icon;
  final HomeMenuEntryCategory category;
  final Future<void> Function(BuildContext context) open;
  final bool Function() visible;
}

/// 目录条目的标准导航壳：与首页顶部菜单同一条 Hyperos 页面转场路径。
Future<void> pushHomeMenuPage(BuildContext context, Widget page) {
  return Navigator.of(
    context,
  ).push<void>(HyperosPageRoute<void>(builder: (_) => page));
}

/// Shows the home screen top-right action menu as a small anchored Miuix list
/// popup — the same chrome as every other anchored popup in the app: spring
/// reveal, glass surface, tap-outside to dismiss.
///
/// Rows are plain text, except the logged-in withU couple action, which shows
/// the web-style paired avatars in the leading row.
///
/// [entries] 是菜单条目（`resolveHomeMenuEntries` 的结果）；相邻条目
/// 分类变化时插入 8dp 分组间隔。返回被点条目的 [HomeMenuEntry.id]，
/// 由调用方经目录分发导航。
///
/// [anchorKey] must be the key of the top-right "more" button; the popup is
/// positioned just below it via [hyperosPopupPositionBelow].
Future<String?> showHomeTopMenuSheet(
  BuildContext context, {
  required List<HomeMenuEntry> entries,
  required GlobalKey anchorKey,
  Color? foregroundColor,
}) {
  final l10n = AppLocalizations.of(context)!;
  final position = hyperosPopupPositionBelow(context, anchorKey);
  final coupleLoginLeading = _withuCoupleLoginLeading(context);

  return showHyperosListPopup<String>(
    context: context,
    position: position,
    foregroundColor: foregroundColor,
    fixedWidth: _homeTopMenuWidth,
    centerLabels: true,
    showDividers: true,
    items: [
      for (var index = 0; index < entries.length; index++)
        () {
          final isAvatarRow =
              entries[index].id == 'withuCoupleLogin' &&
              coupleLoginLeading != null;
          return HyperosPopupMenuItem<String>(
            label: isAvatarRow ? '' : entries[index].title(l10n),
            leading: entries[index].id == 'withuCoupleLogin'
                ? coupleLoginLeading
                : null,
            value: entries[index].id,
            rowHeight: isAvatarRow ? null : _homeTopMenuRowHeight,
          );
        }(),
    ],
  );
}

const Key _withuCoupleMenuAvatarKey = ValueKey(
  'withu_couple_login_menu_avatar',
);

Widget? _withuCoupleLoginLeading(BuildContext context) {
  final session = context.read<WithuCoupleSessionProvider?>();
  if (session == null || (!session.isLoggedIn && !session.hasStoredSession)) {
    return null;
  }
  return WithuCoupleAvatarGroup(
    userAvatarPath: session.userAvatarPath,
    partnerAvatarPath: session.partnerAvatarPath,
  );
}

class WithuCoupleAvatarGroup extends StatelessWidget {
  const WithuCoupleAvatarGroup({
    super.key,
    required this.userAvatarPath,
    required this.partnerAvatarPath,
  });

  final String? userAvatarPath;
  final String? partnerAvatarPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: _withuCoupleMenuAvatarKey,
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(30),
      ),
      child: SizedBox(
        width: 62,
        height: 36,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: 0,
              child: _WithuCoupleAvatarImage(path: partnerAvatarPath),
            ),
            Positioned(
              left: 0,
              child: _WithuCoupleAvatarImage(path: userAvatarPath),
            ),
            Positioned(
              left: 25,
              top: 12,
              child: Container(
                width: 12,
                height: 12,
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x33F59E0B),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFF94AA), Color(0xFFEA3A5D)],
                    ),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WithuCoupleAvatarImage extends StatelessWidget {
  const _WithuCoupleAvatarImage({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: ClipOval(child: _image),
      ),
    );
  }

  Widget get _image {
    const fallback = _WithuCoupleAvatarFallback();
    final localPath = path;
    if (localPath == null || localPath.isEmpty) {
      return fallback;
    }
    return Image.file(
      File(localPath),
      width: 32,
      height: 32,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

class _WithuCoupleAvatarFallback extends StatelessWidget {
  const _WithuCoupleAvatarFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFF3C1D3),
      child: Icon(Icons.person_outline_rounded, size: 18, color: Colors.white),
    );
  }
}
