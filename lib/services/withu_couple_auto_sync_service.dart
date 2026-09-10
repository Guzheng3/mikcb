import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../providers/timetable_provider.dart';
import 'app_log_service.dart';
import 'withu_couple_timetable_service.dart';

class WithuCoupleAutoSyncService {
  // Named parameter keeps the public API (`timetableService:`); a private
  // initializing formal would rename it, so the assignment stays explicit.
  WithuCoupleAutoSyncService({
    required WithuCoupleTimetableService timetableService,
    this.debounceDelay = const Duration(seconds: 3),
    this.maxDebounceDelay = const Duration(seconds: 15),
    this.pullOnBind = true,
    this.pullInterval = const Duration(seconds: 30),
    // ignore: prefer_initializing_formals
  }) : _timetableService = timetableService;

  final WithuCoupleTimetableService _timetableService;
  final Duration debounceDelay;

  /// 连续编辑的上传上限：从第一次改动算起超过这个时长就立即上传。
  /// 只用 [debounceDelay] 的话，间隔小于它的连续编辑（拖滑块、批量改课）
  /// 会把上传无限往后推。
  final Duration maxDebounceDelay;
  final bool pullOnBind;
  final Duration pullInterval;

  TimetableProvider? _provider;
  Timer? _debounceTimer;
  Timer? _pullTimer;
  String? _lastTimetableHash;
  String? _lastSettingsHash;
  bool _isSyncing = false;
  bool _hasPendingSync = false;
  bool _hasPendingPull = false;

  /// 排队中的请求里是否有「必须跳过本地改动判断」的补传（冷启动补传）。
  bool _pendingForceUpload = false;

  /// 本进程内是否还有本地改动没上传（内存镜像，不写盘）。
  bool _uploadDirty = false;
  DateTime? _dirtySince;

  void bind(TimetableProvider provider) {
    if (identical(_provider, provider)) {
      return;
    }

    _provider?.removeListener(_handleProviderChanged);
    _provider = provider;
    _lastTimetableHash = _timetableHash(provider);
    _lastSettingsHash = _settingsHash(provider);
    provider.addListener(_handleProviderChanged);

    _pullTimer?.cancel();
    _pullTimer = Timer.periodic(pullInterval, (_) {
      // 周期兜底也要推一次：上一次上传失败（离线 / 服务端 5xx）时，本地
      // 改动会一直卡着，只有用户再编辑一次才会重试。
      unawaited(syncNow());
      unawaited(pullPartnerChanges());
    });

    // 上一个进程没来得及上传的本地改动：启动就补传，不等下一次编辑。
    unawaited(_uploadLeftoversFromPreviousSession(provider));

    if (pullOnBind) {
      unawaited(_pullPartner(force: true));
    }
  }

  /// 立即同步一次：本地改动上传 + 设置上传（按 hash 去重，无变化时零请求）。
  ///
  /// [forceTimetableUpload] 跳过「本进程是否看到改动」这一层判断，直接拿
  /// 本地内容与上次同步点比对，用于冷启动补传。
  Future<void> syncNow({bool forceTimetableUpload = false}) async {
    final provider = _provider;
    if (provider == null || _isSyncing) {
      _hasPendingSync = true;
      _pendingForceUpload = _pendingForceUpload || forceTimetableUpload;
      return;
    }
    if (!await _hasSavedSession()) {
      return;
    }

    _isSyncing = true;
    try {
      final timetableHash = _timetableHash(provider);
      final settingsHash = _settingsHash(provider);
      final syncedTimetableHash =
          (await _timetableService.loadConfig()).lastMyTimetableHash;
      var shouldUploadTimetable =
          forceTimetableUpload || timetableHash != _lastTimetableHash;
      if (shouldUploadTimetable) {
        // 只有「本地内容 ≠ 上次同步点」才真的上传，避免把本地旧内容盖回
        // 云端（对方设备可能已经上传过更新的版本）。
        final currentContentHash = await _timetableService
            .currentMyTimetableContentHash(provider);
        shouldUploadTimetable =
            currentContentHash != null &&
            currentContentHash != syncedTimetableHash;
      }
      if (!shouldUploadTimetable) {
        _lastTimetableHash = timetableHash;
        _clearUploadDirty();
      }
      final shouldUploadSettings = settingsHash != _lastSettingsHash;

      if (shouldUploadTimetable) {
        // 记一次尝试窗口：失败后不要每个通知都重试，等周期兜底或下一次编辑。
        _dirtySince = DateTime.now();
        final error = await _timetableService.uploadMyTimetableForPartner(
          provider: provider,
          packageId: 'withu-couple-timetable',
        );
        if (error == null) {
          _lastTimetableHash = timetableHash;
          _clearUploadDirty();
        } else {
          // 保持 dirty：下一个周期 tick / 冷启动补传会重试。
          _logSyncError('withu_auto_timetable_upload_failed', error);
        }
      }

      if (shouldUploadSettings) {
        final error = await _timetableService.uploadPersonalSettings(
          provider: provider,
        );
        if (error == null) {
          _lastSettingsHash = settingsHash;
        } else {
          _logSyncError('withu_auto_settings_upload_failed', error);
        }
      }
    } finally {
      _isSyncing = false;
    }

    _drainPendingRequests();
  }

  Future<void> handleAppResumed() async {
    // 回前台先补掉挂起的本地改动，再拉对方课表。
    await flushPendingSync();
    await pullPartnerChanges();
  }

