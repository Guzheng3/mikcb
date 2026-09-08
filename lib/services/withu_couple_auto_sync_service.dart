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
    this.pullOnBind = true,
    this.pullInterval = const Duration(seconds: 30),
    // ignore: prefer_initializing_formals
  }) : _timetableService = timetableService;

  final WithuCoupleTimetableService _timetableService;
  final Duration debounceDelay;
  final bool pullOnBind;
  final Duration pullInterval;

  TimetableProvider? _provider;
  Timer? _debounceTimer;
  Timer? _pullTimer;
  String? _lastTimetableHash;
  String? _lastSettingsHash;
  bool _isSyncing = false;
  bool _hasPendingSync = false;

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
      unawaited(pullPartnerChanges());
    });

    if (pullOnBind) {
      unawaited(_pullPartnerOnBind(provider));
    }
  }

  Future<void> syncNow() async {
    final provider = _provider;
    if (provider == null || _isSyncing) {
      _hasPendingSync = true;
      return;
    }
    if (!await _hasSavedSession()) {
      return;
    }

    _isSyncing = true;
    try {
      final timetableHash = _timetableHash(provider);
      final settingsHash = _settingsHash(provider);
      final shouldUploadTimetable = timetableHash != _lastTimetableHash;
      final shouldUploadSettings = settingsHash != _lastSettingsHash;

      if (shouldUploadTimetable) {
        final error = await _timetableService.uploadMyTimetableForPartner(
          provider: provider,
          packageId: 'withu-couple-timetable',
        );
        if (error == null) {
          _lastTimetableHash = timetableHash;
        } else {
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

    if (_hasPendingSync) {
      _hasPendingSync = false;
      _scheduleSync();
    }
  }

  Future<void> handleAppResumed() {
    return pullPartnerChanges();
  }

  Future<void> pullPartnerChanges() async {
    final provider = _provider;
    if (provider == null || _isSyncing) {
      return;
    }
    if (!await _hasSavedSession()) {
      return;
    }

    _isSyncing = true;
    try {
      final result = await _timetableService.pullPartnerTimetable(
        provider: provider,
      );
      if (result.status == WithuCouplePullStatus.failed) {
        _logSyncError('withu_auto_partner_pull_failed', result.errorCode ?? '');
      }
    } finally {
      _isSyncing = false;
    }
  }

  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pullTimer?.cancel();
    _pullTimer = null;
    _provider?.removeListener(_handleProviderChanged);
    _provider = null;
  }

  Future<void> _pullPartnerOnBind(TimetableProvider provider) async {
    if (!await _hasSavedSession()) {
      return;
    }

    final result = await _timetableService.pullPartnerTimetable(
      provider: provider,
      force: true,
    );
    if (result.status == WithuCouplePullStatus.failed) {
      _logSyncError('withu_auto_partner_pull_failed', result.errorCode ?? '');
    }
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

  void _scheduleSync() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDelay, () {
      unawaited(syncNow());
    });
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
        'semesterStartDate': myProfile.settings.semesterStartDate,
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
