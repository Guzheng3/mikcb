import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../logging/app_debug_log.dart';
import '../logging/app_log_messages.dart';
import 'app_log_service.dart';

enum CoupleTimetableWidgetStatus { ok, coupleModeOff, notLoggedIn }

extension CoupleTimetableWidgetStatusX on CoupleTimetableWidgetStatus {
  String get value {
    switch (this) {
      case CoupleTimetableWidgetStatus.ok:
        return 'ok';
      case CoupleTimetableWidgetStatus.coupleModeOff:
        return 'couple_mode_off';
      case CoupleTimetableWidgetStatus.notLoggedIn:
        return 'not_logged_in';
    }
  }
}

class CoupleTimetableWidgetBreak {
  final String startTime;
  final String endTime;

  const CoupleTimetableWidgetBreak({
    required this.startTime,
    required this.endTime,
  });

  Map<String, dynamic> toJson() {
    return {'startTime': startTime, 'endTime': endTime};
  }
}

class CoupleTimetableWidgetCourse {
  final String id;
  final String name;
  final String? shortName;
  final String location;
  final String color;
  final int startSection;
  final int endSection;
  final String startTime;
  final String endTime;
  final List<CoupleTimetableWidgetBreak> breaks;

  const CoupleTimetableWidgetCourse({
    required this.id,
    required this.name,
    required this.shortName,
    required this.location,
    required this.color,
    required this.startSection,
    required this.endSection,
    required this.startTime,
    required this.endTime,
    required this.breaks,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'shortName': shortName,
      'location': location,
      'color': color,
      'startSection': startSection,
      'endSection': endSection,
      'startTime': startTime,
      'endTime': endTime,
      'breaks': breaks.map((breakTime) => breakTime.toJson()).toList(),
    };
  }
}

class CoupleTimetableWidgetDayCourses {
  final List<CoupleTimetableWidgetCourse> today;
  final List<CoupleTimetableWidgetCourse> tomorrow;

  const CoupleTimetableWidgetDayCourses({
    required this.today,
    required this.tomorrow,
  });

  Map<String, dynamic> toJson() {
    return {
      'today': today.map((course) => course.toJson()).toList(),
      'tomorrow': tomorrow.map((course) => course.toJson()).toList(),
    };
  }
}

class CoupleTimetableWidgetSnapshot {
  static const String defaultMyName = 'xoveg';
  static const String defaultPartnerName = 'govex';

  final String myName;
  final String partnerName;
  final String? leftColorHex;
  final String? rightColorHex;
  final CoupleTimetableWidgetStatus status;
  final int generatedAtMillis;
  final CoupleTimetableWidgetDayCourses mine;
  final CoupleTimetableWidgetDayCourses partner;

  const CoupleTimetableWidgetSnapshot({
    required this.myName,
    required this.partnerName,
    required this.leftColorHex,
    required this.rightColorHex,
    required this.status,
    required this.generatedAtMillis,
    required this.mine,
    required this.partner,
  });

  factory CoupleTimetableWidgetSnapshot.unavailable(
    CoupleTimetableWidgetStatus status,
  ) {
    return CoupleTimetableWidgetSnapshot(
      myName: defaultMyName,
      partnerName: defaultPartnerName,
      leftColorHex: null,
      rightColorHex: null,
      status: status,
      generatedAtMillis: DateTime.now().millisecondsSinceEpoch,
      mine: const CoupleTimetableWidgetDayCourses(today: [], tomorrow: []),
      partner: const CoupleTimetableWidgetDayCourses(today: [], tomorrow: []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'myName': myName,
      'partnerName': partnerName,
      'leftColorHex': leftColorHex,
      'rightColorHex': rightColorHex,
      'status': status.value,
      'generatedAtMillis': generatedAtMillis,
      'mine': mine.toJson(),
      'partner': partner.toJson(),
    };
  }

  Map<String, dynamic> toDedupJson() {
    final payload = toJson();
    payload.remove('generatedAtMillis');
    return payload;
  }
}

class CoupleTimetableWidgetService {
  CoupleTimetableWidgetService._();

  static const MethodChannel _channel = MethodChannel(
    'com.mutx163.qingyu/home_widget',
  );

  static String? _lastPushedPayload;

  static Future<void> syncSnapshot(
    CoupleTimetableWidgetSnapshot snapshot,
  ) async {
    final payload = jsonEncode(snapshot.toDedupJson());
    if (payload == _lastPushedPayload) {
      return;
    }
    try {
      await _channel.invokeMethod('syncCoupleSnapshot', snapshot.toJson());
      _lastPushedPayload = payload;
    } on MissingPluginException {
      // The channel is only implemented by the Android host.
    } catch (e) {
      unawaited(
        AppLogService.instance.warn(
          'couple_widget_sync_failed',
          AppLogMessages.homeWidgetSyncFailed,
          extras: {'error': '$e'},
        ),
      );
      appDebugLog('CoupleTimetableWidget', 'sync snapshot failed: $e');
    }
  }

  static Future<void> clearSnapshot() async {
    _lastPushedPayload = null;
    try {
      await _channel.invokeMethod('clearCoupleSnapshot');
    } on MissingPluginException {
      // The channel is only implemented by the Android host.
    } catch (e) {
      unawaited(
        AppLogService.instance.warn(
          'couple_widget_clear_failed',
          AppLogMessages.homeWidgetClearFailed,
          extras: {'error': '$e'},
        ),
      );
      appDebugLog('CoupleTimetableWidget', 'clear snapshot failed: $e');
    }
  }
}