  /// 立刻上传挂起的本地改动，不等防抖计时器（退到后台 / 退出前调用）。
  Future<void> flushPendingSync() async {
    if (!_uploadDirty) {
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = null;
    await syncNow();
  }

  Future<void> handleAppPaused() => flushPendingSync();

  Future<void> pullPartnerChanges() => _pullPartner(force: false);

  void dispose() {
    final hadPendingUpload =
        _uploadDirty || (_debounceTimer?.isActive ?? false);
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (hadPendingUpload) {
      // 进程即将退出：尽力补一次上传。就算这次没跑完，下次冷启动的
      // [_uploadLeftoversFromPreviousSession] 还会按同步点补传。
      unawaited(syncNow());
    }
    _pullTimer?.cancel();
    _pullTimer = null;
    _provider?.removeListener(_handleProviderChanged);
    _provider = null;
  }

  Future<void> _pullPartner({required bool force}) async {
    final provider = _provider;
    if (provider == null || _isSyncing) {
      // 忙时排队而不是丢弃：回前台拉取与周期拉取经常撞在一起。
      _hasPendingPull = true;
      return;
    }
    if (!await _hasSavedSession()) {
      return;
    }

    _isSyncing = true;
    try {
      final result = await _timetableService.pullPartnerTimetable(
        provider: provider,
        force: force,
      );
      if (result.status == WithuCouplePullStatus.failed) {
        _logSyncError('withu_auto_partner_pull_failed', result.errorCode ?? '');
      }
    } finally {
      _isSyncing = false;
    }

    _drainPendingRequests();
  }

  /// 上一个进程残留的未上传改动：本地内容与「上次同步点」不一致就补传。
  ///
  /// 没有同步点的设备（刚换机登录、还没上传过）不动手，避免把云端更新的
  /// 课表盖回去——那种情况交给显式的登录/立即同步流程按时间戳判断。
  Future<void> _uploadLeftoversFromPreviousSession(
    TimetableProvider provider,
  ) async {
    if (!await _hasSavedSession()) {
      return;
    }
    final config = await _timetableService.loadConfig();
    final syncedHash = config.lastMyTimetableHash;
    if (syncedHash == null) {
      return;
    }
    final currentContentHash = await _timetableService
        .currentMyTimetableContentHash(provider);
    if (currentContentHash == null || currentContentHash == syncedHash) {
      return;
    }
    await syncNow(forceTimetableUpload: true);
  }

  void _handleProviderChanged() {
    _scheduleSync();
  }

  Future<bool> _hasSavedSession() async {
    try {
      return await _timetableService.authService.loadSession() != null;
    } catch (_) {
      return false;
    }
  }

  void _scheduleSync({bool forceTimetableUpload = false}) {
    if (_provider == null) {
      return;
    }
    _uploadDirty = true;
    final now = DateTime.now();
    _dirtySince ??= now;

    _debounceTimer?.cancel();
    final waited = now.difference(_dirtySince!);
    final delay = waited >= maxDebounceDelay ? Duration.zero : debounceDelay;
    _debounceTimer = Timer(delay, () {
      unawaited(syncNow(forceTimetableUpload: forceTimetableUpload));
    });
  }

  void _clearUploadDirty() {
    _uploadDirty = false;
    _dirtySince = null;
  }

  /// 一次同步结束后消费排队中的请求（先补上传，再补拉取）。
  void _drainPendingRequests() {
    if (_hasPendingSync) {
      _hasPendingSync = false;
      final forceUpload = _pendingForceUpload;
      _pendingForceUpload = false;
      _scheduleSync(forceTimetableUpload: forceUpload);
    }
    if (_hasPendingPull) {
      _hasPendingPull = false;
      unawaited(pullPartnerChanges());
    }
  }

  String _timetableHash(TimetableProvider provider) {
    final myProfile = provider.myTimetableProfile;
    if (myProfile == null) {
      return '';
    }
    final payload = {
      'profileName': myProfile.name,
      'courses': myProfile.courses.map((course) => course.toJson()).toList(),
      'scheduleItems': myProfile.scheduleItems
          .map((item) => item.toJson())
          .toList(),
      'currentWeek': myProfile.currentWeek,
      'settings': {
        'sections': myProfile.settings.sections
            .map((section) => section.toJson())
            .toList(),
        'activeTimeSchemeId': myProfile.settings.activeTimeSchemeId,
        'semesterWeekCount': myProfile.settings.semesterWeekCount,
        'semesterStartDate':
            myProfile.settings.semesterStartDate?.millisecondsSinceEpoch,
      },
      'timeSchemes': provider.timeSchemes
          .map((scheme) => scheme.toJson())
          .toList(),
      'scheduleDateRules': provider.scheduleDateRules
          .map((rule) => rule.toJson())
          .toList(),
      'locationTimeGroups': provider.locationTimeGroups
          .map((group) => group.toJson())
          .toList(),
    };
    return sha256.convert(utf8.encode(jsonEncode(payload))).toString();
  }

  String _settingsHash(TimetableProvider provider) {
    return sha256
        .convert(utf8.encode(jsonEncode(provider.settings.toJson())))
        .toString();
  }

  void _logSyncError(String category, String code) {
    unawaited(
      AppLogService.instance.warn(category, code, extras: {'code': code}),
    );
  }
}
