import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/partner_timetable_binding.dart';
import '../data/timetable_repository.dart';
import '../models/timetable_profile.dart';
import '../domain/couple_timetable_logic.dart';
import 'data_transfer_service.dart';
import 'storage_service.dart';

enum PartnerImportResultKind { created, updated }

class PartnerImportResult {
  final PartnerImportResultKind kind;
  final PartnerTimetableBinding binding;
  final TimetableProfile profile;

  const PartnerImportResult({
    required this.kind,
    required this.binding,
    required this.profile,
  });
}

class PartnerTimetableService {
  static const String partnerProfileId = 'partner-imported';

  PartnerTimetableService({
    StorageService? storageService,
    DataTransferService? dataTransferService,
  }) : _storageService = storageService ?? StorageService(),
       _dataTransferService = dataTransferService ?? DataTransferService();

  final StorageService _storageService;
  final DataTransferService _dataTransferService;

  /// profiles 变更统一走仓储（阶段 2 收口）：partner RMW 与 provider
  /// 写路径共享同一入口，为后续批量提交 / 分片存储保留单一协调点。
  late final TimetableRepository _profileRepository = TimetableRepository(
    _storageService,
  );

  String computeContentHash(String content) {
    return sha256.convert(utf8.encode(content)).toString();
  }

  List<T> _mergeById<T>(
    List<T> previous,
    List<T> incoming, {
    required String Function(T item) idOf,
    required bool Function(T left, T right) isEqual,
  }) {
    final previousById = <String, T>{
      for (final item in previous)
        if (idOf(item).trim().isNotEmpty) idOf(item): item,
    };
    final incomingIds = <String>{};
    final merged = <T>[];

    for (final item in incoming) {
      final id = idOf(item).trim();
      if (id.isEmpty || incomingIds.add(id)) {
        final previousItem = previousById[id];
        merged.add(
          previousItem != null && isEqual(previousItem, item)
              ? previousItem
              : item,
        );
      }
    }
    return merged;
  }

  Future<PartnerImportResult> importFromContent(
    String content, {
    String? partnerName,
  }) async {
    if (_dataTransferService.isFullBackupJson(content)) {
      throw const FormatException('partner_import_requires_single_profile');
    }

    final backup = _dataTransferService.parsePartnerTimetableJson(content);
    final now = DateTime.now();
    final existingBinding = await _profileRepository
        .getPartnerTimetableBinding();
    final contentHash = computeContentHash(content);

    final displayName = partnerName?.trim().isNotEmpty == true
        ? partnerName!.trim()
        : backup.profileName?.trim().isNotEmpty == true
        ? backup.profileName!.trim()
        : 'TA的课表';

    late final bool isUpdate;
    late final TimetableProfile partnerProfile;

    await _profileRepository.updateProfiles((profiles) {
      isUpdate =
          existingBinding != null &&
          profiles.any((profile) => profile.id == partnerProfileId);
      final previousProfile = isUpdate
          ? profiles.firstWhere((profile) => profile.id == partnerProfileId)
          : null;
      final syncedSettings = _dataTransferService
          .sanitizeSettingsForPartnerSync(backup.settings);

      partnerProfile = TimetableProfile(
        id: partnerProfileId,
        name: displayName,
        courses: _mergeById(
          previousProfile?.courses ?? const [],
          backup.courses,
          idOf: (course) => course.id,
          isEqual: (left, right) =>
              jsonEncode(left.toJson()) == jsonEncode(right.toJson()),
        ),
        tasks: _mergeById(
          previousProfile?.tasks ?? const [],
          backup.tasks,
          idOf: (task) => task.id,
          isEqual: (left, right) =>
              jsonEncode(left.toJson()) == jsonEncode(right.toJson()),
        ),
        scheduleItems: _mergeById(
          previousProfile?.scheduleItems ?? const [],
          backup.scheduleItems,
          idOf: (item) => item.id,
          isEqual: (left, right) =>
              jsonEncode(left.toJson()) == jsonEncode(right.toJson()),
        ),
        exams: _mergeById(
          previousProfile?.exams ?? const [],
          backup.exams,
          idOf: (exam) => exam.id,
          isEqual: (left, right) =>
              jsonEncode(left.toJson()) == jsonEncode(right.toJson()),
        ),
        settings: syncedSettings,
        currentWeek: backup.currentWeek,
        createdAt: isUpdate
            ? profiles
                  .firstWhere((profile) => profile.id == partnerProfileId)
                  .createdAt
            : now,
        lastUsedAt: now,
        profileKind: TimetableProfileKind.partnerImported,
      );

      return [
        for (final profile in profiles)
          if (profile.id != partnerProfileId) profile,
        partnerProfile,
      ];
    });

    final binding = PartnerTimetableBinding(
      partnerProfileId: partnerProfileId,
      partnerName: displayName,
      linkedAt: existingBinding?.linkedAt ?? now,
      lastImportedAt: now,
      sourceFileHash: contentHash,
      weekOffset: existingBinding?.weekOffset ?? 0,
      mineColorHex:
          existingBinding?.mineColorHex ??
          CoupleTimetableLogic.mineColorHexDefault,
      partnerColorHex:
          existingBinding?.partnerColorHex ??
          CoupleTimetableLogic.partnerColorHexDefault,
      togetherColorHex:
          existingBinding?.togetherColorHex ??
          CoupleTimetableLogic.togetherColorHexDefault,
    );

    await _profileRepository.savePartnerTimetableBinding(binding);

    return PartnerImportResult(
      kind: isUpdate
          ? PartnerImportResultKind.updated
          : PartnerImportResultKind.created,
      binding: binding,
      profile: partnerProfile,
    );
  }

  Future<void> unlink() async {
    await _profileRepository.updateProfiles((profiles) {
      return profiles
          .where((profile) => profile.id != partnerProfileId)
          .toList();
    });
    await _profileRepository.savePartnerTimetableBinding(null);
  }
}
