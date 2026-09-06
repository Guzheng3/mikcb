import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:university_timetable/l10n/app_localizations.dart';
import 'package:university_timetable/providers/withu_couple_session_provider.dart';
import 'package:university_timetable/providers/timetable_provider.dart';
import 'package:university_timetable/services/holiday_service.dart';
import 'package:university_timetable/ui/hyperos/hyperos_navigation.dart';

class TestApp extends StatelessWidget {
  final Widget home;

  /// 可选的 withU 情侣会话 Provider（首页情侣标题数据源）。默认提供
  /// 未登录态实例——不主动 restore，测试不会触碰网络/安全存储。
  final WithuCoupleSessionProvider? sessionProvider;
  const TestApp({super.key, required this.home, this.sessionProvider});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      navigatorObservers: [hyperosRouteObserver],
      builder: (context, child) {
        return ScaffoldMessenger(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            resizeToAvoidBottomInset: false,
            body: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: ChangeNotifierProvider<WithuCoupleSessionProvider>(
        create: (_) => sessionProvider ?? WithuCoupleSessionProvider(),
        child: home,
      ),
    );
  }
}

/// Escape the testWidgets FakeAsync zone for SharedPreferences / HTTP.
Future<T> runRealAsync<T>(
  WidgetTester tester,
  Future<T> Function() action,
) async {
  final result = await tester.runAsync(action);
  return result as T;
}

/// Provider ready for widget tests without hanging on FakeAsync I/O.
Future<TimetableProvider> createInitializedTestProvider(
  WidgetTester tester,
) async {
  // Mock holiday HTTP so getDataForYear never blocks on network inside
  // testWidgets FakeAsync (where Future.timeout is dilatated).
  // xiaoai returns {code, data:[]}, fallback ailcc expects {code, holiday:{}}.
  // Return empty list so both paths are fast and valid regardless of URL.
  final mockHolidayClient = MockClient((request) async {
    final url = request.url.toString();
    if (url.contains('ailcc')) {
      return http.Response('{"code":0,"holiday":{}}', 200);
    }
    return http.Response('{"code":0,"data":[]}', 200);
  });
  final holidayService = HolidayService(client: mockHolidayClient);
  late TimetableProvider provider;
  await tester.runAsync(() async {
    provider = TimetableProvider(
      autoInitialize: false,
      enableLiveActivitySync: false,
      holidayService: holidayService,
    );
    await provider.initialize();
  });
  return provider;
}
