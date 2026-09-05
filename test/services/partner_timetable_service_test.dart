import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_timetable/models/course.dart';
import 'package:university_timetable/models/course_task.dart';
import 'package:university_timetable/models/exam.dart';
import 'package:university_timetable/models/schedule_item.dart';
import 'package:university_timetable/models/timetable_profile.dart';
import 'package:university_timetable/models/timetable_settings.dart';
import 'package:university_timetable/services/data_transfer_service.dart';
import 'package:university_timetable/services/partner_timetable_service.dart';
import 'package:university_timetable/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storageService;
  late DataTransferService dataTransferService;
  late PartnerTimetableService partnerService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storageService = StorageService();
    storageService.resetForTesting();
    await storageService.init();
    dataTransferService = DataTransferService();
    partnerService = PartnerTimetableService(
      storageService: storageService,
      dataTransferService: dataTransferService,
    );

    final defaultProfile = TimetableProfile(
      id: 'default',
      name: '默认课表',
      courses: const [],
      settings: TimetableSettings.defaults(),
      currentWeek: 1,
      createdAt: DateTime(2026, 7, 8),
      lastUsedAt: DateTime(2026, 7, 8),
    );
    await storageService.saveProfiles([defaultProfile]);
    await storageService.setActiveProfileId('default');
  });

  test('imports partner timetable from single profile backup', () async {
    final content = dataTransferService.buildBackupJson(
      profileName: '小明的课表',
      courses: [
        Course(
          id: 'c1',
          name: '高数',
          teacher: '张老师',
          location: 'A101',
          dayOfWeek: 1,
          startSection: 1,
          endSection: 2,
          startTime: '08:00',
          endTime: '09:40',
        ),
      ],
      settings: TimetableSettings.defaults(),
      currentWeek: 3,
    );

    final result = await partnerService.importFromContent(content);

    expect(result.kind, PartnerImportResultKind.created);
    expect(result.profile.isPartnerImported, isTrue);
    expect(result.profile.courses.single.name, '高数');
    expect(result.binding.partnerName, '小明的课表');

    final profiles = await storageService.getProfiles();
    expect(
      profiles.any(
        (profile) => profile.id == PartnerTimetableService.partnerProfileId,
      ),
      isTrue,
    );
    expect(await storageService.getPartnerTimetableBinding(), isNotNull);
  });

  test('updates existing partner profile on re-import', () async {
    final first = dataTransferService.buildBackupJson(
      profileName: 'TA',
      courses: [
        Course(
          id: 'c1',
          name: '高数',
          teacher: '张老师',
          location: 'A101',
          dayOfWeek: 1,
          startSection: 1,
          endSection: 2,
          startTime: '08:00',
          endTime: '09:40',
        ),
      ],
      settings: TimetableSettings.defaults(),
      currentWeek: 1,
    );
    await partnerService.importFromContent(first);

    final second = dataTransferService.buildBackupJson(
      profileName: 'TA',
      courses: [
        Course(
          id: 'c2',
          name: '英语',
          teacher: '李老师',
          location: 'B202',
          dayOfWeek: 2,
          startSection: 3,
          endSection: 4,
          startTime: '10:00',
          endTime: '11:40',
        ),
      ],
      settings: TimetableSettings.defaults(),
      currentWeek: 2,
    );
    final result = await partnerService.importFromContent(second);

    expect(result.kind, PartnerImportResultKind.updated);
    expect(result.profile.courses.single.name, '英语');
    expect(result.profile.currentWeek, 2);
  });

  test('re-import merges changed courses by stable id', () async {
    final first = dataTransferService.buildBackupJson(
      profileName: 'TA',
      courses: [
        Course(
          id: 'c1',
          name: 'Math',
          teacher: 'Teacher A',
          location: 'A101',
          dayOfWeek: 1,
          startSection: 1,
          endSection: 2,
          startTime: '08:00',
          endTime: '09:40',
        ),
        Course(
          id: 'c2',
          name: 'English',
          teacher: 'Teacher B',
          location: 'B202',
          dayOfWeek: 2,
          startSection: 3,
          endSection: 4,
          startTime: '10:00',
          endTime: '11:40',
        ),
        Course(
          id: 'c3',
          name: 'Physics',
          teacher: 'Teacher C',
          location: 'C303',
          dayOfWeek: 3,
          startSection: 5,
          endSection: 6,
          startTime: '14:00',
          endTime: '15:40',
        ),
      ],
      settings: TimetableSettings.defaults(),
      currentWeek: 1,
    );
    await partnerService.importFromContent(first);

    final second = dataTransferService.buildBackupJson(
      profileName: 'TA',
      courses: [
        Course(
          id: 'c1',
          name: 'Math',
          teacher: 'Teacher A Updated',
          location: 'D404',
          dayOfWeek: 1,
          startSection: 1,
          endSection: 2,
          startTime: '08:00',
          endTime: '09:40',
        ),
        Course(
          id: 'c2',
          name: 'English',
          teacher: 'Teacher B',
          location: 'B202',
          dayOfWeek: 2,
          startSection: 3,
          endSection: 4,
          startTime: '10:00',
          endTime: '11:40',
        ),
        Course(
          id: 'c4',
          name: 'Chemistry',
          teacher: 'Teacher D',
          location: 'E505',
          dayOfWeek: 4,
          startSection: 7,
          endSection: 8,
          startTime: '16:00',
          endTime: '17:40',
        ),
      ],
      settings: TimetableSettings.defaults(),
      currentWeek: 2,
    );

    final result = await partnerService.importFromContent(second);

    expect(result.kind, PartnerImportResultKind.updated);
    expect(result.profile.courses.map((course) => course.id), [
      'c1',
      'c2',
      'c4',
    ]);
    expect(
      result.profile.courses.firstWhere((course) => course.id == 'c1').teacher,
      'Teacher A Updated',
    );
    expect(
      result.profile.courses.firstWhere((course) => course.id == 'c2').location,
      'B202',
    );
    expect(result.profile.courses.any((course) => course.id == 'c3'), isFalse);
  });

  test('re-import incrementally merges tasks, schedule items, and exams', () async {
    final createdAt = DateTime(2026, 7, 8);
    final first = dataTransferService.buildBackupJson(
      profileName: 'TA',
      courses: const [],
      tasks: [
        CourseTask(
          id: 't1',
          title: 'Math homework',
          isCompleted: false,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
        CourseTask(
          id: 't2',
          title: 'Physics lab',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      ],
      scheduleItems: [
        ScheduleItem(
          id: 's1',
          title: 'Club meeting',
          location: 'A101',
          startDate: createdAt,
          endDate: createdAt,
          startTime: '18:00',
          endTime: '19:00',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
        ScheduleItem(
          id: 's2',
          title: 'Exam review',
          startDate: createdAt.add(const Duration(days: 1)),
          startTime: '20:00',
          endTime: '21:00',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      ],
      exams: [
        Exam(
          id: 'e1',
          courseId: 'c1',
          name: 'Math exam',
          dateTime: createdAt.add(const Duration(days: 2)),
          startTime: '09:00',
          endTime: '11:00',
          location: 'A201',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
        Exam(
          id: 'e2',
          courseId: 'c2',
          name: 'Physics exam',
          dateTime: createdAt.add(const Duration(days: 3)),
          startTime: '14:00',
          endTime: '16:00',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      ],
      settings: TimetableSettings.defaults(),
      currentWeek: 1,
    );
    await partnerService.importFromContent(first);

    final second = dataTransferService.buildBackupJson(
      profileName: 'TA',
      courses: const [],
      tasks: [
        CourseTask(
          id: 't1',
          title: 'Math homework',
          isCompleted: true,
          createdAt: createdAt,
          updatedAt: createdAt.add(const Duration(hours: 1)),
        ),
        CourseTask(
          id: 't3',
          title: 'Chemistry report',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      ],
      scheduleItems: [
        ScheduleItem(
          id: 's1',
          title: 'Club meeting',
          location: 'B202',
          startDate: createdAt,
          endDate: createdAt,
          startTime: '18:00',
          endTime: '19:00',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
        ScheduleItem(
          id: 's3',
          title: 'Dinner',
          startDate: createdAt.add(const Duration(days: 4)),
          startTime: '19:30',
          endTime: '20:30',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      ],
      exams: [
        Exam(
          id: 'e1',
          courseId: 'c1',
          name: 'Math exam',
          dateTime: createdAt.add(const Duration(days: 2)),
          startTime: '09:00',
          endTime: '11:00',
          location: 'C303',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
        Exam(
          id: 'e3',
          courseId: 'c3',
          name: 'Chemistry exam',
          dateTime: createdAt.add(const Duration(days: 5)),
          startTime: '10:00',
          endTime: '12:00',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      ],
      settings: TimetableSettings.defaults(),
      currentWeek: 2,
    );

    final result = await partnerService.importFromContent(second);

    expect(result.kind, PartnerImportResultKind.updated);
    expect(result.profile.tasks.map((task) => task.id), ['t1', 't3']);
    expect(
      result.profile.tasks.firstWhere((task) => task.id == 't1').isCompleted,
      isTrue,
    );
    expect(
      result.profile.scheduleItems.map((item) => item.id),
      ['s1', 's3'],
    );
    expect(
      result.profile.scheduleItems
          .firstWhere((item) => item.id == 's1')
          .location,
      'B202',
    );
    expect(result.profile.exams.map((exam) => exam.id), ['e1', 'e3']);
    expect(
      result.profile.exams.firstWhere((exam) => exam.id == 'e1').location,
      'C303',
    );
  });

  test('re-import preserves partner week offset', () async {
    final content = dataTransferService.buildBackupJson(
      profileName: 'TA',
      courses: const [],
      settings: TimetableSettings.defaults(),
      currentWeek: 1,
    );
    await partnerService.importFromContent(content);
    final binding = await storageService.getPartnerTimetableBinding();
    expect(binding, isNotNull);
    await storageService.savePartnerTimetableBinding(
      binding!.copyWith(weekOffset: 2),
    );

    await partnerService.importFromContent(content);
    final updated = await storageService.getPartnerTimetableBinding();
    expect(updated?.weekOffset, 2);
  });

  test('re-import preserves partner couple colors', () async {
    final content = dataTransferService.buildBackupJson(
      profileName: 'TA',
      courses: const [],
      settings: TimetableSettings.defaults(),
      currentWeek: 1,
    );
    await partnerService.importFromContent(content);
    final binding = await storageService.getPartnerTimetableBinding();
    await storageService.savePartnerTimetableBinding(
      binding!.copyWith(
        mineColorHex: '#FF5722',
        partnerColorHex: '#4CAF50',
        togetherColorHex: '#00BCD4',
      ),
    );

    await partnerService.importFromContent(content);
    final updated = await storageService.getPartnerTimetableBinding();
    expect(updated?.mineColorHex, '#FF5722');
    expect(updated?.partnerColorHex, '#4CAF50');
    expect(updated?.togetherColorHex, '#00BCD4');
  });

  test('unlink removes partner profile and binding', () async {
    final content = dataTransferService.buildBackupJson(
      profileName: 'TA',
      courses: const [],
      settings: TimetableSettings.defaults(),
      currentWeek: 1,
    );
    await partnerService.importFromContent(content);
    await partnerService.unlink();

    final profiles = await storageService.getProfiles();
    expect(
      profiles.any(
        (profile) => profile.id == PartnerTimetableService.partnerProfileId,
      ),
      isFalse,
    );
    expect(await storageService.getPartnerTimetableBinding(), isNull);
  });
}
