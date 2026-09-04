import 'dart:convert';

import 'package:crypto/crypto.dart';

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

  Future<WithuCoupleConfig> loadConfig() => _configStore.load();

  Future<void> disconnect() async {
    await _authService.disconnect();
    final config = await _configStore.load();
    await _configStore.save(
      config.copyWith(
        clearLastPulledAt: true,
        clearLastRemoteContentHash: true,
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

  Future<String?> uploadMyTimetableForPartner({
    required TimetableProvider provider,
  }) async {
    if (await _authService.loadSession() == null) {
      return 'withu_couple_not_connected';
    }

    try {
      await provider.initialize();
      final content = _dataTransferService.buildBackupJson(
        profileName: provider.activeProfile?.name,
        courses: provider.courses,
        scheduleItems: provider.scheduleItems,
        settings: provider.settings,
        currentWeek: provider.currentWeek,
      );
      final decodedContent = jsonDecode(content);
      if (decodedContent is! Map) {
        return 'withu_invalid_response';
      }
      await _authService.postJson('save', {'content': decodedContent});
      return null;
    } on WithuCoupleApiException catch (error) {
      return error.code;
    } on FormatException catch (error) {
      return _errorCode(error);
    } catch (_) {
      return 'withu_request_failed';
    }
  }

  String _errorCode(FormatException error) => error.message.startsWith('withu_')
      ? error.message
      : 'withu_invalid_response';
}
