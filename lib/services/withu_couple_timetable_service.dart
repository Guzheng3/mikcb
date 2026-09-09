import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/timetable_profile.dart';
import '../models/couple_timetable_history.dart';
import '../providers/timetable_provider.dart';
import 'data_transfer_service.dart';
import 'withu_couple_auth_service.dart';
import 'withu_couple_config.dart';

enum WithuCouplePullStatus { imported, updated, unchanged, failed }

class WithuCouplePullResult {
  final WithuCouplePullStatus status;
  final String? errorCode;
  final String? importKind;

  const WithuCouplePullResult({
    required this.status,
    this.errorCode,
    this.importKind,
  });
}

class WithuCoupleTimetableService {
  WithuCoupleTimetableService({
    required this._authService,
    WithuCoupleConfigStore? configStore,
    DataTransferService? dataTransferService,
  }) : _configStore = configStore ?? const WithuCoupleConfigStore(),
       _dataTransferService = dataTransferService ?? DataTransferService();

  final WithuCoupleAuthService _authService;
  final WithuCoupleConfigStore _configStore;
  final DataTransferService _dataTransferService;

  WithuCoupleAuthService get authService => _authService;

  Future<WithuCoupleConfig> loadConfig() => _configStore.load();

  Future<void> disconnect() async {
    await _authService.disconnect();
    final config = await _configStore.load();
    await _configStore.save(
      config.copyWith(
        clearLastPulledAt: true,
        clearLastRemoteContentHash: true,
        clearLastMyTimetableHash: true,
        clearLastMyTimetableSyncedAt: true,
      ),
    );
  }

  Future<WithuCouplePullResult> pullPartnerTimetable({
    required TimetableProvider provider,
    bool force = false,
  }) async {
    final config = await loadConfig();
    if (await _authService.loadSession() == null) {
      return const WithuCouplePullResult(
        status: WithuCouplePullStatus.failed,
        errorCode: 'withu_couple_not_connected',
      );
    }

    try {
      final payload = await _authService.getJson('partner');
      if (payload['partner'] == null) {
        return const WithuCouplePullResult(
          status: WithuCouplePullStatus.unchanged,
        );
      }
      final rawPartnerTimetable = payload['partner_timetable'];
      if (rawPartnerTimetable is! Map ||
          rawPartnerTimetable['content'] is! Map) {
        return const WithuCouplePullResult(
          status: WithuCouplePullStatus.failed,
          errorCode: 'withu_partner_timetable_missing',
        );
      }

      final content = jsonEncode(rawPartnerTimetable['content']);
      if (_dataTransferService.isFullBackupJson(content)) {
        return const WithuCouplePullResult(
          status: WithuCouplePullStatus.failed,
          errorCode: 'partner_import_requires_single_profile',
        );
      }

      final contentHash =
          rawPartnerTimetable['content_hash'] as String? ??
          sha256.convert(utf8.encode(content)).toString();
      if (!force &&
          config.lastRemoteContentHash == contentHash &&
          provider.hasPartnerBinding) {
        await provider.syncCoupleTimetableWidgetSnapshot();
        return const WithuCouplePullResult(
          status: WithuCouplePullStatus.unchanged,
        );
      }

      final rawPartner = payload['partner'];
      final partnerName = rawPartner is Map
          ? WithuCoupleUser.fromJson(
              Map<String, dynamic>.from(rawPartner),
            ).displayName
          : null;
      final importResult = await provider.importPartnerTimetable(
        content,
        partnerName: partnerName,
      );
      await _configStore.save(
        config.copyWith(
          lastPulledAt: DateTime.now(),
          lastRemoteContentHash: contentHash,
        ),
      );
      await provider.syncCoupleTimetableWidgetSnapshot();
      return WithuCouplePullResult(
        status: importResult.kind.name == 'created'
            ? WithuCouplePullStatus.imported
            : WithuCouplePullStatus.updated,
        importKind: importResult.kind.name,
      );
    } on FormatException catch (error) {
      return WithuCouplePullResult(
        status: WithuCouplePullStatus.failed,
        errorCode: _errorCode(error),
      );
    } on WithuCoupleApiException catch (error) {
      return WithuCouplePullResult(
        status: WithuCouplePullStatus.failed,
        errorCode: error.code,
      );
    } catch (_) {
      return const WithuCouplePullResult(
        status: WithuCouplePullStatus.failed,
        errorCode: 'withu_request_failed',
      );
    }
  }

