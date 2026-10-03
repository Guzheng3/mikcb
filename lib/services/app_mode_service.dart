import 'storage_service.dart';

/// 应用运行模式（内存单例）。
///
/// 三态由两个事实推导，不在服务里另设开关位：
/// - [offlineMode] == true → 离线模式（数据不上云，隐藏情侣云入口）；
/// - 已登录未绑定 → 单人模式；已登录且已绑定 → 情侣模式（由
///   WithuCoupleSessionProvider 的会话与 partner 字段承载）。
///
/// [offlineMode] 在首启流程（登录页「离线模式」出口）写入，之后只读：
/// 同步读 [offlineMode] 供菜单目录 / 标题栏等无异步上下文的调用方判定，
/// 写入只能走 [setOfflineMode]（落盘 + 更新内存镜像）。
class AppModeService {
  AppModeService._internal();
  static final AppModeService instance = AppModeService._internal();

  bool _offlineMode = false;

  /// 是否处于离线模式。启动管线必须先 [load]（或显式赋值）再进入主界面，
  /// 否则首帧读到的是默认 false。
  bool get offlineMode => _offlineMode;

  /// 启动时从磁盘装载离线标记。
  Future<void> load() async {
    _offlineMode = await StorageService().isOfflineMode();
  }

  /// 写入离线标记（落盘 + 内存镜像同步更新）。
  Future<void> setOfflineMode(bool value) async {
    _offlineMode = value;
    await StorageService().setOfflineMode(value);
  }
}
