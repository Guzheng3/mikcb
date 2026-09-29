import 'package:flutter/material.dart';

/// Miuix 扩展图标名 → Material Icons 的兼容映射（唯一真源）。
///
/// 背景：圆钮图标挑选页与 Miuix 组件展示页原先把 `MiuixIcons.extended` 的
/// 小驼峰图标名当作公开字符串使用（[TimetableSettings.glassDockButtonIconName]
/// 直接持久化该名字）。flutter_miuix 的扩展图标表是 156 个图标 × 5 字重的
/// SVG 路径常量（release AOT 约 1.29 MB），为移除该表，这里把实际用到的名字
/// 映射为 Material Icons 常量。
///
/// 之所以保留小驼峰名字作为 key：旧版本持久化的名字必须继续可解析，否则
/// 用户已选中的圆钮图标会在升级后丢失。
///
/// 全部条目都是 `const IconData` 字面量，`--tree-shake-icons` 能精确保留，
/// MaterialIcons 字体不会因此膨胀。
const Map<String, IconData> kMiuixIconByName = {
  'add': Icons.add_rounded,
  'alarm': Icons.alarm_rounded,
  'all': Icons.apps_rounded,
  'background': Icons.wallpaper_rounded,
  'clear': Icons.clear_rounded,
  'contacts': Icons.contacts_rounded,
  'convertFile': Icons.upload_file_rounded,
  'copy': Icons.content_copy_rounded,
  'create': Icons.create_rounded,
  'cut': Icons.content_cut_rounded,
  'delete': Icons.delete_rounded,
  'edit': Icons.edit_rounded,
  'email': Icons.email_rounded,
  'favorites': Icons.favorite_border_rounded,
  'favoritesFill': Icons.favorite_rounded,
  'gridView': Icons.grid_view_rounded,
  'home': Icons.home_rounded,
  'image': Icons.image_rounded,
  'info': Icons.info_outline_rounded,
  'layers': Icons.layers_rounded,
  'listView': Icons.view_list_rounded,
  'lock': Icons.lock_rounded,
  'messages': Icons.forum_rounded,
  'months': Icons.calendar_month_rounded,
  'more': Icons.more_horiz_rounded,
  'notes': Icons.sticky_note_2_rounded,
  'paste': Icons.content_paste_rounded,
  'redo': Icons.redo_rounded,
  'refresh': Icons.refresh_rounded,
  'remove': Icons.remove_rounded,
  'report': Icons.insert_chart_rounded,
  'search': Icons.search_rounded,
  'settings': Icons.settings_rounded,
  'share': Icons.share_rounded,
  'show': Icons.visibility_rounded,
  'sidebar': Icons.view_sidebar_rounded,
  'stopwatch': Icons.timer_rounded,
  'theme': Icons.palette_rounded,
  'timer': Icons.schedule_rounded,
  'tune': Icons.tune_rounded,
  'undo': Icons.undo_rounded,
  'weeks': Icons.date_range_rounded,
};

/// 兼容旧调用 `MiuixIcons.extended.byName(name[, weight])`。
/// 字重参数被忽略：Material Icons 只有单字重。
IconData? miuixIconByName(String name, [Object? weight]) =>
    kMiuixIconByName[name];

/// 兼容旧调用 `MiuixIcons.extended.names`。
final List<String> kMiuixIconNames = kMiuixIconByName.keys.toList(
  growable: false,
);