  Future<WithuCouplePullResult> pullMyTimetable({
    required TimetableProvider provider,
  }) async {
    if (await _authService.loadSession() == null) {
      return const WithuCouplePullResult(
        status: WithuCouplePullStatus.failed,
        errorCode: 'withu_couple_not_connected',
      );
    }

    try {
      final payload = await _authService.getJson('bootstrap');
      final rawMyTimetable = payload['timetable'];
      if (rawMyTimetable is! Map || rawMyTimetable['content'] is! Map) {
        return const WithuCouplePullResult(
          status: WithuCouplePullStatus.unchanged,
        );
      }

      final cloudContent = rawMyTimetable['content'];
      final cloudContentJson = jsonEncode(cloudContent);
      if (_dataTransferService.isFullBackupJson(cloudContentJson)) {
        return const WithuCouplePullResult(
          status: WithuCouplePullStatus.failed,
          errorCode: 'withu_my_timetable_requires_single_profile',
        );
      }

      final localPackage = await _buildMyTimetablePackage(provider);
      final localContent = localPackage?.content;
      final localHash = localContent == null
          ? null
          : sha256.convert(utf8.encode(localContent)).toString();
      final config = await loadConfig();
      final localChanged =
          localHash == null || localHash != config.lastMyTimetableHash;
      final localIsNewer =
          localChanged &&
          !_cloudIsNewerThanLocal(config: config, payload: payload);
      if (localContent != null &&
          _jsonEquals(jsonDecode(localContent), cloudContent)) {
        return const WithuCouplePullResult(
          status: WithuCouplePullStatus.unchanged,
        );
      }
      if (localIsNewer) {
        return const WithuCouplePullResult(
          status: WithuCouplePullStatus.unchanged,
        );
      }

      final restored = await provider.restoreMyTimetable(cloudContentJson);
      if (restored) {
        await _rememberSyncedMyTimetable(provider: provider);
      }
      return WithuCouplePullResult(
        status: restored
            ? WithuCouplePullStatus.updated
            : WithuCouplePullStatus.unchanged,
      );
    } on FormatException catch (error) {
      return WithuCouplePullResult(
        status: WithuCouplePullStatus.failed,
        errorCode: _errorCode(error),
      );
    } on WithuCoupleApiException catch (error) {
      return WithuCouplePullResult(
        status: WithuCouplePullStatus.failed,
        errorCode: error.code,
      );
    } catch (_) {
      return const WithuCouplePullResult(
        status: WithuCouplePullStatus.failed,
        errorCode: 'withu_request_failed',
      );
    }
  }

