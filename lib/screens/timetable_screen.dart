import 'dart:async';
import 'dart:io';
import 'package:flutter_miuix/miuix.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:university_timetable/ui/hyperos/hyperos.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:animations/animations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show
        Drag,
        DragStartBehavior,
        VelocityTracker,
        kMinFlingVelocity,
        kTouchSlop;
import 'package:flutter/material.dart';
import 'package:university_timetable/l10n/app_localizations.dart';
import 'package:university_timetable/l10n/service_message_localizer.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/class_reminder.dart';
import '../models/course.dart';
import '../models/exam.dart';
import '../models/schedule_item.dart';
import '../models/liquid_glass_tuning.dart';
import '../models/timetable_settings.dart';
import '../providers/timetable_provider.dart';
import '../providers/withu_couple_session_provider.dart';
import '../services/withu_couple_timetable_service.dart';
import '../services/partner_timetable_service.dart';
import '../widgets/class_reminder_sheet.dart';
import 'withu_couple_login_screen.dart';
import '../utils/app_toast.dart';
import '../utils/hex_color.dart';
import '../utils/course_color_palette.dart';
import '../widgets/home_page_region_blur.dart';
import '../utils/home_page_background.dart';
import '../utils/home_startup_visual_primer.dart';
import '../ui/hyperos/liquid/liquid_glass_tokens.dart';
import '../ui/hyperos/liquid/hyperos_liquid_glass_surface.dart'
    show UndimmedBackdropCapture;
import '../widgets/course_action_sheet.dart';
import '../widgets/course_followup_sheets.dart';
import '../widgets/course_note_sheet.dart';
import '../widgets/couple_timetable_history_sheet.dart';
import '../widgets/course_card.dart';
import '../widgets/course_surface.dart';
import '../widgets/course_grid_surface_host.dart';
import '../widgets/home_menu_catalog.dart';
import '../widgets/home_top_menu.dart';
import '../widgets/preblurred_wallpaper_glass.dart';
import '../widgets/profile_quick_switch_sheet.dart';
import '../widgets/week_selector_picker_sheet.dart';
import 'add_course_screen.dart';
import 'add_exam_screen.dart';
import 'add_schedule_item_screen.dart';
import 'course_import_screen.dart';
import 'timetable_profiles_screen.dart';

class TimetableScreen extends StatefulWidget {
  final bool enableProgressTimer;

  const TimetableScreen({super.key, this.enableProgressTimer = true});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

/// Per-pointer flick probe for the day pager. One instance per finger, so
/// overlapping touches can't corrupt each other's velocity read. Besides the
/// debug logging, the probe's displacement/duration feeds the rescue velocity
/// consumed by [_DayPagerFlickRescuePhysics] when the framework tracker
/// starves (see that class for the failure mode).
class _DayPagerFlickProbe {
  _DayPagerFlickProbe(this.tracker, this.downTime, this.downPosition)
    : lastTime = downTime;

  final VelocityTracker tracker;
  final Duration downTime;
  final Offset downPosition;
  Duration lastTime;
  int samples = 1;
}

class _DayViewBlankTapProbe {
  _DayViewBlankTapProbe(this.downTime, this.downPosition);

  final Duration downTime;
  final Offset downPosition;
}

/// Day-pager snap physics with a raw-pointer fallback velocity.
///
/// Failure mode (captured in the `[DayPager]` logs): under frame jank Android
/// delivers batched touch moves once per vsync, so a 50�?00ms flick can reach
/// Dart with fewer than the three samples VelocityTracker needs ? the drag
/// then ends with zero velocity and the page snaps back even though the
/// finger travelled 100+px. When the incoming velocity is below the fling
/// threshold, this physics re-runs the standard PageScrollPhysics snap with
/// the probe's displacement/duration estimate instead of bouncing back.
///
/// Only effective with `pageSnapping: false`: PageView otherwise wraps its
/// own PageScrollPhysics *outside* whatever physics it is given and this
/// override would never be reached. The snap behaviour itself still comes
/// from [_SpringPageScrollPhysics], so page targeting and rescue behavior are
/// unchanged.
typedef _PagerDragStartPageReader = double? Function();

class _DayPagerFlickRescuePhysics extends _SpringPageScrollPhysics {
  const _DayPagerFlickRescuePhysics({
    required this.takeRescueVelocity,
    super.takeDragStartPage,
    super.parent,
  });

  /// One-shot supplier of the scroll-space rescue velocity; 0 = none armed.
  final double Function() takeRescueVelocity;

  @override
  _DayPagerFlickRescuePhysics applyTo(ScrollPhysics? ancestor) {
    return _DayPagerFlickRescuePhysics(
      takeRescueVelocity: takeRescueVelocity,
      takeDragStartPage: takeDragStartPage,
      parent: buildParent(ancestor),
    );
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    var effectiveVelocity = velocity;
    if (velocity.abs() < kMinFlingVelocity) {
      final rescue = takeRescueVelocity();
      if (rescue != 0) {
        if (kDebugMode) {
          debugPrint(
            '[DayPager] rescue: vx=${rescue.toStringAsFixed(1)} '
            '(drag reported ${velocity.toStringAsFixed(1)})',
          );
        }
        effectiveVelocity = rescue;
      }
    }
    return super.createBallisticSimulation(position, effectiveVelocity);
  }
}

/// Page snap physics shared by the timetable pagers.
///
/// Target-page selection matches `PageScrollPhysics`; only release motion uses
/// the app's critically damped MIUI spring, which carries pointer velocity
/// into the settle instead of restarting on a fixed-duration curve.
class _SpringPageScrollPhysics extends PageScrollPhysics {
  const _SpringPageScrollPhysics({
    super.parent,
    this.takeDragStartPage,
    this.settlePeriod = HyperosMiuixAnim.standardSpringPeriod,
  });

  final double settlePeriod;

  /// A short backward drag commits to the neighbor page. The standard 50%
  /// threshold makes the timetable feel inert because most swipes end with
  /// very low pointer velocity after decelerating through the course grid.
  static const double dragSnapFraction = 0.16;
  static const double forwardDragSnapFraction = 0.42;

  final _PagerDragStartPageReader? takeDragStartPage;

  SpringDescription get _spring => SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: math.pow(2 * math.pi / settlePeriod, 2).toDouble(),
  );

  @override
  _SpringPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _SpringPageScrollPhysics(
      takeDragStartPage: takeDragStartPage,
      settlePeriod: settlePeriod,
      parent: buildParent(ancestor),
    );
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    // Defer boundary catch-up to the parent so Android keeps its clamped
    // overscroll behavior.
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }

    final tolerance = toleranceFor(position);
    final pageUnit = position is PageMetrics
        ? math.max(1, position.viewportDimension * position.viewportFraction)
        : math.max(1, position.viewportDimension);
    var page = position.pixels / pageUnit;
    if (velocity < -tolerance.velocity) {
      page -= 0.5;
    } else if (velocity > tolerance.velocity) {
      page += 0.5;
    } else {
      final startPage = takeDragStartPage?.call();
      if (startPage == null) {
        page = page.roundToDouble();
      } else {
        final dragDelta = page - startPage;
        if (dragDelta.abs() >= 0.5) {
          // A long zero-velocity drag still follows standard paging.
          page = page.roundToDouble();
        } else if (dragDelta >= forwardDragSnapFraction) {
          page = startPage + 1;
        } else if (dragDelta <= -dragSnapFraction) {
          page = startPage + dragDelta.sign;
        }
      }
    }

    final target = page.roundToDouble() * pageUnit;
    if (target == position.pixels) {
      return null;
    }
    return ScrollSpringSimulation(
      _spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }
}

class _TimetableScreenState extends State<TimetableScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const int _minWeek = 1;
  static const double _weekDayHeaderHeight = 40;
  static const double _homeTitleHorizontalNudge = 4;
  static const Duration _weekSlideDuration = Duration(milliseconds: 280);
  static const Duration _dayExpandDuration = Duration(milliseconds: 360);
  static const Duration _dayCollapseDuration = Duration(milliseconds: 240);
  static const double _dayViewCardRadius = 20;
  static const Duration _coupleHeartbeatDuration = Duration(milliseconds: 1154);
  static const Duration _coupleBeamDuration = Duration(milliseconds: 3000);
  static const double _coupleLineWidth = 24;

  /// One-shot reveal replaying the week card-pager entrance whenever the
  /// active profile (my/her timetable) switches via the couple title.
  static const Duration _profileSwitchRevealDuration = Duration(
    milliseconds: 290,
  );

  /// 52 bpm: two visual beats per cycle, matching the CSS heartbeat curve.
  static final Animatable<double> _coupleHeartbeatScaleTween =
      TweenSequence<double>([
        TweenSequenceItem(tween: Tween(begin: 1, end: 1.3), weight: 14),
        TweenSequenceItem(tween: Tween(begin: 1.3, end: 1), weight: 14),
        TweenSequenceItem(tween: Tween(begin: 1, end: 1.3), weight: 14),
        TweenSequenceItem(tween: Tween(begin: 1.3, end: 1), weight: 28),
        TweenSequenceItem(tween: ConstantTween(1), weight: 30),
      ]);

  /// 鐜荤拑鍧炶嵂涓稿崰鐢ㄩ珮搴︼細鑽父 56 + 搴曢儴瀹夊�?6锛堣嵂涓搁《鍒板睆骞曞簳鐨勮窛绂伙級銆?
  static const double _glassDockPillOccupancy = 62;

  /// 鐜荤拑鍧炵幓鐠冩潗璐ㄥ疄楠屽紑鍏筹紙鐢ㄦ�?A/B 瀵规瘮鐢級�?
  ///
  /// true = 鍖呭師鐗堥粯璁ゆ潗璐細搴曟爮鏈綋 kBottomBarGlassDefaults銆佹嫋鎷介€忛暅
  /// baseIndicatorSettings锛堣交寰€忛暅寮洸锛夈€乸inch 0.4銆乪xpansion 姘村�?2/
  /// 鍨傜�?銆佽川閲忚嚜閫傚簲锛涘彸渚ф诞閽笌鑽父鏄惧紡鍏辩敤杩欎唤瀹樻柟搴曟爮鏉愯川鈥斺€?
  /// 鍖呫€屽師鐗堛€嶄笅涓よ€呬笉浼犲弬鏃跺唴閮ㄩ粯璁ゅ悇涓嶇浉鍚岋紝浼氬憟鐜扮幓鐠冩柇灞傘�?
  /// 姝ゅ墠鑷畾涔夌殑銆屾媺婊℃姌灏勬嫋鎷介€忛暅銆嶅湪绾�?娴呰壊澹佺焊涓婂憟鍥涘懆鎶樺皠銆?
  /// 涓棿鍏ㄩ€忔槑鐨勩€岀敎鐢滃湀銆嶈鎰燂紝鏁呮暣浣撳洖閫€鍘熺増渚涘姣斻�?
  ///
  /// false = 鏃х殑 mikcb 鑷畾涔夎皟鏍★紙sheetSettingsFor 璺熼殢銆屾恫鎬佺幓鐠冭皟
  /// 鏍°€? dragLensSettings 鎷夋弧鎶樺皠 + pinch 1.0 + premium/minimal 寮哄�?
  /// ? + 娴挳涓庤嵂涓哥粺涓€鏉愯川锛夈€傜敤鎴疯嫢涓嶆弧鎰忓師鐗堣鎰燂紝鏀瑰洖 false 鍗冲�?
  /// 涓€閿繕鍘燂紱纭婊℃剰鍚庡彲鍒犻櫎 false 鍒嗘敮涓庢湰寮€鍏炽�?
  static const bool _kStockDockGlass = true;

  late final PageController _weekPageController;
  late final AnimationController _dayViewExpandController;
  late final AnimationController _coupleHeartbeatController;
  late final AnimationController _coupleBeamController;
  late final AnimationController _profileSwitchController;
  late final Animation<double> _coupleHeartbeatScale;
  final Map<PageController, double> _pagerLastActivePage = {};
  final Map<PageController, double> _pagerLeadDirection = {};
  final Map<int, ScrollController> _weekGridScrollControllers = {};

  /// 鏃ヨ鍥鹃敋鐐瑰睍寮�?鏀惰捣涓庤缃〉鎷栧姩杞満鏈熼棿锛屽崱鐗囩幓鐠?fill 闇€瑕佹瘡甯?
  /// 閲嶉噰鏍凤紙澹佺焊灞忓箷鍥哄畾銆佸崱鐗囩Щ鍔級锛屽惁鍒欑汗鐞嗗仠鐣欏湪鏃т綅缃細
  /// 鍗＄墖宸﹀崐鏄棫澹佺焊銆佸彸鍗婇€忔槑锛堟挄瑁傦級銆?
  late final Listenable _glassDockCardRepaint;

  /// The single day-view pager: pages are globally continuous across weeks
  /// (globalPage = (week-1)*visibleCount + dayIndex), so crossing a week
  /// boundary is an ordinary page transition on the same Scrollable ? the
  /// gesture is never dropped and content follows the finger through the
  /// whole semester.
  PageController? _dayViewPageController;
  final Set<PageController> _pendingDayViewControllerDisposals = {};

  /// Recently disposed controllers are retained only as short-lived tombstones.
  /// A stale replacement frame can still call [_ensureDayViewPageController]
  /// before the old render tree detaches; two post-frame hops are enough to
  /// cover that race without growing for the lifetime of the screen.
  final Set<PageController> _disposedDayViewControllers = {};
  bool _isSyncingWeekPage = false;
  bool _isSyncingDayViewPage = false;
  int? _pendingSyncedWeek;
  int? _lastObservedWeekPage;
  int? _pendingSettledWeek;
  int? _pendingCommittedWeek;
  bool _isCommittingWeek = false;
  late int _visibleWeek;
  late final ValueNotifier<int> _visibleWeekListenable;
  final GlobalKey _timetableSurfaceKey = GlobalKey();

  /// Anchor for the top-right "more" menu popup (positioned below this key).
  final GlobalKey _topMenuButtonKey = GlobalKey();
  TimetableProvider? _lastSyncedProvider;
  String? _lastSyncedProfileId;
  Timer? _dayAgendaProgressTimer;

  /// Minute-of-day the progress heartbeat last forwarded.
  int _lastProgressMinuteOfDay = -1;

  /// Verbose per-build day-view logging. Off by default: rebuilding all
  /// cached pager pages floods the log otherwise (see the heartbeat below).
  /// Flip temporarily when debugging the day view build pipeline.
  static bool logDayViewBuilds = false;

  /// Heartbeat for day-view ongoing-course badges / summary while day view
  /// is open. Deliberately not a setState on this State: only the day pages
  /// rebuild on each tick.
  ///
  /// Everything those pages render depends on wall-clock time at **minute**
  /// resolution (the provider matches "in progress" via hour*60+minute), so
  /// the 1 s probe only forwards a tick when the minute actually rolled over.
  /// Ticking every second used to rebuild all three cached pager pages with
  /// byte-identical output ? log flood plus wasted list-rebuild CPU.
  final ValueNotifier<int> _dayAgendaProgressTick = ValueNotifier<int>(0);

  /// Midpoint preview of the day the pager is heading to. Lets the weekday
  /// header recolour the instant onPageChanged fires, while the full selection
  /// commit still waits for ScrollEnd (_settleDayViewPage). Scoped: only the
  /// header cell row listens.
  final ValueNotifier<(int, int)?> _dayHeaderPreview =
      ValueNotifier<(int, int)?>(null);

  /// Raw-pointer fling meter for the day pager: one probe per finger,
  /// tracking the true displacement/duration the framework tracker loses
  /// when touch batching starves it (see _DayPagerFlickRescuePhysics).
  final Map<int, _DayPagerFlickProbe> _dayPagerFlickProbes =
      <int, _DayPagerFlickProbe>{};

  /// Blank-area tap probes for the day-pager overlay. These raw listeners do
  /// not join the gesture arena, so horizontal page swipes still win normally.
  final Map<int, _DayViewBlankTapProbe> _dayViewBlankTapProbes =
      <int, _DayViewBlankTapProbe>{};

  /// Pointer ids currently over an interactive day-view target (course card,
  /// summary action, etc.). The overlay skips blank-dismiss for these pointers.
  final Set<int> _dayViewInteractivePointerIds = <int>{};

  /// Pending scroll-space rescue velocity, armed on pointer-up and consumed
  /// once by [_dayPagerPhysics] within the same event dispatch.
  double _dayPagerRescueVelocityX = 0;
  DateTime? _dayPagerRescueArmedAt;
  double? _dayPagerDragStartPage;

  /// 鍗曟鎵嬪娍鍙厑璁镐竴娆℃棩鍒囨崲鐐瑰嚮闇囨劅鐨勯棭閿併€俹nPageChanged 鍦ㄦ粦杩囨瘡涓�?
  /// 涓偣鏃堕兘浼氳Е鍙戯細蹇€熺敥鍔ㄤ竴娆¤法涓ら〉銆佹垨鐢╁姩鍚庡脊绨у洖寮瑰啀瓒婅繃涓偣�?
  /// 閮戒細杩炲搷涓ゆ銆傛寚閽堟寜涓?/ 鏄熸湡鏍忔嫋鍔ㄥ紑濮嬫椂閲嶆柊姝﹁锛宻ettle 鎻愪氦鍚庝篃
  /// 閲嶆柊姝﹁锛堣鐩栫函鎯€ч棶棰橈級銆?
  bool _daySwipeHapticFired = false;
  late final _DayPagerFlickRescuePhysics _dayPagerPhysics =
      _DayPagerFlickRescuePhysics(
        takeRescueVelocity: _takeDayPagerRescueVelocity,
        takeDragStartPage: () => _dayPagerDragStartPage,
        parent: const ClampingScrollPhysics(),
      );
  late final _SpringPageScrollPhysics _weekPagerPhysics =
      _SpringPageScrollPhysics(
        takeDragStartPage: () =>
            _weekPagerDragStartPage ?? _weekPagerPendingDragStartPage,
        // OPPO-style home settle: slightly faster than the app-wide spring so
        // the page locks to the finger release without a long visible tail.
        settlePeriod: 0.32,
        parent: const ClampingScrollPhysics(),
      );

  /// Live handle bridging weekday-bar drags into the day pager, so the bar
  /// scrubs the pager follow-finger instead of snapping a week on release.
  /// Nulled via the position's onDragCanceled when the pager disposes the
  /// drag activity mid-gesture (e.g. the cross-week boundary handoff swaps
  /// controllers).
  Drag? _weekdayBarDrag;

  /// Bar鈫抪ager amplification captured at drag start: the bar spans a whole
  /// week, so sweeping its width must carry the pager across every visible
  /// day (7 pages with weekends shown, 5 without).
  double _weekdayBarDragScale = 1;
  int? _selectedDayOfWeek;
  int? _selectedWeekForDayView;
  int? _dayViewTransitionSourceWeek;
  int? _dayViewTransitionSourceDayOfWeek;
  double _weekSwipeDirection = 1;
  double? _weekPagerDragStartPage;

  /// Start page captured at scroll start, but only promoted to
  /// [_weekPagerDragStartPage] once the drag produces real horizontal
  /// movement. A vertical drag on the course grid (which uses
  /// NeverScrollableScrollPhysics) still surfaces as a horizontal
  /// ScrollStart because the week pager's horizontal recognizer wins the
  /// arena; without this gate such a drag would arm the swipe deck and
  /// paint a duplicate settled week beside the pager's real card.
  double? _weekPagerPendingDragStartPage;

  /// the deck's AnimatedBuilder re-runs even though the pager page is
  /// integral (no controller notification fires there).
  final ValueNotifier<int> _weekDeckReleaseTick = ValueNotifier<int>(0);

  /// Guards against scheduling more than one post-frame deck-release pass.
  bool _weekDeckHoldScheduled = false;

  /// Tracks whether the active week deck has already produced a controller
  /// tick. The matching integral-page tick then rebuilds the real PageView in
  /// the same frame instead of leaving only the frozen hold card visible.
  bool _weekDeckSettleRebuildArmed = false;
  bool _weekDeckSettleRebuildScheduled = false;

  /// One drag-generation cache for fully built deck cards. AnimatedBuilder
  /// reruns every frame, but the cached widget instances let Flutter skip the
  /// expensive course-grid build/layout while transforms still track 1:1.
  final Map<int, Widget> _weekDeckCardCache = <int, Widget>{};
  double _daySwipeDirection = 1;
  double _dayViewAnchorFraction = 0.5;
  bool _isDaySwipeAnimating = false;

  /// 搴曟爮鐐归€夌殑鍐呭祵椤?id锛堥�?null 鏃跺唴瀹瑰尯鍒囨崲涓鸿椤碉紝鐜荤拑鍧炲父椹伙級銆?
  String? _dockInlinePageId;

  /// Finger travel (after resistance) required to fire quick import.
  static const double _homePullQuickImportTriggerDistance =
      HyperosHomePullPhysics.triggerDistance;

  /// Visual / tracked pull cap; keep above the trigger so the indicator can
  /// overshoot slightly before release.
  static const double _homePullQuickImportMaxDistance =
      HyperosHomePullPhysics.maxVisualDistance;

  /// Damping range for the cubic curve f(x)=x - x\u00B2 + x\u00B3/3; f(1)\u00B7range = maxVisual.
  static const double _homePullDampingRange =
      HyperosHomePullPhysics.dampingRange;

  // Raw finger travel (clamped); visual offset = damped(touch/range)*range.
  double _homePullTouchDistance = 0;

  // Visual pull offset (derived from _homePullTouchDistance).
  double _homePullDragDistance = 0;

  // Threshold haptic latch: arm below trigger, fire once above.
  bool _homePullHapticArmed = true;

  // Spring-back (created in initState, disposed there).
  AnimationController? _homePullSettleSpring;
  int _homePullSettleGeneration = 0;
  bool _isHomePullQuickImportRunning = false;
  VoidCallback? _homePullQuickImportCancel;
  double? _wallpaperTopLuminance;

  /// Luminance of the wallpaper band the weekday/date chrome bar sits over.
  /// The status/title strip can be bright while the band below (where the
  /// weekday bar lives) is dark, so the weekday ink must not reuse the top
  /// sample.
  double? _wallpaperWeekdayLuminance;

  /// Luminance of the wallpaper band the day-view cards sit over. The top
  /// band can be dark while mid-screen is bright (or vice versa), so card ink
  /// must not reuse the chrome sample.
  double? _wallpaperBodyLuminance;
  String? _wallpaperLuminanceSampleKey;
  String? _wallpaperLuminanceRequestedKey;
  bool _wallpaperLuminanceFileExists = false;

  /// Last "custom weekday ink is unreadable" combination already warned about
  /// this session; the persisted twin lives in SharedPreferences.
  String? _weekdayInkWarnedSignature;
  bool _weekdayInkWarningShowing = false;

  Color _colorFromHex(String hexColor, Color fallback) {
    return parseHexColorOrFallback(hexColor, fallback: fallback);
  }

  ScrollController _getWeekGridScrollController(int week) {
    return _weekGridScrollControllers.putIfAbsent(week, ScrollController.new);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final provider = context.read<TimetableProvider>();
    final initialWeek = provider.currentWeek;
    _visibleWeek = initialWeek;
    _pendingSettledWeek = initialWeek;
    _visibleWeekListenable = ValueNotifier<int>(initialWeek);
    _weekPageController = PageController(
      initialPage:
          _clampWeek(initialWeek, provider.settings.semesterWeekCount) - 1,
    );
    _lastObservedWeekPage = _weekPageController.initialPage;
    _dayViewExpandController = AnimationController(
      vsync: this,
      duration: _dayExpandDuration,
      reverseDuration: _dayCollapseDuration,
    );
    _coupleHeartbeatController = AnimationController(
      vsync: this,
      duration: _coupleHeartbeatDuration,
    )..repeat();
    _coupleHeartbeatScale = _coupleHeartbeatController.drive(
      _coupleHeartbeatScaleTween.chain(CurveTween(curve: Curves.easeInOut)),
    );
    _coupleBeamController = AnimationController(
      vsync: this,
      duration: _coupleBeamDuration,
    )..repeat();
    _profileSwitchController = AnimationController(
      vsync: this,
      duration: _profileSwitchRevealDuration,
      value: 1,
    );
    // 鏃ヨ鍥鹃敋鐐瑰睍寮�?鏀惰捣鏈熼棿锛屽崱鐗囩幓鐠?fill 蹇呴』姣忓抚閲嶉噰鏍峰�?
    // 锛堝惁鍒欑汗鐞嗗仠鍦ㄦ棫灞忓箷浣嶇疆锛屽崱鐗囧憟鐜板崐杈规ā绯婂崐杈归€忔槑锛夈€?
    _glassDockCardRepaint = _dayViewExpandController;
    _dayAgendaProgressTimer = widget.enableProgressTimer
        ? Timer.periodic(const Duration(seconds: 1), (_) {
            if (!mounted || !_isDayView) {
              return;
            }
            // The pages' output cannot change within one minute (ongoing
            // badges resolve time at minute granularity), so skip identical
            // seconds instead of dirtying three cached pager pages.
            final now = DateTime.now();
            final minuteOfDay = now.hour * 60 + now.minute;
            if (minuteOfDay == _lastProgressMinuteOfDay) {
              return;
            }
            _lastProgressMinuteOfDay = minuteOfDay;
            _dayAgendaProgressTick.value++;
          })
        : null;
    _homePullSettleSpring = AnimationController.unbounded(vsync: this)
      ..addListener(_driveHomePullSettle);
    _weekPageController.addListener(_handleWeekPageControllerChanged);
    _restoreViewStateFromProvider(provider);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _homePullQuickImportCancel?.call();
    _homePullSettleSpring?.dispose();
    _weekPageController.removeListener(_handleWeekPageControllerChanged);
    _weekPageController.dispose();
    for (final controller in _weekGridScrollControllers.values) {
      controller.dispose();
    }
    _weekGridScrollControllers.clear();
    _dayViewExpandController.dispose();
    _coupleHeartbeatController.dispose();
    _coupleBeamController.dispose();
    _profileSwitchController.dispose();
    _visibleWeekListenable.dispose();
    _dayAgendaProgressTimer?.cancel();
    _dayAgendaProgressTick.dispose();
    _dayHeaderPreview.dispose();
    final dayViewController = _dayViewPageController;
    if (dayViewController != null) {
      dayViewController.dispose();
    }
    for (final controller in _pendingDayViewControllerDisposals) {
      controller.dispose();
    }
    _pendingDayViewControllerDisposals.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final provider = context.read<TimetableProvider>();
      unawaited(provider.syncTemporalContext());
      // Force-push the current stage and display settings to the native
      // live-update service.  The native alarm may have fired while the app
      // was backgrounded and started the service with stale snapshot settings;
      // this ensures the correct style is applied as soon as the user returns.
      unawaited(provider.refreshLiveActivityNow());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<TimetableProvider>(
      builder: (context, provider, child) {
        _syncViewStateIfNeeded(provider);
        _syncWeekPageWithProvider(provider.currentWeek, provider.settings);
        final colorScheme = Theme.of(context).colorScheme;
        final foruiTheme = context.theme;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final darkFallback = colorScheme.surface;
        final settings = provider.settings;
        // 鍚姩棰勭儹鍣ㄨ嫢宸插畬鎴愪寒搴﹂噰鏍凤紝棣栧抚鐩存帴閲囩敤锛氭爣棰?鐘舵€佹�?鏄熸湡鏍忕殑
        // 榛戠櫧澧ㄦ瀬鎬х涓€甯у嵆姝ｇ‘锛屼笉鍑虹幇銆屾寜涓婚鍏滃簳鍐嶇炕闈€嶇殑闂彉銆備粎鍦ㄦ湰椤?
        // 灏氭湭寮€濮嬮噰鏍锋椂鐢熸晥锛涘紓姝ョ簿纭噰鏍风収甯歌繍琛屽苟浠ュ悓鍊煎箓绛夋敹鏁涖€?
        _seedWallpaperLuminanceFromStartupPrimer(settings);
        final glassDockForm =
            settings.homeNavigationForm == HomeNavigationForm.glassDock;
        final viewportSize = MediaQuery.sizeOf(context);
        final hasBackdrop = hasHomePageBackdropImage(settings);
        final statusBarShowsBackdrop = homePageRegionShowsBackdrop(
          settings,
          HomePageBackgroundScope.statusBar,
        );
        final timetableShowsBackdrop = homePageRegionShowsBackdrop(
          settings,
          HomePageBackgroundScope.timetable,
        );
        final pageBackgroundColor = resolveHomePageBackgroundColor(
          settings: settings,
          isDark: isDark,
          darkFallback: darkFallback,
        );
        final headerBackground = resolveHomePageRegionBackground(
          settings: settings,
          isDark: isDark,
          darkFallback: darkFallback,
          region: HomePageBackgroundScope.header,
        );
        final timetableBackground = resolveHomePageRegionBackground(
          settings: settings,
          isDark: isDark,
          darkFallback: darkFallback,
          region: HomePageBackgroundScope.timetable,
        );
        final headerShowsBackdrop = homePageRegionShowsBackdrop(
          settings,
          HomePageBackgroundScope.header,
        );
        final headerUsesFrostedChrome =
            hasBackdrop &&
            (headerShowsBackdrop || settings.homePageHeaderBlurEnabled);
        final headerBarColor = headerUsesFrostedChrome
            ? Colors.transparent
            : headerBackground.color;
        final scaffoldBackgroundColor = timetableShowsBackdrop
            ? Colors.transparent
            : timetableBackground.color;
        // The page's own background is transparent over wallpaper, so derive
        // status-bar icon polarity from the sampled top band when available.
        final systemOverlayBackground = resolveHomePageStatusBarBackground(
          pageBackground: pageBackgroundColor,
          statusBarShowsBackdrop: statusBarShowsBackdrop,
          hasBackdrop: hasBackdrop,
          isDark: isDark,
          usesFrostedChrome: headerUsesFrostedChrome,
          wallpaperTopLuminance: _wallpaperTopLuminance,
        );

        _scheduleWallpaperLuminanceSampleIfNeeded(
          settings,
          viewportSize: viewportSize,
        );
        // After the sample lands: a hand-picked weekday ink can be invisible
        // over this wallpaper ? never silently override it, explain instead.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _maybeWarnWeekdayInkContrast(provider, settings);
          }
        });
        final chromeForeground = _resolveHomeChromeForeground(
          // Only flip by wallpaper luminance when the header band actually
          // shows the wallpaper / frosted glass; with the scope toggled off it
          // paints the opaque page background and must use the theme ink.
          headerShowsWallpaper: headerUsesFrostedChrome,
          themeForeground: foruiTheme.colors.foreground,
        );
        final chromeMutedForeground = hasBackdrop
            ? homePageChromeMutedForeground(chromeForeground)
            : foruiTheme.colors.mutedForeground;

        final coupleHeaderTitle =
            provider.settings.coupleTimetableOverlayEnabled;
        final homeTitle = _buildHomeTitle(
          provider,
          foreground: chromeForeground,
          mutedForeground: chromeMutedForeground,
        );

        final followsWeekPager =
            hasBackdrop && settings.homePageBackdropFollowsWeekPager;
        // Keep the same frosted chrome band in day view. The weekday header
        // already paints a transparent fill when blur is on; without this
        // overlay the title/weekday chrome becomes fully clear over wallpaper.
        final continuousChromeBlur = homePageHasAnyChromeBlur(
          settings,
          hasBackdrop: hasBackdrop,
        );
        // Cards fall back to a plain translucent tint when blur is off, so
        // building the pre-blurred bitmap would decode and Gaussian-blur the
        // whole wallpaper for nothing.
        final backdropBlurOn =
            hasBackdrop && HyperosBlurredHeader.backdropBlurEnabled(context);
        final cardStyle = settings.courseCardSurfaceStyle;
        // Gaussian cards sample the cached bitmap instead of a live
        // BackdropFilter while the day-view shell is animating.
        final useCoursePreblur =
            backdropBlurOn && cardStyle == CourseCardSurfaceStyle.gaussian;
        // The day-view summary card is drawn from this same bitmap whenever
        // the chrome band has glass ? regardless of the course-card style.
        // Without it the card's PreblurredWallpaperAlignedFill paints nothing
        // and the card reads as transparent (bare wash over raw wallpaper).
        final useHomePreblur =
            useCoursePreblur || (backdropBlurOn && continuousChromeBlur);
        // 鍏变韩绾嚱鏁拌В鏋愶紝涓庡惎鍔ㄩ鐑櫒鏋勯€犲悓涓€浠?PreblurredWallpaperCache
        // 閿綅锛堝垎鏀涔変笌鍘熷唴鑱旈棴鍖呬竴鑷达級銆?
        final dockAppearance = FrostedAppearanceScope.of(context);
        final homePreblurSigma = resolveHomePreblurSigma(
          gaussianCardsDrive:
              backdropBlurOn && cardStyle == CourseCardSurfaceStyle.gaussian,
          // 棰勬ā绯婁綅鍥炬湇鍔＄殑鏄椤电幓鐠冨甫/鎽樿鍗★紝璺熼殢銆岄椤电幓鐠冨甫銆嶅紑鍏炽€?
          liquidGlassChrome:
              dockAppearance.glassMode == FrostedGlassMode.liquidGlass &&
              dockAppearance.liquidGlassHomeChromeEnabled,
          sheetBlurSigma: HyperosBlurredHeader.blurSigmaOf(context),
          liquidGlassTunedBlur:
              (dockAppearance.liquidGlassTuning ?? LiquidGlassTuning.defaults)
                  .blur,
        );
        // 涓庤缃〉璇捐〃棰勮瀹屽叏鍚屾瀯鐨勭粍閲囨牱缁撴瀯锛欱ackdropGroup 鍐呭厛鏀惧叏灏哄�?
        // UndimmedBackdropCapture锛堢粍鍐呴�?filter 缂撳瓨鏁村睆澹佺焊锛夛紝chrome 鐜荤�?
        // 甯﹂噰鏍疯繖浠藉叏灏哄鑳屾櫙銆傛鍓嶉椤电幓鐠冨甫鍙兘閲囨牱鑷繁 band bounds 鐨勮�?
        // 鏅紝鎶樺皠浣嶇Щ鍦ㄥ甫杈硅閽冲埗锛岃鎰熶笌棰勮锛堢粍鍐呭叏灏哄閲囨牱锛変笉涓€鑷淬€?
        final Widget homeStack = BackdropGroup(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasBackdrop)
                followsWeekPager
                    ? HomePageSlidingBackdropLayer(
                        controller: _weekPageController,
                        pageCount: settings.semesterWeekCount,
                        settings: settings,
                      )
                    : homePageBackdropLayer(settings: settings),
              if (hasBackdrop && !statusBarShowsBackdrop)
                HomePageStatusBarBackdropMask(color: pageBackgroundColor),
              // 缁勫唴棣栦釜 grouped filter锛氱紦瀛樻湭鍘嬫殫鐨勫叏灞忓绾镐緵鐜荤拑甯﹂噰鏍凤紝
              // 涓庨瑙堢殑 UndimmedBackdropCapture 鍚屾銆佸悓鐩稿浣嶇疆�?
              if (continuousChromeBlur)
                const Positioned.fill(child: UndimmedBackdropCapture()),
              // Single continuous glass for title + weekday (no time-column blur).
              // Stays fixed above the sliding wallpaper so chrome text stays sharp
              // while the photo moves as one continuous sheet.
              if (continuousChromeBlur)
                HomePageContinuousChromeFrostedOverlay(
                  headerBlurEnabled: settings.homePageHeaderBlurEnabled,
                  weekdayBarBlurEnabled: settings.homePageWeekdayBarBlurEnabled,
                  includeStatusBar: statusBarShowsBackdrop,
                  weekdayBarHeight: _weekDayHeaderHeight,
                ),
              HyperosRootPage(
                overlayHeader: false,
                backgroundColor: scaffoldBackgroundColor,
                headerDecoration: BoxDecoration(color: headerBarColor),
                headerPadding: EdgeInsets.fromLTRB(
                  8,
                  0,
                  8,
                  headerUsesFrostedChrome ? 0.0 : 2.0,
                ),
                systemOverlayStyle: HyperosColors.systemOverlayForBackground(
                  systemOverlayBackground,
                ),
                title: coupleHeaderTitle ? const SizedBox.shrink() : homeTitle,
                fullWidthCenterChild: coupleHeaderTitle ? homeTitle : null,
                suffixes: [
                  KeyedSubtree(
                    key: _topMenuButtonKey,
                    child: FHeaderAction(
                      icon: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(
                            Icons.more_vert_rounded,
                            color: chromeForeground,
                          ),
                        ],
                      ),
                      semanticsLabel: l10n.moreTooltip,
                      onPress: _showTopActionsSheet,
                    ),
                  ),
                ],
                child: Padding(
                  padding: EdgeInsets.only(
                    // 鏃ヨ琛ㄧ殑鍒楄〃瑙嗗彛淇濇寔鍏ㄥ睆锛氶伩璁╂敼涓哄垪琛ㄨ嚜韬殑婊氬姩
                    // padding锛堣�?_buildExpandedDayColumnView锛夛紝婊氬姩涓崱鐗?
                    // 杩炵画绌胯繃搴曢儴閬胯甯︼紝涓嶅湪閬胯杈圭晫琚‖瑁佸嚭涓€鏉′笌纾ㄧ�?
                    // 鍗＄墖鑹插樊鏄庢樉鐨勩€岀敓澹佺焊銆嶇┖甯︼紱鍛ㄨ琛ㄧ綉鏍间笉鍙粴鍔�?
                    // 閬胯浠嶇敱杩欓噷鐨勫竷灞�?padding 鎵挎媴銆?
                    bottom: glassDockForm && !_isDayView ? 0.0 : 0,
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: provider.isLoading
                        // Single-stage: system splash already covers loading;
                        // render matching background to avoid spinner flash
                        // if provider momentarily reports loading post-splash.
                        ? ColoredBox(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFF121212)
                                : Colors.white,
                          )
                        : MediaQuery.removeViewInsets(
                            context: context,
                            removeBottom: true,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                _wrapProfileSwitchReveal(
                                  _buildHomePullQuickImportSurface(
                                    provider: provider,
                                    settings: settings,
                                    hasBackdrop: hasBackdrop,
                                  ),
                                ),
                                if (_isHomePullQuickImportRunning ||
                                    _homePullDragDistance > 0)
                                  _buildHomePullQuickImportIndicator(l10n),
                                ValueListenableBuilder<int>(
                                  valueListenable: _visibleWeekListenable,
                                  builder: (context, visibleWeek, child) {
                                    if (!_shouldShowFloatingBackToCurrentWeekButton(
                                      provider,
                                      provider.settings,
                                      visibleWeek,
                                    )) {
                                      return const SizedBox.shrink();
                                    }
                                    return _buildFloatingBackToCurrentWeekButton(
                                      provider,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        );
        // 鐜荤拑鍧炲舰鎬佷笅璇捐〃锛堝惈澹佺焊锛変笌璁剧疆椤甸兘甯搁┗鎸傝浇锛岀�?Offstage 鍒囨崲锛?
        // - 璁剧疆椤电殑婊氬姩浣嶇疆涓庡ぇ鏍囬鎶樺彔鐘舵€佷笉�?Tab 鍒囨崲涓㈠け锛堝垏璧板啀鍒囧洖锛?
        //   鏍囬淇濇寔绂诲紑鏃剁殑鎶樺彔鎬侊級�?
        // - 澹佺焊灞傞殢 homeStack 甯搁┗锛岃В鐮佺紦瀛樹笉澶辨晥锛屽垏鍥炶琛ㄤ笉榛戦棯�?
        // 鐜荤拑鍧炲鑸缁堢敱 [_wrapWithGlassDock] 娴湪鏈€涓婂眰�?
        final Widget dockContent = useHomePreblur
            ? PreblurredWallpaperScope(
                // Same pre-blur model as the week grid: sample one cached
                // frost bitmap by card screen position. In day view the week
                // pager is locked, so drive repaints from the day agenda pager
                // and treat the wallpaper as screen-fixed (it never follows
                // the day swipe).
                wallpaperPath: resolveHomePageBackdropImagePath(settings),
                blurSigma: homePreblurSigma,
                pageController: _isDayView
                    ? _ensureDayViewPageController(settings)
                    : _weekPageController,
                followsPager: _isDayView ? false : followsWeekPager,
                // 閿氱偣灞曞紑/鏀惰捣涓庤缃〉鎷栧姩杞満鏈熼棿鍗＄墖鍦ㄧЩ鍔ㄨ€屽绾?
                // 灞忓箷鍥哄畾锛歠ill 蹇呴』姣忓抚閲嶉噰鏍凤紝鍚﹀垯绾圭悊鍋滃湪鏃у睆骞曚綅�?
                // 锛堝崱鐗囧崐杈规ā绯婂崐杈归€忔槑锛夈€傚悎骞朵袱涓姩鐢荤粺涓€椹卞姩閲嶉噰鏍枫�?
                repaint: _glassDockCardRepaint,
                child: homeStack,
              )
            : homeStack;
        if (!glassDockForm) {
          return _wrapWithGlassDock(
            dockContent,
            glassDockForm: false,
            settings: settings,
            l10n: l10n,
          );
        }
        // 搴曟爮涓哄彲缂栨帓蹇嵎鍖猴細椤甸潰绫绘潯鐩湪棣栭〉鏍堝唴鍒囨崲锛堝唴宓屽涓伙紝
        // 鐜荤拑鍧炲父椹绘偓娴級锛屼粎鏈櫥璁扮殑娴佺▼椤垫墠鎺ㄥ叆鏂拌矾鐢便€?
        final inlineId = _dockInlinePageId;
        final inlineBuilder = inlineId == null
            ? null
            : inlineDockPageFor(inlineId);
        final Widget hostedContent = inlineBuilder == null
            ? dockContent
            : Stack(
                fit: StackFit.expand,
                children: [
                  dockContent,
                  // 涓庢棫銆岃�?Tab銆嶄竴鑷达細鐐瑰簳鏍忛棯鐜扮洿鍒囷紝鏃犳粦鍔ㄨ浆鍦恒�?
                  Positioned.fill(
                    child: Material(
                      type: MaterialType.transparency,
                      child: Scaffold(
                        backgroundColor: Theme.of(
                          context,
                        ).scaffoldBackgroundColor,
                        body: HyperosSubpageNoBack(
                          // 鐜荤拑鍧炴弧灞忔偓娴鎵€鏈夊唴宓岄〉鐢熸晥锛氭敞鍏ュ簳閮ㄦ粴鍔?
                          // 浣欓噺锛堜笌�?鍛ㄨ琛ㄥ悓鍙ｅ緞锛夛紝鍒楄〃鏈熬鍙暣浣撴粦�?
                          // 鑽父涓婃柟锛汬yperosListView 鑷姩娑堣垂锛屾柊澧炲唴�?
                          // 椤垫棤椤婚€愰〉閫傞厤�?
                          child: GlassDockScrollReliefScope(
                            inset: _glassDockContentScrollInset(settings),
                            child: Builder(builder: inlineBuilder),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
        // 绯荤粺杩斿洖涓嶆嫤鍐呭祵椤碉細涓庢棩/鍛ㄨ琛ㄥ悓鍙ｅ緞锛屽簳鏍忎换鎰忕姸鎬侊紙鏃?�?
        // 璇捐〃鎴栧唴宓岄〉锛夋寜杩斿洖閮界洿鎺ラ€€鍑哄簲鐢紙鏍硅矾鐢?bubble ? 绯荤粺閫€鍑猴級�?
        // 鏀跺洖鍐呭祵椤佃蛋搴曟爮鍒囨崲锛堢�?�?�?Tab 鎴栧叾浠栭〉闈㈡潯鐩級涓庡渾閽啀鐐广�?
        return _wrapWithGlassDock(
          hostedContent,
          glassDockForm: true,
          settings: settings,
          l10n: l10n,
        );
      },
    );
  }

  List<String> _weekdayLabels(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return [
      l10n.weekdayMon,
      l10n.weekdayTue,
      l10n.weekdayWed,
      l10n.weekdayThu,
      l10n.weekdayFri,
      l10n.weekdaySat,
      l10n.weekdaySun,
    ];
  }

  String _weekdayLabel(BuildContext context, int dayOfWeek) {
    final labels = _weekdayLabels(context);
    if (dayOfWeek < 1 || dayOfWeek > labels.length) {
      return dayOfWeek.toString();
    }
    return labels[dayOfWeek - 1];
  }

  bool get _isDayView =>
      _selectedDayOfWeek != null && _selectedWeekForDayView != null;

  bool get _shouldShowDayViewOverlay =>
      _selectedDayOfWeek != null &&
      (_isDayView || _dayViewExpandController.isAnimating);

  int? get _visibleDayViewWeek {
    if (_isDaySwipeAnimating && _dayViewTransitionSourceWeek != null) {
      return _dayViewTransitionSourceWeek;
    }
    return _selectedWeekForDayView;
  }

  int _resolveStoredDayOfWeek(TimetableSettings settings, int storedDayOfWeek) {
    final visibleDays = _visibleDayNumbers(settings);
    if (visibleDays.contains(storedDayOfWeek)) {
      return storedDayOfWeek;
    }
    return visibleDays.first;
  }

  void _restoreViewStateFromProvider(TimetableProvider provider) {
    final settings = provider.settings;
    _visibleWeek = _clampWeek(provider.currentWeek, settings.semesterWeekCount);
    _pendingSettledWeek = _visibleWeek;
    _pendingCommittedWeek = null;
    _visibleWeekListenable.value = _visibleWeek;
    final restoredDayOfWeek = _resolveStoredDayOfWeek(
      settings,
      settings.timetableLastViewedDayOfWeek,
    );
    _lastSyncedProvider = provider;
    _lastSyncedProfileId = provider.activeProfileId;
    _dayViewTransitionSourceWeek = null;
    _dayViewTransitionSourceDayOfWeek = null;
    _isSyncingDayViewPage = false;
    _isDaySwipeAnimating = false;
    // Keep the old controller alive through the replacement frame. AnimatedBuilder
    // detaches from the old PageController during that rebuild; disposing at
    // the first post-frame callback is still early enough to race didUpdateWidget.
    final oldController = _dayViewPageController;
    _dayViewPageController = null;
    if (oldController != null) {
      _disposeDayViewControllerAfterReplacement(oldController);
    }
    if (settings.timetableHomeViewMode == TimetableHomeViewMode.day) {
      _selectedWeekForDayView = _visibleWeek;
      _selectedDayOfWeek = restoredDayOfWeek;
      _dayViewExpandController.value = 1;
    } else {
      _selectedWeekForDayView = null;
      _selectedDayOfWeek = null;
      _dayViewExpandController.value = 0;
    }
  }

  void _applyVisibleWeek(
    int week, {
    bool rebuild = false,
    bool syncDayView = false,
  }) {
    final shouldSyncDayView = syncDayView && _selectedWeekForDayView != week;
    if (_visibleWeek == week && !shouldSyncDayView) {
      return;
    }
    _visibleWeek = week;
    _visibleWeekListenable.value = week;
    if ((rebuild || shouldSyncDayView) && mounted) {
      setState(() {
        if (shouldSyncDayView) {
          _selectedWeekForDayView = week;
        }
      });
      return;
    }
  }

  bool get _hasPendingLocalWeekTransition =>
      (_pendingSettledWeek != null && _pendingSettledWeek != _visibleWeek) ||
      _pendingCommittedWeek != null ||
      _isCommittingWeek;

  void _syncViewStateIfNeeded(TimetableProvider provider) {
    final previousProfileId = _lastSyncedProfileId;
    final shouldReplayProfileSwitch =
        previousProfileId != null &&
        previousProfileId != provider.activeProfileId;
    if (identical(_lastSyncedProvider, provider) &&
        _lastSyncedProfileId == provider.activeProfileId) {
      return;
    }
    _restoreViewStateFromProvider(provider);
    // Replay the week card-pager entrance so switching my/her timetable reads
    // as the same incoming-card-rises motion instead of a hard cut.
    if (shouldReplayProfileSwitch) {
      _profileSwitchController.forward(from: 0);
    }
  }

  void _persistViewState(
    TimetableProvider provider, {
    required TimetableHomeViewMode mode,
    int? dayOfWeek,
  }) {
    final resolvedDayOfWeek = _resolveStoredDayOfWeek(
      provider.settings,
      dayOfWeek ??
          _selectedDayOfWeek ??
          provider.settings.timetableLastViewedDayOfWeek,
    );
    if (provider.settings.timetableHomeViewMode == mode &&
        provider.settings.timetableLastViewedDayOfWeek == resolvedDayOfWeek) {
      return;
    }
    // Lightweight path: no notifyListeners / live-activity churn. The old
    // updateTimetableSettings route re-broadcast the whole provider on every
    // day switch, rebuilding the home screen a second time mid-animation.
    unawaited(
      provider.persistHomeViewState(mode: mode, dayOfWeek: resolvedDayOfWeek),
    );
  }

  bool _isSelectedDay(int week, int dayOfWeek) {
    if (!_isDayView) {
      return false;
    }
    // Mid-swipe the preview leads the committed selection so the header
    // highlight flips at the pager midpoint, not after the spring settles.
    final preview = _dayHeaderPreview.value;
    if (preview != null) {
      return preview.$1 == week && preview.$2 == dayOfWeek;
    }
    return _selectedWeekForDayView == week && _selectedDayOfWeek == dayOfWeek;
  }

  /// Opaque chrome for day-view layers over wallpaper-backed week chrome.
  double get _dayViewAnchorAlignmentX =>
      (_dayViewAnchorFraction * 2).clamp(0.0, 2.0) - 1;

  void _captureDayViewAnchor(Offset globalPosition) {
    final surfaceContext = _timetableSurfaceKey.currentContext;
    final surfaceBox = surfaceContext?.findRenderObject() as RenderBox?;
    if (surfaceBox == null ||
        !surfaceBox.hasSize ||
        surfaceBox.size.width <= 0) {
      return;
    }
    final localDx = surfaceBox.globalToLocal(globalPosition).dx;
    setState(() {
      _dayViewAnchorFraction = (localDx / surfaceBox.size.width).clamp(
        0.1,
        0.9,
      );
    });
  }

  Future<void> _toggleDayView({
    required int week,
    required int dayOfWeek,
    required TimetableSettings settings,
    bool animate = true,
  }) async {
    final provider = context.read<TimetableProvider>();
    var normalizedWeek = _clampWeek(week, settings.semesterWeekCount);
    // A week swipe may still be settling when the dock is tapped. Open the
    // day view on the page the week pager is actually showing and start its
    // commit now; otherwise closing later lets the stale provider week pull
    // the pager back to week 1.
    if (!_isDayView) {
      final settledWeek = _resolveSettledWeek(
        provider,
        fallbackWeek: normalizedWeek,
      );
      if (settledWeek != normalizedWeek) {
        _finalizeWeekPageSettled(provider, fallbackWeek: settledWeek);
        normalizedWeek = settledWeek;
        if (_weekPageController.hasClients &&
            _weekPageController.page != settledWeek - 1) {
          // Programmatic jump: the swipe deck is gesture-only, so fall back
          // to the pager's own slide instead of a stale deck takeover.
          _weekDeckSettleRebuildArmed = false;
          _weekDeckSettleRebuildScheduled = false;
          _weekPagerDragStartPage = null;
          _weekPagerPendingDragStartPage = null;
          _lastObservedWeekPage = settledWeek - 1;
          _weekPageController.jumpToPage(settledWeek - 1);
        }
      }
    }
    final isSameSelection =
        _isDayView &&
        _selectedWeekForDayView == normalizedWeek &&
        _selectedDayOfWeek == dayOfWeek;
    if (isSameSelection) {
      await _closeDayView(settings, animate: animate);
      return;
    }
    if (_isDayView && _selectedWeekForDayView == normalizedWeek) {
      await _switchDayWithinWeek(settings, normalizedWeek, dayOfWeek);
      return;
    }
    final shouldAnimateOpen = animate && !_isDayView;
    if (!_isDayView) {
      _recreateDayViewPageController(
        settings,
        week: normalizedWeek,
        dayOfWeek: dayOfWeek,
      );
    }
    // Collapse the expand controller *before* the overlay mounts so the first
    // painted frame is the small/transparent state. Otherwise a leftover value
    // of 1 (restore / interrupted close / hot reload) makes open look like a
    // hard cut, while close still has a visible reverse animation. The dock's
    // flash path (shouldAnimateOpen=false) inverts this on purpose: land on 1
    // so the first painted frame is the fully expanded day view.
    if (!_isDayView) {
      _dayViewExpandController.value = shouldAnimateOpen ? 0 : 1;
    }
    _dayHeaderPreview.value = null;
    setState(() {
      _selectedWeekForDayView = normalizedWeek;
      _selectedDayOfWeek = dayOfWeek;
    });
    _persistViewState(
      context.read<TimetableProvider>(),
      mode: TimetableHomeViewMode.day,
      dayOfWeek: dayOfWeek,
    );
    _maybeSelectionClick(settings);
    if (shouldAnimateOpen) {
      // Start open animation without awaiting completion (close still awaits
      // reverse). Controller was reset to 0 above so the first frame is small.
      unawaited(_dayViewExpandController.forward());
    }
  }

  Future<void> _closeDayView(
    TimetableSettings settings, {
    bool animate = true,
  }) async {
    if (!_isDayView) {
      return;
    }
    _maybeSelectionClick(settings);
    if (_dayViewExpandController.value > 0) {
      if (animate) {
        await _dayViewExpandController.reverse();
        if (!mounted) {
          return;
        }
      } else {
        // 搴曟爮闂幇鐩村垏锛氳烦杩囨敹璧峰姩鐢荤洿鎺ュ綊闆讹紝涓庝笅鏂规竻鐞嗗悓甯х敓鏁堛�?
        _dayViewExpandController.value = 0;
      }
    }
    _dayHeaderPreview.value = null;
    setState(() {
      _selectedWeekForDayView = null;
      _selectedDayOfWeek = null;
      _dayViewTransitionSourceWeek = null;
      _dayViewTransitionSourceDayOfWeek = null;
    });
    _persistViewState(
      context.read<TimetableProvider>(),
      mode: TimetableHomeViewMode.week,
    );
  }

  int _dayViewPageIndexForDay(
    TimetableSettings settings,
    int week,
    int dayOfWeek,
  ) {
    final visibleDays = _visibleDayNumbers(settings);
    final dayIndex = math.max(0, visibleDays.indexOf(dayOfWeek));
    // Globally continuous across weeks: no edge pages, crossing a week is a
    // normal one-page transition on the single day pager.
    return (week - 1) * visibleDays.length + dayIndex;
  }

  int _dayViewPageCount(TimetableSettings settings) {
    return _visibleDayNumbers(settings).length * settings.semesterWeekCount;
  }

  _DayViewPageTarget _dayViewTargetForPage(
    TimetableSettings settings,
    int page,
  ) {
    final visibleDays = _visibleDayNumbers(settings);
    final count = visibleDays.length;
    final week = (page ~/ count) + 1;
    return _DayViewPageTarget(week: week, dayOfWeek: visibleDays[page % count]);
  }

  PageController _ensureDayViewPageController(TimetableSettings settings) {
    final existing = _dayViewPageController;
    // Never hand out a controller that is pending disposal: the pre-blur
    // fill (and the PageView) would latch onto it, and once the deferred
    // disposal runs a stale LayoutBuilder rebuild can hit the disposed
    // controller and throw.
    //
    // A client-less controller is NOT stale: several build-pass call sites
    // (pre-blur scope, weekday bar, day panel) resolve the controller before
    // the PageView attaches. Replacing a healthy-but-unattached controller
    // here used to orphan the weekday bar's AnimatedBuilder subscription on
    // the first instance, freezing the bar at the crossing-start frame while
    // the pager kept scrolling.
    if (existing != null &&
        !_pendingDayViewControllerDisposals.contains(existing) &&
        !_disposedDayViewControllers.contains(existing)) {
      return existing;
    }
    final fresh = _createDayViewPageController(settings);
    _dayViewPageController = fresh;
    if (existing != null) {
      // Stale controller (created but never attached, or detached after the
      // day view closed): replace it instead of reusing a dead position.
      _disposeDayViewControllerAfterReplacement(existing);
    }
    return fresh;
  }

  PageController _createDayViewPageController(
    TimetableSettings settings, {
    int? week,
    int? dayOfWeek,
  }) {
    return PageController(
      initialPage: _dayViewPageIndexForDay(
        settings,
        week ?? _selectedWeekForDayView ?? _visibleWeek,
        dayOfWeek ?? _selectedDayOfWeek ?? 1,
      ),
    );
  }

  /// Recreates the single day pager anchored on the given day (used when the
  /// day view opens so the first painted frame lands on the requested day).
  /// The old controller is kept alive for two post-frame hops so the
  /// replacing tree can detach.
  void _recreateDayViewPageController(
    TimetableSettings settings, {
    int? week,
    int? dayOfWeek,
  }) {
    final old = _dayViewPageController;
    _dayViewPageController = _createDayViewPageController(
      settings,
      week: week,
      dayOfWeek: dayOfWeek,
    );
    if (old != null) {
      _disposeDayViewControllerAfterReplacement(old);
    }
  }

  void _rememberDisposedDayViewController(PageController controller) {
    if (!_disposedDayViewControllers.add(controller)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _disposedDayViewControllers.remove(controller);
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _disposedDayViewControllers.remove(controller);
      });
    });
  }

  void _disposeDayViewControllerAfterReplacement(PageController controller) {
    if (!_pendingDayViewControllerDisposals.add(controller)) {
      return;
    }

    // The replacement widget tree builds and detaches over a couple of
    // frames. Disposal waits until nothing can reach the controller any
    // more: the field was swapped (no future build will hand it out) and no
    // live PageView still holds it. The pre-blur fill re-latches its
    // listener in the same build that swaps the field, so this ordering
    // guarantees the listener is detached before dispose ? otherwise a
    // stale LayoutBuilder rebuild can hit the disposed controller and throw
    // (a PageController used after being disposed).
    void retryDispose() {
      if (!mounted) {
        if (_pendingDayViewControllerDisposals.remove(controller)) {
          controller.dispose();
        }
        return;
      }
      if (_dayViewPageController == controller || controller.hasClients) {
        if (controller.hasClients) {
          // A PageView still holds this controller: force a rebuild so the
          // next _ensureDayViewPageController swaps in a fresh controller
          // and the old one detaches, then re-check next frame.
          setState(() {});
        }
        _pendingDayViewControllerDisposals.add(controller);
        WidgetsBinding.instance.addPostFrameCallback((_) => retryDispose());
        WidgetsBinding.instance.scheduleFrame();
        return;
      }
      if (_pendingDayViewControllerDisposals.remove(controller)) {
        _rememberDisposedDayViewController(controller);
        controller.dispose();
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        if (_pendingDayViewControllerDisposals.remove(controller)) {
          controller.dispose();
        }
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => retryDispose());
      WidgetsBinding.instance.scheduleFrame();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  int _displayedDayForWeek(int week) {
    if (_dayViewTransitionSourceWeek == week &&
        _dayViewTransitionSourceDayOfWeek != null) {
      return _dayViewTransitionSourceDayOfWeek!;
    }
    return _selectedDayOfWeek ?? 1;
  }

  void _syncDayViewPageWithSelection(TimetableSettings settings) {
    if (_isSyncingDayViewPage || !_isDayView) {
      return;
    }
    if (_dayViewTransitionSourceWeek != null) {
      return;
    }
    final controller = _dayViewPageController;
    if (controller == null || !controller.hasClients) {
      return;
    }
    // A live drag / fling owns the pager: selection commit is deferred to
    // ScrollEnd, so a mid-gesture rebuild would read the stale selection here
    // and jumpToPage would yank the fling back to the old page.
    if (controller.position.isScrollingNotifier.value) {
      return;
    }
    final week = _selectedWeekForDayView ?? _visibleWeek;
    final targetPage = _dayViewPageIndexForDay(
      settings,
      week,
      _displayedDayForWeek(week),
    );
    final currentPage = controller.page?.round() ?? controller.initialPage;
    if (currentPage == targetPage) {
      return;
    }
    controller.jumpToPage(targetPage);
  }

  Future<void> _switchDayWithinWeek(
    TimetableSettings settings,
    int week,
    int dayOfWeek, {
    bool animate = true,
  }) async {
    final controller = _ensureDayViewPageController(settings);
    _dayHeaderPreview.value = null;
    setState(() {
      _selectedWeekForDayView = week;
      _selectedDayOfWeek = dayOfWeek;
    });
    _persistViewState(
      context.read<TimetableProvider>(),
      mode: TimetableHomeViewMode.day,
      dayOfWeek: dayOfWeek,
    );
    _maybeSelectionClick(settings);
    if (!controller.hasClients) {
      return;
    }
    final targetPage = _dayViewPageIndexForDay(settings, week, dayOfWeek);
    final currentPage = controller.page?.round() ?? controller.initialPage;
    if (currentPage == targetPage) {
      return;
    }
    _isSyncingDayViewPage = true;
    try {
      if (animate) {
        await controller.animateToPage(
          targetPage,
          duration: _weekSlideDuration,
          curve: Curves.easeInOutCubicEmphasized,
        );
      } else {
        controller.jumpToPage(targetPage);
      }
    } finally {
      _isSyncingDayViewPage = false;
    }
  }

  Future<void> _animateDayViewToWeek(
    TimetableProvider provider,
    TimetableSettings settings,
    int targetWeek,
    int targetDayOfWeek, {
    bool animateWeekPage = true,
  }) async {
    if (_selectedWeekForDayView == null || _selectedDayOfWeek == null) {
      return;
    }
    final normalizedTargetWeek = _clampWeek(
      targetWeek,
      provider.settings.semesterWeekCount,
    );
    if (normalizedTargetWeek == _selectedWeekForDayView &&
        targetDayOfWeek == _selectedDayOfWeek) {
      return;
    }

    _isDaySwipeAnimating = true;
    try {
      _dayHeaderPreview.value = null;
      setState(() {
        _dayViewTransitionSourceWeek = _selectedWeekForDayView;
        _dayViewTransitionSourceDayOfWeek = _selectedDayOfWeek;
        _selectedWeekForDayView = normalizedTargetWeek;
        _selectedDayOfWeek = targetDayOfWeek;
      });
      _persistViewState(
        provider,
        mode: TimetableHomeViewMode.day,
        dayOfWeek: targetDayOfWeek,
      );
      // Same single pager scrolls to the target day; the week page follows
      // for state consistency (it is faded out while the day view is open).
      await _switchDayWithinWeek(
        settings,
        normalizedTargetWeek,
        targetDayOfWeek,
        animate: animateWeekPage,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _dayViewTransitionSourceWeek = null;
        _dayViewTransitionSourceDayOfWeek = null;
      });
      if (normalizedTargetWeek != _visibleWeek) {
        await _jumpToWeek(
          provider,
          normalizedTargetWeek,
          animatePage: animateWeekPage,
        );
      }
    } finally {
      _isDaySwipeAnimating = false;
      // 鏃ヨ鍥炬粦鍔ㄥ尯澶栧眰�?IgnorePointer ? build 鏃惰鍙栬鏍囧織锛氫笂闈㈡墍鏈?
      // setState 閮藉彂鐢熷湪鏍囧織浠嶄负 true 鐨勬湡闂达紝鑻ユ澶勪笉澶嶄綅鍚庡啀琛ヤ竴娆￠噸寤猴�?
      // 銆屽洖鍒颁粖澶┿€嶈浆鍦虹粨鏉熷�?ignoring:true 浼氭案涔呮粸鐣欙紝鏃ヨ鍥惧乏鍙虫粦�?
      // 灏卞啀涔熸棤鍝嶅簲銆傚繀椤绘樉寮忛噸寤轰竴甯ф妸鎸囬拡鏀捐�?
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _handleDayViewPageChanged(
    TimetableProvider provider,
    TimetableSettings settings,
    int page,
  ) async {
    if (_isSyncingDayViewPage || _isDaySwipeAnimating) {
      if (kDebugMode) {
        debugPrint(
          '[DayPager] pageChanged($page) ignored: '
          'syncing=$_isSyncingDayViewPage animating=$_isDaySwipeAnimating',
        );
      }
      return;
    }
    final target = _dayViewTargetForPage(settings, page);
    if (kDebugMode) {
      debugPrint(
        '[DayPager] pageChanged($page) -> week=${target.week} '
        'day=${target.dayOfWeek}',
      );
    }
    if (_selectedWeekForDayView == target.week &&
        _selectedDayOfWeek == target.dayOfWeek) {
      return;
    }
    // Midpoint preview: recolour the weekday header the moment the pager
    // crosses a page midpoint (matching the indicator), via the scoped
    // notifier ? no full-State rebuild while the fling is still running.
    // Committing the selection here instead (setState + persist + week-page
    // jump) rebuilt the whole home screen on *every* page crossing ? a single
    // real-device swipe crosses 30+ pages and each rebuild re-samples the
    // wallpaper blur, which starved the main thread into an ANR. The actual
    // selection commit stays on ScrollEnd (_settleDayViewPage), which now
    // re-checks until the pager is truly stationary.
    _dayHeaderPreview.value = (target.week, target.dayOfWeek);
    // 鍗曟鎵嬪娍鍙渿涓€娆★細蹇€熺敥鍔ㄨ法涓ら�?/ 寮圭哀鍥炲脊鍐嶈繃涓偣鏃讹紝onPageChanged
    // 浼氳繛鍙戝娆★紝涓嶉棭閿佸氨浼氫竴娆℃粦鍔ㄨЕ鍙戜袱娆￠渿鍔ㄣ€?
    if (!_daySwipeHapticFired) {
      _daySwipeHapticFired = true;
      _maybeSelectionClick(settings);
    }
  }

  /// Commits the settled day-pager page once the horizontal scroll has fully
  /// stopped, mirroring the week pager's ScrollEnd ? finalize model so the
  /// setState + persist never land mid-animation. A cross-week landing is an
  /// ordinary page here (the pager is globally continuous), so the week page
  /// follows the committed week for state consistency.
  void _settleDayViewPage(
    TimetableProvider provider,
    TimetableSettings settings,
  ) {
    if (_isSyncingDayViewPage || _isDaySwipeAnimating) {
      if (kDebugMode) {
        debugPrint(
          '[DayPager] settle skipped: syncing=$_isSyncingDayViewPage '
          'animating=$_isDaySwipeAnimating',
        );
      }
      return;
    }
    final controller = _dayViewPageController;
    if (controller == null || !controller.hasClients) {
      return;
    }
    // A ScrollEnd fires at the end of *every* activity, including the frame
    // where a new gesture begins (the previous drag's end is dispatched
    // before this drag's first move). Under fake-async test frames the snap
    // spring can still be running at that point (page=0.9988, not 1.0), so a
    // stale end would commit the old page again and the panel lags the real
    // content by one day. Rather than dropping this commit opportunity
    // entirely (which would lose the fix for consecutive quick swipes),
    // re-check on the next frame until the pager is truly stationary; the
    // commit then lands on the page the content actually shows.
    if (controller.position.isScrollingNotifier.value) {
      _scheduleDayViewSettleRetry(provider, settings);
      return;
    }
    final page = controller.page?.round();
    if (page == null) {
      return;
    }
    final target = _dayViewTargetForPage(settings, page);
    if (kDebugMode) {
      debugPrint(
        '[DayPager] settle: rawPage=${controller.page?.toStringAsFixed(3)} '
        '-> page=$page week=${target.week} day=${target.dayOfWeek} '
        'alreadySelected=${_selectedWeekForDayView == target.week && _selectedDayOfWeek == target.dayOfWeek}',
      );
    }
    _dayHeaderPreview.value = null;
    if (_selectedWeekForDayView == target.week &&
        _selectedDayOfWeek == target.dayOfWeek) {
      return;
    }
    setState(() {
      _selectedWeekForDayView = target.week;
      _selectedDayOfWeek = target.dayOfWeek;
    });
    _persistViewState(
      provider,
      mode: TimetableHomeViewMode.day,
      dayOfWeek: target.dayOfWeek,
    );
    // 鎵嬪娍鏀跺熬锛氶噸鏂版瑁呯偣鍑婚渿鎰燂紝涓嬩竴娆℃粦鍔紙鍚函鎯€х画婊戯級鍙啀娆¤Е鍙戙€?
    _daySwipeHapticFired = false;
    if (target.week != _visibleWeek && !_isSyncingWeekPage) {
      unawaited(_jumpToWeek(provider, target.week, animatePage: false));
    }
  }

  /// Re-checks the day pager on the next frame after a ScrollEnd arrived while
  /// the pager was still scrolling (a stale end interleaved with the next
  /// gesture). Once the pager is truly stationary the selection is committed
  /// to the page the content actually shows; if a fresh gesture owns the
  /// pager we wait for its own ScrollEnd instead of polling forever.
  void _scheduleDayViewSettleRetry(
    TimetableProvider provider,
    TimetableSettings settings,
  ) {
    if (!mounted || !_isDayView) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isDayView) {
        return;
      }
      final controller = _dayViewPageController;
      if (controller == null || !controller.hasClients) {
        return;
      }
      if (controller.position.isScrollingNotifier.value) {
        // Still mid-flight (snap spring running, or a new drag already owns
        // the pager): the next ScrollEnd will retry again.
        return;
      }
      _settleDayViewPage(provider, settings);
    });
  }

  /// Weekday-bar drag ? day-pager bridge. The bar acts as a visible-day-count
  /// (7x) scrubber over the day pager: bar deltas are amplified and injected
  /// straight into the pager's ScrollPosition, so the content follows the
  /// finger at week-per-bar-width speed while the bar itself moves slowly.
  void _startWeekdayBarDrag(
    TimetableSettings settings,
    DragStartDetails details,
  ) {
    _weekdayBarDrag?.cancel();
    _weekdayBarDrag = null;
    if (_isDaySwipeAnimating) {
      return;
    }
    final controller = _dayViewPageController;
    if (controller == null || !controller.hasClients) {
      return;
    }
    _weekdayBarDragScale = _visibleDayNumbers(settings).length.toDouble();
    // 鏄熸湡鏍忓埉鎿︿篃鏄竴娆℃墜鍔匡細鏁存鎷栧姩鍙繚鐣欎竴娆℃棩鍒囨崲鐐瑰嚮闇囨劅�?
    _daySwipeHapticFired = false;
    _dayPagerDragStartPage = controller.page?.roundToDouble();
    _weekdayBarDrag = controller.position.drag(details, () {
      _weekdayBarDrag = null;
    });
  }

  void _updateWeekdayBarDrag(DragUpdateDetails details) {
    final drag = _weekdayBarDrag;
    if (drag == null) {
      return;
    }
    final dx =
        (details.primaryDelta ?? details.delta.dx) * _weekdayBarDragScale;
    drag.update(
      DragUpdateDetails(
        sourceTimeStamp: details.sourceTimeStamp,
        delta: Offset(dx, 0),
        primaryDelta: dx,
        globalPosition: details.globalPosition,
        localPosition: details.localPosition,
      ),
    );
  }

  void _endWeekdayBarDrag(DragEndDetails details) {
    final drag = _weekdayBarDrag;
    _weekdayBarDrag = null;
    if (drag == null) {
      return;
    }
    // Release velocity is amplified like the deltas, then the pager's own
    // snap physics (_dayPagerPhysics) settles it ? same pipeline as a direct
    // content fling, so midpoint preview / ScrollEnd commit stay intact.
    final vx = details.velocity.pixelsPerSecond.dx * _weekdayBarDragScale;
    drag.end(
      DragEndDetails(
        velocity: Velocity(pixelsPerSecond: Offset(vx, 0)),
        primaryVelocity: vx,
      ),
    );
  }

  void _cancelWeekdayBarDrag() {
    final drag = _weekdayBarDrag;
    _weekdayBarDrag = null;
    drag?.cancel();
  }

  double? _pagerDragStartPageFromMetrics(ScrollMetrics metrics) {
    final pageUnit = metrics is PageMetrics
        ? math.max(1, metrics.viewportDimension * metrics.viewportFraction)
        : math.max(1, metrics.viewportDimension);
    return pageUnit <= 0 ? null : metrics.pixels / pageUnit;
  }

  /// One-shot read of the armed rescue velocity for [_dayPagerPhysics].
  /// Freshness-gated so a stale value can never leak into an unrelated
  /// ballistic (the drag consumes it within the same event dispatch).
  double _takeDayPagerRescueVelocity() {
    final armedAt = _dayPagerRescueArmedAt;
    final vx = _dayPagerRescueVelocityX;
    _dayPagerRescueVelocityX = 0;
    _dayPagerRescueArmedAt = null;
    if (armedAt == null ||
        DateTime.now().difference(armedAt) > const Duration(milliseconds: 90)) {
      return 0;
    }
    return vx;
  }

  /// Schedules wallpaper luminance sampling without sync I/O in build.
  ///
  /// File existence is checked asynchronously; results are cached per path,
  /// viewport and wallpaper alignment so a cover crop change cannot keep using
  /// a sample from an off-screen part of the image.
  /// 閲囩敤鍚姩棰勭儹鍣紙HomeStartupVisualPrimer锛夌紦瀛樼殑澹佺焊浜害甯︿綔鍒濆€笺�?
  ///
  /// 鍙湪鍐峰惎鍔ㄩ甯у墠鐨勭┖绐楁湡鐢熸晥涓€娆★細鏈〉浠讳綍浜害瀛楁宸茶璧嬪€兼垨甯歌
  /// 寮傛閲囨牱宸插惎鍔紙requestedKey 闈炵┖锛夋椂鐩存帴杩斿洖锛岀粷涓嶈鐩栫簿纭噰鏍风粨鏋溿�?
  void _seedWallpaperLuminanceFromStartupPrimer(TimetableSettings settings) {
    if (_wallpaperTopLuminance != null ||
        _wallpaperWeekdayLuminance != null ||
        _wallpaperBodyLuminance != null ||
        _wallpaperLuminanceRequestedKey != null) {
      return;
    }
    final bands = HomeStartupVisualPrimer.seededBandsFor(
      resolveHomePageBackdropImagePath(settings),
    );
    if (bands == null) {
      return;
    }
    _wallpaperTopLuminance = bands.top;
    _wallpaperWeekdayLuminance = bands.weekday;
    _wallpaperBodyLuminance = bands.body;
  }

  void _scheduleWallpaperLuminanceSampleIfNeeded(
    TimetableSettings settings, {
    required Size viewportSize,
  }) {
    final path = resolveHomePageBackdropImagePath(settings);
    if (path == null || path.isEmpty) {
      if (_wallpaperTopLuminance != null ||
          _wallpaperWeekdayLuminance != null ||
          _wallpaperBodyLuminance != null ||
          _wallpaperLuminanceSampleKey != null ||
          _wallpaperLuminanceRequestedKey != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          setState(() {
            _wallpaperTopLuminance = null;
            _wallpaperWeekdayLuminance = null;
            _wallpaperBodyLuminance = null;
            _wallpaperLuminanceSampleKey = null;
            _wallpaperLuminanceRequestedKey = null;
            _wallpaperLuminanceFileExists = false;
          });
        });
      }
      return;
    }
    final key = _wallpaperLuminanceKey(
      path: path,
      viewportSize: viewportSize,
      alignX: settings.homePageWallpaperAlignX,
      alignY: settings.homePageWallpaperAlignY,
    );
    if (_wallpaperLuminanceRequestedKey == key &&
        (_wallpaperLuminanceSampleKey == key ||
            !_wallpaperLuminanceFileExists)) {
      return;
    }
    // 鏈柟娉曞湪 build 鏈熼棿琚皟鐢紝鑰?_ensureWallpaperLuminanceForPath 棣栨�?
    // 锛坋xistsSync 缁撴灉鍒嗘祦锛夊惈鍚屾 setState锛氱洿鎺ヨ皟鐢ㄤ細鍦?build 鏈熸妸鏈粍�?
    // 鏍囪剰锛岃Е鍙?"setState() called during build" 寮傚父骞朵腑鏂绾镐寒搴﹂噰鏍?
    // 閾撅紝瀵艰嚧澧ㄨ壊鏋佹€у仠鍦ㄤ富棰橀粯璁よ壊銆傜粺涓€鎺ㄨ繜鍒板抚鍚庨璺戯紝澶╃劧瑙勯�?
    // build 鏈熼檺鍒讹紝閲嶅杩涘叆涔熺�?requestedKey 骞傜瓑鍘婚噸�?
    unawaited(
      Future<void>.sync(() {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          _ensureWallpaperLuminanceForPath(
            path,
            viewportSize: viewportSize,
            alignX: settings.homePageWallpaperAlignX,
            alignY: settings.homePageWallpaperAlignY,
            key: key,
          );
        });
      }),
    );
  }

  /// 閲囨牱缂撳瓨 key锛歚璺緞|瑙嗗彛瀹絰楂榺alignX|alignY`�?
  ///
  /// 缁勬垚瀛楁鍧囦负鍙灇涓剧殑鏈夐檺鏉ユ簮锛堝绾歌矾寰勬潵鑷?managed storage銆佽鍙ｆ潵�?
  /// MediaQuery銆佸榻愬€兼潵�?-1.0~1.0 鐨勬粦鏉嗭級锛岃皟鐢ㄦ柟涓嶄細娉ㄥ叆鎰忓鍒嗛殧绗︺�?
  /// ? `|` 鍒嗛殧瓒充互閬垮厤姝т箟锛屾棤闇€鍝堝笇鎴栫粨鏋勫�?key�?
  String _wallpaperLuminanceKey({
    required String path,
    required Size viewportSize,
    required double alignX,
    required double alignY,
  }) {
    return '$path|${viewportSize.width}x${viewportSize.height}|'
        '${alignX.clamp(-1.0, 1.0)}|${alignY.clamp(-1.0, 1.0)}';
  }

  Future<void> _ensureWallpaperLuminanceForPath(
    String path, {
    required Size viewportSize,
    required double alignX,
    required double alignY,
    required String key,
  }) async {
    if (_wallpaperLuminanceRequestedKey == key &&
        _wallpaperLuminanceSampleKey == key &&
        _wallpaperTopLuminance != null) {
      return;
    }
    // 涓嬮潰鐨勫瓧娈佃祴鍊肩粺涓€鏀舵暃�?setState 鍐咃細鏈柟娉曞湪寮傛鍥炶皟涓繍琛岋�?
    // 椋庢牸娣风敤锛堥儴鍒嗗湪 setState 澶栥€侀儴鍒嗗湪鍐咃級浼氳鍚庣画缁存姢鑰呴毦浠ュ垽�?
    // 鍝簺璧嬪€间細瑙﹀彂閲嶇粯锛屽鏄撴紡鍖呭鑷?UI 涓庣姸鎬佽劚鑺傘�?
    _wallpaperLuminanceRequestedKey = key;
    final fileExists = File(path).existsSync();
    if (!mounted || _wallpaperLuminanceRequestedKey != key) {
      return;
    }
    if (!fileExists) {
      if (_wallpaperTopLuminance != null ||
          _wallpaperWeekdayLuminance != null ||
          _wallpaperBodyLuminance != null ||
          _wallpaperLuminanceSampleKey != null ||
          _wallpaperLuminanceFileExists) {
        setState(() {
          _wallpaperTopLuminance = null;
          _wallpaperWeekdayLuminance = null;
          _wallpaperBodyLuminance = null;
          _wallpaperLuminanceSampleKey = null;
          _wallpaperLuminanceFileExists = false;
        });
      }
      return;
    }
    setState(() {
      _wallpaperLuminanceFileExists = true;
      _wallpaperLuminanceSampleKey = key;
    });
    await _loadWallpaperLuminance(
      path,
      viewportSize: viewportSize,
      alignX: alignX,
      alignY: alignY,
      key: key,
    );
  }

  Future<void> _loadWallpaperLuminance(
    String path, {
    required Size viewportSize,
    required double alignX,
    required double alignY,
    required String key,
  }) async {
    final bands = await sampleHomePageWallpaperLuminanceBands(
      path,
      viewportSize: viewportSize,
      alignX: alignX,
      alignY: alignY,
    );
    if (!mounted || _wallpaperLuminanceSampleKey != key) {
      return;
    }
    if (_wallpaperTopLuminance == bands?.top &&
        _wallpaperWeekdayLuminance == bands?.weekday &&
        _wallpaperBodyLuminance == bands?.body) {
      return;
    }
    setState(() {
      _wallpaperTopLuminance = bands?.top;
      _wallpaperWeekdayLuminance = bands?.weekday;
      _wallpaperBodyLuminance = bands?.body;
    });
  }

  /// Luminance used by both weekday rendering and the contrast explainer.
  /// When the weekday glass band is enabled, its scrim follows the header/top
  /// sample, so the warning must judge the same effective backdrop as the UI.
  double? _weekdayInkLuminance(TimetableSettings settings) {
    return settings.homePageWeekdayBarBlurEnabled
        ? _wallpaperTopLuminance
        : _wallpaperWeekdayLuminance ?? _wallpaperTopLuminance;
  }

  /// One-shot heads-up when a hand-picked weekday-bar ink has too little
  /// contrast against the current wallpaper. The ink is temporarily auto-flipped
  /// for readability ([homePageOverWallpaperInk]); this explains why the custom
  /// colour is not showing and offers restoring the default (auto B/W).
  void _maybeWarnWeekdayInkContrast(
    TimetableProvider provider,
    TimetableSettings settings,
  ) {
    // Judge custom ink against the band actually behind the weekday bar, not
    // the status/title strip above it.
    final luminance = _weekdayInkLuminance(settings);
    if (luminance == null || _weekdayInkWarningShowing) {
      return;
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (!hasHomePageBackdropImage(settings)) {
      return;
    }
    final configuredHex = isDark
        ? settings.weekdayBarFontColorDark
        : settings.weekdayBarFontColorLight;
    final defaultHex = isDark
        ? TimetableSettings.defaultWeekdayBarFontColorDark
        : TimetableSettings.defaultWeekdayBarFontColorLight;
    // Default ink already auto-flips with the wallpaper; only a custom pick
    // can go invisible (and trigger the temporary auto flip).
    if (homePageInkUsesBuiltInDefault(configuredHex, defaultHex)) {
      return;
    }
    final ink = tryParseHexColor(configuredHex);
    if (ink == null) {
      return;
    }
    // ~WCAG ratio against the sampled band; photos are busy, so anything
    // above 3:1 is left alone ? this only catches "nearly invisible".
    if (homePageInkHasSufficientContrast(ink, luminance)) {
      return;
    }
    final signature =
        '$configuredHex|${resolveHomePageBackdropImagePath(settings) ?? ''}|'
        '$isDark';
    if (_weekdayInkWarnedSignature == signature) {
      return;
    }
    _weekdayInkWarnedSignature = signature;
    unawaited(
      _showWeekdayInkContrastDialog(
        provider: provider,
        signature: signature,
        wallpaperIsDark: luminance < 0.45,
        isDarkTheme: isDark,
        defaultHex: defaultHex,
      ),
    );
  }

  Future<void> _showWeekdayInkContrastDialog({
    required TimetableProvider provider,
    required String signature,
    required bool wallpaperIsDark,
    required bool isDarkTheme,
    required String defaultHex,
  }) async {
    const prefsKey = 'weekday_ink_contrast_warned_signature';
    final prefs = await SharedPreferences.getInstance();
    // Same colour + wallpaper + theme was already explained once (persisted):
    // the user chose to keep it, so do not nag on every launch.
    if (prefs.getString(prefsKey) == signature) {
      return;
    }
    if (!mounted || _weekdayInkWarningShowing) {
      return;
    }
    _weekdayInkWarningShowing = true;
    await prefs.setString(prefsKey, signature);
    if (!mounted) {
      _weekdayInkWarningShowing = false;
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    try {
      await showHyperosDialog<void>(
        context: context,
        title: l10n.weekdayInkContrastTitle,
        body: Text(
          wallpaperIsDark
              ? l10n.weekdayInkContrastBodyDark
              : l10n.weekdayInkContrastBodyLight,
        ),
        actions: [
          HyperosDialogAction(
            label: l10n.gotItAction,
            onPressed: () => Navigator.pop(context),
          ),
          HyperosDialogAction(
            label: l10n.resetDefaultAction,
            isPrimary: true,
            onPressed: () {
              // Re-read the live settings: they may have changed while the
              // dialog was up, and only this one field should be touched.
              final current = provider.settings;
              unawaited(
                provider.updateSettings(
                  isDarkTheme
                      ? current.copyWith(weekdayBarFontColorDark: defaultHex)
                      : current.copyWith(weekdayBarFontColorLight: defaultHex),
                ),
              );
              Navigator.pop(context);
            },
          ),
        ],
      );
    } finally {
      _weekdayInkWarningShowing = false;
    }
  }

  Color _resolveHomeChromeForeground({
    required bool headerShowsWallpaper,
    required Color themeForeground,
  }) {
    if (!headerShowsWallpaper) {
      return themeForeground;
    }
    return homePageChromeForegroundForLuminance(
      _wallpaperTopLuminance,
      fallback: themeForeground,
    );
  }

  /// 鏍囬鍒嗗彂锛氭儏渚ｈ琛ㄥ紑鍏冲紑鍚笖宸茬粦�?TA 璇捐〃鏃舵樉绀?
  /// 銆屾垜鐨勬樀�?�?濂圭殑鏄电О銆嶆儏渚ｆ爣棰橈紙鐐瑰嚮鍒囨崲鎴戠�?濂圭殑璇捐〃锛夛紱
  /// 寮€鍏冲叧闂垨鏈粦瀹氭椂鏄剧ず搴旂敤鍚?+ profile 蹇€熷垏鎹€?
  Widget _buildHomeTitle(
    TimetableProvider provider, {
    required Color foreground,
    required Color mutedForeground,
  }) {
    final session = context.watch<WithuCoupleSessionProvider?>();
    if (provider.settings.coupleTimetableOverlayEnabled) {
      if (provider.hasPartnerBinding ||
          (session?.isLoggedIn ?? false) ||
          (session?.hasStoredSession ?? false)) {
        return _buildCoupleTitleSwitcher(
          provider,
          foreground: foreground,
          mutedForeground: mutedForeground,
        );
      }
      return _buildLoggedOutCoupleLoginTitle(
        provider,
        session: session,
        foreground: foreground,
        mutedForeground: mutedForeground,
      );
    }
    return _buildLegacyProfileSwitcherTrigger(
      provider,
      foreground: foreground,
      mutedForeground: mutedForeground,
    );
  }

  /// 鎯呬荆妯″紡宸插紑鍚絾鏈櫥褰曚笖鏈粦�?TA 璇捐〃鏃讹細淇濈暀鏅€氭爣棰樼殑
  /// 灞呬腑鏄剧ず銆屾湭鐧诲綍 ? 鐐瑰嚮鐧诲綍銆嶏紝涓嶆樉绀哄簲鐢ㄥ悕銆?
  Widget _buildLoggedOutCoupleLoginTitle(
    TimetableProvider provider, {
    required WithuCoupleSessionProvider? session,
    required Color foreground,
    required Color mutedForeground,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: GestureDetector(
          key: const ValueKey('withu_couple_login_chip'),
          onTap: _openWithuCoupleLogin,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              l10n.withuCoupleNotLoggedInPrompt,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: HyperosIconColors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 鎯呬荆鏍囬锛歔鎴戠殑鏄电О] 娓愬彉绾?鐖卞�?娓愬彉绾?[濂圭殑鏄电О]锛屽綋鍓嶆樉绀鸿皝�?
  /// 璇捐〃璋佺殑鏄电О甯﹂€変腑鐐癸紱鐐瑰嚮浠绘剰浣嶇疆鍦ㄤ袱浠借琛ㄩ棿鍒囨崲锛岄暱鎸夋墦寮€
  /// profile 蹇€熷垏鎹?sheet锛堝垏鎹㈡垜鑷繁鐨勫浠借琛級銆?
  Widget _buildCoupleTitleSwitcher(
    TimetableProvider provider, {
    required Color foreground,
    required Color mutedForeground,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final session = context.watch<WithuCoupleSessionProvider?>();
    final myProfile = provider.myTimetableProfile;
    final partnerProfile = provider.partnerProfile;
    final myName = session?.userNickname.trim().isNotEmpty == true
        ? session!.userNickname.trim()
        : (myProfile?.name.trim().isNotEmpty == true
              ? myProfile!.name.trim()
              : l10n.coupleTimetableLegendMine);
    final herName = session?.partnerNickname.trim().isNotEmpty == true
        ? session!.partnerNickname.trim()
        : (provider.partnerBinding?.partnerName.trim().isNotEmpty == true
              ? provider.partnerBinding!.partnerName.trim()
              : (partnerProfile?.name.trim().isNotEmpty == true
                    ? partnerProfile!.name.trim()
                    : l10n.coupleTimetableLegendPartner));
    final isHerActive =
        provider.activeProfileId == PartnerTimetableService.partnerProfileId;

    return GestureDetector(
      key: const ValueKey('profile_switcher_trigger'),
      onTap: _toggleCoupleTimetable,
      onLongPress: _showCoupleTitleLongPressActions,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        label: '$myName / $herName',
        button: true,
        child: SizedBox(
          width: double.infinity,
          child: Row(
            // Equal-width halves anchor the heart exactly on the full-title
            // centerline, even when the two nickname widths differ.
            children: [
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _buildCoupleNicknameBlock(
                          name: myName,
                          selected: !isHerActive,
                          foreground: foreground,
                        ),
                      ),
                    ),
                    _buildCoupleGradientLine(foreground, flowToRight: true),
                  ],
                ),
              ),
              _buildCoupleHeartSlot(session),
              Expanded(
                child: Row(
                  children: [
                    _buildCoupleGradientLine(foreground, flowToRight: false),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _buildCoupleNicknameBlock(
                          name: herName,
                          selected: isHerActive,
                          foreground: foreground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 鏄电О鍧楋細DancingScript 鎵嬪啓浣撴樀�?+ 閫変腑鎸囩ず鐐广€傚綋鍓嶈琛ㄥ搴旂殑涓€�?
  /// 鍔犵矖鏍囩孩锛屽彟涓€渚х粏浣撳崐閫忔槑鍓嶆櫙鑹层�?
  Widget _buildCoupleNicknameBlock({
    required String name,
    required bool selected,
    required Color foreground,
  }) {
    final transitionDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _profileSwitchRevealDuration;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedDefaultTextStyle(
            duration: transitionDuration,
            curve: Curves.easeInOutCubic,
            style: TextStyle(
              fontFamily: 'DancingScript',
              fontSize: 22,
              height: 1.1,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: selected ? HyperosIconColors.red : Colors.white,
            ),
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(height: 2),
          AnimatedContainer(
            duration: transitionDuration,
            curve: Curves.easeInOutCubic,
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected
                  ? HyperosIconColors.red
                  : foreground.withValues(alpha: 0.25),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoupleGradientLine(
    Color foreground, {
    required bool flowToRight,
  }) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return Container(
        width: _coupleLineWidth,
        height: 1.2,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: Colors.white,
      );
    }

    return AnimatedBuilder(
      animation: _coupleHeartbeatController,
      builder: (context, _) {
        final pulsePhase = (_coupleBeamController.value + 0.64) % 1;
        final travel = pulsePhase * 2 - 1;
        final offset = (flowToRight ? travel : -travel) * _coupleLineWidth;

        return SizedBox(
          width: _coupleLineWidth,
          height: 2,
          child: Stack(
            alignment: AlignmentDirectional.center,
            children: [
              Container(
                width: double.infinity,
                height: 1.2,
                color: Colors.white,
              ),
              ClipRect(
                child: SizedBox.expand(
                  child: Transform.translate(
                    offset: Offset(offset, 0),
                    child: Align(
                      alignment: flowToRight
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: Container(
                        width: 10,
                        height: 1.2,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(1),
                          gradient: LinearGradient(
                            begin: flowToRight
                                ? Alignment.centerLeft
                                : Alignment.centerRight,
                            end: flowToRight
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            colors: const [
                              Color(0xFFFF5252),
                              Color(0xFFFFAB40),
                              Color(0xFFFFF176),
                              Color(0xFF69F0AE),
                              Color(0xFF40C4FF),
                              Color(0xFFB388FF),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCoupleHeartbeatIcon() {
    if (MediaQuery.disableAnimationsOf(context)) {
      return const Icon(
        Icons.favorite_rounded,
        size: 16,
        color: HyperosIconColors.red,
      );
    }

    return AnimatedBuilder(
      animation: _coupleBeamController,
      builder: (context, child) {
        return Transform.scale(
          scale: _coupleHeartbeatScale.value,
          child: child,
        );
      },
      child: const Icon(
        Icons.favorite_rounded,
        size: 16,
        color: HyperosIconColors.red,
      ),
    );
  }

  /// 鐖卞績浣嶏細宸茬櫥褰曟樉绀虹埍蹇冿紱鏈櫥褰曟樉绀恒€岀櫥褰曘€嶅皬鍏ュ彛锛岀偣鍑昏繘�?
  /// WithU 鐧诲綍寮圭獥锛堝師銆屾湭鐧诲�?�?鐐瑰嚮鐧诲綍銆嶆彁绀虹殑鐧诲綍鍏ュ彛淇濈暀浜庢锛?
  /// 涓嶅啀鏁村潡闇稿崰鏍囬鍖猴紝鎯呬荆鏍囬鐨勫垏鎹㈠姛鑳藉缁堝彲鐢級銆?
  Widget _buildCoupleHeartSlot(WithuCoupleSessionProvider? session) {
    if ((session?.isLoggedIn ?? false) ||
        (session?.hasStoredSession ?? false)) {
      return _buildCoupleHeartbeatIcon();
    }
    return GestureDetector(
      key: const ValueKey('withu_couple_login_chip'),
      onTap: _openWithuCoupleLogin,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          AppLocalizations.of(context)!.withuLoginConfirm,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: HyperosIconColors.red,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// 杩涘�?WithU 鎯呬荆璐﹀彿鐧诲綍寮圭獥锛涚櫥褰曟垚鍔熷埛鏂版爣棰樺尯鐧诲綍鎬併€?
  Future<void> _openWithuCoupleLogin() async {
    final provider = context.read<TimetableProvider>();
    final sessionProvider = context.read<WithuCoupleSessionProvider>();
    final connected = await showWithuCoupleLoginSheet(
      context: context,
      onPullPartner: (service) => service.syncAfterLogin(provider: provider),
    );
    if (connected != true || !mounted) {
      return;
    }
    unawaited(sessionProvider.restoreSession());
    await provider.syncCoupleTimetableWidgetSnapshot();
  }

  /// 鎯呬荆鏍囬鐐瑰嚮锛氬湪鎴戠�?濂圭殑璇捐〃涔嬮棿鍒囨崲銆?
  Future<void> _toggleCoupleTimetable() async {
    final provider = context.read<TimetableProvider>();
    final targetId =
        provider.activeProfileId == PartnerTimetableService.partnerProfileId
        ? provider.myTimetableProfile?.id
        : PartnerTimetableService.partnerProfileId;
    if (targetId == null) {
      return;
    }
    await provider.switchProfile(targetId);
    if (mounted && provider.settings.enableHaptics) {
      HapticFeedback.selectionClick();
    }
  }

  /// 鏍囬锛堟湭缁戝�?TA 璇捐〃鏃讹級锛氬簲鐢ㄥ悕 + profile 蹇€熷垏鎹?sheet�?
  Widget _buildLegacyProfileSwitcherTrigger(
    TimetableProvider provider, {
    required Color foreground,
    required Color mutedForeground,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: _homeTitleHorizontalNudge),
      child: switch (provider.settings.homeTitleStyle) {
        HomeTitleStyle.classic => _buildLegacyClassicProfileSwitcherTrigger(
          provider,
          foreground: foreground,
        ),
        HomeTitleStyle.brand => _buildLegacyBrandProfileSwitcherTrigger(
          provider,
          foreground: foreground,
          mutedForeground: mutedForeground,
        ),
      },
    );
  }

  /// 鏍囬锛坈lassic 鎺掔増锛夛細搴旂敤鍚嶏紝鐐规寜鎵撳紑 profile 蹇€熷垏鎹?sheet�?
  Widget _buildLegacyClassicProfileSwitcherTrigger(
    TimetableProvider provider, {
    required Color foreground,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final foruiTheme = context.theme;
    return GestureDetector(
      key: const ValueKey('profile_switcher_trigger'),
      onTap: _showProfileQuickSwitchSheet,
      behavior: HitTestBehavior.opaque,
      child: Text(
        l10n.timetableAppName,
        style: foruiTheme.typography.display.xl.copyWith(
          fontWeight: FontWeight.w400,
          color: foreground,
        ),
      ),
    );
  }

  /// 鏍囬锛坆rand 鎺掔増锛夛細绗竴琛屽簲鐢ㄥ悕锛岀浜岃褰撳墠璇捐〃鍚嶃€?
  Widget _buildLegacyBrandProfileSwitcherTrigger(
    TimetableProvider provider, {
    required Color foreground,
    required Color mutedForeground,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final foruiTheme = context.theme;
    final activeProfileName = provider.activeProfile?.name.trim();
    return GestureDetector(
      key: const ValueKey('profile_switcher_trigger'),
      onTap: _showProfileQuickSwitchSheet,
      behavior: HitTestBehavior.opaque,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.timetableAppName,
              style: foruiTheme.typography.display.xl.copyWith(
                fontWeight: FontWeight.w400,
                color: foreground,
              ),
            ),
            Text(
              (activeProfileName == null || activeProfileName.isEmpty)
                  ? l10n.switchProfileHint
                  : activeProfileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: foruiTheme.typography.body.sm.copyWith(
                color: mutedForeground,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekDayHeader(
    TimetableProvider provider,
    int week,
    TimetableSettings settings,
    double timeColumnWidth, {
    bool hideBottomBorder = false,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasBackdrop = hasHomePageBackdropImage(settings);
    // Opaque/no-wallpaper chrome still needs a separator, but a full 1dp
    // ThemeData outline lands as a dark multi-physical-pixel band on dense
    // Android screens. Keep the wallpaper path's existing border untouched
    // and use the lighter HyperOS divider token only for the fallback.
    final subtleBorder = hasBackdrop
        ? context.theme.colors.border
        : HyperosColors.dividerLine(context);
    final dividerWidth = hasBackdrop ? 1.0 : 0.5;
    // Only flip by wallpaper luminance when this band actually shows the
    // wallpaper / frosted glass; with the scope toggled off it paints the
    // opaque page background and must use the theme / configured ink.
    final weekdayChromeOverWallpaper =
        hasBackdrop &&
        (homePageRegionShowsBackdrop(
              settings,
              HomePageBackgroundScope.weekdayBar,
            ) ||
            settings.homePageWeekdayBarBlurEnabled);
    // Judge ink from the band actually behind the weekday bar, not the
    // status/title strip above it ? the two can differ on the same photo.
    // With the weekday glass band on, follow the band's scrim polarity (the
    // scrim derives from the top sample) so ink and wash never fight.
    final weekdayLuminance = settings.homePageWeekdayBarBlurEnabled
        ? _wallpaperTopLuminance
        : _wallpaperWeekdayLuminance ?? _wallpaperTopLuminance;
    // Week label sits in the weekday chrome band: auto-invert default black/white
    // over a dark wallpaper; unreadable custom ink follows the same fallback.
    final weekLabelColor = homePageOverWallpaperInk(
      configuredHex: isDark
          ? settings.weekdayBarFontColorDark
          : settings.weekdayBarFontColorLight,
      defaultHex: isDark
          ? TimetableSettings.defaultWeekdayBarFontColorDark
          : TimetableSettings.defaultWeekdayBarFontColorLight,
      themeFallback: colorScheme.onSurface,
      hasBackdrop: weekdayChromeOverWallpaper,
      wallpaperLuminance: weekdayLuminance,
      minContrastRatio: 4.5,
      maximizeContrast: true,
      keepDefaultColorOverWallpaper: true,
    );
    final visibleDays = _visibleDayNumbers(settings);

    // Shared full-row builder: week label + back-to-current-week + the seven
    // day slots + the selection indicator ? one complete weekday bar row.
    // Week view renders one row per page (it scrolls with that page); day
    // view stacks three consecutive weeks and translates them with the pager
    // so the WHOLE bar slides like the week view's header.
    Widget fullWeekRowFor(int rowWeek, {required bool showExtras}) {
      return Row(
        children: [
          SizedBox(
            width: timeColumnWidth,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                InkWell(
                  onTap: _showWeekSelector,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    // 鏃堕棿鍒楀亸绐勶紝鐣ュ悜鍙宠鍛ㄦ涓庤妭娆℃暟瀛楄瑙変腑蹇冨榻愩€?
                    padding: const EdgeInsets.fromLTRB(8, 2, 2, 2),
                    child: _buildFlippingWeekLabel(
                      week: rowWeek,
                      maxWeek: settings.semesterWeekCount,
                      label: l10n.currentWeekCompact(rowWeek),
                      color: weekLabelColor,
                    ),
                  ),
                ),
                // 锛堝唴宓屻€屽洖鏈懆銆嶅皬瀛楀凡绉婚櫎�?
              ],
            ),
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Row(
                  children: visibleDays
                      .map((dayOfWeek) {
                        final date = _dateForWeekDay(
                          settings,
                          rowWeek,
                          dayOfWeek,
                        );
                        final isToday =
                            date != null && _isSameDate(date, DateTime.now());
                        final isSelected = _isSelectedDay(rowWeek, dayOfWeek);
                        final configuredWeekdayHex = isDark
                            ? settings.weekdayBarFontColorDark
                            : settings.weekdayBarFontColorLight;
                        final configuredAccentHex = isDark
                            ? settings.weekdayBarAccentColorDark
                            : settings.weekdayBarAccentColorLight;
                        // Default weekday ink flips with the band behind this
                        // bar; user-custom hex is kept (auto-flipped only when
                        // it would be unreadable). Accent (today/selected) gets
                        // the same readability fallback so the blue "today"
                        // column never vanishes into the photo.
                        final weekdayColor = homePageOverWallpaperInk(
                          configuredHex: configuredWeekdayHex,
                          defaultHex: isDark
                              ? TimetableSettings.defaultWeekdayBarFontColorDark
                              : TimetableSettings
                                    .defaultWeekdayBarFontColorLight,
                          themeFallback: colorScheme.onSurface,
                          hasBackdrop: weekdayChromeOverWallpaper,
                          wallpaperLuminance: weekdayLuminance,
                          minContrastRatio: 4.5,
                          maximizeContrast: true,
                          keepDefaultColorOverWallpaper: true,
                        );
                        final accentColor = homePageOverWallpaperAccent(
                          configuredHex: configuredAccentHex,
                          themeFallback: colorScheme.primary,
                          hasBackdrop: weekdayChromeOverWallpaper,
                          wallpaperLuminance: weekdayLuminance,
                          minContrastRatio: 4.5,
                          maximizeContrast: true,
                        );
                        final labelColor = (isSelected || isToday)
                            ? accentColor
                            : weekdayColor;
                        final subLabelColor = (isSelected || isToday)
                            ? accentColor.withValues(
                                alpha: isSelected ? 0.9 : 0.78,
                              )
                            : homePageOverWallpaperMutedInk(weekdayColor);
                        final showsTodayMarker = isToday && !isSelected;
                        final hasExamOnDay =
                            date != null && provider.hasExamOnDate(date);

                        return Expanded(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              key: ValueKey(
                                'weekday-header-$rowWeek-$dayOfWeek',
                              ),
                              borderRadius: BorderRadius.circular(14),
                              onTapDown: (details) =>
                                  _captureDayViewAnchor(details.globalPosition),
                              onTap: () => _toggleDayView(
                                week: rowWeek,
                                dayOfWeek: dayOfWeek,
                                settings: settings,
                              ),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOutCubic,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 1,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: showsTodayMarker
                                          ? accentColor.withValues(alpha: 0.35)
                                          : Colors.transparent,
                                      width: showsTodayMarker ? 2 : 0,
                                    ),
                                  ),
                                ),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    // 鍥哄�?40dp 鐨勬槦鏈熸爮鎵ｆ帀 3+3 鍐呰竟璺濆拰 0.5
                                    // 鍒嗛殧绾垮悗鏍煎瓙鍙墿 33.5dp锛屽钩閾鸿€冭瘯绾㈢偣浼氭妸
                                    // 鍐呭椤跺埌 34dp 婧㈠嚭锛涙敼鎮诞灞傚悗鍩虹鍐呭�?
                                    // ? 28dp锛屼换浣曞瑙傛ā寮忛兘鏈変綑閲忋�?
                                    Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          _weekdayLabel(context, dayOfWeek),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: isSelected || isToday
                                                ? FontWeight.w800
                                                : FontWeight.w600,
                                            color: labelColor,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        _buildFlippingDateLabel(
                                          settings: settings,
                                          week: rowWeek,
                                          dayOfWeek: dayOfWeek,
                                          date: date,
                                          color: subLabelColor,
                                        ),
                                      ],
                                    ),
                                    if (hasExamOnDay)
                                      Align(
                                        alignment: Alignment.bottomCenter,
                                        child: Container(
                                          key: const ValueKey(
                                            'weekday-exam-dot',
                                          ),
                                          width: 4,
                                          height: 4,
                                          decoration: BoxDecoration(
                                            color: colorScheme.error,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
                if (showExtras)
                  _buildWeekdaySelectionIndicator(
                    settings: settings,
                    week: rowWeek,
                    visibleDays: visibleDays,
                    wallpaperOverChrome: weekdayChromeOverWallpaper,
                    wallpaperLuminance: weekdayLuminance,
                  ),
              ],
            ),
          ),
        ],
      );
    }

    return AnimatedBuilder(
      animation: _weekPageController,
      child: Container(
        height: _weekDayHeaderHeight,
        padding: EdgeInsets.zero,
        decoration: hideBottomBorder
            ? null
            : BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: subtleBorder, width: dividerWidth),
                ),
              ),
        child: _isDayView && _dayViewPageController != null
            ? AnimatedBuilder(
                animation: _dayViewPageController!,
                builder: (context, _) {
                  // The row stays anchored. The selection indicator still
                  // tracks the day pager; cross-week labels flip in place
                  // rather than dragging the complete bar across the screen.
                  final preview = _dayHeaderPreview.value;
                  final selectedWeek =
                      preview?.$1 ?? _selectedWeekForDayView ?? week;
                  return fullWeekRowFor(selectedWeek, showExtras: true);
                },
              )
            : fullWeekRowFor(week, showExtras: true),
      ),
      builder: (context, header) {
        final horizontalPosition = Scrollable.maybeOf(
          context,
          axis: Axis.horizontal,
        )?.position;
        final pageDelta =
            horizontalPosition != null &&
                horizontalPosition.hasContentDimensions &&
                horizontalPosition.viewportDimension > 0
            ? (horizontalPosition.pixels /
                      horizontalPosition.viewportDimension) -
                  (week - 1)
            : 0.0;
        // The page still slides underneath, but the visible weekday bar is
        // counter-translated every frame, so the chrome reads as fixed.
        return Transform.translate(
          offset: Offset(
            -pageDelta.clamp(-1.0, 1.0).toDouble() *
                (horizontalPosition?.viewportDimension ?? 0),
            0,
          ),
          child: header,
        );
      },
    );
  }

  Widget _buildFlippingDateLabel({
    required TimetableSettings settings,
    required int week,
    required int dayOfWeek,
    required DateTime? date,
    required Color color,
  }) {
    final labelStyle = TextStyle(fontSize: 8.5, color: color);

    String formatDate(DateTime? value) {
      if (value == null) {
        return '';
      }
      return '${value.month.toString().padLeft(2, '0')}/'
          '${value.day.toString().padLeft(2, '0')}';
    }

    final staticLabel = Text(formatDate(date), style: labelStyle);
    if (date == null || MediaQuery.disableAnimationsOf(context)) {
      return staticLabel;
    }

    return AnimatedBuilder(
      animation: _weekPageController,
      builder: (context, _) {
        final hasClients = _weekPageController.hasClients;
        final rawPage = hasClients
            ? (_weekPageController.page ??
                  _weekPageController.initialPage.toDouble())
            : _weekPageController.initialPage.toDouble();
        final maxWeek = settings.semesterWeekCount;
        final settledWeek = (rawPage.roundToDouble().round() + 1).clamp(
          1,
          maxWeek,
        );
        if (!hasClients ||
            rawPage < 0 ||
            rawPage > maxWeek - 1 ||
            (rawPage - rawPage.roundToDouble()).abs() < 0.001) {
          return Text(
            formatDate(_dateForWeekDay(settings, settledWeek, dayOfWeek)),
            key: ValueKey('timetable-date-$settledWeek-$dayOfWeek'),
            style: labelStyle,
          );
        }

        final lowerPage = rawPage.floorToDouble();
        final upperPage = (lowerPage + 1).clamp(0.0, (maxWeek - 1).toDouble());
        final progress = (rawPage - lowerPage).clamp(0.0, 1.0);
        final movingForward = _weekSwipeDirection >= 0;
        final leavingWeek =
            ((movingForward ? lowerPage : upperPage).round() + 1).clamp(
              1,
              maxWeek,
            );
        final arrivingWeek =
            ((movingForward ? upperPage : lowerPage).round() + 1).clamp(
              1,
              maxWeek,
            );
        if (leavingWeek == arrivingWeek) {
          return Text(
            formatDate(_dateForWeekDay(settings, settledWeek, dayOfWeek)),
            key: ValueKey('timetable-date-$settledWeek-$dayOfWeek'),
            style: labelStyle,
          );
        }

        final leavingDate = _dateForWeekDay(settings, leavingWeek, dayOfWeek);
        final arrivingDate = _dateForWeekDay(settings, arrivingWeek, dayOfWeek);
        if (leavingDate == null || arrivingDate == null) {
          return staticLabel;
        }

        final leavingOpacity = (movingForward ? 1 - progress : progress).clamp(
          0.0,
          1.0,
        );
        final arrivingOpacity = (movingForward ? progress : 1 - progress).clamp(
          0.0,
          1.0,
        );
        return Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: leavingOpacity,
              child: Text(
                formatDate(leavingDate),
                key: ValueKey('timetable-date-$leavingWeek-$dayOfWeek'),
                style: labelStyle,
              ),
            ),
            Opacity(
              opacity: arrivingOpacity,
              child: Text(
                formatDate(arrivingDate),
                key: ValueKey('timetable-date-$arrivingWeek-$dayOfWeek'),
                style: labelStyle,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFlippingWeekLabel({
    required int week,
    required int maxWeek,
    required String label,
    required Color color,
  }) {
    final labelStyle = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w800,
      color: color,
    );
    final numberMatch = RegExp(r'\d+').firstMatch(label);
    if (numberMatch == null) {
      return Text(label, textAlign: TextAlign.center, style: labelStyle);
    }

    final prefix = label.substring(0, numberMatch.start);
    final suffix = label.substring(numberMatch.end);
    final numberText = numberMatch.group(0)!;
    final scaledFontSize = MediaQuery.textScalerOf(context).scale(10);
    final numberWidth = (scaledFontSize * 1.45).clamp(12.0, 28.0).toDouble();

    Widget buildNumber(String value) {
      return Text(
        value,
        key: ValueKey('timetable-week-number-$value'),
        textAlign: TextAlign.center,
        style: labelStyle,
      );
    }

    Widget buildCompactLabel(List<Widget> children) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      );
    }

    final staticNumberLabel = buildCompactLabel([
      if (prefix.isNotEmpty) Text(prefix, style: labelStyle),
      SizedBox(width: numberWidth, child: buildNumber(numberText)),
      if (suffix.isNotEmpty) Text(suffix, style: labelStyle),
    ]);
    if (MediaQuery.disableAnimationsOf(context)) {
      return staticNumberLabel;
    }

    return buildCompactLabel([
      if (prefix.isNotEmpty) Text(prefix, style: labelStyle),
      SizedBox(
        width: numberWidth,
        child: AnimatedBuilder(
          animation: _weekPageController,
          builder: (context, _) {
            final hasClients = _weekPageController.hasClients;
            final rawPage = hasClients
                ? (_weekPageController.page ??
                      _weekPageController.initialPage.toDouble())
                : _weekPageController.initialPage.toDouble();
            final settledWeek = (rawPage.roundToDouble().round() + 1).clamp(
              1,
              maxWeek,
            );
            if (!hasClients ||
                rawPage < 0 ||
                rawPage > maxWeek - 1 ||
                (rawPage - rawPage.roundToDouble()).abs() < 0.001) {
              return buildNumber('$settledWeek');
            }

            final lowerPage = rawPage.floorToDouble();
            final upperPage = (lowerPage + 1).clamp(
              0.0,
              (maxWeek - 1).toDouble(),
            );
            final progress = (rawPage - lowerPage).clamp(0.0, 1.0);
            final movingForward = _weekSwipeDirection >= 0;
            final leavingWeek =
                ((movingForward ? lowerPage : upperPage).round() + 1).clamp(
                  1,
                  maxWeek,
                );
            final arrivingWeek =
                ((movingForward ? upperPage : lowerPage).round() + 1).clamp(
                  1,
                  maxWeek,
                );
            if (leavingWeek == arrivingWeek) {
              return buildNumber('$settledWeek');
            }

            final leavingOpacity = (movingForward ? 1 - progress : progress)
                .clamp(0.0, 1.0);
            final arrivingOpacity = (movingForward ? progress : 1 - progress)
                .clamp(0.0, 1.0);
            return Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: leavingOpacity,
                  child: buildNumber('$leavingWeek'),
                ),
                Opacity(
                  opacity: arrivingOpacity,
                  child: buildNumber('$arrivingWeek'),
                ),
              ],
            );
          },
        ),
      ),
      if (suffix.isNotEmpty) Text(suffix, style: labelStyle),
    ]);
  }

  Widget _buildWeekdaySelectionIndicator({
    required TimetableSettings settings,
    required int week,
    required List<int> visibleDays,
    required bool wallpaperOverChrome,
    required double? wallpaperLuminance,
  }) {
    final controller = _dayViewPageController;
    if (!_shouldShowDayViewOverlay ||
        controller == null ||
        visibleDays.isEmpty) {
      return const SizedBox.shrink();
    }
    // In day view the indicator follows the pager live even mid cross-week
    // (its week argument is the pager's floor week, which briefly differs
    // from the settled selection); in week view it is per-page and only
    // shows on the settled page.
    if (!_isDayView && _visibleDayViewWeek != week) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectionAccent = homePageOverWallpaperAccent(
      configuredHex: isDark
          ? settings.weekdayBarAccentColorDark
          : settings.weekdayBarAccentColorLight,
      themeFallback: colorScheme.primary,
      hasBackdrop: wallpaperOverChrome,
      wallpaperLuminance: wallpaperLuminance,
    );

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          if (totalWidth <= 0) {
            return const SizedBox.shrink();
          }
          final slotWidth = totalWidth / visibleDays.length;

          return AnimatedBuilder(
            animation: controller,
            builder: (context, child) {
              final rawPage = controller.hasClients
                  ? (controller.page ?? controller.initialPage.toDouble())
                  : controller.initialPage.toDouble();
              // Weekday position within the bar's week: the pager is
              // globally continuous, so subtract the week's page offset.
              final rawDayPosition = rawPage - (week - 1) * visibleDays.length;
              final maxDayIndex = (visibleDays.length - 1).toDouble();
              final clampedDayPosition = rawDayPosition
                  .clamp(0.0, maxDayIndex)
                  .toDouble();
              final overflow = rawDayPosition < 0
                  ? -rawDayPosition
                  : rawDayPosition > maxDayIndex
                  ? rawDayPosition - maxDayIndex
                  : 0.0;
              final fractionalProgress =
                  clampedDayPosition - clampedDayPosition.floorToDouble();
              final betweenDaysProgress =
                  (1 - (2 * (fractionalProgress - 0.5).abs()))
                      .clamp(0.0, 1.0)
                      .toDouble();
              final betweenDaysCurve = Curves.easeInOutCubicEmphasized
                  .transform(betweenDaysProgress);
              final edgeCurve = Curves.easeOutCubic.transform(
                overflow.clamp(0.0, 1.0),
              );
              final morphProgress = math.max(
                betweenDaysCurve * 0.55,
                edgeCurve,
              );
              final baseWidth = math.min(22, slotWidth * 0.34);
              final indicatorWidth =
                  baseWidth + (slotWidth * 0.24 * morphProgress);
              final edgeDirection = rawDayPosition < 0
                  ? -1.0
                  : rawDayPosition > maxDayIndex
                  ? 1.0
                  : 0.0;
              final edgePull = slotWidth * 0.10 * edgeCurve * edgeDirection;
              final centeredLeft =
                  slotWidth * clampedDayPosition +
                  ((slotWidth - indicatorWidth) / 2);
              final maxLeft = math.max(0, totalWidth - indicatorWidth);
              final indicatorLeft = (centeredLeft + edgePull)
                  .clamp(0.0, maxLeft)
                  .toDouble();
              final indicatorHeight = 3.0 + (1.4 * morphProgress);

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: indicatorLeft,
                    bottom: 0,
                    child: DecoratedBox(
                      key: ValueKey('weekday-selection-indicator-$week'),
                      decoration: BoxDecoration(
                        // Match weekday accent (custom blue etc.), not raw primary.
                        color: selectionAccent,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: selectionAccent.withValues(alpha: 0.18),
                            blurRadius: 8 + (8 * morphProgress),
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: SizedBox(
                        width: indicatorWidth,
                        height: indicatorHeight,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTimetableGrid(
    TimetableProvider provider,
    TimetableSettings settings,
    double availableWidth,
    int week,
    double sectionHeight, {
    required ScrollController weekGridScrollController,
    bool animateCourseEntrance = true,
  }) {
    final visibleDays = _visibleDayNumbers(settings);
    final timeColumnWidth = _resolveTimeColumnWidth(settings);
    final cardInset = _resolveCourseCardInset(settings);
    final dayWidth = (availableWidth - timeColumnWidth) / visibleDays.length;
    return SizedBox(
      key: ValueKey<int>(week),
      width: availableWidth,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: timeColumnWidth,
            // Keep the lane transparent while cards slide above it. The
          ),
          Expanded(
            child: homePageBackgroundLayer(
              visual: resolveHomePageRegionBackground(
                settings: settings,
                isDark: Theme.of(context).brightness == Brightness.dark,
                darkFallback: Theme.of(context).colorScheme.surface,
                region: HomePageBackgroundScope.timetable,
              ),
              child: RepaintBoundary(
                child: _wrapCourseGridSurfaceHost(
                  settings: settings,
                  child: Row(
                    children: visibleDays.asMap().entries.map((entry) {
                      final dayIndex = entry.key;
                      final dayOfWeek = entry.value;
                      final dayCourses = _getCoursesForDay(
                        provider.courses,
                        week,
                        dayOfWeek,
                        settings,
                      );
                      final displayItems = _buildHomeDayDisplayItems(
                        provider: provider,
                        settings: settings,
                        week: week,
                        dayOfWeek: dayOfWeek,
                        myCourses: dayCourses,
                      );
                      return SizedBox(
                        width: dayWidth,
                        child: _buildDayColumn(
                          week,
                          dayOfWeek,
                          displayItems,
                          settings,
                          settings.showConflictBadgeOnTimetable,
                          sectionHeight,
                          cardInset,
                          provider,
                          animateCourseEntrance: animateCourseEntrance,
                          dayIndex: dayIndex,
                          dayCount: visibleDays.length,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFixedTimeColumn(
    TimetableSettings settings,
    double sectionHeight, {
    required double followOffset,
    double horizontalOffset = 0,
    double scale = 1,
    double opacity = 1,
  }) {
    return Transform.translate(
      key: const ValueKey('timetable-time-column-motion'),
      offset: Offset(horizontalOffset, followOffset),
      child: Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Column(
            key: const ValueKey('timetable-time-column'),
            children: List.generate(settings.sectionCount, (index) {
              final section = settings.sections[index];
              return Container(
                height: sectionHeight,
                alignment: Alignment.center,
                child: _buildSectionTimeCell(index + 1, section, settings),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildFollowingTimeColumn({
    required TimetableSettings settings,
    required double sectionHeight,
    required int maxWeek,
  }) {
    // The week swipe is a z-stack reveal (see _buildWeekPagerDeck). The
    // fixed rail below only paints while the deck is idle; during the swipe
    // each deck card carries its own copy of the time column (inside
    // _buildWeekDeckCard) so the rail slides and scales together with the
    // timetable instead of staying parked.
    return _buildFixedTimeColumn(settings, sectionHeight, followOffset: 0);
  }

  /// One-shot "incoming card" reveal matching [_buildPagerCardTransition]:
  /// the timetable surface scales 0.79 -> 1, fades 0.22 -> 1 and unblurs
  /// 14 -> 0 when the active profile switches. Wraps week view and the
  /// day-view overlay (both live inside [_buildWeekPager]).
  Widget _wrapProfileSwitchReveal(Widget child) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    return AnimatedBuilder(
      animation: _profileSwitchController,
      child: child,
      builder: (context, content) {
        final progress = _profileSwitchController.value;
        if (progress >= 1) {
          return content!;
        }
        final appearProgress =
            ((progress - _cardPagerAppearStart) / (1.0 - _cardPagerAppearStart))
                .clamp(0.0, 1.0);
        final scale =
            _cardPagerMinScale + (1.0 - _cardPagerMinScale) * appearProgress;
        final alpha =
            (_cardPagerAppearOpacity +
                    (1.0 - _cardPagerAppearOpacity) * appearProgress)
                .clamp(0.0, 1.0);
        final blurSigma = _cardPagerMaxBlurSigma * (1.0 - appearProgress);
        final alphaFilter = ui.ColorFilter.mode(
          Color.fromARGB((alpha * 255).round(), 0, 0, 0),
          ui.BlendMode.dstIn,
        );
        return ImageFiltered(
          imageFilter: blurSigma > 0
              ? ui.ImageFilter.compose(
                  outer: alphaFilter,
                  inner: ui.ImageFilter.blur(
                    sigmaX: blurSigma,
                    sigmaY: blurSigma,
                    tileMode: ui.TileMode.clamp,
                  ),
                )
              : alphaFilter,
          child: Transform.scale(scale: scale, child: content),
        );
      },
    );
  }

  Widget _buildHomePullQuickImportSurface({
    required TimetableProvider provider,
    required TimetableSettings settings,
    required bool hasBackdrop,
  }) {
    // Home timetable only: no HyperOS rubber-band. Other pages keep
    // [HyperosScrollBehavior] from [HyperosRootPage].
    Widget surface = ScrollConfiguration(
      behavior: const _TimetableHomeScrollBehavior(),
      child: Padding(
        key: _timetableSurfaceKey,
        padding: EdgeInsets.only(bottom: hasBackdrop ? 0 : 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return _buildWeekPager(
              provider,
              settings,
              constraints.maxWidth,
              constraints.maxHeight,
            );
          },
        ),
      ),
    );

    if (!settings.homePullQuickImportEnabled) {
      return surface;
    }

    // Prefer scroll overscroll (clamping) so left/right week paging stays free.
    surface = NotificationListener<ScrollNotification>(
      onNotification: _handleHomePullScrollNotification,
      child: surface,
    );

    // Auto-fit week grid has no vertical Scrollable; use a vertical-only drag
    // that does not claim the arena until the gesture is clearly vertical.
    if (settings.timetableAutoFitSectionHeight) {
      surface = _HomePullVerticalDragDetector(
        enabled: !_isDayView && !_isHomePullQuickImportRunning,
        onPullUpdate: _updateHomePullDragDistance,
        onPullEnd: _finishHomePullDrag,
        onPullCancel: _cancelHomePullDrag,
        child: surface,
      );
    }

    return surface;
  }

  Widget _buildHomePullQuickImportIndicator(AppLocalizations l10n) {
    final pullProgress =
        (_homePullDragDistance / _homePullQuickImportTriggerDistance).clamp(
          0.0,
          1.0,
        );
    // Show label a bit earlier so the pill never looks like a lone spinner.
    final showLabel =
        _isHomePullQuickImportRunning ||
        _homePullDragDistance >= _homePullQuickImportTriggerDistance * 0.45;
    const indicatorTopInset = _weekDayHeaderHeight + 8;
    // Subtle follow ? 11px max, eased, not the previous 27px linear slide.
    final followY = () {
      if (_isHomePullQuickImportRunning) return 0.0;
      final d = _homePullDragDistance;
      const cap = 32.0;
      if (d <= cap) return d * 0.34;
      return cap * 0.34 + (d - cap) * 0.06;
    }();
    final eased = Curves.easeOutCubic.transform(pullProgress);
    final scale = _isHomePullQuickImportRunning
        ? 1.0
        : (0.92 + eased * 0.08).clamp(0.92, 1.0);
    // Fade from 0 so the pill doesn't flash at tiny drags.
    final opacity = _isHomePullQuickImportRunning ? 1.0 : eased.clamp(0.0, 1.0);
    // Don't build the pill at all when fully transparent to avoid hit-test.
    if (!_isHomePullQuickImportRunning && pullProgress < 0.02) {
      return const SizedBox.shrink();
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color:
            (isDark
                    ? HyperosMiuixDarkColors.surfaceContainerHigh
                    : HyperosMiuixLightColors.surfaceContainer)
                .withValues(alpha: isDark ? 0.88 : 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: (isDark ? Colors.white : HyperosMiuixLightColors.outline)
              .withValues(alpha: isDark ? 0.10 : 0.14),
          width: 0.6,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.10 : 0.05),
            blurRadius: 36,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: _isHomePullQuickImportRunning
                ? const MiuixCircularProgressIndicator(
                    size: 16,
                    strokeWidth: 1.9,
                  )
                : MiuixCircularProgressIndicator(
                    progress: pullProgress.clamp(0.0, 1.0),
                    size: 16,
                    strokeWidth: 1.9,
                  ),
          ),
          if (showLabel) ...[
            const SizedBox(width: 10),
            Text(
              l10n.homePullQuickImportFetchingCourses,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: HyperosColors.primaryText(context),
                fontWeight: FontWeight.w500,
                letterSpacing: 0.1,
              ),
            ),
          ],
          if (_isHomePullQuickImportRunning) ...[
            const SizedBox(width: 10),
            Container(
              width: 0.8,
              height: 14,
              color: HyperosColors.dividerLine(context),
            ),
            const SizedBox(width: 10),
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: _cancelHomePullQuickImport,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    l10n.quickImportCancelImportAction,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: HyperosColors.primary(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    // Frosted glass when a wallpaper is behind the grid, otherwise the solid
    // Miuix card above. Keep the blur cheap: single BackdropFilter on the pill
    // only, not the whole page.
    final hasBackdrop = hasHomePageBackdropImage(
      context.read<TimetableProvider>().settings,
    );
    final decoratedPill = hasBackdrop
        ? ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: pill,
            ),
          )
        : pill;

    return Positioned(
      top: indicatorTopInset,
      left: 0,
      right: 0,
      child: Center(
        child: Transform.translate(
          offset: Offset(0, followY),
          child: Transform.scale(
            scale: scale,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              opacity: opacity,
              child: decoratedPill,
            ),
          ),
        ),
      ),
    );
  }

  void _updateHomePullDragDistance(double deltaDy) {
    if (_isHomePullQuickImportRunning) {
      return;
    }
    final atRest =
        _homePullDragDistance <= 0.5 && _homePullTouchDistance <= 0.5;
    if (deltaDy <= 0 && atRest) {
      return;
    }
    // Finger takes over from any in-flight settle spring.
    if (_homePullSettleSpring?.isAnimating ?? false) {
      _homePullSettleGeneration++;
      _homePullSettleSpring?.stop();
    }
    if (deltaDy > 0) {
      _homePullTouchDistance = (_homePullTouchDistance + deltaDy).clamp(
        0.0,
        _homePullDampingRange,
      );
    } else {
      // Retract "feels immediate"; keep raw travel 1:1.
      _homePullTouchDistance = (_homePullTouchDistance + deltaDy).clamp(
        0.0,
        _homePullDampingRange,
      );
    }
    final nextVisual = HyperosHomePullPhysics.visualOffset(
      _homePullTouchDistance,
      _homePullDampingRange,
    ).clamp(0.0, _homePullQuickImportMaxDistance);
    const threshold = _homePullQuickImportTriggerDistance;
    final crossedUp =
        _homePullDragDistance < threshold && nextVisual >= threshold;
    final reArmed =
        _homePullDragDistance >= threshold && nextVisual < threshold * 0.88;
    if (reArmed) _homePullHapticArmed = true;
    if (nextVisual == _homePullDragDistance && !crossedUp) {
      return;
    }
    if (crossedUp && _homePullHapticArmed) {
      _homePullHapticArmed = false;
      // 鍚屾璇诲彇 provider锛欵lement 宸插嵏杞芥椂 context.read 浼氭姏寮傚父�?
      // 鍓嶇�?mounted 瀹堝崼鏇夸唬鍚炲紓甯革紝閬垮厤鎺╃洊鐪熷疄鐨?unmounted-read bug�?
      if (mounted) {
        final settings = context.read<TimetableProvider>().settings;
        if (settings.enableHaptics) HapticFeedback.selectionClick();
      }
    }
    setState(() {
      _homePullDragDistance = nextVisual;
    });
  }

  void _finishHomePullDrag() {
    final shouldTrigger =
        _homePullDragDistance >= _homePullQuickImportTriggerDistance;
    _homePullSettleTo(0);
    _homePullHapticArmed = true;
    if (shouldTrigger) {
      unawaited(_runHomePullQuickImport());
    }
  }

  void _cancelHomePullDrag() {
    _homePullSettleTo(0);
    _homePullHapticArmed = true;
  }

  // --- Home pull spring helpers (HyperOS critical-damped, period 0.4s) ---
  void _driveHomePullSettle() {
    final spring = _homePullSettleSpring;
    if (spring == null) return;
    final v = spring.value;
    if (!mounted) return;
    setState(() {
      _homePullDragDistance = v.clamp(0.0, _homePullQuickImportMaxDistance);
      _homePullTouchDistance = HyperosHomePullPhysics.touchForOffset(
        v,
        _homePullDampingRange,
      ).clamp(0.0, _homePullDampingRange);
    });
  }

  void _homePullSettleTo(double target) {
    final spring = _homePullSettleSpring;
    if (spring == null) {
      setState(() {
        _homePullDragDistance = target;
        _homePullTouchDistance = HyperosHomePullPhysics.touchForOffset(
          target,
          _homePullDampingRange,
        );
      });
      return;
    }
    final generation = ++_homePullSettleGeneration;
    spring.value = _homePullDragDistance;
    final sim = SpringSimulation(
      HyperosHomePullPhysics.spring,
      spring.value,
      target,
      0,
    );
    // ignore: discarded_futures
    spring
        .animateWith(sim)
        .then((_) {
          if (!mounted || generation != _homePullSettleGeneration) return;
          setState(() {
            _homePullDragDistance = target;
            _homePullTouchDistance = HyperosHomePullPhysics.touchForOffset(
              target,
              _homePullDampingRange,
            );
          });
        })
        .catchError((Object _) {});
  }

  /// Clamping overscroll at the top of the week/day vertical scrollables.
  bool _handleHomePullScrollNotification(ScrollNotification notification) {
    if (_isHomePullQuickImportRunning) {
      return false;
    }
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) {
      return false;
    }

    final atTop = metrics.pixels <= metrics.minScrollExtent + 0.5;

    // While the pull affordance is open, upward content scroll retracts it.
    //
    // Deliberately does *not* try to undo the scroll: `ScrollPosition.correctBy`
    // is only valid from the layout pass (`applyContentDimensions`), and calling
    // it from a notification callback trips assertions / causes scroll jitter.
    // Letting the list scroll while the indicator retracts is the safe
    // behaviour, and visually reads the same on device.
    if (_homePullDragDistance > 0 && notification is ScrollUpdateNotification) {
      final scrollDelta = notification.scrollDelta ?? 0.0;
      if (scrollDelta > 0) {
        _updateHomePullDragDistance(-scrollDelta);
        return false;
      }
    }

    if (notification is OverscrollNotification && atTop) {
      // Negative overscroll = past the leading edge (top) while pulling down.
      if (notification.overscroll < 0) {
        _updateHomePullDragDistance(-notification.overscroll);
      } else if (notification.overscroll > 0 && _homePullDragDistance > 0) {
        // Positive overscroll at top while pull is open: treat as retract.
        _updateHomePullDragDistance(-notification.overscroll);
      }
      return false;
    }

    if (notification is ScrollEndNotification && _homePullDragDistance > 0) {
      _finishHomePullDrag();
      return false;
    }

    return false;
  }

  void _cancelHomePullQuickImport() {
    final cancel = _homePullQuickImportCancel;
    if (cancel == null) {
      return;
    }
    cancel();
    if (mounted) {
      setState(() {
        _isHomePullQuickImportRunning = false;
        _homePullQuickImportCancel = null;
      });
    }
  }

  Future<void> _runHomePullQuickImport() async {
    if (_isHomePullQuickImportRunning || !mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    _homePullSettleGeneration++;
    _homePullSettleSpring?.stop();
    _homePullHapticArmed = true;
    _homePullTouchDistance = 0;
    setState(() {
      _isHomePullQuickImportRunning = true;
      _homePullDragDistance = 0;
      _homePullQuickImportCancel = null;
    });
    // 鍚屾璇诲彇 provider锛氬墠缃?mounted 瀹堝崼鏇夸唬鍚炲紓甯革紝閬垮厤鎺╃洊
    // unmounted-read ? bug�?
    if (mounted) {
      if (context.read<TimetableProvider>().settings.enableHaptics) {
        HapticFeedback.mediumImpact();
      }
    }
    try {
      await runHomePullWarehouseQuickImport(
        context,
        onNeedsManualAction: () {
          if (!mounted) {
            return;
          }
          showAppLightTip(
            context,
            message: l10n.homePullQuickImportNeedsManualAction,
          );
        },
        onCancelAvailable: (cancel) {
          if (!mounted) {
            return;
          }
          setState(() {
            _homePullQuickImportCancel = cancel;
          });
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _isHomePullQuickImportRunning = false;
          _homePullQuickImportCancel = null;
        });
      }
    }
  }

  // Card paging tuning: the incoming neighbor enters the centered card reveal.
  // Forward (left swipe): the incoming page rises from below (scale 85% -> 100%,
  // opacity 0.0052 -> 1, blur 14 sigma -> 0) while the outgoing page follows the
  // finger away. Backward (right swipe): the outgoing page stacks in place and
  // recedes (opacity 1 -> 0.0052, shrink to 85%, blur) while the left neighbor
  // drops in from the very top.
  static const double _cardPagerAppearStart = 0.1314;
  static const double _cardPagerAppearOpacity = 0.0052;
  static const double _cardPagerMaxBlurSigma = 14;
  static const double _cardPagerMinScale = 0.85;

  /// Only the gesture-target neighbor enters the centered card reveal.
  Widget _buildPagerCardTransition({
    required PageController controller,
    required int page,
    required Widget child,
    double? Function()? takeDragStartPage,
    double? Function()? takeDragDirection,
  }) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, cardChild) {
        final activePage =
            controller.hasClients && controller.position.hasContentDimensions
            ? (controller.page ?? page.toDouble())
            : page.toDouble();
        final leadDirection = _updatePagerLeadDirection(controller, activePage);
        final dragStartPage = takeDragStartPage?.call();
        final dragDirection = takeDragDirection?.call();
        if (dragStartPage == null) return cardChild ?? child;
        final resolvedDirection = dragDirection ?? leadDirection;
        final pageDelta = page - dragStartPage;
        if (pageDelta.abs() > 1.5) {
          return cardChild ?? child;
        }
        final viewportDimension = controller.position.viewportDimension;

        ui.ImageFilter cardFilter({
          required double alpha,
          required double blurSigma,
        }) {
          final alphaFilter = ui.ColorFilter.mode(
            Color.fromARGB((alpha.clamp(0.0, 1.0) * 255).round(), 0, 0, 0),
            ui.BlendMode.dstIn,
          );
          return blurSigma > 0
              ? ui.ImageFilter.compose(
                  outer: alphaFilter,
                  inner: ui.ImageFilter.blur(
                    sigmaX: blurSigma,
                    sigmaY: blurSigma,
                    tileMode: ui.TileMode.clamp,
                  ),
                )
              : alphaFilter;
        }

        // Backward paging (right swipe): the outgoing page stacks in place and
        // recedes (fade out + shrink to 79% + blur) while the left neighbor
        // drops in from the very top.
        if (resolvedDirection < 0) {
          if (pageDelta == -1) {
            // Incoming left neighbor: cancel its PageView offset so it lands
            // centered while the receding neighbor slides over it.
            final dragProgress =
                ((dragStartPage - activePage) / (dragStartPage - page))
                    .clamp(0.0, 1.0)
                    .toDouble();
            final appearProgress =
                ((dragProgress - _cardPagerAppearStart) /
                        (1.0 - _cardPagerAppearStart))
                    .clamp(0.0, 1.0)
                    .toDouble();
            final scale =
                _cardPagerMinScale +
                (1.0 - _cardPagerMinScale) * appearProgress;
            final alpha =
                (_cardPagerAppearOpacity +
                        (1.0 - _cardPagerAppearOpacity) * appearProgress)
                    .clamp(0.0, 1.0);
            final blurSigma =
                _cardPagerMaxBlurSigma * (1.0 - appearProgress).clamp(0.0, 1.0);
            return ImageFiltered(
              imageFilter: cardFilter(alpha: alpha, blurSigma: blurSigma),
              child: Transform.translate(
                offset: Offset((activePage - page) * viewportDimension, 0),
                child: Transform.scale(scale: scale, child: cardChild ?? child),
              ),
            );
          }
          if (pageDelta != 0) return cardChild ?? child;
          // Outgoing page: cancel its PageView offset so it recedes in place.
          final recedeProgress = (dragStartPage - activePage).clamp(0.0, 1.0);
          final scale = 1.0 - (1.0 - _cardPagerMinScale) * recedeProgress;
          final blurSigma = _cardPagerMaxBlurSigma * recedeProgress;
          final alpha = 1.0 - (1.0 - _cardPagerAppearOpacity) * recedeProgress;
          return ImageFiltered(
            imageFilter: cardFilter(alpha: alpha, blurSigma: blurSigma),
            child: Transform.translate(
              offset: Offset((activePage - page) * viewportDimension, 0),
              child: Transform.scale(scale: scale, child: cardChild ?? child),
            ),
          );
        }
        // Forward paging (left swipe): the outgoing page follows the finger
        // away; only the incoming right neighbor enters the reveal.
        if (pageDelta * resolvedDirection <= 0) {
          return cardChild ?? child;
        }
        final dragProgress =
            ((dragStartPage - activePage) / (dragStartPage - page))
                .clamp(0.0, 1.0)
                .toDouble();
        final appearProgress =
            ((dragProgress - _cardPagerAppearStart) /
                    (1.0 - _cardPagerAppearStart))
                .clamp(0.0, 1.0)
                .toDouble();
        final scale =
            _cardPagerMinScale + (1.0 - _cardPagerMinScale) * appearProgress;
        // Cancel only the incoming card's PageView layout offset; the active
        // page still follows the finger.
        final Widget transition = Transform.translate(
          offset: Offset((activePage - page) * viewportDimension, 0),
          child: Transform.scale(scale: scale, child: cardChild ?? child),
        );
        // Use a single image filter for alpha and blur. The completed state
        // keeps the same wrapper so Android does not repaint as a new layer.
        final alpha =
            (_cardPagerAppearOpacity +
                    (1.0 - _cardPagerAppearOpacity) * appearProgress)
                .clamp(0.0, 1.0);
        final blurSigma =
            _cardPagerMaxBlurSigma * (1.0 - appearProgress).clamp(0.0, 1.0);
        return ImageFiltered(
          imageFilter: cardFilter(alpha: alpha, blurSigma: blurSigma),
          child: transition,
        );
      },
    );
  }

  double _updatePagerLeadDirection(
    PageController controller,
    double activePage,
  ) {
    if (!_pagerLastActivePage.containsKey(controller)) {
      // Seed the first observed page so the first drag has a real delta.
      _pagerLastActivePage[controller] = activePage;
      return 0;
    }
    final lastPage = _pagerLastActivePage[controller]!;
    final target = (activePage - lastPage).sign.toDouble();
    final previous = _pagerLeadDirection[controller] ?? 0.0;
    final direction = previous + (target - previous) * 0.55;
    // Commit immediately so the next page builder in the same frame cannot
    // observe a stale start point.
    _pagerLastActivePage[controller] = activePage;
    _pagerLeadDirection[controller] = direction;
    return direction;
  }

  Widget _buildWeekPager(
    TimetableProvider provider,
    TimetableSettings settings,
    double availableWidth,
    double availableHeight,
  ) {
    final visibleDayViewWeek = _visibleDayViewWeek;
    final timeColumnWidth = _resolveTimeColumnWidth(settings);
    final chromeGridClearance =
        hasHomePageBackdropImage(settings) &&
            settings.homePageWeekdayBarBlurEnabled
        ? homePageFrostedRegionSeamOverlap
        : 0.0;
    final timeColumnTop = _weekDayHeaderHeight + chromeGridClearance;
    final timeColumnHeight = (availableHeight - timeColumnTop).clamp(
      0.0,
      double.infinity,
    );
    final fixedTimeColumnSectionHeight =
        settings.timetableAutoFitSectionHeight && settings.sectionCount > 0
        ? timeColumnHeight / settings.sectionCount
        : settings.sectionHeight;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 0,
          top: timeColumnTop,
          width: timeColumnWidth,
          height: timeColumnHeight,
          child: AnimatedBuilder(
            // 鍔ㄧ敾鏈熼棿鏃堕棿杞寸敱 deck 鍗″唴鐨勫壇鏈礋璐ｏ紙闅忓崱鐗囦竴璧风缉鏀?浣嶇Щ锛夛�?
            // 鍥哄畾杞ㄥ湪 deck 婵€娲绘垨鍋滈潬鎸傝捣鏃堕殣钘忥紝闈欐鏃舵仮澶嶃€?
            animation: Listenable.merge([
              _weekPageController,
              _weekDeckReleaseTick,
            ]),
            builder: (context, _) {
              // When the settle rebuild exposes the real PageView, its week
              // page has no standalone time axis. Restore the fixed axis in
              // that exact frame; otherwise the axis disappears for one frame.
              final deckTakingOver =
                  _isWeekDeckActive() ||
                  (_weekPagerDragStartPage != null &&
                      !_weekDeckSettleRebuildScheduled);
              return Offstage(
                offstage: _shouldShowDayViewOverlay || deckTakingOver,
                child: IgnorePointer(
                  child: ClipRect(
                    child: OverflowBox(
                      minHeight: 0,
                      maxHeight: double.infinity,
                      alignment: Alignment.topCenter,
                      child: _buildFollowingTimeColumn(
                        settings: settings,
                        sectionHeight: fixedTimeColumnSectionHeight,
                        maxWeek: settings.semesterWeekCount,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.axis == Axis.horizontal) {
              if (notification is ScrollStartNotification &&
                  notification.dragDetails != null) {
                _weekPagerPendingDragStartPage = _pagerDragStartPageFromMetrics(
                  notification.metrics,
                );
              }
              if (notification is ScrollUpdateNotification &&
                  notification.scrollDelta != 0) {
                _weekSwipeDirection = notification.scrollDelta! > 0 ? 1 : -1;
                // First real horizontal movement promotes the pending
                // start page: vertical drags on the course grid also
                // surface as a horizontal ScrollStart and must never arm
                // the swipe deck (which would paint a duplicate week).
                // A fast follow-up swipe can begin while the previous spring
                // is still settling. Its ScrollStart is real, so replace the
                // stale previous start point; otherwise the deck keeps using
                // the old page and the card appears frozen for one swipe.
                if (_weekPagerPendingDragStartPage != null &&
                    _weekPagerDragStartPage != _weekPagerPendingDragStartPage) {
                  _weekPagerDragStartPage = _weekPagerPendingDragStartPage;
                  _weekPagerPendingDragStartPage = null;
                  _weekDeckSettleRebuildArmed = true;
                  _weekDeckSettleRebuildScheduled = false;
                  if (mounted) setState(() {});
                }
              }
              if (notification is ScrollEndNotification) {
                _weekPagerPendingDragStartPage = null;
                _finalizeWeekPageSettled(provider);
              }
            }
            return false;
          },
          child: IgnorePointer(
            ignoring: _isDayView,
            child: AnimatedBuilder(
              animation: Listenable.merge([
                _weekPageController,
                _weekDeckReleaseTick,
              ]),
              child: PageView.builder(
                key: const ValueKey('week-page-view'),
                controller: _weekPageController,
                itemCount: settings.semesterWeekCount,
                allowImplicitScrolling: true,
                dragStartBehavior: DragStartBehavior.down,
                physics: _weekPagerPhysics,
                // The custom physics owns page snapping. Leaving this enabled
                // would wrap default PageScrollPhysics outside it and hide the
                // spring settle.
                pageSnapping: false,
                onPageChanged: (page) =>
                    _handleWeekPageChanged(page, settings.semesterWeekCount),
                itemBuilder: (context, index) {
                  // Keep the real pager pages mounted during a deck swipe.
                  // Hiding them at the PageView level avoids rebuilding and
                  // replacing every card subtree when the deck hands back.
                  final week = index + 1;
                  return RepaintBoundary(
                    // Lets card glass fills align to the wallpaper instance
                    // that slides with this page (see
                    // PreblurredWallpaperAlignedFill).
                    child: PreblurredWallpaperPage(
                      pageIndex: index,
                      child: _buildWeekPage(
                        provider,
                        settings,
                        availableWidth,
                        availableHeight,
                        week,
                      ),
                    ),
                  );
                },
              ),
              builder: (context, child) => Opacity(
                opacity: _isWeekDeckActive() ? 0.0 : 1.0,
                child: child,
              ),
            ),
          ),
        ),
        if (!_shouldShowDayViewOverlay)
          _buildWeekPagerDeck(
            provider,
            settings,
            availableWidth,
            availableHeight,
          ),
        if (!_shouldShowDayViewOverlay)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: _weekDayHeaderHeight,
            child: _buildFixedWeekHeader(provider, settings, timeColumnWidth),
          ),
        if (_shouldShowDayViewOverlay && visibleDayViewWeek != null)
          Positioned.fill(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 鏃ヨ鍥捐嚜宸辩殑鏄熸湡淇℃伅鏍忥紙scrubber 瑙嗚鐢卞閮ㄦ墜鍔垮眰瑕嗙洊锛夈€?
                _buildWeekDayHeader(
                  provider,
                  visibleDayViewWeek,
                  settings,
                  _resolveTimeColumnWidth(settings),
                  hideBottomBorder: true,
                ),
                Expanded(
                  child: _buildAnchoredDayViewOverlay(
                    provider: provider,
                    settings: settings,
                    week: visibleDayViewWeek,
                  ),
                ),
              ],
            ),
          ),
        // Swipeable weekday bar: when day view is open, the bar is a
        // follow-finger scrubber over the day pager ? drags are amplified by
        // the visible-day count and injected into the pager position, so one
        // bar-width sweep flies the content across the whole week
        // (see _startWeekdayBarDrag).
        if (_shouldShowDayViewOverlay && visibleDayViewWeek != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: _weekDayHeaderHeight,
            child: GestureDetector(
              key: const ValueKey('day-view-weekday-bar-swipe-area'),
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (details) =>
                  _startWeekdayBarDrag(settings, details),
              onHorizontalDragUpdate: _updateWeekdayBarDrag,
              onHorizontalDragEnd: _endWeekdayBarDrag,
              onHorizontalDragCancel: _cancelWeekdayBarDrag,
            ),
          ),
      ],
    );
  }

  /// layer (and the pager placeholders) only exist in this window; at rest the
  /// PageView renders the real pages again.
  bool _isWeekDeckActive() {
    final startPage = _weekPagerDragStartPage;
    if (startPage == null ||
        _isDayView ||
        !_weekPageController.hasClients ||
        !_weekPageController.position.hasContentDimensions) {
      return false;
    }
    final activePage = _weekPageController.page;
    if (activePage == null) return false;
    return (activePage - activePage.roundToDouble()).abs() > 0.0001;
  }

  /// Deck layer that owns the week swipe's z-order.
  ///
  /// PageView always paints higher indexes above lower ones, which is the
  /// opposite of what the swipe wants:
  ///  - Left swipe: the outgoing week leaves on TOP while the incoming week
  ///    rises from a LOWER layer: fade-in 0.22 -> 1 (no blur),
  ///    79% -> 100%.
  ///  - Right swipe: the outgoing week recedes IN PLACE on the lower layer:
  ///    fade-out 1 -> 0.22 (no blur), shrinks to 79%, while the previous week
  ///    slides over it from the TOP layer.
  /// The pager keeps the finger drag; this layer hides the pager's own cards
  /// and draws the two-page stack with explicit child order.
  ///
  /// The deck also owns the settle hand-off: when the spring reaches an
  /// integral page the pager stops notifying, but its placeholder children
  /// linger until the pager rebuilds. In that window the deck holds one frozen
  /// real card and schedules [_completeWeekDeckSettle] to rebuild the pager so
  /// the settled week never blinks away.
  Widget _buildWeekPagerDeck(
    TimetableProvider provider,
    TimetableSettings settings,
    double availableWidth,
    double availableHeight,
  ) {
    // Parent build starts a new content/layout generation. Clear once here so
    // the AnimatedBuilder below can reuse the same card widgets on every drag
    // frame without serving stale provider/theme/layout data.
    _weekDeckCardCache.clear();
    return IgnorePointer(
      child: AnimatedBuilder(
        // Merge: rebuild while the pager moves and again when the settle
        // finishes on an integral page (release tick bump).
        animation: Listenable.merge([
          _weekPageController,
          _weekDeckReleaseTick,
        ]),
        builder: (context, _) {
          if (_isWeekDeckActive()) {
            final startPage = _weekPagerDragStartPage ?? 0;
            final activePage =
                _weekPageController.hasClients &&
                    _weekPageController.position.hasContentDimensions
                ? (_weekPageController.page ?? startPage)
                : startPage;
            final maxIndex = settings.semesterWeekCount;
            final outgoingIndex = startPage.round();
            if (maxIndex <= 0 ||
                outgoingIndex < 0 ||
                outgoingIndex >= maxIndex) {
              return const SizedBox.shrink();
            }
            final viewportWidth =
                _weekPageController.position.viewportDimension;
            if (viewportWidth <= 0) return const SizedBox.shrink();
            final delta = activePage - startPage;
            final direction = delta.abs() < 0.0001
                ? _weekSwipeDirection
                : delta.sign.toDouble();
            return _buildWeekDeckStack(
              provider: provider,
              settings: settings,
              availableWidth: availableWidth,
              availableHeight: availableHeight,
              startPage: startPage,
              delta: delta,
              direction: direction,
            );
          }

          // The deck just shut down on an integral page, but the pager still
          // shows its placeholder children until it rebuilds. Hold one frozen
          // real card this frame and schedule the pager rebuild; otherwise the
          // settled week would blink away for a frame.
          if (_weekPagerDragStartPage != null &&
              _weekPageController.hasClients &&
              _weekPageController.position.hasContentDimensions) {
            // The controller tick below has already rebuilt the real pager
            // card in this frame. Returning empty here avoids stacking a
            // near-identical frozen card on top of it (the visible settle
            // jitter/flash).
            if (!_weekDeckHoldScheduled) {
              _weekDeckHoldScheduled = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _weekDeckHoldScheduled = false;
                if (!mounted) return;
                if (_isWeekDeckActive()) return; // New gesture resumed deck.
                _completeWeekDeckSettle(provider);
              });
            }
            if (_weekDeckSettleRebuildScheduled) {
              return const SizedBox.shrink();
            }
            return _buildWeekDeckSettledCard(
              provider,
              settings,
              availableWidth,
              availableHeight,
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  /// Rebuilds the real pager card on the same animation tick that reaches an
  /// integral page. Without this, the deck hold card has to cover an extra
  /// frame until the post-frame release rebuilds the PageView, which shows as
  /// a one-frame settle flash on device.

  void _handleWeekPageControllerChanged() {
    if (!mounted ||
        _weekPagerDragStartPage == null ||
        _weekDeckSettleRebuildScheduled ||
        !_weekPageController.hasClients ||
        !_weekPageController.position.hasContentDimensions) {
      return;
    }
    if (_isWeekDeckActive()) {
      _weekDeckSettleRebuildArmed = true;
      _weekDeckSettleRebuildScheduled = false;
      return;
    }
    if (!_weekDeckSettleRebuildArmed) {
      return;
    }
    _weekDeckSettleRebuildArmed = false;
    _weekDeckSettleRebuildScheduled = true;
    setState(() {});
  }

  /// Settle hand-off: anchors the pager on the resolved page, clears the
  /// gesture state, and forces the pager to rebuild its real cards so the
  /// settled week stays visible (no blank flash right after the swipe).
  void _completeWeekDeckSettle(TimetableProvider provider) {
    if (!mounted) return;
    final targetWeek = _resolveSettledWeek(provider);
    final targetPage = targetWeek - 1;
    _lastObservedWeekPage = targetPage;
    _weekDeckSettleRebuildArmed = false;
    _weekDeckSettleRebuildScheduled = false;
    _weekPagerDragStartPage = null;
    // A post-frame settle can land after the next gesture has already captured
    // its ScrollStart. Keep that pending start page: clearing it here steals
    // the first real movement of the next swipe, so the pager can sit frozen
    // until a later gesture/rebuild re-arms the deck.
    final hasPendingNextDrag = _weekPagerPendingDragStartPage != null;
    if (!hasPendingNextDrag) {
      _weekPagerPendingDragStartPage = null;
    }
    _weekDeckReleaseTick.value += 1;
    if (_weekPageController.hasClients) {
      final page = _weekPageController.page;
      if (page != null && (page - targetPage).abs() > 0.0001) {
        _weekPageController.jumpToPage(targetPage);
      }
    }
    _finalizeWeekPageSettled(provider);
    if (mounted) {
      setState(() {});
    }
  }

  /// 鏃堕棿杞村湪鍒囧懆鍔ㄧ敾鏈熼棿鐢卞崱鐗囧唴鍓湰璐熻矗锛堣窡闅忓崱鐗囦竴璧风缉鏀?浣嶇Щ/娣″叆锛夛�?
  /// 闈欐鏃跺浐瀹氳建鎭㈠銆傛鏂规硶璁＄畻鍗＄墖鍐呮椂闂磋酱鐨勪綅缃笌鑺傞珮锛屼笌鍥哄畾杞?
  /// 锛坃buildWeekPager 椤堕儴鐨?Positioned锛変繚鎸佸悓涓€鍧愭爣鍩哄噯�?
  ({double width, double top, double height, double sectionHeight})
  _weekDeckTimeColumnMetrics(
    TimetableSettings settings,
    double availableHeight,
  ) {
    final width = _resolveTimeColumnWidth(settings);
    final hasBackdrop = hasHomePageBackdropImage(settings);
    final chromeGridClearance =
        hasBackdrop && settings.homePageWeekdayBarBlurEnabled
        ? homePageFrostedRegionSeamOverlap
        : 0.0;
    final top = _weekDayHeaderHeight + chromeGridClearance;
    final height = (availableHeight - top).clamp(0.0, double.infinity);
    final sectionHeight =
        settings.timetableAutoFitSectionHeight && settings.sectionCount > 0
        ? height / settings.sectionCount
        : settings.sectionHeight;
    return (
      width: width,
      top: top,
      height: height,
      sectionHeight: sectionHeight,
    );
  }

  /// 鍗曞紶鍒囧懆鍗＄墖锛氳琛ㄩ�?+ 鍗＄墖鍐呮椂闂磋酱鍓湰锛屼簩鑰呬綔涓烘暣浣撳弬涓庣缉鏀?
  /// 浣嶇Щ/娣″叆锛堟椂闂磋酱闅忚琛ㄤ竴璧锋粦鍔ㄥ拰缂╂斁锛夈€?
  Widget _buildWeekDeckCard(
    TimetableProvider provider,
    TimetableSettings settings,
    double availableWidth,
    double availableHeight,
    int index,
  ) {
    final cached = _weekDeckCardCache[index];
    if (cached != null) {
      // Returning an identical widget makes Element.updateChild skip this
      // subtree entirely; only the enclosing transform/filter rebuilds.
      return cached;
    }
    final metrics = _weekDeckTimeColumnMetrics(settings, availableHeight);
    final card = RepaintBoundary(
      child: PreblurredWallpaperPage(
        pageIndex: index,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildWeekPage(
              provider,
              settings,
              availableWidth,
              availableHeight,
              index + 1,
            ),
            Positioned(
              left: 0,
              top: metrics.top,
              width: metrics.width,
              height: metrics.height,
              child: ClipRect(
                child: OverflowBox(
                  minHeight: 0,
                  maxHeight: double.infinity,
                  alignment: Alignment.topCenter,
                  child: _buildFollowingTimeColumn(
                    settings: settings,
                    sectionHeight: metrics.sectionHeight,
                    maxWeek: settings.semesterWeekCount,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    _weekDeckCardCache[index] = card;
    return card;
  }

  /// Frozen real card shown on the frame the deck shuts down, before the
  /// pager rebuilds its own cards. Prevents a blank flash at settle end.
  Widget _buildWeekDeckSettledCard(
    TimetableProvider provider,
    TimetableSettings settings,
    double availableWidth,
    double availableHeight,
  ) {
    final activePage =
        _weekPageController.hasClients &&
            _weekPageController.position.hasContentDimensions
        ? (_weekPageController.page ?? 0)
        : 0.0;
    final index = activePage.round();
    final maxIndex = settings.semesterWeekCount;
    if (maxIndex <= 0 || index < 0 || index >= maxIndex) {
      return const SizedBox.shrink();
    }
    return _buildWeekDeckCard(
      provider,
      settings,
      availableWidth,
      availableHeight,
      index,
    );
  }

  /// Lower-layer reveal curve for the week deck. Mirrors the day pager's
  /// [_cardPagerAppearStart] dead zone: the lower card holds its seed state
  /// until the upper layer has travelled that fraction of the page, then ramps
  /// to full over the remaining travel.
  double _weekDeckAppearProgress(double progress) {
    return ((progress - _cardPagerAppearStart) /
            (1.0 - _cardPagerAppearStart))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  /// Week swipe z-order stack; see [_buildWeekPagerDeck] for the
  /// choreography.
  ///
  /// Both cards keep the cross-dissolve (scale + opacity) while the moving
  /// card also travels horizontally:
  /// - Forward (left swipe): the current week follows the finger out to the
  ///   left while it fades; the next week rises in place underneath.
  /// - Backward (right swipe): the previous week slides in from the left while
  ///   it fades in; the current week recedes in place underneath.
  Widget _buildWeekDeckStack({
    required TimetableProvider provider,
    required TimetableSettings settings,
    required double availableWidth,
    required double availableHeight,
    required double startPage,
    required double delta,
    required double direction,
  }) {
    final maxIndex = settings.semesterWeekCount;
    final outgoingIndex = startPage.round();

    Widget deckCard(
      int index, {
      required double translateX,
      double scale = 1.0,
      double opacity = 1.0,
    }) {
      if (index < 0 || index >= maxIndex) {
        return const SizedBox.shrink();
      }
      return Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(translateX, 0),
          child: Transform.scale(
            scale: scale,
            child: _buildWeekDeckCard(
              provider,
              settings,
              availableWidth,
              availableHeight,
              index,
            ),
          ),
        ),
      );
    }

    // Forward (left swipe): the current week slides out to the left while it
    // fades over the next week, which rises in place underneath (scale
    // 85%->100%, opacity 0.52%->100% after the 13.14% dead zone).
    if (direction > 0) {
      final progress = delta.clamp(0.0, 1.0).toDouble();
      final appear = _weekDeckAppearProgress(progress);
      final incomingScale =
          _cardPagerMinScale + (1.0 - _cardPagerMinScale) * appear;
      final incomingOpacity =
          _cardPagerAppearOpacity +
          (1.0 - _cardPagerAppearOpacity) * appear;
      final outgoingOpacity =
          _cardPagerAppearOpacity +
          (1.0 - _cardPagerAppearOpacity) * (1.0 - progress);
      return Stack(
        fit: StackFit.expand,
        children: [
          deckCard(
            outgoingIndex + 1,
            translateX: 0,
            scale: incomingScale,
            opacity: incomingOpacity,
          ),
          deckCard(
            outgoingIndex,
            translateX: -progress * availableWidth,
            opacity: outgoingOpacity,
          ),
        ],
      );
    }

    // Backward (right swipe): the previous week slides in from the left while
    // it fades in; the current week recedes in place underneath.
    final progress = (-delta).clamp(0.0, 1.0).toDouble();
    final appear = _weekDeckAppearProgress(progress);
    final incomingScale =
        _cardPagerMinScale + (1.0 - _cardPagerMinScale) * appear;
    final incomingOpacity =
        _cardPagerAppearOpacity +
        (1.0 - _cardPagerAppearOpacity) * appear;
    final outgoingScale = 1.0 - (1.0 - _cardPagerMinScale) * progress;
    final outgoingOpacity =
        _cardPagerAppearOpacity +
        (1.0 - _cardPagerAppearOpacity) * (1.0 - progress);
    return Stack(
      fit: StackFit.expand,
      children: [
        deckCard(
          outgoingIndex,
          translateX: 0,
          scale: outgoingScale,
          opacity: outgoingOpacity,
        ),
        deckCard(
          outgoingIndex - 1,
          translateX: -(1.0 - progress) * availableWidth,
          scale: incomingScale,
          opacity: incomingOpacity,
        ),
      ],
    );
  }

  Widget _buildFixedWeekHeader(
    TimetableProvider provider,
    TimetableSettings settings,
    double timeColumnWidth,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasBackdrop = hasHomePageBackdropImage(settings);
    final weekdayChromeBlurEnabled =
        hasBackdrop && settings.homePageWeekdayBarBlurEnabled;
    final pageChromeFallback = Theme.of(context).colorScheme.surface;
    final weekdayShowsBackdrop = homePageRegionShowsBackdrop(
      settings,
      HomePageBackgroundScope.weekdayBar,
    );

    return ValueListenableBuilder<int>(
      valueListenable: _visibleWeekListenable,
      builder: (context, visibleWeek, _) {
        return homePageBackgroundLayer(
          visual: homePageRegionChromeVisual(
            settings: settings,
            isDark: isDark,
            darkFallback: pageChromeFallback,
            region: HomePageBackgroundScope.weekdayBar,
            chromeBlurEnabled: weekdayChromeBlurEnabled,
          ),
          child: _buildWeekDayHeader(
            provider,
            visibleWeek,
            settings,
            timeColumnWidth,
            hideBottomBorder: weekdayShowsBackdrop || weekdayChromeBlurEnabled,
          ),
        );
      },
    );
  }

  Widget _buildWeekPage(
    TimetableProvider provider,
    TimetableSettings settings,
    double availableWidth,
    double availableHeight,
    int week,
  ) {
    final hasBackdrop = hasHomePageBackdropImage(settings);
    // Day view keeps the same weekday chrome as the week view: the panel below
    // now shows the wallpaper, so an opaque non-blurred bar would read as a
    // seam across the top of the glass.
    final weekdayChromeBlurEnabled =
        hasBackdrop && settings.homePageWeekdayBarBlurEnabled;
    final chromeGridClearance = weekdayChromeBlurEnabled
        ? homePageFrostedRegionSeamOverlap
        : 0.0;
    // 鑷€傚簲鑺傞珮鎸夊畬鏁村彲鐢ㄩ珮搴﹁绠楋細鐜荤拑鍧炴弧灞忔偓娴笅缃戞牸寤朵几鍒拌嵂�?
    // 搴曚笅锛堝眰娆℃劅锛夛紱琚伄浣忕殑鏈€鍚庡嚑鑺傜敱 _buildWeekPageBody 鐨勬粴鍔ㄤ綑
    // 閲忔晳鍥炩€斺€斾笂婊戞妸鏁存璇捐〃瀹屽叏婊戝嚭鍒拌嵂涓镐笂鏂癸紝涓嬫粦鍐嶈鑽父鐩栧洖�?
    final bodyAvailableHeight =
        (availableHeight - _weekDayHeaderHeight - chromeGridClearance).clamp(
          0.0,
          double.infinity,
        );
    final sectionHeight =
        settings.timetableAutoFitSectionHeight && settings.sectionCount > 0
        ? bodyAvailableHeight / settings.sectionCount
        : settings.sectionHeight;
    final weekGridController = _getWeekGridScrollController(week);
    final grid = _buildTimetableGrid(
      provider,
      settings,
      availableWidth,
      week,
      sectionHeight,
      weekGridScrollController: weekGridController,
      animateCourseEntrance:
          !_isWeekDeckActive() && !_weekDeckSettleRebuildScheduled,
    );

    return KeyedSubtree(
      key: ValueKey('week-page-$week'),
      child: Column(
        children: [
          const SizedBox(height: _weekDayHeaderHeight),
          // Original chrome鈫攇rid clearance (same token as frosted seam overlap).
          // Keeps gaussian cards from sitting flush on the first course row.
          if (weekdayChromeBlurEnabled)
            const SizedBox(height: homePageFrostedRegionSeamOverlap),
          Expanded(
            child: _buildWeekPageBody(
              provider: provider,
              settings: settings,
              week: week,
              grid: grid,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekPageBody({
    required TimetableProvider provider,
    required TimetableSettings settings,
    required int week,
    required Widget grid,
  }) {
    // 鐜荤拑鍧炴弧灞忔偓娴細缃戞牸瑙嗗彛涓嶉伩璁┿€侀摵鍒拌嵂涓稿簳涓嬧€斺€旈潤姝㈡椂鏈€鍚庡嚑�?
    // 鍋滃湪鑽父鍚庨潰锛涚粰绾靛悜婊氬姩琛ヤ竴娈靛簳閮ㄤ綑閲忥紝涓婃粦鎶婅琛ㄦ暣浣撴粦涓婃潵銆?
    // 琚伄鐨勮绋嬪畬鍏ㄩ湶鍒拌嵂涓镐笂鏂癸紝涓嬫粦鍐嶈鑽父鐩栧洖鍐呭銆傝嚜閫傚簲涓庨潪�?
    // 閫傚簲鍦ㄦ缁熶竴锛堣嚜閫傚簲缃戞牸鍚屾牱鍙粴锛夈€傜粡鍏稿舰鎬佹棤鍧烇紙浣欓噺涓?0锛夛�?
    // 淇濇寔鍘熸牱锛氳嚜閫傚簲鎭版弧瑙嗗彛涓嶆粴锛岄潪鑷€傚簲缁存寔鍘熸粴鍔ㄧ粨鏋勩�?
    final weekGridScrollRelief = _glassDockContentScrollInset(settings);
    final weekGridController = _getWeekGridScrollController(week);
    // Auto-fill is an exact-height layout: keep it still. The optional effect
    // only applies when the non-auto-fit layout actually has scroll room.
    final verticalEffectEnabled =
        settings.timetableVerticalScrollEffectEnabled &&
        !settings.timetableAutoFitSectionHeight;
    final Widget weekGrid;
    if (weekGridScrollRelief > 0) {
      weekGrid = SingleChildScrollView(
        key: PageStorageKey<String>('week-scroll-$week'),
        controller: weekGridController,
        // Explicit clamp: do not inherit HyperOS rubber-band here.
        physics: verticalEffectEnabled
            ? const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              )
            : const ClampingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
        child: Padding(
          padding: EdgeInsets.only(bottom: weekGridScrollRelief),
          child: grid,
        ),
      );
    } else if (settings.timetableAutoFitSectionHeight) {
      // Classic auto-fit fills the viewport exactly, so vertical motion is
      // disabled instead of using bounce overscroll as a pseudo effect.
      weekGrid = SingleChildScrollView(
        key: PageStorageKey<String>('week-scroll-$week'),
        controller: weekGridController,
        physics: const NeverScrollableScrollPhysics(),
        child: grid,
      );
    } else {
      weekGrid = SingleChildScrollView(
        key: PageStorageKey<String>('week-scroll-$week'),
        controller: weekGridController,
        physics: verticalEffectEnabled
            ? const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              )
            : const ClampingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
        child: grid,
      );
    }
    // Drive opacity from the expand controller so open and close share the
    // same curve. A boolean AnimatedOpacity snaps the grid away on open while
    // the panel still grows, which reads as "open has no transition".
    return AnimatedBuilder(
      animation: _dayViewExpandController,
      child: weekGrid,
      builder: (context, child) {
        final gridOpacity = (1.0 - _dayViewExpandController.value).clamp(
          0.0,
          1.0,
        );
        return IgnorePointer(
          ignoring: gridOpacity < 0.02,
          child: Opacity(
            // At 0 RenderOpacity skips painting the subtree, so day-view glass
            // samples wallpaper instead of a ghost grid.
            opacity: gridOpacity,
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildAnchoredDayViewOverlay({
    required TimetableProvider provider,
    required TimetableSettings settings,
    required int week,
  }) {
    final selectedDayOfWeek = _displayedDayForWeek(week);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final panel = _buildDayViewPanel(
      provider: provider,
      settings: settings,
      week: week,
      dayOfWeek: selectedDayOfWeek,
    );

    return AnimatedBuilder(
      animation: _dayViewExpandController,
      child: panel,
      builder: (context, child) {
        final curve = _dayViewExpandController.status == AnimationStatus.reverse
            ? Curves.easeInOutCubic
            : Curves.easeInOutCubicEmphasized;
        final progress = curve.transform(_dayViewExpandController.value);
        final scale = 0.94 + (0.06 * progress);
        final widthFactor = 0.18 + (0.82 * progress);
        final heightFactor = math.max(0.04, progress);
        final translateY = (1 - progress) * -24;
        final borderRadius = BorderRadius.circular(28 * (1 - progress));
        final shadowAlpha =
            (theme.brightness == Brightness.dark ? 0.08 : 0.06) *
            (1 - progress);

        return IgnorePointer(
          // Block only while the shell is still a tiny seed (open start / close
          // end). Waiting for 0.98 left the close button unhittable for most of
          // the open animation and flaky under widget-test pumps.
          ignoring: progress < 0.05,
          child: Opacity(
            opacity: Curves.easeOutCubic.transform(progress),
            child: ClipRRect(
              borderRadius: borderRadius,
              child: Align(
                alignment: Alignment(_dayViewAnchorAlignmentX, -1),
                widthFactor: widthFactor,
                heightFactor: heightFactor,
                child: Transform.translate(
                  offset: Offset(0, translateY),
                  child: Transform.scale(
                    scale: scale,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.shadow.withValues(
                              alpha: shadowAlpha,
                            ),
                            blurRadius: 28 * (1 - progress),
                            offset: Offset(0, 12 * (1 - progress)),
                          ),
                        ],
                      ),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDayViewPanel({
    required TimetableProvider provider,
    required TimetableSettings settings,
    required int week,
    required int dayOfWeek,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final darkFallback = colorScheme.surface;
    // Not forced opaque: the panel shows the wallpaper exactly like a week page
    // does, so glass / frosted agenda cards have real content to sample. The
    // week grid underneath is faded to 0 while the day view is up
    // (see _buildWeekPageBody), so nothing shows through but the wallpaper.
    // With no wallpaper this resolver already returns an opaque colour.
    final backgroundVisual = resolveHomePageRegionBackground(
      settings: settings,
      isDark: isDark,
      darkFallback: darkFallback,
      region: HomePageBackgroundScope.timetable,
    );
    final controller = _ensureDayViewPageController(settings);
    _syncDayViewPageWithSelection(settings);
    final pageCount = _dayViewPageCount(settings);

    return homePageBackgroundLayer(
      visual: backgroundVisual,
      child: Container(
        key: const ValueKey('timetable-day-view-panel'),
        child: Column(
          children: [
            const SizedBox(height: 14),
            SizedBox(key: ValueKey('timetable-day-view-$week-$dayOfWeek')),
            Expanded(
              child: IgnorePointer(
                ignoring: _isDaySwipeAnimating,
                // Same as week grid: default PageView.builder keeps per-page
                // RepaintBoundary so horizontal swipes composite cheaply.
                // Pre-blur fills still repaint via pager markNeedsPaint.
                child: Listener(
                  // Raw-pointer fling meter + rescue arming. Touch batching
                  // under jank starves the framework's VelocityTracker (2�?
                  // samples per 50�?00ms flick ? zero velocity ? snap-back);
                  // the probes keep the true displacement/duration so
                  // _dayPagerPhysics can redo the snap with it.
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (event) {
                    // A new touch invalidates any leftover rescue velocity.
                    _dayPagerRescueVelocityX = 0;
                    _dayPagerRescueArmedAt = null;
                    // 鏂版墜鍔块噸鏂板厑璁镐竴娆℃棩鍒囨崲鐐瑰嚮闇囨劅�?
                    _daySwipeHapticFired = false;
                    _dayPagerFlickProbes[event.pointer] = _DayPagerFlickProbe(
                      VelocityTracker.withKind(event.kind)
                        ..addPosition(event.timeStamp, event.position),
                      event.timeStamp,
                      event.position,
                    );
                    if (kDebugMode && _dayPagerFlickProbes.length > 1) {
                      debugPrint(
                        '[DayPager] multi-touch: '
                        'pointers=${_dayPagerFlickProbes.keys.toList()}',
                      );
                    }
                  },
                  onPointerMove: (event) {
                    final probe = _dayPagerFlickProbes[event.pointer];
                    if (probe != null) {
                      probe.tracker.addPosition(
                        event.timeStamp,
                        event.position,
                      );
                      probe.samples++;
                      probe.lastTime = event.timeStamp;
                    }
                  },
                  onPointerUp: (event) {
                    final probe = _dayPagerFlickProbes.remove(event.pointer);
                    if (probe == null) {
                      return;
                    }
                    final path = event.position - probe.downPosition;
                    final pressDuration = event.timeStamp - probe.downTime;
                    final durationMs = pressDuration.inMilliseconds;
                    if (kDebugMode) {
                      final velocity = probe.tracker.getVelocity();
                      final gapMs =
                          (event.timeStamp - probe.lastTime).inMilliseconds;
                      debugPrint(
                        '[DayPager] lift(p${event.pointer}): '
                        'vx=${velocity.pixelsPerSecond.dx.toStringAsFixed(1)} '
                        'dx=${path.dx.toStringAsFixed(1)} '
                        'dur=${durationMs}ms '
                        'samples=${probe.samples} '
                        'gapBeforeUp=${gapMs}ms '
                        'concurrent=${_dayPagerFlickProbes.length} '
                        'minFling=${kMinFlingVelocity.toStringAsFixed(1)}',
                      );
                    }
                    // Arm the rescue: single remaining finger, short and
                    // horizontal-dominant swipes only. The drag recognizer
                    // runs right after this handler and consumes it.
                    if (_dayPagerFlickProbes.isEmpty &&
                        durationMs >= 16 &&
                        durationMs <= 300 &&
                        path.dx.abs() >= 24 &&
                        path.dx.abs() > path.dy.abs()) {
                      final pointerVx =
                          path.dx / (pressDuration.inMicroseconds / 1e6);
                      if (pointerVx.abs() >= kMinFlingVelocity) {
                        // Pointer moving right drags the pager toward the
                        // previous page: scroll velocity is the negation.
                        _dayPagerRescueVelocityX = -pointerVx;
                        _dayPagerRescueArmedAt = DateTime.now();
                      }
                    }
                  },
                  onPointerCancel: (event) {
                    _dayPagerRescueVelocityX = 0;
                    _dayPagerRescueArmedAt = null;
                    final probe = _dayPagerFlickProbes.remove(event.pointer);
                    if (probe != null && kDebugMode) {
                      final durationMs =
                          (event.timeStamp - probe.downTime).inMilliseconds;
                      debugPrint(
                        '[DayPager] CANCEL(p${event.pointer}) after '
                        '${durationMs}ms ? gesture stolen '
                        '(system nav / palm rejection?)',
                      );
                    }
                  },
                  child: NotificationListener<ScrollNotification>(
                    // has fully stopped (see _settleDayViewPage).
                    onNotification: (notification) {
                      if (notification.metrics.axis != Axis.horizontal) {
                        return false;
                      }
                      if (notification is ScrollUpdateNotification) {
                        if (notification.scrollDelta != 0) {
                          _daySwipeDirection = notification.scrollDelta! > 0
                              ? 1
                              : -1;
                        }
                        // 鎷︽�?update 缁х画鍐掓场锛欻yperosRootPage 鐨勮Е杈归渿鍔?
                        // 鐩戝惉浼氬湪瀛︽湡棣?鏈棩鍒拌揪椤佃竟鐣屾椂鍐嶈涓€娆?
                        // selectionClick锛屼笌涓婇潰鐨勯〉涓偣鐐瑰嚮鍙犲姞鎴愪竴娆℃粦�?
                        // 鍙岄渿鍔ㄣ€傛棩鍒囨崲鍙嶉宸插湪椤典腑鐐圭粰杩囷紝杩欓噷灏卞湴娑堣垂銆?
                        return true;
                      }
                      if (notification is ScrollStartNotification &&
                          notification.dragDetails != null) {
                        _dayPagerDragStartPage = _pagerDragStartPageFromMetrics(
                          notification.metrics,
                        );
                        if (kDebugMode) {
                          final metrics = notification.metrics;
                          final page = metrics.viewportDimension == 0
                              ? 0.0
                              : metrics.pixels / metrics.viewportDimension;
                          debugPrint(
                            '[DayPager] start: page=${page.toStringAsFixed(3)} '
                            'drag=${notification.dragDetails != null}',
                          );
                        }
                      } else if (notification is ScrollEndNotification) {
                        if (kDebugMode) {
                          final metrics = notification.metrics;
                          final page = metrics.viewportDimension == 0
                              ? 0.0
                              : metrics.pixels / metrics.viewportDimension;
                          debugPrint(
                            '[DayPager] end: page=${page.toStringAsFixed(3)}',
                          );
                        }
                        _settleDayViewPage(provider, settings);
                      }
                      return false;
                    },
                    child: PageView.builder(
                      key: const ValueKey('day-view-swipe-area'),
                      controller: controller,
                      // pageSnapping off on purpose: PageView would otherwise
                      // wrap its own PageScrollPhysics OUTSIDE ours and the
                      // rescue would never run. _dayPagerPhysics IS the snap.
                      physics: _dayPagerPhysics,
                      pageSnapping: false,
                      itemCount: pageCount,
                      // Same as the week pager: keep neighbours pre-built so a
                      // swipe never hits an itemBuilder spike mid-gesture.
                      allowImplicitScrolling: true,
                      onPageChanged: (page) =>
                          _handleDayViewPageChanged(provider, settings, page),
                      itemBuilder: (context, page) {
                        // 1 Hz progress heartbeat rebuilds only this page's
                        // content (ongoing badges / progress), not the State.
                        return _buildPagerCardTransition(
                          controller: controller,
                          page: page,
                          takeDragStartPage: () => _dayPagerDragStartPage,
                          takeDragDirection: () => _daySwipeDirection,
                          child: ValueListenableBuilder<int>(
                            valueListenable: _dayAgendaProgressTick,
                            builder: (context, _, _) =>
                                _buildDayViewPageContent(
                                  provider: provider,
                                  settings: settings,
                                  page: page,
                                ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One day-pager page: summary card + agenda column.
  ///
  /// Extracted from the pager itemBuilder so [_dayAgendaProgressTick] can
  /// rebuild exactly this subtree once a second instead of the whole home
  /// screen (week pager included), which used to drop day-view FPS.
  Widget _buildDayViewPageContent({
    required TimetableProvider provider,
    required TimetableSettings settings,
    required int page,
  }) {
    final target = _dayViewTargetForPage(settings, page);
    if (logDayViewBuilds) {
      debugPrint(
        '[DayView] build page=$page -> week=${target.week} '
        'day=${target.dayOfWeek}',
      );
    }
    final selectedDate = _dateForWeekDay(
      settings,
      target.week,
      target.dayOfWeek,
    );
    final courses = _getCoursesForDay(
      provider.courses,
      target.week,
      target.dayOfWeek,
      settings,
    );
    final currentCourse =
        _isSelectedDayToday(
          provider: provider,
          settings: settings,
          week: target.week,
          dayOfWeek: target.dayOfWeek,
        )
        ? provider.getCourseInProgress(
            dayOfWeek: target.dayOfWeek,
            week: target.week,
          )
        : null;
    final currentCourseIds =
        _isSelectedDayToday(
          provider: provider,
          settings: settings,
          week: target.week,
          dayOfWeek: target.dayOfWeek,
        )
        ? provider
              .getCoursesInProgress(
                dayOfWeek: target.dayOfWeek,
                week: target.week,
              )
              .map((course) => course.id)
              .toSet()
        : const <String>{};
    final displayItems = _buildHomeDayDisplayItems(
      provider: provider,
      settings: settings,
      week: target.week,
      dayOfWeek: target.dayOfWeek,
      myCourses: courses,
      currentCourseIds: currentCourseIds,
    );
    final agendaItems = _buildDayAgendaItems(
      provider: provider,
      settings: settings,
      week: target.week,
      dayOfWeek: target.dayOfWeek,
      courseItems: displayItems,
    );
    final scheduleItems = agendaItems
        .where((item) => item.isScheduleItem)
        .map((item) => item.scheduleItem!)
        .toList(growable: false);
    if (logDayViewBuilds) {
      debugPrint(
        '[DayView] page=$page items: courses=${displayItems.length} '
        'agenda=${agendaItems.length} schedule=${scheduleItems.length}',
      );
    }
    final isActivePage =
        target.week == _selectedWeekForDayView &&
        target.dayOfWeek == _selectedDayOfWeek;
    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          key: ValueKey('day-content-${target.week}-${target.dayOfWeek}'),
          children: [
            // Keep original side inset / card width; only the
            // surface material matches chrome glass (below).
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _buildDayViewSummary(
                key: isActivePage ? const ValueKey('day-view-summary') : null,
                provider: provider,
                settings: settings,
                week: target.week,
                dayOfWeek: target.dayOfWeek,
                selectedDate: selectedDate,
                currentCourse: currentCourse,
                courseItems: displayItems,
                scheduleItems: scheduleItems,
                agendaItems: agendaItems,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _buildExpandedDayColumnView(
                key: ValueKey('day-column-${target.week}-${target.dayOfWeek}'),
                provider: provider,
                settings: settings,
                week: target.week,
                dayOfWeek: target.dayOfWeek,
              ),
            ),
          ],
        ),
        Listener(
          key: const ValueKey('day-view-blank-tap-dismiss'),
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            _dayViewBlankTapProbes[event.pointer] = _DayViewBlankTapProbe(
              event.timeStamp,
              event.position,
            );
          },
          onPointerMove: (event) {
            final probe = _dayViewBlankTapProbes[event.pointer];
            if (probe == null) {
              return;
            }
            if ((event.position - probe.downPosition).distance > kTouchSlop) {
              _dayViewBlankTapProbes.remove(event.pointer);
            }
          },
          onPointerUp: (event) {
            final probe = _dayViewBlankTapProbes.remove(event.pointer);
            if (probe == null) {
              return;
            }
            if (_dayViewInteractivePointerIds.remove(event.pointer)) {
              return;
            }
            final delta = event.position - probe.downPosition;
            final pressDuration = event.timeStamp - probe.downTime;
            if (delta.distance <= kTouchSlop &&
                pressDuration <= const Duration(milliseconds: 600)) {
              unawaited(_closeDayView(settings));
            }
          },
          onPointerCancel: (event) {
            _dayViewBlankTapProbes.remove(event.pointer);
            _dayViewInteractivePointerIds.remove(event.pointer);
          },
          child: const SizedBox.expand(),
        ),
      ],
    );
  }

  bool _isSelectedDayToday({
    required TimetableProvider provider,
    required TimetableSettings settings,
    required int week,
    required int dayOfWeek,
  }) {
    final resolvedDate = _dateForWeekDay(settings, week, dayOfWeek);
    if (resolvedDate != null) {
      return _isSameDate(resolvedDate, DateTime.now());
    }
    final now = DateTime.now();
    return dayOfWeek == now.weekday && week == _visibleWeek;
  }

  DateTime _resolveDisplayDateForWeekDay({
    required TimetableProvider provider,
    required TimetableSettings settings,
    required int week,
    required int dayOfWeek,
  }) {
    final resolvedDate = _dateForWeekDay(settings, week, dayOfWeek);
    if (resolvedDate != null) {
      return resolvedDate;
    }

    final now = DateTime.now();
    final normalizedToday = DateTime(now.year, now.month, now.day);
    final dayDelta = (week - _visibleWeek) * 7 + dayOfWeek - now.weekday;
    return normalizedToday.add(Duration(days: dayDelta));
  }

  List<ScheduleItemInstance> _getScheduleItemsForWeekDay({
    required TimetableProvider provider,
    required TimetableSettings settings,
    required int week,
    required int dayOfWeek,
  }) {
    final targetDate = _resolveDisplayDateForWeekDay(
      provider: provider,
      settings: settings,
      week: week,
      dayOfWeek: dayOfWeek,
    );
    return provider.getScheduleItemInstancesForDate(targetDate);
  }

  _DayAgendaItem _buildScheduleAgendaItemForDate({
    required ScheduleItemInstance instance,
    required DateTime targetDate,
  }) {
    final item = instance.effectiveItem;
    final normalizedTargetDate = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
    );
    final continuesFromPreviousDay = item.startDate.isBefore(
      normalizedTargetDate,
    );
    final continuesToNextDay = item.endDate.isAfter(normalizedTargetDate);
    return _DayAgendaItem.schedule(
      item,
      instance: instance,
      startTime: continuesFromPreviousDay ? '00:00' : item.startTime,
      endTime: continuesToNextDay ? '23:59' : item.endTime,
      continuesFromPreviousDay: continuesFromPreviousDay,
      continuesToNextDay: continuesToNextDay,
    );
  }

  List<_DayAgendaItem> _buildDayAgendaItems({
    required TimetableProvider provider,
    required TimetableSettings settings,
    required int week,
    required int dayOfWeek,
    required List<_DayCourseDisplayItem> courseItems,
  }) {
    final targetDate = _resolveDisplayDateForWeekDay(
      provider: provider,
      settings: settings,
      week: week,
      dayOfWeek: dayOfWeek,
    );
    final items = <_DayAgendaItem>[
      ...courseItems.map(_DayAgendaItem.course),
      ..._getScheduleItemsForWeekDay(
        provider: provider,
        settings: settings,
        week: week,
        dayOfWeek: dayOfWeek,
      ).map(
        (instance) => _buildScheduleAgendaItemForDate(
          instance: instance,
          targetDate: targetDate,
        ),
      ),
      ...provider.exams
          .where((e) => !e.isExpired && _isSameDate(e.dateTime, targetDate))
          .map(_DayAgendaItem.exam),
    ];

    items.sort((left, right) {
      final startCompare = left.startTime.compareTo(right.startTime);
      if (startCompare != 0) {
        return startCompare;
      }
      final endCompare = left.endTime.compareTo(right.endTime);
      if (endCompare != 0) {
        return endCompare;
      }
      final leftType = left.isExam ? 2 : (left.isScheduleItem ? 1 : 0);
      final rightType = right.isExam ? 2 : (right.isScheduleItem ? 1 : 0);
      if (leftType != rightType) {
        return leftType.compareTo(rightType);
      }
      return left.id.compareTo(right.id);
    });
    return items;
  }

  Widget _buildDayViewSummary({
    Key? key,
    required TimetableProvider provider,
    required TimetableSettings settings,
    required int week,
    required int dayOfWeek,
    required DateTime? selectedDate,
    required Course? currentCourse,
    required List<_DayCourseDisplayItem> courseItems,
    required List<ScheduleItem> scheduleItems,
    required List<_DayAgendaItem> agendaItems,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final foruiTheme = context.theme;
    final colorScheme = theme.colorScheme;
    final isToday = _isSelectedDayToday(
      provider: provider,
      settings: settings,
      week: week,
      dayOfWeek: dayOfWeek,
    );
    final courseCount = courseItems.length;
    final scheduleCount = scheduleItems.length;
    final hasAgenda = agendaItems.isNotEmpty;
    final currentWeekItems = courseItems
        .where((item) => item.isCurrentWeekCourse)
        .toList();
    final nonCurrentWeekCourseCount = courseCount - currentWeekItems.length;
    final conflictCount = courseItems
        .where((item) => item.isConflicting)
        .length;
    final firstAgenda = hasAgenda ? agendaItems.first : null;
    final lastAgenda = hasAgenda ? agendaItems.last : null;
    final locale = Localizations.localeOf(context);
    final localeName = locale.countryCode?.isNotEmpty == true
        ? '${locale.languageCode}_${locale.countryCode}'
        : locale.languageCode;
    final dateLabel = selectedDate != null
        ? _formatDayViewSummaryDate(
            selectedDate,
            dayOfWeek: dayOfWeek,
            localeName: localeName,
          )
        : _weekdayLabel(context, dayOfWeek);
    final targetDate =
        selectedDate ??
        _resolveDisplayDateForWeekDay(
          provider: provider,
          settings: settings,
          week: week,
          dayOfWeek: dayOfWeek,
        );
    final dayExams =
        provider.exams
            .where((e) => !e.isExpired && _isSameDate(e.dateTime, targetDate))
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final today = DateTime.now();
    final normalizedToday = DateTime(today.year, today.month, today.day);
    final selectedDayDate = selectedDate != null
        ? DateTime(selectedDate.year, selectedDate.month, selectedDate.day)
        : null;
    final backToTodayIcon =
        selectedDayDate != null && selectedDayDate.isBefore(normalizedToday)
        ? Icons.arrow_forward_rounded
        : Icons.arrow_back_rounded;

    final isDark = theme.brightness == Brightness.dark;
    final hasBackdrop = hasHomePageBackdropImage(settings);
    final backdropBlurOn =
        hasBackdrop && HyperosBlurredHeader.backdropBlurEnabled(context);
    // 椤舵�?淇℃伅鏍忓紑鐫€鐜荤拑鏃讹紝鎽樿鍗′笌椤堕儴閾幓鐠冨甫鍚屾潗璐ㄣ€佸悓澧ㄨ壊鏋佹€с€?
    final matchesChromeBand = homePageHasAnyChromeBlur(
      settings,
      hasBackdrop: hasBackdrop,
    );
    // 璇剧▼鍗″垏鍒般€岄珮鏂ā绯娿€嶆。涓旀湁澹佺焊鏃讹紝鎽樿鍗′篃璧伴摤鐜荤拑浜（鐮傛潗璐�?
    // CourseSurface 鐨勯珮鏂矾寰勫彧鏈?0.42 鐨勫急涓€?tint锛屾繁鑹插绾镐細鐩存帴閫忓嚭锛?
    // 璁┿€屽洖鍒颁粖�?/ 鍏抽�?/ 鏃ユ湡銆嶆暣寮犲崱璇讳綔鍙戦粦鐨勭幓鐠冿紱閾幓�?wash 涓庡脊绐?
    // 鍚岀骇锛堟祬鑹蹭富棰樼害鐧借壊 0.68锛夛紝淇濊瘉鍗＄墖濮嬬粓鍋忎寒鑹层€?
    final useChromeGlass =
        matchesChromeBand ||
        (backdropBlurOn &&
            settings.courseCardSurfaceStyle == CourseCardSurfaceStyle.gaussian);
    // Ink: 涓庨《閮ㄧ幓鐠冨甫鍚屾潗璐ㄦ椂娌跨敤澹佺焊浜害鑷姩榛戠櫧锛涘惁鍒欏崱闈㈠氨鏄富棰樺簳鑹?
    // 锛堟垨浜（鐮傦級锛屽ⅷ鑹插繀椤昏窡涓婚�?鈥斺�?鎸夊師濮嬪绾镐寒搴︾炕鐧戒細璁╃櫧澧ㄨ惤鍦?
    // 浜壊鍗￠潰涓婁笉鍙�?
    final summaryInk = matchesChromeBand
        ? homePageOverWallpaperInk(
            configuredHex: isDark
                ? settings.weekdayBarFontColorDark
                : settings.weekdayBarFontColorLight,
            defaultHex: isDark
                ? TimetableSettings.defaultWeekdayBarFontColorDark
                : TimetableSettings.defaultWeekdayBarFontColorLight,
            themeFallback: foruiTheme.colors.foreground,
            hasBackdrop: hasBackdrop,
            wallpaperLuminance:
                _wallpaperBodyLuminance ?? _wallpaperTopLuminance,
          )
        : foruiTheme.colors.foreground;
    final summaryMutedInk = homePageOverWallpaperMutedInk(summaryInk);
    // 璇剧▼璁℃暟鑳跺泭涓庛€�?鑺傛棩绋嬨€嶈兌鍥婂悓娆句腑鎬уⅷ锛氳窡鎽樿鍗″叾浣欐枃瀛椾竴鏍疯蛋
    // 澹佺焊鑷姩榛戠櫧锛屾湁璇句笌鍚︿笉鍐嶅垏鎹富棰樿摑寮鸿皟鑹层�?
    final countBadgeColor = summaryInk.withValues(alpha: 0.10);
    final countBadgeTextColor = summaryMutedInk;
    return _dayAgendaSurface(
      key: key,
      settings:
          useChromeGlass ||
              settings.courseCardSurfaceStyle == CourseCardSurfaceStyle.solid
          ? settings
          // 鏃犲绾?妯＄硦琚叧鎺夋椂楂樻柉妗ｆ病鏈夊彲鐢ㄧ殑纾ㄧ爞鏉ユ簮锛岄€€鍖栦负瀹炲績浜崱�?
          : settings.copyWith(
              courseCardSurfaceStyle: CourseCardSurfaceStyle.solid,
            ),
      chromeGlass: useChromeGlass,
      // Neutral wash (not a course hue); CourseSurface owns glass vs solid.
      color: foruiTheme.colors.background,
      gradient: LinearGradient(
        colors: [foruiTheme.colors.background, foruiTheme.colors.background],
      ),
      // 鎽樿鍗℃病鏈夎绋嬭壊濉厖鍙緷鎵橈細鏃犲绾革紙绾壊椤甸潰锛夋椂濉厖鑹蹭笌椤甸潰搴曡壊
      // 鐩稿悓锛屾棤杈规鏃犻槾褰变細鏁村紶闅愬舰锛堜笅鏂硅绋嬪崱�?hue + outerShadow 淇濇�?
      // 杈圭晫锛夈€傝ˉ涓€濂椾腑鎬х粏鎻忚�?+ 鏌斿拰鎶曞奖锛屽嚑浣曞弬鏁颁�?agenda 鍗＄墖涓€鑷达紝
      // 璁╀袱绉嶅崱鐗囧湪绾櫧搴曚笂璇讳綔鍚屼竴涓崱鐗囩郴缁熴€俢hromeGlass 鍒嗘敮鑷粯澹佺�?
      // 閲囨牱鏉愯川锛屽拷鐣ヨ繖涓や釜鍙傛暟锛屼笉鍙楀奖鍝嶃€?
      border: useChromeGlass
          ? null
          : Border.all(color: summaryInk.withValues(alpha: 0.12)),
      shadow: useChromeGlass
          ? null
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      if (isToday)
                        Text(
                          l10n.todayTimetableTitle,
                          style: foruiTheme.typography.body.sm.copyWith(
                            color: summaryMutedInk,
                            fontWeight: FontWeight.w500,
                          ),
                        )
                      else if (_canNavigateDayViewToToday(settings))
                        _dayViewInteractiveListener(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              key: const ValueKey('back-to-today-button'),
                              onTap: () async {
                                await _navigateDayViewToToday(provider);
                              },
                              borderRadius: BorderRadius.circular(999),
                              child: Ink(
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    8,
                                    4,
                                    10,
                                    4,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        backToTodayIcon,
                                        size: 14,
                                        color: colorScheme.onPrimaryContainer,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        l10n.backToTodayAction,
                                        style: foruiTheme.typography.body.xs
                                            .copyWith(
                                              color: colorScheme
                                                  .onPrimaryContainer,
                                              fontWeight: FontWeight.w600,
                                              height: 1.1,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (isToday || _canNavigateDayViewToToday(settings))
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            '·',
                            style: foruiTheme.typography.body.sm.copyWith(
                              color: summaryMutedInk,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      Text(
                        l10n.weekLabel(week),
                        style: foruiTheme.typography.body.sm.copyWith(
                          color: summaryMutedInk,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                _dayViewInteractiveListener(
                  child: IconButton(
                    key: const ValueKey('back-to-week-view-button'),
                    onPressed: () => _closeDayView(settings),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: l10n.backToWeekViewAction,
                    style: IconButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(6),
                      minimumSize: const Size(32, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: summaryMutedInk,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              dateLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: foruiTheme.typography.display.lg.copyWith(
                fontWeight: FontWeight.w400,
                letterSpacing: 0.1,
                height: 1.15,
                color: summaryInk,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: countBadgeColor,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    hasAgenda
                        ? (courseCount > 0
                              ? l10n.courseCountSummary(courseCount)
                              : l10n.scheduleCountSummary(scheduleCount))
                        : l10n.courseCountSummary(0),
                    style: foruiTheme.typography.body.xs2.copyWith(
                      color: countBadgeTextColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (scheduleCount > 0 && courseCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: summaryInk.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      l10n.scheduleCountSummary(scheduleCount),
                      style: foruiTheme.typography.body.xs2.copyWith(
                        color: summaryMutedInk,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (firstAgenda != null)
                  Text(
                    '${l10n.classStartsAtLabel(firstAgenda.startTime)} · ${l10n.classEndsAtLabel(lastAgenda!.endTime)}',
                    style: foruiTheme.typography.body.xs2.copyWith(
                      color: summaryMutedInk,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
            if (currentCourse != null ||
                conflictCount > 0 ||
                nonCurrentWeekCourseCount > 0 ||
                dayExams.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (currentCourse != null)
                    _buildDayViewSummaryChip(
                      icon: Icons.bolt_rounded,
                      text:
                          '${l10n.ongoingCourseBadge} · ${currentCourse.name}',
                      accentColor: colorScheme.primary,
                    ),
                  if (conflictCount > 0)
                    _buildDayViewSummaryChip(
                      icon: Icons.warning_amber_rounded,
                      text: l10n.conflictCountLabel(conflictCount),
                      accentColor: colorScheme.error,
                    ),
                  if (nonCurrentWeekCourseCount > 0)
                    _buildDayViewSummaryChip(
                      icon: Icons.visibility_rounded,
                      text:
                          '${l10n.nonCurrentWeekLabel} ${l10n.courseCountSummary(nonCurrentWeekCourseCount)}',
                    ),
                  ...dayExams.map(
                    (exam) => _buildDayViewSummaryChip(
                      icon: Icons.school_outlined,
                      text:
                          '${exam.name} · ${exam.daysUntil == 0 ? l10n.examCountdownToday : l10n.examCountdownDays(exam.daysUntil)}',
                      accentColor: colorScheme.error,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDayViewSummaryChip({
    required IconData icon,
    required String text,
    Color? accentColor,
  }) {
    final foruiTheme = context.theme;
    final resolvedAccent = accentColor ?? foruiTheme.colors.mutedForeground;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: resolvedAccent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: resolvedAccent),
          const SizedBox(width: 5),
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: foruiTheme.typography.body.xs.copyWith(
              color: resolvedAccent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDayViewSummaryDate(
    DateTime date, {
    required int dayOfWeek,
    required String localeName,
  }) {
    final formattedDate = DateFormat.MMMd(localeName).format(date);
    return '$formattedDate ${_weekdayLabel(context, dayOfWeek)}';
  }

  Widget _buildDayViewEmptyState({
    required int week,
    required TimetableSettings settings,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasBackdrop = hasHomePageBackdropImage(settings);
    final colorScheme = Theme.of(context).colorScheme;
    // Same wallpaper auto-contrast as weekday / time-axis chrome: default ink
    // flips black鈫攚hite over dark photos; user-custom hex is kept as-is. The
    // empty state sits mid-screen, so judge from the card-region band.
    final titleColor = homePageOverWallpaperInk(
      configuredHex: isDark
          ? settings.weekdayBarFontColorDark
          : settings.weekdayBarFontColorLight,
      defaultHex: isDark
          ? TimetableSettings.defaultWeekdayBarFontColorDark
          : TimetableSettings.defaultWeekdayBarFontColorLight,
      themeFallback: colorScheme.onSurface,
      hasBackdrop: hasBackdrop,
      wallpaperLuminance: _wallpaperBodyLuminance ?? _wallpaperTopLuminance,
    );
    final subtitleColor = homePageOverWallpaperMutedInk(titleColor);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.dayViewEmptyTitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: titleColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.weekLabel(week),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: subtitleColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayViewInteractiveListener({required Widget child}) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _dayViewInteractivePointerIds.add(event.pointer);
      },
      child: child,
    );
  }

  Widget _buildExpandedDayColumnView({
    required Key key,
    required TimetableProvider provider,
    required TimetableSettings settings,
    required int week,
    required int dayOfWeek,
  }) {
    final courses = _getCoursesForDay(
      provider.courses,
      week,
      dayOfWeek,
      settings,
    );
    final currentCourseIds =
        _isSelectedDayToday(
          provider: provider,
          settings: settings,
          week: week,
          dayOfWeek: dayOfWeek,
        )
        ? provider
              .getCoursesInProgress(dayOfWeek: dayOfWeek, week: week)
              .map((course) => course.id)
              .toSet()
        : const <String>{};
    final displayItems = _buildHomeDayDisplayItems(
      provider: provider,
      settings: settings,
      week: week,
      dayOfWeek: dayOfWeek,
      myCourses: courses,
      currentCourseIds: currentCourseIds,
    );
    final agendaItems = _buildDayAgendaItems(
      provider: provider,
      settings: settings,
      week: week,
      dayOfWeek: dayOfWeek,
      courseItems: displayItems,
    );
    // 鐜荤拑鍧為伩璁╋紙鍚簳閮ㄥ畨鍏ㄥ尯锛夛細鏃ヨ琛ㄨ鍙ｅ叏灞忥紝閬胯浠ユ粴鍔?padding
    // 瀹炵幇鈥斺€旈潤姝㈠湪鍒楄〃搴曢儴鏃舵渶鍚庝竴椤逛粛鍋滃湪鐜荤拑鍧炰笂鏂癸紝婊氬姩涓崱鐗囧�?
    // 杩炵画绌胯繃閬胯甯︼紝涓嶅啀鍦ㄨ竟鐣岃纭鍑轰笌纾ㄧ爞鍗＄墖鑹插樊鏄庢樉鐨勭┖甯︺€?
    // 婊″睆鎮诞锛坥verlay锛夊悓鏍峰彇婊氬姩浣欓噺锛堣嵂涓稿崰鐢ㄥ厹搴曪級锛氭鍓?overlay
    // 浣欓噺涓?0锛屼笅婊戝埌搴曟渶鍚庝竴寮犲崱浠嶅帇鍦ㄨ嵂涓稿悗闈紝鏃犳硶婊戝嚭鏉ョ湅�?
    final dockScrollAvoidance = _glassDockContentScrollInset(settings);
    if (agendaItems.isEmpty) {
      return Padding(
        key: key,
        padding: EdgeInsets.fromLTRB(14, 0, 14, 8 + dockScrollAvoidance),
        child: _buildDayViewEmptyColumn(week: week, settings: settings),
      );
    }
    // Gaussian cards sample the cached wallpaper bitmap while the day view
    // moves; the shared host keeps their BackdropFilter capture at grid scope.
    final agendaList = ListView.separated(
      key: PageStorageKey<String>('day-agenda-$week-$dayOfWeek'),
      padding: EdgeInsets.fromLTRB(14, 0, 14, 8 + dockScrollAvoidance),
      physics: const ClampingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      itemCount: agendaItems.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, itemIndex) {
        final item = agendaItems[itemIndex];
        return _buildDayAgendaEntry(week: week, settings: settings, item: item);
      },
    );
    return CourseGridSurfaceHost(settings: settings, child: agendaList);
  }

  Widget _buildDayViewEmptyColumn({
    required int week,
    required TimetableSettings settings,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
      child: _buildDayViewEmptyState(week: week, settings: settings),
    );
  }

  /// Day-view card surface honouring [TimetableSettings.courseCardSurfaceStyle].
  ///
  /// Shares [CourseSurface] with the week grid so the two views cannot drift.
  /// The tap target sits *inside* the surface behind a transparent [Material]
  /// so ink ripples paint above the frost rather than on the far page Material
  /// (which is what `Ink(decoration:)` used to buy us on an opaque card).
  Widget _dayAgendaSurface({
    required TimetableSettings settings,
    required Color color,
    required Widget child,
    Key? key,
    Gradient? gradient,
    Border? border,
    List<BoxShadow>? shadow,
    double radius = _dayViewCardRadius,
    VoidCallback? onTap,
    double opacityScale = 1,
    bool chromeGlass = false,
  }) {
    final content = onTap == null
        ? child
        : Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(radius),
              child: child,
            ),
          );
    if (chromeGlass) {
      // Chrome-band LOOK, course-card IMPLEMENTATION: the cached pre-blurred
      // wallpaper sample under the chrome wash colour ? a plain drawImageRect
      // + ColoredBox, exactly like the agenda cards below. A live
      // BackdropFilter / liquid glass here had to be swapped out around every
      // pager swipe (per-frame backdrop resampling on the hot path) and the
      // material hop flashed on each swipe; one permanent material can't
      // flicker, and it stays opacity-safe through the open/close ramp.
      return ClipRRect(
        key: key,
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            const Positioned.fill(child: PreblurredWallpaperAlignedFill()),
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  // 涓庨椤?chrome 鐜荤拑甯﹀悓瑙傛劅锛氭恫鎬佺幓鐠冧笅鍙湁鐜荤拑鏈壊�?
                  // 涓嶅啀鍙犲姞鍙�?scrim�?
                  color: HomePageChromeGlassFill.standInWashColor(context),
                ),
              ),
            ),
            content,
          ],
        ),
      );
    }
    return CourseSurface(
      key: key,
      style: settings.courseCardSurfaceStyle,
      color: color,
      borderRadius: radius,
      opacityScale: opacityScale,
      solidGradient: gradient,
      border: border,
      outerShadow: shadow,
      child: content,
    );
  }

  Widget _buildDayAgendaEntry({
    required int week,
    required TimetableSettings settings,
    required _DayAgendaItem item,
  }) {
    final Widget entry;
    if (item.isExam) {
      if (logDayViewBuilds) {
        debugPrint('[DayView] build agenda entry: exam id=${item.exam?.id}');
      }
      entry = _buildExamAgendaEntry(
        item.exam!,
        provider: context.read<TimetableProvider>(),
      );
    } else if (item.isScheduleItem) {
      if (logDayViewBuilds) {
        debugPrint(
          '[DayView] build agenda entry: schedule id=${item.scheduleItem?.id}',
        );
      }
      entry = _buildScheduleAgendaEntry(item, settings: settings);
    } else {
      final courseItem = item.courseItem!;
      if (logDayViewBuilds) {
        debugPrint(
          '[DayView] build agenda entry: course id=${courseItem.course.id} '
          'name=${courseItem.course.name}',
        );
      }
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
      final l10n = AppLocalizations.of(context)!;
      final colorHex = _resolveDisplayCourseColor(
        courseItem,
        settings: settings,
      );
      final resolvedColor = _colorFromHex(
        colorHex ?? courseItem.course.color,
        Colors.blue,
      );
      final palette = _resolveDayAgendaPalette(
        resolvedColor,
        foregroundHex: courseItem.course.textColor,
        settings: settings,
      );
      final onCardColor = palette.foregroundColor;
      final statusBadges = <Widget>[
        if (courseItem.isCurrentCourse)
          _buildDayAgendaStatusBadge(
            text: l10n.ongoingCourseBadge,
            textColor: onCardColor,
            backgroundColor: Colors.white.withValues(alpha: 0.18),
          ),
        if (courseItem.isConflicting && settings.showConflictBadgeOnTimetable)
          _buildDayAgendaStatusBadge(
            text: l10n.conflictLabel,
            textColor: Colors.white,
            backgroundColor: colorScheme.error,
          ),
        if (!courseItem.isCurrentWeekCourse)
          _buildDayAgendaStatusBadge(
            text: l10n.nonCurrentWeekLabel,
            textColor: onCardColor,
            backgroundColor: Colors.white.withValues(alpha: 0.14),
          ),
        if (courseItem.course.isSuspendedInWeek(week))
          _buildDayAgendaStatusBadge(
            text: l10n.suspendedBadgeLabel,
            textColor: Colors.white,
            backgroundColor: Colors.red.shade700,
          ),
        if (courseItem.course.hasHomeworkInWeek(week))
          _buildDayAgendaHomeworkDot(),
      ];
      final cardDecoration = BoxDecoration(
        color: palette.baseColor,
        borderRadius: BorderRadius.circular(_dayViewCardRadius),
        border: courseItem.isConflicting
            ? Border.all(
                color: colorScheme.error.withValues(alpha: 0.30),
                width: 1.4,
              )
            : null,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.baseColor,
            if (courseItem.isConflicting)
              Color.lerp(palette.fillColor, colorScheme.error, 0.12) ??
                  palette.fillColor
            else
              palette.fillColor,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color:
                (courseItem.isConflicting
                        ? colorScheme.error
                        : palette.fillColor)
                    .withValues(alpha: courseItem.isConflicting ? 0.20 : 0.18),
            blurRadius: courseItem.isConflicting ? 18 : 16,
            offset: const Offset(0, 4),
          ),
        ],
      );
      final progressInfo = courseItem.isCurrentCourse
          ? _resolveDayAgendaProgressInfo(courseItem.course, palette: palette)
          : null;

      final isSuspended = courseItem.course.isSuspendedInWeek(week);
      // Keep frost readable; only a light dim for suspended / conflict states.
      final effectiveOpacity = isSuspended ? 0.84 : courseItem.opacity;

      Future<void> openCourseNotes() {
        return showCourseNoteSheet(
          context,
          course: courseItem.course,
          week: week,
        );
      }

      // Released behaviour: tap expands the card into the editor via a container
      // transform. Dimming stays on opacityScale (not an Opacity wrapper) so
      // glass surfaces can still sample the backdrop.
      entry = OpenContainer<void>(
        key: ValueKey('day-view-edit-card-${courseItem.course.id}'),
        tappable: false,
        transitionType: ContainerTransitionType.fadeThrough,
        transitionDuration: const Duration(milliseconds: 420),
        openColor: theme.scaffoldBackgroundColor,
        closedColor: Colors.transparent,
        closedElevation: 0,
        openElevation: 0,
        closedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_dayViewCardRadius),
        ),
        openShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        openBuilder: (context, _) => ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: AddCourseScreen(
            courseGroup: context.read<TimetableProvider>().courseGroupForCourse(
              courseItem.course,
            ),
            initialCourse: courseItem.course,
          ),
        ),
        closedBuilder: (context, openContainer) {
          final content = progressInfo != null
              ? _buildCurrentDayAgendaCard(
                  item: courseItem,
                  week: week,
                  settings: settings,
                  progressInfo: progressInfo,
                  l10n: l10n,
                  colorScheme: colorScheme,
                  ink: palette.foregroundColor,
                  openContainer: openContainer,
                  onOpenNotes: openCourseNotes,
                  opacityScale: effectiveOpacity,
                )
              : _buildDefaultDayAgendaCard(
                  item: courseItem,
                  week: week,
                  settings: settings,
                  l10n: l10n,
                  palette: palette,
                  statusBadges: statusBadges,
                  cardDecoration: cardDecoration,
                  openContainer: openContainer,
                  onOpenNotes: openCourseNotes,
                  opacityScale: effectiveOpacity,
                );
          return Material(color: Colors.transparent, child: content);
        },
      );
    }
    return _dayViewInteractiveListener(child: entry);
  }

  Widget _buildDefaultDayAgendaCard({
    required _DayCourseDisplayItem item,
    required int week,
    required TimetableSettings settings,
    required AppLocalizations l10n,
    required _DayAgendaPalette palette,
    required List<Widget> statusBadges,
    required BoxDecoration cardDecoration,
    required VoidCallback openContainer,
    required VoidCallback onOpenNotes,
    double opacityScale = 1,
  }) {
    final sectionLabel = l10n.sectionRangeLabel(
      item.course.startSection,
      item.course.endSection,
    );
    final teacherValue = item.course.teacher.trim().isNotEmpty
        ? item.course.teacher.trim()
        : l10n.unknownTeacher;
    final teacherLine = '${l10n.teacherPrefix(teacherValue)} ? $sectionLabel';
    final locationValue = item.course.location.trim().isNotEmpty
        ? item.course.location.trim()
        : l10n.unknownLocation;
    final locationLine = l10n.locationPrefix(locationValue);
    final sessionNote = item.course.sessionNoteForWeek(week);
    final sessionPreview = sessionNote?.trimmedText;
    final ink = palette.foregroundColor;
    return _dayAgendaSurface(
      settings: settings,
      color: palette.baseColor,
      opacityScale: opacityScale,
      // Reuse the legacy decoration's pieces so `solid` stays pixel-identical.
      gradient: cardDecoration.gradient,
      border: cardDecoration.border as Border?,
      shadow: cardDecoration.boxShadow,
      onTap: openContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _dayAgendaInkWash(ink, lightAlpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.schedule_rounded, size: 13, color: ink),
                            const SizedBox(width: 5),
                            Text(
                              '${item.course.startTime} - ${item.course.endTime}',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: ink,
                                    fontWeight: FontWeight.w400,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      ...statusBadges,
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                _buildDayAgendaNoteAction(
                  l10n: l10n,
                  ink: ink,
                  onPressed: onOpenNotes,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.course.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                // Auto ink: flips black/white against the wallpaper band
                // behind glass cards (white-on-white mist was unreadable).
                color: ink,
                fontWeight: FontWeight.w400,
                height: 1.10,
              ),
            ),
            const SizedBox(height: 10),
            _buildCurrentDayAgendaInfoRow(
              icon: Icons.person_outline_rounded,
              text: teacherLine,
              ink: ink,
            ),
            const SizedBox(height: 5.5),
            _buildCurrentDayAgendaInfoRow(
              icon: Icons.location_on_outlined,
              text: locationLine,
              ink: ink,
            ),
            if (sessionPreview != null && sessionPreview.isNotEmpty) ...[
              const SizedBox(height: 5.5),
              _buildCurrentDayAgendaInfoRow(
                icon: Icons.sticky_note_2_outlined,
                text: sessionPreview,
                ink: ink,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentDayAgendaCard({
    required _DayCourseDisplayItem item,
    required int week,
    required TimetableSettings settings,
    required _DayAgendaProgressInfo progressInfo,
    required AppLocalizations l10n,
    required ColorScheme colorScheme,
    required Color ink,
    required VoidCallback openContainer,
    required VoidCallback onOpenNotes,
    double opacityScale = 1,
  }) {
    final theme = Theme.of(context);
    final sectionLabel = l10n.sectionRangeLabel(
      item.course.startSection,
      item.course.endSection,
    );
    final teacherValue = item.course.teacher.trim().isNotEmpty
        ? item.course.teacher.trim()
        : l10n.unknownTeacher;
    final teacherLine = '${l10n.teacherPrefix(teacherValue)} ? $sectionLabel';
    final locationValue = item.course.location.trim().isNotEmpty
        ? item.course.location.trim()
        : l10n.unknownLocation;
    final locationLine = l10n.locationPrefix(locationValue);
    final borderColor = item.isConflicting
        ? colorScheme.error.withValues(alpha: 0.30)
        : Colors.transparent;
    final sessionNote = item.course.sessionNoteForWeek(week);
    final sessionPreview = sessionNote?.trimmedText;

    // Over glass the elapsed-progress fill has to stay see-through, or that
    // part of the card turns into a flat opaque block and the frost disappears.
    final progressFill =
        settings.courseCardSurfaceStyle == CourseCardSurfaceStyle.solid
        ? progressInfo.fillColor
        : progressInfo.fillColor.withValues(alpha: 0.55);

    return _dayAgendaSurface(
      settings: settings,
      color: progressInfo.baseColor,
      opacityScale: opacityScale,
      // Flat fill, matching the legacy decoration (this card has no gradient).
      gradient: LinearGradient(
        colors: [progressInfo.baseColor, progressInfo.baseColor],
      ),
      border: Border.all(color: borderColor, width: 1.2),
      shadow: [
        BoxShadow(
          color: progressInfo.fillColor.withValues(alpha: 0.18),
          blurRadius: 18,
          offset: const Offset(0, 4),
        ),
      ],
      onTap: openContainer,
      child: ClipRRect(
        key: ValueKey('day-agenda-progress-card-${item.course.id}'),
        borderRadius: BorderRadius.circular(_dayViewCardRadius),
        child: Stack(
          children: [
            Positioned.fill(
              // Isolated: the animating fill must not invalidate the card's
              // glass surface / text layers on every animation frame.
              child: RepaintBoundary(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(
                    end: progressInfo.progress.clamp(0.0, 1.0),
                  ),
                  // Must stay below the 1 s progress tick, or the tween is
                  // retargeted before it settles and day view animates every
                  // frame forever (see _quantizeDayAgendaProgress).
                  duration: const Duration(milliseconds: 600),
                  builder: (context, animatedProgress, child) {
                    return FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: animatedProgress,
                      child: child,
                    );
                  },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: progressFill,
                      borderRadius: BorderRadius.circular(_dayViewCardRadius),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: _dayAgendaInkWash(ink, lightAlpha: 0.18),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 13,
                                    color: ink,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    '${item.course.startTime} - ${item.course.endTime}',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: ink,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _buildDayAgendaStatusBadge(
                              text: progressInfo.statusText,
                              textColor: progressInfo.statusTextColor,
                              backgroundColor:
                                  progressInfo.statusBackgroundColor,
                            ),
                            if (item.isConflicting)
                              _buildDayAgendaStatusBadge(
                                text: l10n.conflictLabel,
                                textColor: Colors.white,
                                backgroundColor: colorScheme.error,
                              ),
                            if (item.course.hasHomeworkInWeek(week))
                              _buildDayAgendaHomeworkDot(),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      _buildDayAgendaNoteAction(
                        l10n: l10n,
                        ink: ink,
                        onPressed: onOpenNotes,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.course.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w400,
                      height: 1.10,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildCurrentDayAgendaInfoRow(
                    icon: Icons.person_outline_rounded,
                    text: teacherLine,
                    ink: ink,
                  ),
                  const SizedBox(height: 5.5),
                  _buildCurrentDayAgendaInfoRow(
                    icon: Icons.location_on_outlined,
                    text: locationLine,
                    ink: ink,
                  ),
                  if (sessionPreview != null && sessionPreview.isNotEmpty) ...[
                    const SizedBox(height: 5.5),
                    _buildCurrentDayAgendaInfoRow(
                      icon: Icons.sticky_note_2_outlined,
                      text: sessionPreview,
                      ink: ink,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayAgendaHomeworkDot() {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.2),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.assignment_outlined,
        size: 11,
        color: HyperosColors.destructive,
      ),
    );
  }

  Widget _buildDayAgendaNoteAction({
    required AppLocalizations l10n,
    required Color ink,
    required VoidCallback onPressed,
  }) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _dayAgendaInkWash(ink, lightAlpha: 0.16),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _dayAgendaInkWash(ink, lightAlpha: 0.22),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sticky_note_2_outlined, size: 14, color: ink),
                const SizedBox(width: 5),
                Text(
                  l10n.courseNoteAction,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: ink,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExamAgendaEntry(
    Exam exam, {
    required TimetableProvider provider,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    // 楂樻柉妯＄硦妗ｄ笅閿欒绾㈠彧鏈?~42% tint锛屼寒鑹插绾镐細閫忔垚娴呯矇搴曪紝鍐欐鐨?
    // 鐧藉ⅷ浼氭礂娌★紱涓庤�?鏃ョ▼鍗′竴鑷存敼鐢ㄨ嚜鍔ㄩ粦鐧藉ⅷ鑹层�?
    final ink = _dayAgendaAutoInk(
      colorScheme.error,
      settings: provider.settings,
    );
    final course = provider.getCourseForExam(exam);
    final courseName = course?.name ?? '';
    final location = exam.location ?? course?.location ?? '';
    final daysUntil = exam.daysUntil;
    final countdownText = daysUntil == 0
        ? l10n.examCountdownToday
        : l10n.examCountdownDays(daysUntil);

    return OpenContainer<void>(
      key: ValueKey('day-view-exam-card-${exam.id}'),
      tappable: false,
      transitionType: ContainerTransitionType.fadeThrough,
      transitionDuration: const Duration(milliseconds: 360),
      openColor: theme.scaffoldBackgroundColor,
      closedColor: Colors.transparent,
      closedElevation: 0,
      openElevation: 0,
      closedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      openShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      openBuilder: (context, _) => ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: AddExamScreen(exam: exam),
      ),
      closedBuilder: (context, openContainer) {
        return _dayAgendaSurface(
          settings: provider.settings,
          color: colorScheme.error,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.error,
              Color.lerp(colorScheme.error, colorScheme.errorContainer, 0.25) ??
                  colorScheme.error,
            ],
          ),
          shadow: [
            BoxShadow(
              color: colorScheme.error.withValues(alpha: 0.20),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
          onTap: openContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _dayAgendaInkWash(ink, lightAlpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.school_outlined, size: 14, color: ink),
                          const SizedBox(width: 4),
                          Text(
                            l10n.examBadgeLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _dayAgendaInkWash(ink, lightAlpha: 0.16),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        countdownText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: ink,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  exam.name,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 3.5),
                if (exam.startTime.isNotEmpty && exam.endTime.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '${exam.startTime} - ${exam.endTime}',
                      style: TextStyle(
                        fontSize: 13,
                        color: ink.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                if (location.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      location,
                      style: TextStyle(
                        fontSize: 13,
                        color: ink.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                if (courseName.isNotEmpty)
                  Text(
                    courseName,
                    style: TextStyle(
                      fontSize: 12,
                      color: ink.withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildScheduleAgendaEntry(
    _DayAgendaItem agendaItem, {
    required TimetableSettings settings,
  }) {
    final item = agendaItem.scheduleItem!;
    final sourceItem = agendaItem.scheduleInstance?.item ?? item;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final baseColor = _colorFromHex(item.color, colorScheme.primary);
    final cardColor = Color.lerp(baseColor, Colors.black, 0.10) ?? baseColor;
    final l10n = AppLocalizations.of(context)!;
    final hasLocation = item.location?.trim().isNotEmpty == true;
    final hasNote = item.note?.trim().isNotEmpty == true;
    final isCrossDay = item.endDate.isAfter(item.startDate);
    final progressInfo = _resolveScheduleAgendaProgressInfo(item, baseColor);
    // Same auto black/white as course agenda cards (glass over bright mist).
    final ink = _dayAgendaAutoInk(cardColor, settings: settings);

    return OpenContainer<void>(
      key: ValueKey('day-view-schedule-card-${agendaItem.id}'),
      tappable: false,
      transitionType: ContainerTransitionType.fadeThrough,
      transitionDuration: const Duration(milliseconds: 360),
      openColor: theme.scaffoldBackgroundColor,
      closedColor: Colors.transparent,
      closedElevation: 0,
      openElevation: 0,
      closedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_dayViewCardRadius),
      ),
      openShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      openBuilder: (context, _) => ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: AddScheduleItemScreen(
          scheduleItem: sourceItem,
          occurrenceDate: agendaItem.scheduleInstance?.occurrenceDate,
        ),
      ),
      closedBuilder: (context, openContainer) {
        if (progressInfo != null) {
          return Material(
            color: Colors.transparent,
            child: _buildCurrentScheduleAgendaCard(
              item: item,
              agendaItem: agendaItem,
              settings: settings,
              progressInfo: progressInfo,
              l10n: l10n,
              colorScheme: colorScheme,
              ink: ink,
              openContainer: openContainer,
            ),
          );
        }
        return _dayAgendaSurface(
          settings: settings,
          color: cardColor,
          gradient: LinearGradient(colors: [cardColor, cardColor]),
          shadow: [
            BoxShadow(
              color: cardColor.withValues(alpha: 0.20),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
          onTap: openContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _dayAgendaInkWash(ink, lightAlpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.event_note_rounded, size: 13, color: ink),
                          const SizedBox(width: 5),
                          Text(
                            '${agendaItem.startTime} - ${agendaItem.endTime}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildDayAgendaStatusBadge(
                      text: l10n.scheduleBadgeLabel,
                      textColor: ink,
                      backgroundColor: _dayAgendaInkWash(ink, lightAlpha: 0.18),
                    ),
                    if (isCrossDay)
                      _buildDayAgendaStatusBadge(
                        text: l10n.crossDayBadgeLabel,
                        textColor: ink,
                        backgroundColor: _dayAgendaInkWash(
                          ink,
                          lightAlpha: 0.18,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: ink,
                    fontWeight: FontWeight.w800,
                    height: 1.10,
                  ),
                ),
                if (hasLocation) ...[
                  const SizedBox(height: 10),
                  _buildCurrentDayAgendaInfoRow(
                    icon: Icons.location_on_outlined,
                    text: l10n.locationPrefix(item.location!.trim()),
                    ink: ink,
                  ),
                ],
                if (hasNote) ...[
                  const SizedBox(height: 5.5),
                  _buildCurrentDayAgendaInfoRow(
                    icon: Icons.notes_rounded,
                    text: item.note!.trim(),
                    ink: ink,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCurrentScheduleAgendaCard({
    required ScheduleItem item,
    required _DayAgendaItem agendaItem,
    required TimetableSettings settings,
    required _DayAgendaProgressInfo progressInfo,
    required AppLocalizations l10n,
    required ColorScheme colorScheme,
    required Color ink,
    required VoidCallback openContainer,
  }) {
    final theme = Theme.of(context);
    final hasLocation = item.location?.trim().isNotEmpty == true;
    final hasNote = item.note?.trim().isNotEmpty == true;
    final isCrossDay = item.endDate.isAfter(item.startDate);
    // See _buildCurrentDayAgendaCard: the fill must stay see-through on glass.
    final progressFill =
        settings.courseCardSurfaceStyle == CourseCardSurfaceStyle.solid
        ? progressInfo.fillColor
        : progressInfo.fillColor.withValues(alpha: 0.55);

    return _dayAgendaSurface(
      settings: settings,
      color: progressInfo.baseColor,
      // Flat fill, matching the legacy decoration (no gradient here).
      gradient: LinearGradient(
        colors: [progressInfo.baseColor, progressInfo.baseColor],
      ),
      shadow: [
        BoxShadow(
          color: progressInfo.fillColor.withValues(alpha: 0.18),
          blurRadius: 18,
          offset: const Offset(0, 4),
        ),
      ],
      onTap: openContainer,
      child: ClipRRect(
        key: ValueKey('day-agenda-progress-schedule-card-${item.id}'),
        borderRadius: BorderRadius.circular(_dayViewCardRadius),
        child: Stack(
          children: [
            Positioned.fill(
              // Isolated: the animating fill must not invalidate the card's
              // glass surface / text layers on every animation frame.
              child: RepaintBoundary(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(
                    end: progressInfo.progress.clamp(0.0, 1.0),
                  ),
                  // Below the 1 s tick so the tween settles between steps
                  // (see _quantizeDayAgendaProgress).
                  duration: const Duration(milliseconds: 600),
                  builder: (context, animatedProgress, child) {
                    return FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: animatedProgress,
                      child: child,
                    );
                  },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: progressFill,
                      borderRadius: BorderRadius.circular(_dayViewCardRadius),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _dayAgendaInkWash(ink, lightAlpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.event_note_rounded,
                              size: 13,
                              color: ink,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${agendaItem.startTime} - ${agendaItem.endTime}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildDayAgendaStatusBadge(
                        text: progressInfo.statusText,
                        textColor: progressInfo.statusTextColor,
                        backgroundColor: progressInfo.statusBackgroundColor,
                      ),
                      _buildDayAgendaStatusBadge(
                        text: l10n.scheduleBadgeLabel,
                        textColor: ink,
                        backgroundColor: _dayAgendaInkWash(
                          ink,
                          lightAlpha: 0.18,
                        ),
                      ),
                      if (isCrossDay)
                        _buildDayAgendaStatusBadge(
                          text: l10n.crossDayBadgeLabel,
                          textColor: ink,
                          backgroundColor: _dayAgendaInkWash(
                            ink,
                            lightAlpha: 0.18,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w800,
                      height: 1.10,
                    ),
                  ),
                  if (hasLocation) ...[
                    const SizedBox(height: 10),
                    _buildCurrentDayAgendaInfoRow(
                      icon: Icons.location_on_outlined,
                      text: l10n.locationPrefix(item.location!.trim()),
                      ink: ink,
                    ),
                  ],
                  if (hasNote) ...[
                    const SizedBox(height: 5.5),
                    _buildCurrentDayAgendaInfoRow(
                      icon: Icons.notes_rounded,
                      text: item.note!.trim(),
                      ink: ink,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentDayAgendaInfoRow({
    required IconData icon,
    required String text,
    required Color ink,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 14, color: ink.withValues(alpha: 0.82)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ink.withValues(alpha: 0.92),
              fontWeight: FontWeight.w400,
              fontSize: 11.5,
              height: 1.15,
            ),
          ),
        ),
      ],
    );
  }

  /// Translucent chip/pill glaze under [ink]-coloured content.
  ///
  /// White ink keeps the legacy white glaze; dark ink flips to a dark glaze ?
  /// a white wash under dark text over a bright wallpaper adds no contrast.
  Color _dayAgendaInkWash(Color ink, {required double lightAlpha}) {
    return ink.computeLuminance() > 0.5
        ? Colors.white.withValues(alpha: lightAlpha)
        : Colors.black.withValues(alpha: lightAlpha * 0.55);
  }

  /// Progress snapped to ~0.4% steps (�?.5 px on a full-width card).
  ///
  /// The raw ratio has sub-second precision, so it used to change on every
  /// 1 s tick and the progress tween was retargeted before it could finish ?
  /// day view ended up animating (and re-rasterizing all its glass chrome)
  /// on every frame, forever. Stepping is visually indistinguishable while
  /// letting the tween settle, so no frames are scheduled between steps.
  static double _quantizeDayAgendaProgress(double raw) {
    const steps = 250;
    return ((raw * steps).floorToDouble() / steps).clamp(0.02, 0.98);
  }

  _DayAgendaProgressInfo? _resolveDayAgendaProgressInfo(
    Course course, {
    required _DayAgendaPalette palette,
  }) {
    final now = DateTime.now();
    final startMinutes = _parseDayAgendaClockMinutes(course.startTime);
    final endMinutes = _parseDayAgendaClockMinutes(course.endTime);
    if (startMinutes == null ||
        endMinutes == null ||
        endMinutes <= startMinutes) {
      return null;
    }
    final currentMinutes =
        now.hour * 60 +
        now.minute +
        (now.second / 60) +
        (now.millisecond / 60000);
    if (currentMinutes < startMinutes || currentMinutes >= endMinutes) {
      return null;
    }
    final elapsedMinutes = currentMinutes - startMinutes;
    final totalMinutes = endMinutes - startMinutes;
    final remainingMinutes = math.max(0, (endMinutes - currentMinutes).ceil());
    final progress = _quantizeDayAgendaProgress(elapsedMinutes / totalMinutes);
    final isEndingSoon = remainingMinutes <= 10;
    return _DayAgendaProgressInfo(
      progress: progress,
      remainingMinutes: remainingMinutes,
      statusText: isEndingSoon
          ? AppLocalizations.of(
              context,
            )!.dayAgendaEndingSoonStatus(remainingMinutes)
          : AppLocalizations.of(
              context,
            )!.dayAgendaInProgressStatus(remainingMinutes),
      statusBackgroundColor: Colors.white,
      statusTextColor: isEndingSoon
          ? HyperosColors.destructive
          : palette.fillColor,
      baseColor: palette.baseColor,
      fillColor: palette.fillColor,
    );
  }

  _DayAgendaProgressInfo? _resolveScheduleAgendaProgressInfo(
    ScheduleItem item,
    Color background,
  ) {
    final now = DateTime.now();
    final start = _buildScheduleDateTime(item.startDate, item.startTime);
    final end = _buildScheduleDateTime(item.endDate, item.endTime);
    if (start == null || end == null || !end.isAfter(start)) {
      return null;
    }
    if (now.isBefore(start) || !now.isBefore(end)) {
      return null;
    }

    final fillColor = Color.lerp(background, Colors.black, 0.18) ?? background;
    final baseColor = Color.lerp(fillColor, Colors.white, 0.10) ?? fillColor;
    final elapsedMinutes = now.difference(start).inMilliseconds / 60000;
    final totalMinutes = end.difference(start).inMilliseconds / 60000;
    final remainingMinutes = math.max(
      0,
      end.difference(now).inMinutes +
          (end.difference(now).inSeconds % 60 > 0 ? 1 : 0),
    );
    final progress = _quantizeDayAgendaProgress(elapsedMinutes / totalMinutes);
    final isEndingSoon = remainingMinutes <= 10;

    return _DayAgendaProgressInfo(
      progress: progress,
      remainingMinutes: remainingMinutes,
      statusText: isEndingSoon
          ? AppLocalizations.of(
              context,
            )!.scheduleAgendaEndingSoonStatus(remainingMinutes)
          : AppLocalizations.of(
              context,
            )!.scheduleAgendaInProgressStatus(remainingMinutes),
      statusBackgroundColor: Colors.white,
      statusTextColor: isEndingSoon ? HyperosColors.destructive : fillColor,
      baseColor: baseColor,
      fillColor: fillColor,
    );
  }

  DateTime? _buildScheduleDateTime(DateTime date, String clock) {
    final minutes = _parseDayAgendaClockMinutes(clock);
    if (minutes == null) {
      return null;
    }
    return DateTime(
      date.year,
      date.month,
      date.day,
      minutes ~/ 60,
      minutes % 60,
    );
  }

  int? _parseDayAgendaClockMinutes(String value) {
    final parts = value.split(':');
    if (parts.length != 2) {
      return null;
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return null;
    }
    return hour * 60 + minute;
  }

  _DayAgendaPalette _resolveDayAgendaPalette(
    Color background, {
    String? foregroundHex,
    TimetableSettings? settings,
  }) {
    // Keep pastel import colors light; only a tiny white lift for depth.
    final fillColor = background;
    final baseColor = Color.lerp(fillColor, Colors.white, 0.06) ?? fillColor;
    final customInk = foregroundHex == null || foregroundHex.trim().isEmpty
        ? null
        : _colorFromHex(foregroundHex, Colors.white);
    // 鑷畾涔夊瓧鑹诧紙瀵煎�?LAN 鍚屾鎼哄甫锛夊湪瀹炲績鍗￠潰涓婂仛鍙鎬у厹搴曪細涓庡崱�?
    // 鍚岃壊绯绘椂锛堝钃濆瓧閰嶈摑鍗★級鏇挎崲涓洪粦鐧芥渶浼樺ⅷ鑹层€傜幓鐠冩。鎸夊绾镐寒搴﹁蛋鐜荤�?
    // 瑙勫垯锛堝僵鑹插ⅷ鍥炶惤鑷姩榛戠櫧銆佷腑鎬уⅷ瀵规瘮搴﹂棬妲涳級锛屼笌 CourseCard 琛屼�?
    // 涓€鑷达紱澹佺焊浜害鏈煡鏃朵繚鐣欑敤鎴烽€夋嫨銆?
    final showsWallpaper =
        settings != null &&
        courseCardSurfaceShowsWallpaper(settings.courseCardSurfaceStyle);
    final foregroundColor = customInk == null
        ? _dayAgendaAutoInk(fillColor, settings: settings)
        : resolveReadableCourseCardTitleColor(
            preferred: customInk,
            cardColor: fillColor,
            surfaceShowsWallpaper: showsWallpaper,
            wallpaperLuminance: showsWallpaper
                ? (_wallpaperBodyLuminance ?? _wallpaperTopLuminance)
                : null,
          );
    return _DayAgendaPalette(
      baseColor: baseColor,
      fillColor: fillColor,
      foregroundColor: foregroundColor,
    );
  }

  /// Default agenda-card ink when the course has no custom text colour.
  ///
  /// Opaque styles keep the legacy white-on-hue. The gaussian style shows
  /// mostly wallpaper through a ~40% tint, so the ink flips black/white against
  /// the blend of course hue and the wallpaper band behind the cards ? a bright
  /// wallpaper region otherwise gives white-on-white.
  Color _dayAgendaAutoInk(Color fill, {TimetableSettings? settings}) {
    if (settings == null) {
      return Colors.white;
    }
    final glassOverWallpaper =
        hasHomePageBackdropImage(settings) &&
        settings.courseCardSurfaceStyle == CourseCardSurfaceStyle.gaussian;
    if (!glassOverWallpaper) {
      return Colors.white;
    }
    final wallpaperLuminance =
        _wallpaperBodyLuminance ?? _wallpaperTopLuminance;
    if (wallpaperLuminance == null) {
      return Colors.white;
    }
    final effectiveLuminance =
        fill.computeLuminance() * 0.5 + wallpaperLuminance * 0.5;
    return homePageChromeForegroundForLuminance(
      effectiveLuminance,
      fallback: Colors.white,
    );
  }

  Widget _buildDayAgendaStatusBadge({
    required String text,
    required Color textColor,
    required Color backgroundColor,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w400,
          fontSize: 10.5,
          height: 1,
        ),
      ),
    );
  }

  BorderRadius _groupedDayColumnBorderRadius(
    int dayIndex,
    int dayCount, {
    double radius = 12,
  }) {
    if (dayCount <= 1) {
      return BorderRadius.circular(radius);
    }
    return BorderRadius.only(
      topLeft: dayIndex == 0 ? Radius.circular(radius) : Radius.zero,
      bottomLeft: dayIndex == 0 ? Radius.circular(radius) : Radius.zero,
      topRight: dayIndex == dayCount - 1
          ? Radius.circular(radius)
          : Radius.zero,
      bottomRight: dayIndex == dayCount - 1
          ? Radius.circular(radius)
          : Radius.zero,
    );
  }

  Widget _buildDayColumn(
    int week,
    int dayOfWeek,
    List<_DayCourseDisplayItem> displayItems,
    TimetableSettings settings,
    bool showConflictBadge,
    double sectionHeight,
    double cardInset,
    TimetableProvider provider, {
    required bool animateCourseEntrance,
    required int dayIndex,
    required int dayCount,
  }) {
    final courseCards = <Widget>[];
    final gridLines = <Widget>[];

    final date = _dateForWeekDay(settings, week, dayOfWeek);
    final isDayHoliday = date != null && provider.isHoliday(date);

    for (
      var sectionIndex = 0;
      sectionIndex < settings.sectionCount;
      sectionIndex++
    ) {
      final section = sectionIndex + 1;
      final startingCourses = _getDisplayItemsStartingAtSection(
        displayItems,
        section,
      );

      gridLines.add(
        Positioned(
          top: sectionIndex * sectionHeight,
          left: 0,
          right: 0,
          height: sectionHeight,
          child: const SizedBox.expand(),
        ),
      );

      for (final item in startingCourses) {
        // Staggered entrance: each card slides up with a small delay based on
        // its day column and section position. Uses Transform only (no
        // Opacity wrapper) so backdrop blur stays intact during and after.
        final staggerSlot = (dayIndex * 2 + sectionIndex.clamp(0, 3)).clamp(
          0,
          7,
        );
        final staggerBegin = staggerSlot * 0.06;
        final entranceCurve = Interval(
          staggerBegin.clamp(0, 0.6),
          1,
          curve: Curves.easeOutCubic,
        );
        courseCards.add(
          Positioned(
            top: sectionIndex * sectionHeight,
            left: 0,
            right: 0,
            height: item.course.sectionCount * sectionHeight,
            child: TweenAnimationBuilder<double>(
              // During a week deck hand-off the real PageView element is newly
              // mounted. Starting this implicit entrance at 0 would replay the
              // 8-px stagger and read as a one-frame settle jerk. Pre-settle
              // builds therefore start at the final value; the post-settle
              // rebuild reuses that state and does not restart the tween.
              tween: Tween(begin: animateCourseEntrance ? 0.0 : 1.0, end: 1.0),
              duration: animateCourseEntrance
                  ? const Duration(microseconds: 290131)
                  : Duration.zero,
              curve: entranceCurve,
              child: CourseCard(
                course: item.course,
                overrideColorHex: _resolveDisplayCourseColor(
                  item,
                  settings: settings,
                ),
                compactOverlineText: _resolveCompactOverlineText(
                  item,
                  showConflictBadge,
                ),
                topRightBadgeText: _resolveCompactBadgeText(
                  item,
                  showConflictBadge,
                ),
                // 鏃ヨ琛細杩欒妭璇撅紙璇剧▼脳鐪熷疄鏃ユ湡锛夊凡璁惧崟鑺傝鎻愰啋鏃讹紝鍦ㄥ�?
                // 瑙掓爣鏃佷寒閾冮摏銆?
                hasReminder:
                    date != null &&
                    provider.classReminderFor(
                          item.course.id,
                          ClassReminderEntry.formatDate(date),
                        ) !=
                        null,
                showHomeworkIndicator: item.course.hasHomeworkInWeek(week),
                isHighlighted: item.isCurrentCourse,
                isHoliday: isDayHoliday,
                isSuspended: item.course.isSuspendedInWeek(week),
                isCompact: true,
                showName: settings.courseCardShowName,
                showTeacher: settings.courseCardShowTeacher,
                showLocation: settings.courseCardShowLocation,
                showTime: settings.courseCardShowTime,
                showTimeLabels: settings.courseCardShowTimeLabels,
                showWeeks: settings.courseCardShowWeeks,
                showDescription: settings.courseCardShowDescription,
                verticalAlign: settings.courseCardVerticalAlign,
                horizontalAlign: settings.courseCardHorizontalAlign,
                onTap: () =>
                    _showCourseActions(item.course, week, displayItem: item),
                compactTitleFontSize: settings.courseCardFontSize,
                compactSubtitleFontSize: (settings.courseCardFontSize - 1)
                    .clamp(7.0, 14.0),
                compactVerticalPadding: sectionHeight < 64 ? 4 : 6,
                compactOuterInset: cardInset,
                surfaceStyle: settings.courseCardSurfaceStyle,
                // 鐜荤拑妗ｈ嚜鍔ㄩ粦鐧藉垽瀹氱殑澹佺焊甯︿寒搴︼紱瀹炰綋鍗″拷鐣ャ�?
                wallpaperLuminance:
                    _wallpaperBodyLuminance ?? _wallpaperTopLuminance,
                // Dim conflict / non-current via fill alphas, keep frost
                // working.
                surfaceOpacity: item.opacity,
                titleColorHex: resolveCourseCardTitleColorHex(
                  courseTextColorHex: item.course.textColor,
                  settingsTitleColorLight: settings.courseCardTitleColorLight,
                  settingsTitleColorDark: settings.courseCardTitleColorDark,
                  isDark: Theme.of(context).brightness == Brightness.dark,
                ),
                detailColorHex: resolveCourseCardDetailColorHex(
                  courseTextColorHex: item.course.textColor,
                  settingsDetailColorLight: settings.courseCardDetailColorLight,
                  settingsDetailColorDark: settings.courseCardDetailColorDark,
                  settingsTitleColorLight: settings.courseCardTitleColorLight,
                  settingsTitleColorDark: settings.courseCardTitleColorDark,
                  isDark: Theme.of(context).brightness == Brightness.dark,
                ),
              ),
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, (1 - value) * 8),
                  child: child,
                );
              },
            ),
          ),
        );
      }
    }

    return Container(
      height: settings.sectionCount * sectionHeight,
      decoration: BoxDecoration(
        borderRadius: _groupedDayColumnBorderRadius(dayIndex, dayCount),
      ),
      child: Stack(
        clipBehavior: Clip.antiAlias,
        children: [...gridLines, ...courseCards],
      ),
    );
  }

  Future<void> _showWeekSelector() async {
    final provider = context.read<TimetableProvider>();
    final availableWeeks = provider.settings.availableWeeks;
    final currentSemesterWeek = _resolveCurrentSemesterWeek(provider.settings);
    final selectedWeek = await showWeekSelectorPickerSheet(
      context,
      availableWeeks: availableWeeks,
      visibleWeek: _visibleWeek,
      currentSemesterWeek: currentSemesterWeek,
    );

    if (!mounted || selectedWeek == null) {
      return;
    }

    await _jumpToWeek(provider, selectedWeek);
  }

  List<_DayCourseDisplayItem> _getDisplayItemsStartingAtSection(
    List<_DayCourseDisplayItem> items,
    int section,
  ) {
    return items.where((item) => item.course.startSection == section).toList();
  }

  List<_DayCourseDisplayItem> _buildHomeDayDisplayItems({
    required TimetableProvider provider,
    required TimetableSettings settings,
    required int week,
    required int dayOfWeek,
    required List<Course> myCourses,
    Set<String> currentCourseIds = const <String>{},
  }) {
    return _buildDayCourseDisplayItems(
      courses: myCourses,
      week: week,
      settings: settings,
      conflictMap: provider.courseConflictMapForWeek(week),
      currentCourseIds: currentCourseIds,
    );
  }

  List<_DayCourseDisplayItem> _buildDayCourseDisplayItems({
    required List<Course> courses,
    required int week,
    required TimetableSettings settings,
    required Map<String, List<Course>> conflictMap,
    Set<String> currentCourseIds = const <String>{},
  }) {
    return courses
        .where((course) {
          final isCurrentWeekCourse = course.isInWeek(week);
          if (isCurrentWeekCourse) {
            return true;
          }
          if (_hasCurrentWeekOverlap(courses, course, week)) {
            return false;
          }
          return _isPreferredNonCurrentCourse(courses, course, week);
        })
        .map((course) {
          final isCurrentWeekCourse = course.isInWeek(week);
          final isConflicting = conflictMap.containsKey(course.id);
          return _DayCourseDisplayItem(
            course: course,
            isCurrentWeekCourse: isCurrentWeekCourse,
            isConflicting: isConflicting,
            isCurrentCourse: currentCourseIds.contains(course.id),
            opacity: !isCurrentWeekCourse
                ? 0.62
                : (isConflicting ? settings.timetableConflictCourseOpacity : 1),
          );
        })
        .toList()
      ..sort((left, right) {
        final startCompare = left.course.startSection.compareTo(
          right.course.startSection,
        );
        if (startCompare != 0) {
          return startCompare;
        }
        final leftCurrent = left.isCurrentWeekCourse;
        final rightCurrent = right.isCurrentWeekCourse;
        if (leftCurrent != rightCurrent) {
          return leftCurrent ? 1 : -1;
        }
        final endCompare = left.course.endSection.compareTo(
          right.course.endSection,
        );
        if (endCompare != 0) {
          return endCompare;
        }
        return left.course.id.compareTo(right.course.id);
      });
  }

  String? _resolveDisplayCourseColor(
    _DayCourseDisplayItem item, {
    required TimetableSettings settings,
  }) {
    if (!item.isCurrentWeekCourse) {
      return '#94A3B8';
    }
    return settings.timetableUseUnifiedCardColor
        ? settings.timetableUnifiedCardColor
        : null;
  }

  String? _resolveCompactOverlineText(
    _DayCourseDisplayItem item,
    bool showConflictBadge,
  ) {
    final l10n = AppLocalizations.of(context)!;
    if (!item.isCurrentWeekCourse) {
      return l10n.nonCurrentWeekLabel;
    }
    if (item.isConflicting && showConflictBadge) {
      return l10n.conflictLabel;
    }
    return null;
  }

  String? _resolveCompactBadgeText(
    _DayCourseDisplayItem item,
    bool showConflictBadge,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final labels = <String>[];
    if (item.isCurrentCourse) {
      labels.add(l10n.ongoingCourseBadge);
    }
    if (item.isConflicting && showConflictBadge) {
      labels.add(l10n.conflictLabel);
    }
    if (labels.isEmpty) {
      return null;
    }
    return labels.join(' · ');
  }

  bool _hasCurrentWeekOverlap(List<Course> courses, Course target, int week) {
    return courses.any(
      (course) =>
          course.id != target.id &&
          course.isInWeek(week) &&
          !(course.endSection < target.startSection ||
              target.endSection < course.startSection),
    );
  }

  bool _isPreferredNonCurrentCourse(
    List<Course> courses,
    Course target,
    int week,
  ) {
    final overlappingNonCurrentCourses =
        courses
            .where(
              (course) =>
                  !course.isInWeek(week) &&
                  !(course.endSection < target.startSection ||
                      target.endSection < course.startSection),
            )
            .toList()
          ..sort((left, right) {
            final leftDistance = _distanceToNearestActiveWeek(left, week);
            final rightDistance = _distanceToNearestActiveWeek(right, week);
            if (leftDistance != rightDistance) {
              return leftDistance.compareTo(rightDistance);
            }
            final startCompare = left.startWeek.compareTo(right.startWeek);
            if (startCompare != 0) {
              return startCompare;
            }
            final endCompare = left.endWeek.compareTo(right.endWeek);
            if (endCompare != 0) {
              return endCompare;
            }
            return left.id.compareTo(right.id);
          });

    return overlappingNonCurrentCourses.isNotEmpty &&
        overlappingNonCurrentCourses.first.id == target.id;
  }

  int _distanceToNearestActiveWeek(Course course, int week) {
    for (var offset = 0; offset <= 60; offset++) {
      final previousWeek = week - offset;
      if (previousWeek >= 1 && course.isInWeek(previousWeek)) {
        return offset;
      }
      final nextWeek = week + offset;
      if (offset > 0 && course.isInWeek(nextWeek)) {
        return offset;
      }
    }
    return 999;
  }

  List<Course> _getCoursesForDay(
    List<Course> allCourses,
    int week,
    int dayOfWeek,
    TimetableSettings settings,
  ) {
    return allCourses.where((course) {
      if (course.dayOfWeek != dayOfWeek) {
        return false;
      }
      final isCurrentWeek = course.isInWeek(week);
      if (isCurrentWeek) {
        return true;
      }
      return settings.timetableShowNonCurrentWeekCourses;
    }).toList()..sort((a, b) {
      final startCompare = a.startSection.compareTo(b.startSection);
      if (startCompare != 0) return startCompare;
      final aCurrent = a.isInWeek(week);
      final bCurrent = b.isInWeek(week);
      if (aCurrent != bCurrent) {
        return aCurrent ? 1 : -1;
      }
      final endCompare = a.endSection.compareTo(b.endSection);
      if (endCompare != 0) return endCompare;
      return a.id.compareTo(b.id);
    });
  }

  int _clampWeek(int week, int maxWeek) {
    if (week < _minWeek) return _minWeek;
    if (week > maxWeek) return maxWeek;
    return week;
  }

  DateTime? _dateForWeekDay(
    TimetableSettings settings,
    int week,
    int dayOfWeek,
  ) {
    final semesterStart = settings.semesterStartDate;
    if (semesterStart == null) {
      return null;
    }

    final normalizedStart = DateTime(
      semesterStart.year,
      semesterStart.month,
      semesterStart.day,
    ).subtract(Duration(days: semesterStart.weekday - 1));

    return normalizedStart.add(Duration(days: (week - 1) * 7 + dayOfWeek - 1));
  }

  /// Calendar week of today relative to [TimetableSettings.semesterStartDate].
  ///
  /// Returns null when semester start is unset, before week 1, or **past the
  /// configured [TimetableSettings.semesterWeekCount]** (vacation / after term).
  /// Callers must not invent weeks outside that range ? never auto-expand the
  /// semester just to "return to today".
  int? _resolveCurrentSemesterWeek(TimetableSettings settings) {
    final semesterStart = settings.semesterStartDate;
    if (semesterStart == null) {
      return null;
    }

    final normalizedNow = DateTime.now();
    final normalizedToday = DateTime(
      normalizedNow.year,
      normalizedNow.month,
      normalizedNow.day,
    );
    final normalizedStart = DateTime(
      semesterStart.year,
      semesterStart.month,
      semesterStart.day,
    ).subtract(Duration(days: semesterStart.weekday - 1));
    final week = (normalizedToday.difference(normalizedStart).inDays ~/ 7) + 1;
    if (week < 1 || week > settings.semesterWeekCount) {
      return null;
    }
    return week;
  }

  /// Whether day-view may show / act on "back to today".
  ///
  /// False when today is outside the configured semester (e.g. already on
  /// vacation after the last teaching week) so we never jump to a wrong
  /// "same weekday last week" or expand semesterWeekCount.
  bool _canNavigateDayViewToToday(TimetableSettings settings) {
    final now = DateTime.now();
    final visibleDays = _visibleDayNumbers(settings);
    if (!visibleDays.contains(now.weekday)) {
      return false;
    }
    return _resolveCurrentSemesterWeek(settings) != null;
  }

  Future<void> _navigateDayViewToToday(TimetableProvider provider) async {
    final now = DateTime.now();
    final settings = provider.settings;
    final currentSemesterWeek = _resolveCurrentSemesterWeek(settings);
    if (!_canNavigateDayViewToToday(settings) || currentSemesterWeek == null) {
      return;
    }
    await _animateDayViewToWeek(
      provider,
      settings,
      currentSemesterWeek,
      now.weekday,
    );
  }

  bool _canReturnToCurrentWeek(TimetableSettings settings, int week) {
    final currentSemesterWeek = _resolveCurrentSemesterWeek(settings);
    return currentSemesterWeek != null && currentSemesterWeek != week;
  }

  bool _shouldShowFloatingBackToCurrentWeekButton(
    TimetableProvider provider,
    TimetableSettings settings,
    int visibleWeek,
  ) {
    if (_isDayView) {
      return false;
    }
    // 銆屽洖鏈懆銆嶅凡鏀舵暃涓烘诞閽敮涓€鍏ュ彛锛堟牱寮忔灇涓句粎瀛樺吋瀹癸紝璇诲彇�?
    // 涓€寰嬭縼绉讳负 floating锛夛紝姝ゅ涓嶅啀鏈夋帴绠″垎鏀€?
    if (settings.timetableBackToCurrentWeekButtonStyle !=
        BackToCurrentWeekButtonStyle.floating) {
      return false;
    }
    return _canReturnToCurrentWeek(settings, visibleWeek);
  }

  /// 鐜荤拑鍧炲舰鎬佷笅銆屽彲婊氬姩璇捐〃鍐呭銆嶇殑搴曢儴婊氬姩浣欓噺锛堟棩璇捐〃鍒楄〃銆佸懆�?
  /// 琛ㄧ旱鍚戞粴鍔級锛氳鍙ｄ繚鎸佸師鏍凤紝浣欓噺鍙姞闀垮彲婊氬姩鍖洪棿鈥斺€旈潤姝㈡椂鍐呭�?
  /// 鐓у父閾烘弧锛屼笅婊戝埌搴曞悗鏈€鍚庝竴椤瑰仠鍦ㄦ诞鍔ㄨ嵂涓镐笂鏂癸紝琚嵂涓搁伄浣忕殑璇剧▼
  /// 鍙互婊戝嚭鏉ョ湅銆傛寜鑽父鍥哄畾鍗犵�?+ 搴曢儴瀹夊叏鍖哄厹搴曘�?
  double _glassDockContentScrollInset(TimetableSettings settings) {
    if (settings.homeNavigationForm != HomeNavigationForm.glassDock) {
      return 0;
    }
    return _glassDockPillOccupancy + MediaQuery.viewPaddingOf(context).bottom;
  }

  /// 鐜荤拑鍧炲舰鎬侊細鎶婂簳閮ㄦ恫鎬佺幓鐠冭嵂涓稿鑸彔鍔犲埌椤甸潰涔嬩笂�?
  ///
  /// 缁忓吀褰㈡€佺洿鎺ヨ繑鍥炲師鍐呭锛岃涓轰笌涔嬪墠瀹屽叏涓€鑷淬€?
  Widget _wrapWithGlassDock(
    Widget child, {
    required bool glassDockForm,
    required TimetableSettings settings,
    required AppLocalizations l10n,
  }) {
    if (!glassDockForm) {
      return child;
    }
    // 娴挳涓庤嵂涓告樉寮忓悓婧愭潗璐細stock 瀹為獙鎬佷紶鍖呭畼鏂瑰簳鏍忛粯璁わ紝
    // 鑷畾涔夋€佽蛋 sheetSettingsFor / frosted 鍥為€€锛堜�?bar 鍐呴儴涓€鑷达級�?
    LiquidGlassSettings? dockBtnSettings;
    GlassQuality? dockBtnQuality;
    if (_kStockDockGlass) {
      dockBtnSettings = MikcbLiquidGlassTokens.stockBottomBarGlass;
      dockBtnQuality = null; // 鍖呭師鐗堣嚜閫傚簲璐ㄩ噺
    } else {
      final dockAppearance = FrostedAppearanceScope.of(context);
      // 銆屾恫鎬佺幓鐠冧綔鐢ㄨ寖�?�?鐜荤拑鍧炲鑸€嶅叧闂椂鍦嗛挳鍥為€€纾ㄧ爞鑽父鏉愯川�?
      final dockUseLiquidGlass =
          dockAppearance.glassMode == FrostedGlassMode.liquidGlass &&
          dockAppearance.liquidGlassDockEnabled &&
          !LiquidGlassDegradation.shouldDegrade(context);
      final dockIsDark = Theme.of(context).brightness == Brightness.dark;
      dockBtnSettings = dockUseLiquidGlass
          ? MikcbLiquidGlassTokens.sheetSettingsFor(
              dockIsDark ? Brightness.dark : Brightness.light,
              tuning: dockAppearance.liquidGlassTuning,
            )
          : LiquidGlassSettings(
              blur: dockAppearance.sheetBlurSigma,
              glassColor: HyperosBlurredHeader.sheetTintColor(
                context,
                withBlur: true,
              ),
            );
      dockBtnQuality = dockUseLiquidGlass
          ? GlassQuality.premium
          : GlassQuality.minimal;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            // 瀹樻�?iOS 26 褰㈡€侊細灞呬腑鑽�?+ 鍙充晶鐙珛鍦嗛挳锛屾暣缁勫眳涓€?
            // 鍦嗛挳鍥哄畾灞曞紑锛堝姞璇剧▼鍞竴涓诲姩鍏ュ彛锛屼笉鍐嶉殢椤垫敹璧凤級�?
            // 鏉愯川缁?dockBtnSettings 涓庤嵂涓告樉寮忓悓婧愩€?
            child: Builder(
              builder: (context) {
                final lum = _dockInlinePageId != null
                    ? null
                    : _wallpaperBodyLuminance; // 鍐呭祵椤佃〃鎬佸彧鐪嬩富棰?
                final isDarkTheme =
                    Theme.of(context).brightness == Brightness.dark;
                final ink = (lum != null ? lum < 0.45 : isDarkTheme)
                    ? Colors.white.withValues(alpha: 0.9)
                    : Colors.black.withValues(alpha: 0.75);
                return Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 272),
                        child: _buildGlassDockBar(
                          settings: settings,
                          l10n: l10n,
                        ),
                      ),
                      if (settings.glassDockShowAddButton) ...[
                        const SizedBox(width: 8),
                        _buildDockMergeSlot(
                          ink: ink,
                          l10n: l10n,
                          settings: dockBtnSettings,
                          quality: dockBtnQuality,
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// 鐜荤拑鍧炲簳閮ㄥ鑸細鍛ㄨ琛?/ 鏃ヨ琛?/ 璁剧疆銆?
  ///
  /// 浣跨�?liquid_glass_widgets ? [GlassTabBar.bottom]锛坕OS 26 瀹樻柟褰㈡€侊細
  /// 娴姩鑽父 + 鎷栨嫿鎸囩ず鍣紝鑷甫鐪熷疄鎶樺皠 shader 涓庤嚜閫傚簲璐ㄩ噺锛夈€?
  Widget _buildGlassDockBar({
    required TimetableSettings settings,
    required AppLocalizations l10n,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    // 搴曟爮鏂囧瓧鏋佹€у垎娲撅細璇捐〃鎬佽窡闅忓绾镐寒搴︼紙琛ㄩ潰 = 澹佺�?+ 鐧界幓鐠冿級�?
    // 鍐呭祵椤佃〃鎬佸簳鏍忔诞鍦ㄧ函鑹查〉闈笂锛屽彧鐪嬩富棰樷€斺€斿惁鍒欑櫧搴曡缃〉浼氭部�?
    // 鏆楀绾哥殑娴呰壊澧紝鐧藉瓧鐪嬩笉瑙侊紙鑷姩鍙嶈壊澶辨晥鐨勬牴鍥狅級�?
    final wallpaperLuminance = _dockInlinePageId != null
        ? null
        : _wallpaperBodyLuminance;
    final barUsesLightInk = wallpaperLuminance != null
        ? wallpaperLuminance < 0.45
        : isDark;
    final unselectedColor = barUsesLightInk
        ? Colors.white.withValues(alpha: 0.62)
        : Colors.black.withValues(alpha: 0.48);
    // 閫変腑鑹诧細鏆楄〃闈㈢敤鐧借壊锛涗寒琛ㄩ潰涓婃祬鑹蹭富棰樼�?primary 鏈韩鍋忔繁鍙敤锛?
    // 娣辫壊涓婚�?primary 鍋忔祬鍦ㄤ寒鐜荤拑涓婂姣斿害涓嶈冻 ? 鍒囨繁鑹插ⅷ�?
    final selectedColor = barUsesLightInk
        ? Colors.white
        : (isDark && wallpaperLuminance != null && wallpaperLuminance >= 0.45
              ? Colors.black.withValues(alpha: 0.80)
              : colorScheme.primary);
    // 搴曟爮鏉愯川锛圼_kStockDockGlass]=true 鏃朵笅闈㈠叏閮ㄨ蛋鍖呭師鐗堥粯璁わ紝姝ゆ�?
    // 浠呭湪瀹為獙鍏抽棴鏃跺弬涓庤绠楋級锛?
    // - 璺熼殢銆岄珮绾ф潗璐ㄣ€嶈缃紙涓庡脊绐?椤堕�?鍗＄墖缁熶竴锛夛細娑叉€佺幓鐠冪�?
    //   sheetSettingsFor锛堣窡闅忋€屾恫鎬佺幓鐠冭皟鏍°€嶏級+ premium 瀹屾暣鎶樺皠�?
    // - 鏍囧�?楂樻柉锛氶€€鍖栦负楂樻柉妯＄硦鑽父锛坆lur/tint 涓庡脊绐?frosted 涓€鑷达級銆?
    final appearance = FrostedAppearanceScope.of(context);
    // 銆屾恫鎬佺幓鐠冧綔鐢ㄨ寖�?�?鐜荤拑鍧炲鑸€嶅叧闂椂搴曟爮鍥為€€纾ㄧ爞鑽父銆?
    final useLiquidGlass =
        !_kStockDockGlass &&
        appearance.glassMode == FrostedGlassMode.liquidGlass &&
        appearance.liquidGlassDockEnabled &&
        !LiquidGlassDegradation.shouldDegrade(context);
    // 鍔ㄦ€佸叆鍙ｅ垪琛細搴曟爮鏈€�?5 妲斤紝鐢ㄦ埛鍦ㄣ€岄椤典笌瀵艰埅銆嶈嚜鐢辩紪鎺?
    // ? day'/'week' 瑙嗗浘鍔ㄤ綔 + 鐩綍浠绘剰鏉＄洰锛屽惈璁剧疆椤碉級�?
    final dockIds = resolveGlassDockActionIds(settings);
    return GlassTabBar.bottom(
      tabs: [for (final id in dockIds) _dockTabForId(id, l10n)],
      selectedIndex: _dockSelectedIndex(dockIds),
      onTabSelected: (index) => _handleDockTap(dockIds[index], settings),
      // 鐙珛鍦嗛挳鏀圭敱鍧炲眰銆屾按婊村悎骞舵Ы銆嶆覆鏌擄紙瑙?_wrapWithGlassDock锛夛�?
      // 鏁撮鎸夐挳婊戝叆鑽父骞惰鍦嗗舰瑁佸垏锛岃繍鍔ㄤ笌閬僵閮借创鍚堣嵂涓哥甯藉姬搴︺€?
      barHeight: 56,
      settings: _kStockDockGlass
          ? MikcbLiquidGlassTokens.stockBottomBarGlass
          : (useLiquidGlass
                ? MikcbLiquidGlassTokens.sheetSettingsFor(
                    isDark ? Brightness.dark : Brightness.light,
                    tuning: appearance.liquidGlassTuning,
                  )
                : LiquidGlassSettings(
                    blur: appearance.sheetBlurSigma,
                    glassColor: HyperosBlurredHeader.sheetTintColor(
                      context,
                      withBlur: true,
                    ),
                  )),
      indicatorSettings: _kStockDockGlass
          ? null
          : (useLiquidGlass ? MikcbLiquidGlassTokens.dragLensSettings : null),
      indicatorPinchStrength: useLiquidGlass ? 1.0 : 0.4,
      quality: _kStockDockGlass
          ? null
          : (useLiquidGlass ? GlassQuality.premium : GlassQuality.minimal),
      iconSize: 22,
      labelFontSize: 10,
      horizontalPadding: 6,
      verticalPadding: 6,
      selectedIconColor: selectedColor,
      unselectedIconColor: unselectedColor,
      selectedLabelColor: selectedColor,
      unselectedLabelColor: unselectedColor,
    );
  }

  /// 鐙珛鍦嗛挳锛氫笌鑽父鍚岃川鐨勬恫鎬佺幓鐠冨渾閽�?6 姝ｅ渾锛夈€?
  ///
  /// 鏉愯川涓庤嵂涓告樉寮忓悓婧愶紙_wrapWithGlassDock 浼犲�?stockBottomBarGlass锛夛�?
  /// useOwnLayer:true + isStationary:true 淇濊�?minimal 鍥為€€鏃朵粛淇濈暀
  /// BackdropFilter 妯＄硦鈥斺€斾笌鑽�?frosted 鍥為€€涓€鑷达紝娑堥櫎鈥滀袱绉嶆潗璐ㄢ€濇柇灞傘€?
  Widget _buildDockMergeSlot({
    required Color ink,
    required AppLocalizations l10n,
    required LiquidGlassSettings? settings,
    required GlassQuality? quality,
  }) {
    // 鏉愯川鏂眰鏍瑰洜锛氭鍓嶆澶勪互 useOwnLayer:false 娓叉煋锛圠iquidGlass.grouped锛夛�?
    // 浣嗗潪灞?Row 鏍戝娌℃湁浠讳�?LiquidGlassLayer/BluetoothGroup 绁栧厛锛?
    // Impeller ? grouped 鍦ㄦ棤灞傛椂鐩存帴鍥為€€涓哄浐鑹叉棤鐜荤拑鈥斺€旂湅璧锋潵鍍忎竴鍧?
    // 瀹炶壊鍦嗙墖锛屼笌鑽父鐨勭湡娑叉€佺幓鐠冨畬鍏ㄤ袱绉嶆潗璐ㄣ€傛敼�?useOwnLayer:true
    // + isStationary:true 鍚庯紝鎸夐挳涓庤嵂涓稿叡浜悓璐ㄧ殑 stockBottomBarGlass /
    // sheetSettings锛屼笖鍦?minimal/闄嶇骇璺緞涓や晶涓€鑷翠繚�?BackdropFilter�?
    // 鐙珛鍦嗛挳涓庤嵂涓哥甯藉悓鍦嗭紙56 姝ｅ渾锛夛紝澶栧�?SizedBox(56) ? Row 闂磋�?
    // 鐢辫皟鐢ㄤ晶 SizedBox(width:8) 鎵挎媴锛屾棤闇€ 68 楂樼殑鏂瑰舰杩囨浮妲藉強浜屾�?
    // ClipRRect 瑁佸垏锛堜細鎶婄幓鐠冭竟缂樺厜鍒囩‖锛夈€?
    return SizedBox(
      width: 56,
      height: 56,
      child: GlassButton(
        icon: _roundButtonIcon(context.read<TimetableProvider>().settings),
        onTap: () =>
            _handleRoundButtonTap(context.read<TimetableProvider>().settings),
        label: l10n.glassDockExtraButtonSemanticLabel,
        iconSize: 22,
        iconColor: ink,
        settings: settings,
        quality: quality,
        useOwnLayer: true,
        isStationary: true,
      ),
    );
  }

  /// 搴曟爮鎸夐挳 ? GlassTab 瑙嗚閰嶇疆锛氳鍥惧姩浣滅敤鍥哄畾鍥炬爣锛岄〉闈㈡潯鐩彇鐩綍�?
  GlassTab _dockTabForId(String id, AppLocalizations l10n) {
    return GlassTab(
      icon: Icon(glassDockActionIcon(id)),
      label: glassDockActionLabel(l10n, id),
    );
  }

  /// 鍦嗛挳鍥炬爣锛氱敤鎴疯嚜閫夌�?Miuix 鐭㈤噺鍥炬爣浼樺厛锛涙湭閫夋�?addCourse 鏄剧�?
  /// 鍔犲彿銆佸叾浣欏姛鑳芥樉绀虹洰褰曞浘鏍囥€?
  Widget _roundButtonIcon(TimetableSettings settings) {
    final customName = settings.glassDockButtonIconName;
    if (customName != null && customName.isNotEmpty) {
      final vector = MiuixIcons.extended.byName(customName);
      if (vector != null) {
        return MiuixIcon(vector: vector);
      }
    }
    final id = settings.glassDockButtonEntryId;
    if (id != 'addCourse' && id.isNotEmpty) {
      final entry = homeMenuEntryById(id);
      if (entry != null) {
        return Icon(entry.icon);
      }
    }
    return const Icon(Icons.add_rounded);
  }

  /// 鍦嗛挳鐐瑰嚮鍒嗗彂锛歛ddCourse/绌鸿蛋娣诲姞璇剧▼寮瑰眰锛涘唴宓屾敞鍐岄〉鍦ㄩ椤垫爤鍐?
  /// 鍒囨崲锛堝潪甯搁┗锛屽啀鐐瑰悓閽敹鍥烇級锛涘叾浣欑洰褰曟潯鐩櫘閫氭帹鍏ャ�?
  void _handleRoundButtonTap(TimetableSettings settings) {
    final id = settings.glassDockButtonEntryId;
    if (id == 'addCourse' || id.isEmpty) {
      unawaited(_showAddCourseSheet());
      return;
    }
    if (inlineDockPageFor(id) != null) {
      setState(() {
        _dockInlinePageId = (_dockInlinePageId == id) ? null : id;
      });
      // 鍦嗛挳淇濈暀 toggle 鏀跺洖锛圱ab 渚у啀鐐瑰綋鍓嶉〉宸叉敼鏃犲姩浣滐細鍦嗛挳鏃犻€変腑�?
      // 鎸囩ず锛屾寜閽紡銆屽啀鐐规挙閿€銆嶆垚绔嬶級锛涘紑/鏀?鎹㈤〉閮芥槸鐪熷疄鍒囨崲锛岀粰瑙﹁�?
      _maybeSelectionClick(settings);
      return;
    }
    final entry = homeMenuEntryById(id);
    if (entry != null) {
      _maybeSelectionClick(settings);
      unawaited(entry.open(context));
    }
  }

  /// 褰撳墠鎵€鍦ㄨ鍥撅紙鏃?鍛級鍦ㄦ帓鍒椾腑鐨勪笅鏍囷紱鎺掑垪鏈惈璇ヨ鍥炬椂楂樹寒 0�?
  /// 閬垮厤搴撴柇瑷€瓒婄晫锛堟鏃跺簳鏍忓叏鏄〉闈㈠叆鍙ｏ紝鏃犮€屽綋鍓嶉〉銆嶈涔夛級銆?
  int _dockSelectedIndex(List<String> ids) {
    final inline = _dockInlinePageId;
    if (inline != null && ids.contains(inline)) {
      return ids.indexOf(inline);
    }
    final current = _isDayView ? kGlassDockActionDay : kGlassDockActionWeek;
    final index = ids.indexOf(current);
    return index >= 0 ? index : 0;
  }

  /// 搴曟爮鐐瑰嚮鍒嗗彂锛?day'/'week' 闂幇鐩村垏锛坅nimate:false锛屼笉鎾敋鐐瑰睍寮�?
  /// 鏀惰捣杞満锛屽榻愩€岀偣搴曟爮鐩存帴灏变綅銆嶇殑鎵嬫劅锛屾棩鏈熸爮璺緞涓嶅彈褰卞搷锛夊苟鏀跺洖
  /// 鍐呭祵椤碉紱椤甸潰鏉＄洰璧板唴宓屽涓伙紙鍧炲父椹伙級锛屾湭鐧昏鐨勬祦绋嬮〉鎵嶆帹鍏ユ柊璺敱�?
  ///
  /// 瑙﹁鍙ｅ緞锛堟仮澶?3e41ac20锛夛細鐪熷疄鍒囨崲锛堝垏瑙嗗�?寮€�?鎹㈤�?鏀堕�?鎺ㄨ矾鐢憋級
  /// 缁欎竴娆¤Е瑙夛紝閲嶅鐐瑰嚮褰撳墠 Tab 闈欓煶鈥斺€旀�?鍛ㄩ潬鏃㈡湁瀹堝崼锛涘唴宓岄〉鍐嶇偣
  /// 褰撳墠椤典笉鍐嶇炕杞敹鍥烇紙涓?�?�?鍚屽彛寰勶紝鏀堕〉璧板垏瑙嗗浘鎴栧渾閽啀鐐癸級銆?
  void _handleDockTap(String id, TimetableSettings settings) {
    final leavingInlinePage =
        _dockInlinePageId != null &&
        (id == kGlassDockActionDay || id == kGlassDockActionWeek);
    if (leavingInlinePage) {
      // 浠庡唴宓岄〉鐐硅鍥惧垏鎹細鍏堟敹椤靛啀鍒囪鍥撅紝閬垮厤涓ゅ眰鐘舵€佸彔鍔犮€?
      setState(() => _dockInlinePageId = null);
    }
    switch (id) {
      case kGlassDockActionDay:
        if (_isDayView) {
          // 閲嶅鐐规棩 Tab 鏃犲姩浣滐紱浠庡唴宓岄〉鏀跺洖钀藉洖鏃ヨ琛ㄦ槸涓€娆＄湡瀹炲垏鎹?
          // 锛堣惤鍥炲紓瑙嗗浘鐨勮矾�?_toggleDayView 鍐呴儴宸查渿锛屾澶勫彧琛ュ悓瑙嗗浘锛夈�?
          if (leavingInlinePage) {
            _maybeSelectionClick(settings);
          }
          return;
        }
        unawaited(
          _toggleDayView(
            week: _visibleWeek,
            dayOfWeek: _resolveStoredDayOfWeek(
              settings,
              settings.timetableLastViewedDayOfWeek,
            ),
            settings: settings,
            animate: false,
          ),
        );
      case kGlassDockActionWeek:
        if (!_isDayView) {
          _persistViewState(
            context.read<TimetableProvider>(),
            mode: TimetableHomeViewMode.week,
          );
          // 閲嶅鐐瑰懆 Tab 鏃犲姩浣滐紱浠庡唴宓岄〉鏀跺洖钀藉洖鍛ㄨ琛ㄦ槸涓€娆＄湡瀹炲垏鎹€?
          if (leavingInlinePage) {
            _maybeSelectionClick(settings);
          }
          return;
        }
        // 闂幇鏀惰捣锛歘closeDayView 鍐呴儴瀹屾垚闇囧姩銆佺姸鎬佹竻鐞嗕笌鎸佷箙鍖栥�?
        unawaited(_closeDayView(settings, animate: false));
      default:
        // 鍐呭祵浼樺厛锛氭敞鍐岃繃鐨勯〉闈㈠湪棣栭〉鏍堝唴鍒囨崲锛岀幓鐠冨潪淇濇寔鎮诞锛涙湭鐧昏
        // 鐨勮蛋鏅€氭帹鍏ャ€傚啀鐐瑰綋鍓嶅唴宓岄〉涓?�?�?Tab 鍚屽彛寰勬棤鍔ㄤ綔锛屽叾浣欏�?
        // 鏄湡瀹炲垏鎹紙寮€�?鎹㈤�?鎺ㄨ矾鐢憋級锛岀粺涓€鍦ㄦ缁欒Е瑙夊弽棣堛€?
        if (inlineDockPageFor(id) != null) {
          if (_dockInlinePageId == id) {
            return;
          }
          setState(() => _dockInlinePageId = id);
          _maybeSelectionClick(settings);
          return;
        }
        final entry = homeMenuEntryById(id);
        if (entry != null) {
          _maybeSelectionClick(settings);
          unawaited(entry.open(context));
        }
    }
  }

  Widget _buildFloatingBackToCurrentWeekButton(TimetableProvider provider) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final foruiColors = context.theme.colors;
    final buttonOpacity =
        provider.settings.timetableFloatingBackToCurrentWeekButtonOpacity;
    final borderRadius = BorderRadius.circular(18);
    // Do not wrap [HyperosFrostedSurface] in [Opacity]: Flutter's
    // [BackdropFilter] cannot sample content behind an opacity layer, so the
    // button would only show a solid tint and ignore the frosted-blur switch.
    final useBlur = HyperosBlurredHeader.backdropBlurEnabled(context);
    final baseTint = HyperosBlurredHeader.homePageRegionTintColor(
      context,
      withBlur: useBlur,
    );
    final frostedTint = baseTint.withValues(
      alpha: (baseTint.a * buttonOpacity).clamp(0.0, 1.0),
    );
    final contentOpacity = buttonOpacity.clamp(0.0, 1.0);
    // 娑叉€佺幓鐠冩ā寮忎笅鐢ㄧ湡鎶樺皠鍦嗚鐜荤拑锛岃€屼笉鏄珮鏂ā绯婄（鐮傗€斺€?
    // 涓庡簳鏍?鐙珛鎸夐挳鍚屼竴濂楁潗璐ㄨ瑷€銆?
    final dockAppearance = FrostedAppearanceScope.of(context);
    // 銆屾恫鎬佺幓鐠冧綔鐢ㄨ寖�?�?鐜荤拑鍧炲鑸€嶅叧闂椂鍥炴诞鎸夐挳鍥炵（鐮傚渾鐗囥�?
    final useLiquidGlassMaterial =
        dockAppearance.glassMode == FrostedGlassMode.liquidGlass &&
        dockAppearance.liquidGlassDockEnabled &&
        !LiquidGlassDegradation.shouldDegrade(context);

    final glassDockForm =
        provider.settings.homeNavigationForm == HomeNavigationForm.glassDock;
    // 鎸夐挳闇€濮嬬粓娴湪鐜荤拑鍧炶嵂涓镐箣涓婏細鐜荤拑鍧炲舰鎬佷笅缁熶竴鍙栥€屽唴瀹归伩璁╅噺 +
    // 24 瑙嗚杈硅窛銆嶄笌銆岃嵂涓稿崰鐢?+ 12 瑙嗚闂撮殭銆嶇殑杈冨ぇ鍊尖€斺€斿懆瑙嗗浘鐢卞灞?
    // 甯冨眬閬胯鍨珮銆佹棩/璁剧疆椤佃鍙ｅ叏灞忔椂鎸夐挳鑷閬胯锛屼袱绉嶅疄鐜颁笅閮戒笉�?
    // 鑽父閬尅锛涚粡鍏稿舰鎬佷繚鎸佸師 24px 杈硅窛銆?
    final double dockBackButtonBottom;
    if (!glassDockForm) {
      dockBackButtonBottom = 24;
    } else {
      dockBackButtonBottom =
          math.max(24, _glassDockPillOccupancy + 12) +
          MediaQuery.viewPaddingOf(context).bottom;
    }
    return SafeArea(
      minimum: EdgeInsets.only(right: 20, bottom: dockBackButtonBottom),
      child: Align(
        alignment: Alignment.bottomRight,
        child: Tooltip(
          message: l10n.backToCurrentWeekAction,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              border: Border.all(
                color: foruiColors.border.withValues(
                  alpha: foruiColors.border.a * contentOpacity,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha:
                        (theme.brightness == Brightness.dark ? 0.12 : 0.06) *
                        contentOpacity,
                  ),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: useLiquidGlassMaterial
                ? GlassButton.custom(
                    onTap: () => _jumpToCurrentWeek(provider),
                    shape: const LiquidRoundedRectangle(borderRadius: 18),
                    settings: MikcbLiquidGlassTokens.sheetSettingsFor(
                      theme.brightness,
                      tuning: dockAppearance.liquidGlassTuning,
                    ),
                    quality: GlassQuality.premium,
                    // 宕╂簝淇锛氭閽寕鍦ㄦ棤浠讳綍 LiquidGlassLayer 绁栧厛鐨勮８ Stack 涓婏�?
                    // premium + 榛樿�?useOwnLayer:false 浼氳Е�?LiquidGlassBlendGroup
                    // ? renderLink != null 鏂█銆傛樉寮忚嚜甯﹀眰锛沬sStationary ?
                    // _buildDockMergeSlot / 鍖呭�?BottomBarExtraBtn 瀵归綈锛?
                    // 淇濊瘉寮曟搸闄嶇骇璺緞浠嶄繚鐣?BackdropFilter 妯＄硦銆?
                    useOwnLayer: true,
                    isStationary: true,
                    child: Opacity(
                      opacity: contentOpacity,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.my_location_rounded,
                              size: 15,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              l10n.backToCurrentWeekAction,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: colorScheme.onSurface,
                                height: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : ClipRRect(
                    borderRadius: borderRadius,
                    child: HyperosFrostedSurface(
                      borderRadius: borderRadius,
                      tint: frostedTint,
                      child: Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          key: const ValueKey('back-to-current-week-button'),
                          onTap: () => _jumpToCurrentWeek(provider),
                          borderRadius: borderRadius,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.my_location_rounded,
                                  size: 15,
                                  color: colorScheme.primary.withValues(
                                    alpha:
                                        colorScheme.primary.a * contentOpacity,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  l10n.backToCurrentWeekAction,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: colorScheme.onSurface.withValues(
                                      alpha:
                                          colorScheme.onSurface.a *
                                          contentOpacity,
                                    ),
                                    height: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  bool _isSameDate(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  Future<void> _jumpToCurrentWeek(TimetableProvider provider) async {
    if (provider.settings.semesterStartDate == null) {
      if (!mounted) return;
      showAppToast(
        context,
        message: AppLocalizations.of(context)!.pleaseSetSemesterStartDate,
        kind: AppToastKind.warning,
      );
      return;
    }

    final currentSemesterWeek = _resolveCurrentSemesterWeek(provider.settings);
    if (currentSemesterWeek == null) {
      return;
    }

    await _jumpToWeek(provider, currentSemesterWeek);
    _maybeSelectionClick(provider.settings);
  }

  Future<void> _jumpToWeek(
    TimetableProvider provider,
    int week, {
    bool animatePage = true,
  }) async {
    if (_isSyncingWeekPage) {
      return;
    }

    final targetWeek = _clampWeek(week, provider.settings.semesterWeekCount);
    if (targetWeek == _visibleWeek) {
      return;
    }

    if (!_weekPageController.hasClients) {
      _pendingSettledWeek = targetWeek;
      _pendingCommittedWeek = targetWeek;
      _applyVisibleWeek(
        targetWeek,
        rebuild: _isDayView || provider.settings.semesterStartDate == null,
        syncDayView: _isDayView,
      );
      await _commitPendingWeek(provider);
      return;
    }

    _isSyncingWeekPage = true;
    try {
      // Programmatic jump: the swipe deck is gesture-only, so fall back to
      // the pager's own slide instead of a stale deck takeover.
      _weekPagerDragStartPage = null;
      _weekPagerPendingDragStartPage = null;
      if (animatePage) {
        await _weekPageController.animateToPage(
          targetWeek - 1,
          duration: (targetWeek - _visibleWeek).abs() == 1
              ? _weekSlideDuration
              : const Duration(milliseconds: 360),
          curve: Curves.easeInOutCubicEmphasized,
        );
      } else {
        // Day-view boundary swipes already provide the horizontal motion.
        _weekPageController.jumpToPage(targetWeek - 1);
      }
      _pendingSettledWeek = targetWeek;
    } finally {
      _isSyncingWeekPage = false;
    }

    _finalizeWeekPageSettled(
      provider,
      fallbackWeek: targetWeek,
      syncDayView: _isDayView,
    );
  }

  void _handleWeekPageChanged(int page, int maxWeek) {
    _lastObservedWeekPage = page;
    _pendingSettledWeek = _clampWeek(page + 1, maxWeek);
    _visibleWeekListenable.value = _pendingSettledWeek!;
  }

  /// One shared backdrop group for gaussian cards on this week page.
  Widget _wrapCourseGridSurfaceHost({
    required TimetableSettings settings,
    required Widget child,
  }) {
    return CourseGridSurfaceHost(settings: settings, child: child);
  }

  /// ? provider 鐨勫綋鍓嶅懆娆″悓姝ュ埌鍛ㄨ�?pager�?
  ///
  /// 璇ユ柟娉曞湪 build 涓皟鐢紙澶栭儴鍛ㄦ鏉ユ簮鍙兘鍦ㄤ竴甯у唴澶氭鍒拌揪锛夛紝鍓綔鐢?
  /// 閫氳�?post-frame 鍥炶皟鏀舵暃涓斿甫涓夐噸闃查噸鍏ワ紙[_pendingSyncedWeek]�?
  /// [_isSyncingWeekPage]銆乕_hasPendingLocalWeekTransition]锛夛細鍚屼竴鐩爣椤?
  /// 涓嶄細閲嶅 jump锛屾湰鍦版墜鍔胯繘琛屼腑缁濅笉鎶㈤〉銆傝繖鏄€宐uild 涓甫鍓綔鐢ㄣ€嶇�?
  /// 鍙楁帶渚嬪鈥斺€旇縼鍒?didChangeDependencies 闇€瑕佸尯鍒嗗懆娆℃潵婧愬苟鏀瑰姩
  /// 鍚屾鏃跺簭锛屽綋鍓嶅疄鐜扮殑琛屼负涓庡畧鍗凡鍦ㄦ祴璇曚腑閿氬畾锛屼繚鎸佺幇鐘躲€?
  void _syncWeekPageWithProvider(int week, TimetableSettings settings) {
    final maxWeek = settings.semesterWeekCount;
    if (_isSyncingWeekPage || _hasPendingLocalWeekTransition) {
      return;
    }

    final targetWeek = _clampWeek(week, maxWeek);
    final targetPage = targetWeek - 1;
    final shouldSyncDayView =
        _isDayView &&
        !_isDaySwipeAnimating &&
        _selectedWeekForDayView != targetWeek;
    final needsVisualSync =
        _visibleWeek != targetWeek ||
        shouldSyncDayView ||
        _lastObservedWeekPage != targetPage;
    if (!needsVisualSync) {
      return;
    }
    if (_pendingSyncedWeek == targetPage) {
      return;
    }
    _pendingSyncedWeek = targetPage;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingSyncedWeek = null;
      if (!mounted || _isSyncingWeekPage || _hasPendingLocalWeekTransition) {
        return;
      }

      final syncDayView =
          _isDayView &&
          !_isDaySwipeAnimating &&
          _selectedWeekForDayView != targetPage + 1;
      _pendingSettledWeek = targetPage + 1;
      _applyVisibleWeek(
        targetPage + 1,
        rebuild: syncDayView || settings.semesterStartDate == null,
        syncDayView: syncDayView,
      );

      if (syncDayView && mounted) {
        setState(() {
          _dayViewTransitionSourceWeek = null;
          _dayViewTransitionSourceDayOfWeek = null;
        });
      }

      if (!_weekPageController.hasClients) {
        return;
      }
      final currentPage =
          _lastObservedWeekPage ?? _weekPageController.initialPage;
      if (currentPage == targetPage) {
        return;
      }

      // Programmatic jump: the swipe deck is gesture-only, so fall back to
      // the pager's own slide instead of a stale deck takeover.
      _weekDeckSettleRebuildArmed = false;
      _weekDeckSettleRebuildScheduled = false;
      _weekPagerDragStartPage = null;
      _weekPagerPendingDragStartPage = null;
      _lastObservedWeekPage = targetPage;
      _weekPageController.jumpToPage(targetPage);
    });
  }

  int _resolveSettledWeek(TimetableProvider provider, {int? fallbackWeek}) {
    final maxWeek = provider.settings.semesterWeekCount;
    if (_weekPageController.hasClients) {
      final page = _weekPageController.page;
      if (page != null) {
        return _clampWeek(page.round() + 1, maxWeek);
      }
    }
    if (_lastObservedWeekPage != null) {
      return _clampWeek(_lastObservedWeekPage! + 1, maxWeek);
    }
    return _clampWeek(
      fallbackWeek ?? _pendingSettledWeek ?? _visibleWeek,
      maxWeek,
    );
  }

  void _finalizeWeekPageSettled(
    TimetableProvider provider, {
    int? fallbackWeek,
    bool syncDayView = false,
  }) {
    final targetWeek = _resolveSettledWeek(
      provider,
      fallbackWeek: fallbackWeek,
    );
    _pendingSettledWeek = targetWeek;
    _pendingCommittedWeek = targetWeek;
    _applyVisibleWeek(
      targetWeek,
      rebuild: syncDayView || provider.settings.semesterStartDate == null,
      syncDayView: syncDayView,
    );
    unawaited(_commitPendingWeek(provider));
  }

  Future<void> _commitPendingWeek(TimetableProvider provider) async {
    if (_isCommittingWeek) {
      return;
    }
    _isCommittingWeek = true;
    try {
      while (mounted) {
        final targetWeek = _pendingCommittedWeek;
        if (targetWeek == null) {
          return;
        }
        if (targetWeek == provider.currentWeek) {
          _pendingCommittedWeek = null;
          continue;
        }
        _pendingCommittedWeek = null;
        _maybeSelectionClick(provider.settings);
        await provider.setCurrentWeek(targetWeek, notify: false);
      }
    } finally {
      _isCommittingWeek = false;
    }
  }

  Future<void> _navigateToAddCourse(BuildContext context) async {
    await _showAddCourseSheet();
  }

  void _editCourse(Course course) {
    final provider = context.read<TimetableProvider>();
    final group = provider.courseGroupForCourse(course);
    Navigator.push(
      context,
      HyperosPageRoute(
        settings: const RouteSettings(name: '/course/edit'),
        builder: (context) =>
            AddCourseScreen(courseGroup: group, initialCourse: course),
      ),
    );
  }

  DateTime _resolveAddScheduleInitialDate(TimetableProvider provider) {
    if (_isDayView &&
        _selectedWeekForDayView != null &&
        _selectedDayOfWeek != null) {
      return _resolveDisplayDateForWeekDay(
        provider: provider,
        settings: provider.settings,
        week: _selectedWeekForDayView!,
        dayOfWeek: _selectedDayOfWeek!,
      );
    }
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _showAddCourseSheet() async {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<TimetableProvider>();
    final initialDayOfWeek = _isDayView && _selectedDayOfWeek != null
        ? _selectedDayOfWeek!
        : DateTime.now().weekday;
    await showHomeHyperosSheet<void>(
      context: context,
      builder: (sheetContext) {
        final itemWidth =
            ((MediaQuery.sizeOf(sheetContext).width - 32 - 24) / 3).clamp(
              96.0,
              120.0,
            );

        return HyperosSheet(
          title: l10n.addCourseSheetTitle,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: itemWidth,
                child: _HomeActionPageButton(
                  sheetRoute: ModalRoute.of(sheetContext),
                  icon: Icons.view_week_rounded,
                  title: l10n.addCourseTitle,
                  pageBuilder: (_) => AddCourseScreen(
                    initialWeek: _visibleWeek,
                    initialDayOfWeek: initialDayOfWeek,
                  ),
                ),
              ),
              SizedBox(
                width: itemWidth,
                child: _HomeActionPageButton(
                  sheetRoute: ModalRoute.of(sheetContext),
                  icon: Icons.event_note_rounded,
                  title: l10n.addScheduleAction,
                  pageBuilder: (_) => AddScheduleItemScreen(
                    initialDate: _resolveAddScheduleInitialDate(provider),
                  ),
                ),
              ),
              SizedBox(
                width: itemWidth,
                child: _HomeActionPageButton(
                  sheetRoute: ModalRoute.of(sheetContext),
                  icon: Icons.school_outlined,
                  title: l10n.addExam,
                  pageBuilder: (_) => const AddExamScreen(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showCourseActions(
    Course course,
    int week, {
    _DayCourseDisplayItem? displayItem,
  }) async {
    final previewItems = _buildCourseActionPreviewItems(
      course,
      week,
      displayItem: displayItem,
    );
    final result = await showCourseActionSheet(
      context,
      previewItems: previewItems,
      week: week,
      onEdit: _editCourse,
      // 鍗曡妭璇炬彁閱掍緷璧栧師鐢熺簿纭椆閽熻皟搴︼紝鍏朵粬骞冲彴涓嶆樉绀哄叆鍙ｃ�?
      onSetAlarm: (!kIsWeb && Platform.isAndroid)
          ? (target) => _openClassReminderSheet(target, week)
          : null,
    );

    if (!mounted) {
      return;
    }

    if (result != null) {
      await _handleCourseActionResult(result, week);
    }
  }

  Future<void> _handleCourseActionResult(
    CourseActionSheetResult result,
    int week,
  ) async {
    switch (result) {
      case CourseActionSheetResult reschedule
          when reschedule.rescheduleDraft != null:
        await _applyRescheduleDraft(
          reschedule.course,
          sourceWeek: week,
          draft: reschedule.rescheduleDraft!,
        );
      case CourseActionSheetResult deleteResult
          when deleteResult.deleteMode != null:
        switch (deleteResult.deleteMode!) {
          case CourseDeleteMode.course:
            await _confirmDeleteCourse(deleteResult.course);
          case CourseDeleteMode.occurrence:
            await _confirmDeleteOccurrence(deleteResult.course, week);
        }
      case CourseActionSheetResult suspendResult
          when suspendResult.suspendMode != null:
        final provider = context.read<TimetableProvider>();
        final course = suspendResult.course;
        switch (suspendResult.suspendMode!) {
          case CourseSuspendMode.thisWeek:
            await provider.toggleCourseSuspension(course.id, week);
          case CourseSuspendMode.allWeeks:
            final hasAnySuspended = course.suspendedWeeks?.isNotEmpty ?? false;
            if (hasAnySuspended) {
              await provider.unsuspendAllWeeks(course.id);
            } else {
              await provider.suspendAllWeeks(course.id);
            }
        }
      default:
        break;
    }
  }

  /// 鍗曡妭璇炬彁閱掞細鎵撳紑鎻愰啋璁剧疆寮瑰眰锛堝揩鎹锋彁鍓嶉噺 / 鑷畾涔夋椂�?/ 鍙栨秷锛夈€?
  Future<void> _openClassReminderSheet(Course course, int week) {
    return showClassReminderSheet(context, course: course, week: week);
  }

  List<CourseActionPreviewItem> _buildCourseActionPreviewItems(
    Course course,
    int week, {
    _DayCourseDisplayItem? displayItem,
  }) {
    final items = <CourseActionPreviewItem>[
      CourseActionPreviewItem(course: course),
    ];
    for (final conflict in _conflictsForCourseInWeek(course, week)) {
      if (items.any((item) => item.course.id == conflict.id)) {
        continue;
      }
      items.add(CourseActionPreviewItem(course: conflict, isConflict: true));
    }
    return items;
  }

  List<Course> _conflictsForCourseInWeek(Course course, int week) {
    final conflictMap = context
        .read<TimetableProvider>()
        .courseConflictMapForWeek(week);
    final seenIds = <String>{};
    final conflicts = <Course>[];
    for (final conflict in conflictMap[course.id] ?? const <Course>[]) {
      if (conflict.id == course.id || !seenIds.add(conflict.id)) {
        continue;
      }
      conflicts.add(conflict);
    }
    conflicts.sort((left, right) {
      final dayCompare = left.dayOfWeek.compareTo(right.dayOfWeek);
      if (dayCompare != 0) {
        return dayCompare;
      }
      final startCompare = left.startSection.compareTo(right.startSection);
      if (startCompare != 0) {
        return startCompare;
      }
      return left.id.compareTo(right.id);
    });
    return conflicts;
  }

  Future<void> _confirmDeleteCourse(Course course) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDeleteCourseConfirmDialog(
      context,
      title: l10n.deleteScheduleTitle,
      message: l10n.deleteScheduleConfirmMessage(
        course.name,
        l10n.courseWeekdaySectionSummary(
          course.weekDescription(l10n),
          _weekdayLabel(context, course.dayOfWeek),
          course.startSection,
          course.endSection,
        ),
      ),
    );

    if (!confirmed || !mounted) {
      return;
    }

    await context.read<TimetableProvider>().deleteCourse(course.id);
    if (!mounted) {
      return;
    }
    showAppToast(
      context,
      message: AppLocalizations.of(context)!.deletedCourseMessage(course.name),
      kind: AppToastKind.success,
    );
  }

  Future<void> _confirmDeleteOccurrence(Course course, int sourceWeek) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDeleteOccurrenceConfirmDialog(
      context,
      title: l10n.deleteLessonTitle,
      message: l10n.deleteOccurrenceConfirmMessage(
        course.name,
        sourceWeek,
        l10n.weekdaySectionTimeSummary(
          _weekdayLabel(context, course.dayOfWeek),
          course.startSection,
          course.endSection,
          course.startTime,
          course.endTime,
        ),
      ),
    );

    if (!confirmed || !mounted) {
      return;
    }

    try {
      final changed = await context
          .read<TimetableProvider>()
          .deleteCourseOccurrence(courseId: course.id, sourceWeek: sourceWeek);
      if (!mounted) {
        return;
      }
      showAppToast(
        context,
        message: changed
            ? l10n.occurrenceDeletedMessage(sourceWeek)
            : l10n.noChangesDetected,
        kind: changed ? AppToastKind.success : AppToastKind.info,
      );
    } on ArgumentError catch (error) {
      if (!mounted) {
        return;
      }
      showAppToast(
        context,
        message: error.message != null
            ? localizeServiceMessage(l10n, error.message!.toString())
            : AppLocalizations.of(context)!.deleteFailed,
        kind: AppToastKind.error,
      );
    }
  }

  Future<void> _applyRescheduleDraft(
    Course course, {
    required int sourceWeek,
    required CourseRescheduleDraft draft,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<TimetableProvider>();

    try {
      final changed = await provider.rescheduleCourseOccurrence(
        courseId: course.id,
        sourceWeek: sourceWeek,
        targetWeek: draft.targetWeek,
        targetDayOfWeek: draft.targetDayOfWeek,
        targetStartSection: draft.targetStartSection,
        targetEndSection: draft.targetEndSection,
        targetLocation: draft.targetLocation,
      );
      if (!mounted) {
        return;
      }
      showAppToast(
        context,
        message: changed
            ? l10n.rescheduledToMessage(
                draft.targetWeek,
                _weekdayLabel(context, draft.targetDayOfWeek),
                draft.targetStartSection,
                draft.targetEndSection,
              )
            : l10n.noChangesDetected,
        kind: changed ? AppToastKind.success : AppToastKind.info,
      );
    } on ArgumentError catch (error) {
      if (!mounted) {
        return;
      }
      showAppToast(
        context,
        message: error.message != null
            ? localizeServiceMessage(l10n, error.message!.toString())
            : AppLocalizations.of(context)!.rescheduleFailed,
        kind: AppToastKind.error,
      );
    }
  }

  Widget _buildSectionTimeCell(
    int sectionNumber,
    SectionTime section,
    TimetableSettings settings,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasBackdrop = hasHomePageBackdropImage(settings);
    // Same wallpaper auto-contrast as weekday ink; user-custom time-axis hex
    // is never replaced. The time column spans the body band (not the
    // status/title strip), so judge from the card-region sample.
    final timeAxisColor = homePageOverWallpaperInk(
      configuredHex: isDark
          ? settings.timeAxisFontColorDark
          : settings.timeAxisFontColorLight,
      defaultHex: isDark
          ? TimetableSettings.defaultTimeAxisFontColorDark
          : TimetableSettings.defaultTimeAxisFontColorLight,
      themeFallback: isDark ? Colors.white : Colors.grey.shade800,
      hasBackdrop: hasBackdrop,
      wallpaperLuminance: _wallpaperBodyLuminance ?? _wallpaperTopLuminance,
      minContrastRatio: 4.5,
      maximizeContrast: true,
      keepDefaultColorOverWallpaper: true,
    );
    final timeAxisMutedColor = homePageOverWallpaperMutedInk(timeAxisColor);
    final compactTextStyle = TextStyle(
      fontSize: (settings.compactFontSize - 2).clamp(6.0, 10.0),
      color: timeAxisMutedColor,
      height: 1.05,
    );

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$sectionNumber',
          style: TextStyle(
            fontSize: settings.compactFontSize.clamp(8.0, 11.0),
            fontWeight: FontWeight.bold,
            color: timeAxisColor,
          ),
        ),
        if (settings.timetableSectionTimeDisplayMode !=
            SectionTimeDisplayMode.hidden)
          Text(section.startTime, style: compactTextStyle),
        if (settings.timetableSectionTimeDisplayMode ==
            SectionTimeDisplayMode.startAndEnd)
          Text(section.endTime, style: compactTextStyle),
      ],
    );
  }

  List<int> _visibleDayNumbers(TimetableSettings settings) {
    return settings.timetableHideWeekends
        ? const [1, 2, 3, 4, 5]
        : const [1, 2, 3, 4, 5, 6, 7];
  }

  double _resolveTimeColumnWidth(TimetableSettings settings) {
    return switch (settings.timetableTimeColumnWidthMode) {
      TimetableTimeColumnWidthMode.narrow => 34,
      TimetableTimeColumnWidthMode.wide => 40,
    };
  }

  double _resolveCourseCardInset(TimetableSettings settings) {
    return settings.timetableCourseCardGap.clamp(0.0, 3.0);
  }

  void _maybeSelectionClick(TimetableSettings settings) {
    if (!settings.enableHaptics) {
      return;
    }
    HapticFeedback.selectionClick();
  }

  Future<void> _showProfileQuickSwitchSheet() async {
    final provider = context.read<TimetableProvider>();
    final selected = await showProfileQuickSwitchSheet(
      context,
      // 鎯呬荆璇捐〃寮€鍏冲紑鍚�?TA 璇捐〃鍚屼负鍙垏鎹㈣琛紙鎯呬荆鏍囬�?鍗＄墖鍙冲崐
      // 鐩磋揪锛夛紝涓€骞跺垪鍑猴紱寮€鍏冲叧闂椂鍥炲埌鍘熸牱锛氬彧鍒楁垜鑷繁鐨勮琛ㄣ�?
      profiles: provider.profiles
          .where(
            (profile) =>
                provider.settings.coupleTimetableOverlayEnabled ||
                !profile.isPartnerImported,
          )
          .toList(growable: false),
      activeProfileId: provider.activeProfileId,
      onManageTimetables: (buttonContext) {
        _openPopupActionPage(
          buttonContext,
          pageBuilder: (_) => const TimetableProfilesScreen(),
          sheetRoute: ModalRoute.of(buttonContext),
        );
      },
      onShowHistory: _showCoupleTimetableHistory,
    );

    if (!mounted || selected == null) {
      return;
    }
    if (selected == provider.activeProfileId) {
      return;
    }
    await provider.switchProfile(selected);
    if (!mounted) {
      return;
    }
    _maybeSelectionClick(provider.settings);
  }

  /// 鎯呬荆鏍囬闀挎寜锛氬彧缁欍€屽巻鍙茶琛?/ 璇捐〃绠＄悊銆嶄袱涓洿杈惧叆鍙ｏ紝
  /// 涓嶅啀寮瑰嚭銆屽垏鎹㈣琛ㄣ€嶇殑 profile 鍒楄〃銆傝琛ㄧ鐞嗕互寮圭獥鎵撳紑�?
  Future<void> _showCoupleTitleLongPressActions() async {
    final l10n = AppLocalizations.of(context)!;
    await showHomeHyperosSheet<void>(
      context: context,
      builder: (sheetContext) {
        return HyperosSheet(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Builder(
                builder: (buttonContext) {
                  return HyperosButton(
                    label: l10n.coupleHistorySheetTitle,
                    variant: HyperosButtonVariant.secondary,
                    expand: true,
                    onPressed: () => _showCoupleTimetableHistory(buttonContext),
                  );
                },
              ),
              const SizedBox(height: 10),
              Builder(
                builder: (buttonContext) {
                  return HyperosButton(
                    label: l10n.timetableManagement,
                    variant: HyperosButtonVariant.secondary,
                    expand: true,
                    onPressed: () =>
                        _openTimetableManagementPopup(buttonContext),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// 璇捐〃绠＄悊锛氫互寮圭獥褰㈠紡鎵撳紑锛堟弧灞?Dialog锛夛紝鑰屼笉鏄帹杩涚鐞嗗瓙椤靛鑸爤銆?
  void _openTimetableManagementPopup(BuildContext buttonContext) {
    final navigator = Navigator.of(buttonContext);
    final sheetRoute = ModalRoute.of(buttonContext);
    unawaited(
      showDialog<void>(
        context: buttonContext,
        useRootNavigator: false,
        builder: (_) =>
            const Dialog.fullscreen(child: TimetableProfilesScreen()),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (sheetRoute != null && sheetRoute.isActive) {
        navigator.removeRoute(sheetRoute);
      }
    });
  }

  Future<void> _showCoupleTimetableHistory(BuildContext sheetContext) async {
    final provider = context.read<TimetableProvider>();
    final session = context.read<WithuCoupleSessionProvider>();
    final withuService = WithuCoupleTimetableService(
      authService: session.authService,
    );
    final entry = await showCoupleTimetableHistorySheet(
      context: sheetContext,
      onLoadEntries: withuService.fetchMyHistory,
    );
    if (!mounted || entry == null) {
      return;
    }

    final result = await withuService.rollbackMyTimetable(
      provider: provider,
      historyId: entry.id,
    );
    final restored = result.status != WithuCouplePullStatus.failed;
    if (!mounted) {
      return;
    }
    if (restored) {
      showAppToast(
        context,
        message: AppLocalizations.of(context)!.coupleHistoryRestored,
        kind: AppToastKind.success,
      );
    }
  }

  Future<void> _showTopActionsSheet() async {
    // The anchored menu floats over the wallpaper; give its rows the same
    // wallpaper-aware ink as the home chrome (white over dark wallpaper,
    // dark over light) instead of the theme's onSurface color.
    final provider = context.read<TimetableProvider>();
    final settings = provider.settings;
    final hasBackdrop = hasHomePageBackdropImage(settings);
    final headerShowsBackdrop = homePageRegionShowsBackdrop(
      settings,
      HomePageBackgroundScope.header,
    );
    final headerUsesFrostedChrome =
        hasBackdrop &&
        (headerShowsBackdrop || settings.homePageHeaderBlurEnabled);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final menuForeground = isDarkMode
        ? _resolveHomeChromeForeground(
            headerShowsWallpaper: headerUsesFrostedChrome,
            themeForeground: context.theme.colors.foreground,
          )
        : Colors.black;

    // 鑿滃崟褰㈡€佺敱璁剧疆鍒嗘祦锛氥€屽叓瀹牸銆嶆槸 v2.0.5.5 宸插彂甯冪増鏈殑搴曢儴寮瑰眰锛?
    // 銆屽垪琛ㄣ€嶆槸褰撳墠鐨勯敋瀹氬脊绐椼€備袱绉嶅舰鎬佸叡浜悓涓€浠借嚜瀹氫箟鎺掑垪
    // 锛坔omeGridMenuActions锛夛紝缁熶竴浠ュ叆鍙?id 鍥炰紶锛屽啀缁忕洰褰曞垎鍙戝�?
    // 鍏ㄥ簲鐢ㄤ换鎰忎簩绾ч〉闈?鍔熻兘銆?
    final menuEntries = resolveHomeTopMenuEntries(settings);
    final String? selectedId;
    if (settings.homeMenuStyle == HomeMenuStyle.grid) {
      selectedId = await showHomeTopGridMenuSheet(
        context,
        entries: menuEntries,
        themeSeedHex: settings.themeSeedColor,
      );
    } else {
      selectedId = await showHomeTopMenuSheet(
        context,
        entries: menuEntries,
        anchorKey: _topMenuButtonKey,
        foregroundColor: menuForeground,
      );
    }

    if (!mounted || selectedId == null) {
      return;
    }

    // Let the sheet route finish closing before pushing the next page.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      return;
    }

    switch (selectedId) {
      // 娣诲姞璇剧▼渚濊禆棣栭〉瀹夸富涓婁笅鏂囧甫鏃ヨ鍥鹃€変腑鏃ユ湡寮瑰眰锛涘叾浣欏叏閮ㄨ蛋鐩綍鍒嗗彂�?
      case 'addCourse':
        await _navigateToAddCourse(context);
      default:
        HomeMenuEntry? entry;
        for (final candidate in menuEntries) {
          if (candidate.id == selectedId) {
            entry = candidate;
            break;
          }
        }
        if (entry != null) {
          await entry.open(context);
        }
    }
  }
}

void _openPopupActionPage(
  BuildContext buttonContext, {
  required WidgetBuilder pageBuilder,
  required Route<dynamic>? sheetRoute,
}) {
  final renderBox = buttonContext.findRenderObject() as RenderBox?;
  final buttonOffset = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
  final buttonSize = renderBox?.size ?? const Size(80, 80);
  final sourceRect = buttonOffset & buttonSize;
  final navigator = Navigator.of(buttonContext);

  navigator.push(
    _OpenOnlyContainerPageRoute<void>(
      sourceRect: sourceRect,
      builder: pageBuilder,
      backgroundColor: Theme.of(buttonContext).scaffoldBackgroundColor,
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (sheetRoute != null && sheetRoute.isActive) {
      navigator.removeRoute(sheetRoute);
    }
  });
}

class _OpenOnlyContainerPageRoute<T> extends PageRouteBuilder<T> {
  final Rect sourceRect;
  final WidgetBuilder builder;
  final Color backgroundColor;

  _OpenOnlyContainerPageRoute({
    required this.sourceRect,
    required this.builder,
    required this.backgroundColor,
  }) : super(
         transitionDuration: const Duration(milliseconds: 420),
         reverseTransitionDuration: Duration.zero,
         opaque: false,
         pageBuilder: (context, animation, secondaryAnimation) =>
             builder(context),
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           final size = MediaQuery.of(context).size;
           final sourceCenter = sourceRect.center;
           final screenCenter = Offset(size.width / 2, size.height / 2);
           final alignment = Alignment(
             ((sourceCenter.dx / size.width) * 2).clamp(0.0, 2.0) - 1,
             ((sourceCenter.dy / size.height) * 2).clamp(0.0, 2.0) - 1,
           );
           final curved = CurvedAnimation(
             parent: animation,
             curve: Curves.easeInOutCubicEmphasized,
           );
           return AnimatedBuilder(
             animation: curved,
             child: child,
             builder: (context, child) {
               final progress = curved.value;
               final scale = 0.84 + (0.16 * progress);
               final offset = Offset.lerp(
                 sourceCenter - screenCenter,
                 Offset.zero,
                 progress,
               )!;
               final borderRadius = BorderRadius.lerp(
                 BorderRadius.circular(22),
                 BorderRadius.zero,
                 progress,
               )!;
               return Stack(
                 fit: StackFit.expand,
                 children: [
                   ColoredBox(
                     color: backgroundColor.withValues(
                       alpha: Curves.easeOutCubic.transform(progress),
                     ),
                   ),
                   Transform.translate(
                     offset: offset,
                     child: Transform.scale(
                       alignment: alignment,
                       scale: scale,
                       child: ClipRRect(
                         borderRadius: borderRadius,
                         child: Material(color: backgroundColor, child: child),
                       ),
                     ),
                   ),
                 ],
               );
             },
           );
         },
       );
}

class _HomeActionPageButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final WidgetBuilder pageBuilder;
  final Route<dynamic>? sheetRoute;

  const _HomeActionPageButton({
    required this.icon,
    required this.title,
    required this.pageBuilder,
    required this.sheetRoute,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (buttonContext) {
        return _HomeActionButtonBody(
          icon: icon,
          title: title,
          onTap: () => _openPopupActionPage(
            buttonContext,
            pageBuilder: pageBuilder,
            sheetRoute: sheetRoute,
          ),
        );
      },
    );
  }
}

class _HomeActionButtonBody extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool enabled;

  const _HomeActionButtonBody({
    required this.icon,
    required this.title,
    required this.onTap,
  }) : enabled = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final colors = context.theme.colors;
    final highlightColor = enabled
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;

    return HyperosFrostedSurface(
      borderRadius: HyperosTheme.cardBorderRadius,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: HyperosTheme.cardBorderRadius,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                HyperosFrostedSurface(
                  borderRadius: const BorderRadius.all(Radius.circular(16)),
                  blurEnabled: false,
                  tint: HyperosBlurredHeader.accentSurfaceTintColor(
                    highlightColor,
                  ),
                  child: SizedBox(
                    width: 46,
                    height: 46,
                    child: Center(child: Icon(icon, color: highlightColor)),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w400,
                    height: 1.25,
                    color: enabled ? null : colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DayViewPageTarget {
  final int week;
  final int dayOfWeek;

  const _DayViewPageTarget({required this.week, required this.dayOfWeek});
}

class _DayCourseDisplayItem {
  final Course course;
  final bool isCurrentWeekCourse;
  final bool isConflicting;
  final bool isCurrentCourse;
  final double opacity;

  const _DayCourseDisplayItem({
    required this.course,
    required this.isCurrentWeekCourse,
    required this.isConflicting,
    required this.isCurrentCourse,
    required this.opacity,
  });
}

class _DayAgendaItem {
  final _DayCourseDisplayItem? courseItem;
  final ScheduleItem? scheduleItem;
  final ScheduleItemInstance? scheduleInstance;
  final Exam? exam;
  final String startTime;
  final String endTime;
  final bool continuesFromPreviousDay;
  final bool continuesToNextDay;

  const _DayAgendaItem._({
    this.courseItem,
    this.scheduleItem,
    this.scheduleInstance,
    this.exam,
    required this.startTime,
    required this.endTime,
    this.continuesFromPreviousDay = false,
    this.continuesToNextDay = false,
  });

  factory _DayAgendaItem.course(_DayCourseDisplayItem item) {
    return _DayAgendaItem._(
      courseItem: item,
      startTime: item.course.startTime,
      endTime: item.course.endTime,
    );
  }

  factory _DayAgendaItem.schedule(
    ScheduleItem item, {
    ScheduleItemInstance? instance,
    required String startTime,
    required String endTime,
    bool continuesFromPreviousDay = false,
    bool continuesToNextDay = false,
  }) {
    return _DayAgendaItem._(
      scheduleItem: item,
      scheduleInstance: instance,
      startTime: startTime,
      endTime: endTime,
      continuesFromPreviousDay: continuesFromPreviousDay,
      continuesToNextDay: continuesToNextDay,
    );
  }

  factory _DayAgendaItem.exam(Exam exam) {
    return _DayAgendaItem._(
      exam: exam,
      startTime: exam.startTime,
      endTime: exam.endTime,
    );
  }

  bool get isScheduleItem => scheduleItem != null;
  bool get isExam => exam != null;
  String get id =>
      exam?.id ??
      (isScheduleItem
          ? scheduleInstance?.occurrenceId ?? scheduleItem!.id
          : courseItem!.course.id);
}

class _DayAgendaProgressInfo {
  final double progress;
  final int remainingMinutes;
  final String statusText;
  final Color statusBackgroundColor;
  final Color statusTextColor;
  final Color baseColor;
  final Color fillColor;

  const _DayAgendaProgressInfo({
    required this.progress,
    required this.remainingMinutes,
    required this.statusText,
    required this.statusBackgroundColor,
    required this.statusTextColor,
    required this.baseColor,
    required this.fillColor,
  });
}

class _DayAgendaPalette {
  final Color baseColor;
  final Color fillColor;
  final Color foregroundColor;

  const _DayAgendaPalette({
    required this.baseColor,
    required this.fillColor,
    required this.foregroundColor,
  });
}

/// Home timetable only: clamping scroll, no HyperOS rubber-band overscroll.
class _TimetableHomeScrollBehavior extends ScrollBehavior {
  const _TimetableHomeScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // No Material stretch / glow ? keep the grid hard-edged.
    return child;
  }
}

/// Vertical pull detector that yields to horizontal week paging.
///
/// Claims the gesture arena only after the drag is clearly more vertical than
/// horizontal, so left/right week swipes stay smooth.
class _HomePullVerticalDragDetector extends StatefulWidget {
  const _HomePullVerticalDragDetector({
    required this.child,
    required this.enabled,
    required this.onPullUpdate,
    required this.onPullEnd,
    required this.onPullCancel,
  });

  final Widget child;
  final bool enabled;
  final ValueChanged<double> onPullUpdate;
  final VoidCallback onPullEnd;
  final VoidCallback onPullCancel;

  @override
  State<_HomePullVerticalDragDetector> createState() =>
      _HomePullVerticalDragDetectorState();
}

class _HomePullVerticalDragDetectorState
    extends State<_HomePullVerticalDragDetector> {
  double _accumulatedDx = 0;
  double _accumulatedDy = 0;
  bool _isTrackingVerticalPull = false;

  static const double _axisDecisionDistance = 10;

  void _resetTracking() {
    _accumulatedDx = 0;
    _accumulatedDy = 0;
    _isTrackingVerticalPull = false;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        _resetTracking();
      },
      onPointerMove: (event) {
        final delta = event.delta;
        _accumulatedDx += delta.dx;
        _accumulatedDy += delta.dy;

        if (!_isTrackingVerticalPull) {
          final absDx = _accumulatedDx.abs();
          final absDy = _accumulatedDy.abs();
          if (absDx < _axisDecisionDistance && absDy < _axisDecisionDistance) {
            return;
          }
          // Prefer horizontal week paging when the gesture is not clearly vertical.
          if (absDy <= absDx * 1.15) {
            return;
          }
          _isTrackingVerticalPull = true;
        }

        if (_isTrackingVerticalPull) {
          widget.onPullUpdate(delta.dy);
        }
      },
      onPointerUp: (_) {
        if (_isTrackingVerticalPull) {
          widget.onPullEnd();
        } else {
          widget.onPullCancel();
        }
        _resetTracking();
      },
      onPointerCancel: (_) {
        if (_isTrackingVerticalPull) {
          widget.onPullCancel();
        }
        _resetTracking();
      },
      child: widget.child,
    );
  }
}