  Future<List<CoupleTimetableHistoryEntry>> fetchMyHistory() async {
    if (await _authService.loadSession() == null) {
      return const [];
    }

    try {
      final payload = await _authService.getJson('history');
      final rows = payload['history'];
      if (rows is! List) {
        return const [];
      }
      return rows
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (row) => CoupleTimetableHistoryEntry.fromServerJson(
              Map<String, dynamic>.from(row),
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<WithuCouplePullResult> rollbackMyTimetable({
    required TimetableProvider provider,
    required String historyId,
  }) async {
    if (await _authService.loadSession() == null) {
      return const WithuCouplePullResult(
        status: WithuCouplePullStatus.failed,
        errorCode: 'withu_couple_not_connected',
      );
    }

    try {
      final id = int.tryParse(historyId);
      if (id == null || id <= 0) {
        return const WithuCouplePullResult(
          status: WithuCouplePullStatus.failed,
          errorCode: 'withu_invalid_history_entry',
        );
      }
      await _authService.postJson('rollback', {'historyId': id});
      return pullMyTimetable(provider: provider);
    } on WithuCoupleApiException catch (error) {
      return WithuCouplePullResult(
        status: WithuCouplePullStatus.failed,
        errorCode: error.code,
      );
    } catch (_) {
      return const WithuCouplePullResult(
        status: WithuCouplePullStatus.failed,
        errorCode: 'withu_request_failed',
      );
    }
  }

  Future<WithuCouplePullResult> syncAfterLogin({
    required TimetableProvider provider,
  }) async {
    final pullMyResult = await pullMyTimetable(provider: provider);
    if (pullMyResult.status == WithuCouplePullStatus.failed) {
      return pullMyResult;
    }

    final uploadError = await uploadMyTimetableForPartner(provider: provider);
    final pullResult = await pullPartnerTimetable(
      provider: provider,
      force: true,
    );
    if (uploadError != null) {
      return WithuCouplePullResult(
        status: WithuCouplePullStatus.failed,
        errorCode: uploadError,
      );
    }
    return pullResult;
  }

  Future<String?> uploadMyTimetableForPartner({
    required TimetableProvider provider,
    String? packageId,
  }) async {
    if (await _authService.loadSession() == null) {
      return 'withu_couple_not_connected';
    }

    try {
      await provider.initialize();
      // 上传的是「我的课表」：当前课表停在 TA 时不能把 TA 的课表传给对方。
      final myProfile = provider.myTimetableProfile;
      if (myProfile == null) {
        return 'withu_couple_not_connected';
      }
      final content = _dataTransferService.buildBackupJson(
        profileName: myProfile.name,
        courses: myProfile.courses,
        scheduleItems: myProfile.scheduleItems,
        settings: _dataTransferService.sanitizeSettingsForPartnerSync(
          myProfile.settings,
        ),
        currentWeek: myProfile.currentWeek,
        timeSchemes: provider.timeSchemes,
        scheduleDateRules: provider.scheduleDateRules,
        locationTimeGroups: provider.locationTimeGroups,
        packageId: packageId,
      );
      final decodedContent = jsonDecode(content);
      if (decodedContent is! Map) {
        return 'withu_invalid_response';
      }
      await _authService.postJson('save', {'content': decodedContent});
      await _rememberSyncedMyTimetable(content: content);
      return null;
    } on WithuCoupleApiException catch (error) {
      return error.code;
    } on FormatException catch (error) {
      return _errorCode(error);
    } catch (_) {
      return 'withu_request_failed';
    }
  }

  Future<String?> currentMyTimetableContentHash(
    TimetableProvider provider,
  ) async {
    final package = await _buildMyTimetablePackage(provider);
    if (package == null) {
      return null;
    }
    return _myTimetableContentHash(package.content);
  }

  Future<String?> uploadPersonalSettings({
    required TimetableProvider provider,
  }) async {
    if (await _authService.loadSession() == null) {
      return 'withu_couple_not_connected';
    }

    try {
      await provider.initialize();
      await _authService.postJson('save_settings', {
        'content': provider.settings.toJson(),
      });
      return null;
    } on WithuCoupleApiException catch (error) {
      return error.code;
    } on FormatException catch (error) {
      return _errorCode(error);
    } catch (_) {
      return 'withu_request_failed';
    }
  }

  String _errorCode(FormatException error) {
    final message = error.message.trim();
    return message.isEmpty ? 'withu_invalid_response' : message;
  }

  Future<({String content, TimetableProfile profile})?>
  _buildMyTimetablePackage(
    TimetableProvider provider, {
    String? packageId,
  }) async {
    await provider.initialize();
    // Conflict checks and uploads always target "mine", even while the UI
    // Upload always targets the signed-in user's timetable, even while
    // the UI is displaying the partner timetable.
    final myProfile = provider.myTimetableProfile;
    if (myProfile == null) {
      return null;
    }
    final content = _dataTransferService.buildBackupJson(
      profileName: myProfile.name,
      courses: myProfile.courses,
      scheduleItems: myProfile.scheduleItems,
      settings: _dataTransferService.sanitizeSettingsForPartnerSync(
        myProfile.settings,
      ),
      currentWeek: myProfile.currentWeek,
      timeSchemes: provider.timeSchemes,
      scheduleDateRules: provider.scheduleDateRules,
      locationTimeGroups: provider.locationTimeGroups,
      packageId: packageId,
    );
    return (content: content, profile: myProfile);
  }

  Future<void> _rememberSyncedMyTimetable({
    TimetableProvider? provider,
    String? content,
  }) async {
    final syncedContent =
        content ??
        (provider == null ? null : await _buildMyTimetablePackage(provider))
            ?.content;
    if (syncedContent == null) {
      return;
    }
    final syncedHash = _myTimetableContentHash(syncedContent);
    final config = await _configStore.load();
    await _configStore.save(
      config.copyWith(
        lastMyTimetableHash: syncedHash,
        lastMyTimetableSyncedAt: DateTime.now(),
      ),
    );
  }

  String _myTimetableContentHash(String content) {
    final decoded = jsonDecode(content);
    if (decoded is Map) {
      final payload = Map<String, dynamic>.from(decoded)
        ..remove('packageId')
        ..remove('exportedAt');
      return sha256.convert(utf8.encode(jsonEncode(payload))).toString();
    }
    return sha256.convert(utf8.encode(content)).toString();
  }

  bool _cloudIsNewerThanLocal({
    required WithuCoupleConfig config,
    required Map<String, dynamic> payload,
  }) {
    final syncedAt = config.lastMyTimetableSyncedAt;
    if (syncedAt == null) {
      return true;
    }

    final rawTimetable = payload['timetable'];
    if (rawTimetable is! Map) {
      return true;
    }
    final serverTime = _parseServerTime(
      rawTimetable['server_time'] as String? ??
          payload['server_time'] as String?,
    );
    final updatedAt = _parseServerTime(rawTimetable['updated_at'] as String?);
    if (serverTime == null || updatedAt == null) {
      return true;
    }

    final cloudAge = serverTime.difference(updatedAt);
    final localAge = DateTime.now().difference(syncedAt);
    return cloudAge < localAge;
  }

  DateTime? _parseServerTime(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value.replaceFirst(' ', 'T'));
  }

  bool _jsonEquals(Object? a, Object? b) {
    if (a is Map && b is Map) {
      if (a.length != b.length) {
        return false;
      }
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_jsonEquals(a[key], b[key])) {
          return false;
        }
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) {
        return false;
      }
      for (var index = 0; index < a.length; index++) {
        if (!_jsonEquals(a[index], b[index])) {
          return false;
        }
      }
      return true;
    }
    return a == b;
  }
}
