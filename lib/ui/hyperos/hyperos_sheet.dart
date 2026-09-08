import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'hyperos_blurred_header.dart';
import 'hyperos_miuix_spec.dart';
import 'hyperos_motion.dart';
import 'hyperos_theme.dart';
import 'hyperos_tokens.dart';
import 'frosted/liquid_glass_degradation.dart';
import 'hyperos_widgets.dart';
import 'liquid/hyperos_liquid_glass_surface.dart';

/// Extra height painted below an edge-flush glass sheet's bottom edge so the
/// liquid-glass specular fringe along the straight bottom side lands outside
/// the panel's clip and is cut 鈥?otherwise that fringe shows as a 1px
/// hairline seam where the panel meets the screen bottom (same failure as the
/// top edge, see `homePageChromeGlassTopEdgeOverdraw`).
const hyperosEdgeSheetBottomOverdraw = 4.0;

/// Marks descendants as sitting on a frosted (blur + milky tint) panel.
///
/// Used by [HyperosButton] secondary fill so cancel / neutral actions stay
/// readable against glass instead of blending into white-on-white.
class HyperosFrostedPanelScope extends InheritedWidget {
  const HyperosFrostedPanelScope({required super.child, super.key});

  static bool of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<HyperosFrostedPanelScope>() !=
        null;
  }

  @override
  bool updateShouldNotify(covariant HyperosFrostedPanelScope oldWidget) {
    return false;
  }
}

/// Visual chrome for [HyperosSheetFrame] / [HyperosSheet].
enum HyperosSheetChrome {
  /// Floating card: left/right/bottom outer gap + full rounded corners.
  /// Matches [HyperosDialog] (settings / form sheets).
  floating,

  /// Edge-flush panel: full width, top corners only, sits on screen bottom.
  /// Preferred for home timetable menus and action sheets.
  edge,
}

/// 鏈鐨勬恫鎬佺幓鐠冩潗璐ㄥ彈銆屾恫鎬佺幓鐠冧綔鐢ㄨ寖鍥淬€嶅摢涓€妗ｅ紑鍏虫帶鍒躲€?
enum HyperosSheetLiquidGlassGroup {
  /// 搴曢儴寮圭獥涓庡璇濇锛坰howHyperosSheet / HyperosDialog 绯伙紝榛樿寮€锛夈€?
  sheetDialog,

  /// 瀵硅瘽寮忓叏灞忛€夋嫨闈㈡澘鈥斺€旈璁句富棰樸€佸瓧浣撶瓑闀垮垪琛ㄩ€夋嫨寮圭獥锛堥粯璁ゅ叧锛?  /// 澶ч潰绉姌灏勫湪闀垮垪琛ㄤ笂鍋忕偒涓旀洿璐圭數锛岄粯璁や繚鎸佺粡鍏哥（鐮傦級銆?
  selectSheet,
}

/// Provides default [HyperosSheetChrome] for nested [HyperosSheetFrame]s.
class HyperosSheetChromeScope extends InheritedWidget {
  const HyperosSheetChromeScope({
    required this.chrome,
    required super.child,
    super.key,
  });

  final HyperosSheetChrome chrome;

  static HyperosSheetChrome? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<HyperosSheetChromeScope>()
        ?.chrome;
  }

  static HyperosSheetChrome of(BuildContext context) {
    return maybeOf(context) ?? HyperosSheetChrome.floating;
  }

  @override
  bool updateShouldNotify(covariant HyperosSheetChromeScope oldWidget) {
    return chrome != oldWidget.chrome;
  }
}

/// HyperOS bottom sheet panel shell.
///
/// Defaults to the shared modal glass material using the same tuning as the
/// top chrome. Defaults to [HyperosSheetChrome.floating] unless an ancestor
/// [HyperosSheetChromeScope] or [chrome] overrides it.
class HyperosSheetFrame extends StatelessWidget {
  const HyperosSheetFrame({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 16),
    this.maxHeight,
    this.frosted = true,
    this.chrome,
    this.liquidGlassRole = HyperosLiquidGlassRole.modal,
    this.liquidGlassContentLegibilityFill = false,
    this.liquidGlassGroup = HyperosSheetLiquidGlassGroup.sheetDialog,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? maxHeight;

  /// When true (default), milky frosted glass + live blur when enabled in
  /// settings. Sigma / tint / master switch come from [FrostedAppearanceScope].
  final bool frosted;

  /// When null, uses [HyperosSheetChromeScope] or [HyperosSheetChrome.floating].
  final HyperosSheetChrome? chrome;

  /// Material role used when [frosted] resolves to liquid glass.
  ///
  /// All modal shells default to [HyperosLiquidGlassRole.modal] so dialogs,
  /// action sheets, and pickers share one clear material. Override this only
  /// for a deliberately different embedded surface.
  final HyperosLiquidGlassRole liquidGlassRole;

  /// Whether liquid-glass content receives the extra opaque legibility fill.
  ///
  /// Defaults to false so every sheet/dialog uses the same clear material as
  /// the home chrome band (9de96b8 / A 鏂规閫氶€忕粺涓€). Set true explicitly
  /// only for a deliberately milky panel.
  final bool liquidGlassContentLegibilityFill;

  /// 銆屾恫鎬佺幓鐠冧綔鐢ㄨ寖鍥淬€嶅紑鍏虫。浣嶏細鏈娑叉€佹潗璐ㄨ窡闅忓脊绐楀璇濇锛堥粯璁わ級
  /// 杩樻槸瀵硅瘽寮忓叏灞忛€夋嫨闈㈡澘锛堥璁句富棰樼瓑闀垮垪琛ㄩ€夋嫨寮圭獥锛夈€?
  final HyperosSheetLiquidGlassGroup liquidGlassGroup;

  /// 鏈褰撳墠鏄惁鍏佽浣跨敤娑叉€佺幓鐠冩潗璐紙鍏ㄥ眬妯″紡 脳 瀹舵棌寮€鍏筹級銆?
  bool _liquidGlassAllowed(FrostedAppearance appearance) =>
      switch (liquidGlassGroup) {
        HyperosSheetLiquidGlassGroup.sheetDialog =>
          appearance.liquidGlassSheetDialogEnabled,
        HyperosSheetLiquidGlassGroup.selectSheet =>
          appearance.liquidGlassSelectSheetEnabled,
      };

  @override
  Widget build(BuildContext context) {
    final resolvedChrome = chrome ?? HyperosSheetChromeScope.of(context);
    final panel = switch (resolvedChrome) {
      HyperosSheetChrome.floating => _buildFloatingPanel(context),
      HyperosSheetChrome.edge => _buildEdgePanel(context),
    };

    if (maxHeight == null) {
      return panel;
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight!),
      child: panel,
    );
  }

  Widget _buildFloatingPanel(BuildContext context) {
    const outerInset = HyperosMiuixDialog.outsideMarginHorizontal;
    final bottomSafeInset = MediaQuery.paddingOf(context).bottom;
    final borderRadius = BorderRadius.circular(HyperosTokens.cardRadius);
    final content = Padding(padding: padding, child: child);

    final panel = frosted
        ? _buildFrostedSurface(
            context: context,
            borderRadius: borderRadius,
            content: content,
          )
        : Material(
            color: HyperosColors.surfaceContainer(context),
            shape: HyperosTheme.cardShape(),
            clipBehavior: Clip.antiAlias,
            child: content,
          );

    // BoxShadow creates a dark ring around the panel 鈥?visible on all sides,
    // moves with the panel (no tracking), and matches the panel's rounded
    // corners naturally.  The shadow sits BEHIND the frosted glass, so
    // BackdropFilter inside the glass samples the bright page content, not
    // the shadow.
    return Padding(
      padding: EdgeInsets.fromLTRB(
        outerInset,
        0,
        outerInset,
        outerInset + bottomSafeInset,
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          boxShadow: [
            BoxShadow(
              // 涓?anchored popup 姘旀场鍚岀骇锛氳交鎶曞奖锛屼笉鍐嶅舰鎴愭槑鏄炬殫鐜€?
              color: Color(0x24000000),
              blurRadius: 20,
            ),
          ],
        ),
        child: panel,
      ),
    );
  }

  Widget _buildEdgePanel(BuildContext context) {
    const borderRadius = BorderRadius.vertical(
      top: Radius.circular(HyperosTokens.cardRadius),
    );
    final content = SafeArea(
      top: false,
      child: Padding(padding: padding, child: child),
    );

    if (frosted) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: SizedBox(
          width: double.infinity,
          child: HyperosFrostedPanelScope(
            child: Stack(
              children: [
                // Paint the glass a few pixels below the visible panel so the
                // liquid-glass specular fringe on its straight bottom edge
                // lands outside the ClipRRect and is clipped 鈥?otherwise it
                // shows as a 1px hairline seam where the edge sheet meets the
                // screen bottom (see hyperosEdgeSheetBottomOverdraw).
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  bottom: -hyperosEdgeSheetBottomOverdraw,
                  child: _buildFrostedBackground(
                    context: context,
                    borderRadius: borderRadius,
                  ),
                ),
                // The real content is the non-positioned sizing child: a
                // Stack containing only Positioned children sizes itself to
                // constraints.biggest, which used to blow the edge sheet up
                // to full screen with the content pinned to the top and blank
                // glass below.
                content,
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: HyperosColors.scaffoldBackground(context),
        borderRadius: borderRadius,
      ),
      child: content,
    );
  }

  /// Glass / tint / solid background layer for a frosted panel.
  ///
  /// Painted separately from the content so callers can overdraw the glass
  /// past the panel's clip edge (see [_buildEdgePanel]) while the layout
  /// stays driven by the real content.
  Widget _buildFrostedBackground({
    required BuildContext context,
    required BorderRadius borderRadius,
  }) {
    final appearance = FrostedAppearanceScope.of(context);

    // Liquid glass mode: real-time refraction shader panel. Checked before
    // the gaussian blur gate because liquid glass carries its own blur 鈥?
    // gating it on backdropBlurEnabled (liveBlurSupported && blurEnabled)
    // would make the frame a solid gray slab on desktop/web while the nested
    // tiles keep rendering liquid glass.
    // 銆屾恫鎬佺幓鐠冧綔鐢ㄨ寖鍥淬€嶅搴斿鏃忓紑鍏冲叧闂椂锛屾暣妗嗗洖閫€纾ㄧ爞/瀹炲簳鏉愯川銆?
    if (appearance.glassMode == FrostedGlassMode.liquidGlass &&
        _liquidGlassAllowed(appearance) &&
        !LiquidGlassDegradation.shouldDegrade(context)) {
      return HyperosLiquidGlassSurface(
        role: liquidGlassRole,
        borderRadius: borderRadius.topLeft.x,
        instantUnderlay: true,
        useAncestorBackdropGroup: true,
        contentLegibilityFill: liquidGlassContentLegibilityFill,
        child: const SizedBox.expand(),
      );
    }

    final useBlur = HyperosBlurredHeader.backdropBlurEnabled(context);

    // Blur off 鈫?solid opaque panel (no translucent scrim over the page).
    if (!useBlur) {
      return Material(
        color: HyperosColors.surfaceContainer(context),
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: const SizedBox.expand(),
      );
    }

    // Frosted / gaussian / translucent: BackdropFilter + tint.
    final tint = HyperosBlurredHeader.sheetTintColor(context, withBlur: true);

    return ClipRRect(
      borderRadius: borderRadius,
      child: FrostedHeaderBackground(
        blurSigma: HyperosBlurredHeader.blurSigmaOf(context),
        tint: tint,
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _buildFrostedSurface({
    required BuildContext context,
    required BorderRadius borderRadius,
    required Widget content,
  }) {
    final appearance = FrostedAppearanceScope.of(context);

    // Liquid glass mode: real-time refraction shader panel. Checked before
    // the gaussian blur gate because liquid glass carries its own blur 鈥?
    // gating it on backdropBlurEnabled (liveBlurSupported && blurEnabled)
    // would make the frame a solid gray slab on desktop/web while nested
    // tiles keep rendering liquid glass.
    // 銆屾恫鎬佺幓鐠冧綔鐢ㄨ寖鍥淬€嶅搴斿鏃忓紑鍏冲叧闂椂锛屾暣妗嗗洖閫€纾ㄧ爞/瀹炲簳鏉愯川銆?
    if (appearance.glassMode == FrostedGlassMode.liquidGlass &&
        _liquidGlassAllowed(appearance) &&
        !LiquidGlassDegradation.shouldDegrade(context)) {
      return HyperosFrostedPanelScope(
        child: HyperosLiquidGlassSurface(
          role: liquidGlassRole,
          borderRadius: borderRadius.topLeft.x,
          instantUnderlay: true,
          useAncestorBackdropGroup: true,
          contentLegibilityFill: liquidGlassContentLegibilityFill,
          child: content,
        ),
      );
    }

    final useBlur = HyperosBlurredHeader.backdropBlurEnabled(context);

    // Blur off 鈫?solid opaque panel (no translucent scrim over the page).
    if (!useBlur) {
      return HyperosFrostedPanelScope(
        child: Material(
          color: HyperosColors.surfaceContainer(context),
          borderRadius: borderRadius,
          clipBehavior: Clip.antiAlias,
          child: content,
        ),
      );
    }

    // Frosted / gaussian / translucent: BackdropFilter + tint.
    final tint = HyperosBlurredHeader.sheetTintColor(context, withBlur: true);

    return HyperosFrostedPanelScope(
      child: ClipRRect(
        borderRadius: borderRadius,
        child: FrostedHeaderBackground(
          blurSigma: HyperosBlurredHeader.blurSigmaOf(context),
          tint: tint,
          child: content,
        ),
      ),
    );
  }
}

/// Bottom sheet body with optional title (uses [HyperosSheetFrame] chrome).
class HyperosSheet extends StatelessWidget {
  const HyperosSheet({
    super.key,
    this.title,
    required this.child,
    this.description,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 16),
    this.frosted = true,
    this.chrome,
  });

  final String? title;
  final Widget child;
  final String? description;
  final EdgeInsetsGeometry padding;
  final bool frosted;
  final HyperosSheetChrome? chrome;

  @override
  Widget build(BuildContext context) {
    return HyperosSheetFrame(
      frosted: frosted,
      padding: padding,
      chrome: chrome,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title!, style: HyperosTypography.sheetTitle(context)),
            const SizedBox(height: 16),
          ],
          child,
          if (description != null) ...[
            const SizedBox(height: 12),
            HyperosSectionDescription(text: description!),
          ],
        ],
      ),
    );
  }
}

/// Bottom velocity threshold to dismiss (pixels/second).
const double _kDismissVelocity = 600;

/// Bottom distance threshold to dismiss (fraction of sheet height).
const double _kDismissFraction = 0.3;

/// The minimum exit velocity in slide fractions per second. This prevents a
/// slow threshold release from handing off to a zero-velocity curve.
const double _kSheetExitVelocity = 1.4;

/// The route slide distance as a fraction of the sheet's own height. This is
/// also the distance needed to guarantee that the sheet is fully offscreen
/// before the route is removed.
const double _kSheetSlideFraction = 1;

/// One algebraic ease-out is used in both directions so a drag can hand off to
/// the route without changing the sheet's visual position on release. Keep the
/// inverse in `_dragValue` aligned with this formula.
class _SheetSlideCurve extends Curve {
  const _SheetSlideCurve();

  @override
  double transform(double t) => 1 - math.pow(1 - t, 3).toDouble();
}

const Curve _kSheetSlideCurve = _SheetSlideCurve();

/// The reverse direction maps route progress into exit progress first. That
/// gives the panel a visible start, an accelerating middle, and a decelerating
/// finish instead of freezing at the bottom and diving off at the last frame.
class _SheetExitCurve extends Curve {
  const _SheetExitCurve();

  @override
  double transform(double t) {
    final exit = (1 - t).clamp(0.0, 1.0).toDouble();
    if (exit < 0.5) {
      return 4 * math.pow(exit, 3).toDouble();
    }
    return 1 - math.pow(-2 * exit + 2, 3) / 2;
  }
}

const Curve _kSheetExitCurve = _SheetExitCurve();

double _sheetSlideProgress(Animation<double> animation, {double? exitStart}) {
  final value = animation.value.clamp(0.0, 1.0);
  final start = exitStart?.clamp(0.0, 1.0) ?? 0;
  if (start <= 0) {
    return _kSheetSlideCurve.transform(value);
  }

  // A pop can begin in the middle of a drag. Normalize the remaining route
  // range so the exit starts exactly at the finger's visual position.
  final elapsed = ((start - value) / start).clamp(0.0, 1.0).toDouble();
  final startProgress = 1 - math.pow(1 - start, 3).toDouble();
  return startProgress * _kSheetExitCurve.transform(elapsed);
}

class _SheetSlideAnimation extends Animation<Offset> {
  const _SheetSlideAnimation(this.parent, {required this.exitStart});

  final Animation<double> parent;
  final double? Function() exitStart;

  @override
  void addListener(VoidCallback listener) => parent.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => parent.removeListener(listener);

  @override
  void addStatusListener(AnimationStatusListener listener) {
    parent.addStatusListener(listener);
  }

  @override
  void removeStatusListener(AnimationStatusListener listener) {
    parent.removeStatusListener(listener);
  }

  @override
  AnimationStatus get status => parent.status;

  @override
  Offset get value {
    final progress = _sheetSlideProgress(parent, exitStart: exitStart());
    return Offset(0, 1 - progress);
  }
}

/// A wrapper that adds vertical drag-to-dismiss for the sheet content.
///
/// Wraps the sheet content (not the full-screen Align) so that the
/// [LayoutBuilder] measures the actual sheet height, enabling the
/// distance-based dismiss threshold.
///
/// Dragging only translates the panel 鈥?the sheet never fades out. An
/// `Opacity` layer here would degrade frosted [BackdropFilter] / liquid glass
/// shaders (the same reason [_SheetSlideUp] avoids animated Opacity), showing
/// as transparency flicker while the panel is dragged down.
class _DragDismissableSheet extends StatefulWidget {
  const _DragDismissableSheet({required this.child});

  final Widget child;

  @override
  State<_DragDismissableSheet> createState() => _DragDismissableSheetState();
}

class _DragDismissableSheetState extends State<_DragDismissableSheet> {
  /// Pixel offset the sheet has been dragged down (0 = at rest).
  ///
  /// A [ValueNotifier] instead of `setState`: dragging would otherwise rebuild
  /// the whole frosted / liquid glass subtree on every pointer move. The
  /// notifier only rebuilds the [Transform.translate] layer while the sheet
  /// subtree stays mounted untouched (same pattern as [HyperosPage]).
  double _dragOffset = 0;
  final GlobalKey _sheetKey = GlobalKey();

  _HyperosSheetRoute<dynamic>? get _sheetRoute =>
      ModalRoute.of<dynamic>(context) as _HyperosSheetRoute<dynamic>?;

  double get _slideDistance =>
      _measuredSheetHeight ??
      MediaQuery.sizeOf(context).height * _kSheetSlideFraction;

  double? get _measuredSheetHeight {
    final box = _sheetKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return null;
    }
    return box.size.height;
  }

  double get _dragValue {
    final normalized = (_dragOffset / _slideDistance).clamp(0.0, 1.0);
    // The sheet's downward distance is (1 - controller.value)^3. Solve that
    // mapping so the route-driven slide lands on the same pixel as the
    // finger without adding a second transform.
    return 1 - math.pow(normalized, 1 / 3).toDouble();
  }

  void _onVerticalDragStart(DragStartDetails details) {
    final controller = _sheetRoute?.sheetController;
    if (controller == null) {
      return;
    }
    final wasReversing = controller.status == AnimationStatus.reverse;
    controller.stop();
    final value = controller.value.clamp(0.0, 1.0);
    final sheetRoute = _sheetRoute;
    final downwardProgress =
        1 -
        (sheetRoute?.currentSlideProgress ??
            _kSheetSlideCurve.transform(value));
    if (wasReversing) {
      sheetRoute?._isPopping = false;
      sheetRoute?._exitStartValue = null;
    }
    _dragOffset = _slideDistance * downwardProgress.clamp(0.0, 1.0);
    if (wasReversing) {
      // A drag takes over a reverse transition. Put the controller back in
      // forward mode without advancing it so the route uses the same curve as
      // the finger on every following update.
      controller.forward(from: controller.value);
      controller.stop();
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    final controller = _sheetRoute?.sheetController;
    if (controller == null) {
      return;
    }
    final dy = details.primaryDelta ?? 0;
    if (dy > 0 || _dragOffset > 0) {
      _dragOffset = (_dragOffset + dy).clamp(0.0, double.infinity);
    }
    controller.value = _dragValue;
    if (controller.value <= 0) {
      Navigator.of(context).maybePop();
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final sheetRoute = _sheetRoute;

    // Dismiss if velocity or distance exceeds threshold.
    if (velocity > _kDismissVelocity ||
        _dragOffset > _slideDistance * _kDismissFraction) {
      // The route controller already carries the dragged position. Keep the
      // wrapper at zero so pop does not apply the finger offset a second time.
      _dragOffset = 0;
      sheetRoute?._exitVelocity = velocity / _slideDistance;
      Navigator.of(context).pop();
      return;
    }

    // Keep the route transition as the single source of truth when restoring.
    if (_dragOffset > 0) {
      final routeProgress = _dragValue;
      final remainingDistance = _slideDistance * (1 - routeProgress);
      final durationMs = (220 * (remainingDistance / _slideDistance)).clamp(
        80,
        220,
      );
      final sheetController = _sheetRoute?.sheetController;
      if (sheetController != null) {
        sheetController
          ..duration = Duration(milliseconds: durationMs.toInt())
          ..forward();
      }
      _dragOffset = 0;
    }
  }

  void _onVerticalDragCancel() {
    _onVerticalDragEnd(DragEndDetails(primaryVelocity: 0));
  }

  @override
  Widget build(BuildContext context) {
    // The route controller is the single visual source of truth: it is
    // set to the exact inverse of the finger's slide fraction. Do not add
    // a Transform.translate here, or every drag offset is applied twice.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: _onVerticalDragStart,
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onVerticalDragEnd: _onVerticalDragEnd,
      onVerticalDragCancel: _onVerticalDragCancel,
      child: KeyedSubtree(key: _sheetKey, child: widget.child),
    );
  }
}

/// Internal sheet route whose controller can be driven by the drag gesture.
class _HyperosSheetRoute<T> extends RawDialogRoute<T> {
  _HyperosSheetRoute({
    required super.pageBuilder,
    required super.barrierDismissible,
    required super.barrierLabel,
    required super.transitionDuration,
    required this.reverseDuration,
    super.barrierColor,
  });

  final Duration reverseDuration;

  /// `controller` is protected on [TransitionRoute]; expose only this route's
  /// gesture control surface.
  AnimationController? get sheetController => controller;

  /// The wrapped route animation does not reliably expose reverse direction,
  /// so dismissal is tracked by the route lifecycle itself.
  bool _isPopping = false;
  bool get isPopping => _isPopping;
  double? _exitStartValue;
  double? get exitStartValue => _exitStartValue;
  double? _exitVelocity;

  double get currentSlideProgress {
    final value = (controller?.value ?? 0).clamp(0.0, 1.0);
    final start = _exitStartValue?.clamp(0.0, 1.0) ?? 0;
    if (start <= 0) {
      return _kSheetSlideCurve.transform(value);
    }
    final elapsed = ((start - value) / start).clamp(0.0, 1.0).toDouble();
    final startProgress = 1 - math.pow(1 - start, 3).toDouble();
    return startProgress * _kSheetExitCurve.transform(elapsed);
  }

  @override
  bool didPop(T? result) {
    _exitStartValue = controller?.value ?? 0;
    _isPopping = true;
    return super.didPop(result);
  }

  @override
  Duration get reverseTransitionDuration => reverseDuration;

  // RawDialogRoute's default FadeTransition would fade the whole panel while
  // it slides and can also destabilize frosted / liquid-glass shaders. The
  // scrim below owns the fade; the sheet itself only slides.
  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }

  // AnimationController.reverse scales duration by the remaining distance.
  // That makes a threshold release finish in only a few dozen milliseconds,
  // which reads as a sudden pop. Give every drag-to-route handoff the full
  // reverse duration while continuing from the exact dragged value.
  @override
  Simulation? createSimulation({required bool forward}) {
    if (forward) {
      return null;
    }
    final currentValue = controller?.value ?? 0;
    if (currentValue <= 0 || reverseDuration <= Duration.zero) {
      return null;
    }
    return _HyperosSheetExitSimulation(
      start: currentValue,
      durationInSeconds:
          reverseDuration.inMicroseconds / Duration.microsecondsPerSecond,
      initialVelocity: _exitVelocity,
    );
  }
}

class _HyperosSheetExitSimulation extends Simulation {
  _HyperosSheetExitSimulation({
    required this.start,
    required this.durationInSeconds,
    this.initialVelocity,
  });

  final double start;
  final double durationInSeconds;
  final double? initialVelocity;

  double _exitCurveInverse(double progress) {
    if (progress <= 0) {
      return 1;
    }
    if (progress >= 1) {
      return 0;
    }
    if (progress > 0.5) {
      return math.pow((1 - progress) / 4, 1 / 3).toDouble();
    }
    return 1 - math.pow(progress / 4, 1 / 3).toDouble();
  }

  double _visualProgress(double time) {
    final startProgress = 1 - math.pow(1 - start, 3).toDouble();
    final velocity = (initialVelocity ?? _kSheetExitVelocity).clamp(
      _kSheetExitVelocity,
      3 / durationInSeconds,
    );
    // A Hermite curve starts with the finger's velocity and stops smoothly.
    // The cubic coefficient is capped at 3 so a fast fling cannot overshoot.
    final initialSlope = (-velocity / startProgress).clamp(
      -3 / durationInSeconds,
      0.0,
    );
    final t = (time / durationInSeconds).clamp(0.0, 1.0).toDouble();
    final towardEnd = 2 * math.pow(t, 3) - 3 * math.pow(t, 2) + 1;
    final startTangent =
        initialSlope *
        durationInSeconds *
        (math.pow(t, 3) - 2 * math.pow(t, 2) + t);
    return (startProgress * (towardEnd + startTangent)).clamp(
      0.0,
      startProgress,
    );
  }

  @override
  double x(double time) {
    final progress =
        _visualProgress(time) / (1 - math.pow(1 - start, 3).toDouble());
    return start * (1 - _exitCurveInverse(progress));
  }

  @override
  double dx(double time) {
    if (time >= durationInSeconds) {
      return 0;
    }
    final next = x(time + 1 / 120);
    return (next - x(time)) * 120;
  }

  @override
  bool isDone(double time) => time >= durationInSeconds;
}

class _SheetSlideUp extends StatelessWidget {
  const _SheetSlideUp({
    required this.animation,
    required this.exitStart,
    required this.child,
  });

  final Animation<double> animation;
  final double? Function() exitStart;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _SheetSlideAnimation(animation, exitStart: exitStart),
      child: child,
    );
  }
}

class _SheetScrim extends StatelessWidget {
  const _SheetScrim({
    required this.animation,
    required this.color,
    required this.exitStart,
  });

  final Animation<double> animation;
  final Color color;
  final double? Function() exitStart;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final progress = _sheetSlideProgress(
            animation,
            exitStart: exitStart(),
          );
          return ColoredBox(color: color.withValues(alpha: color.a * progress));
        },
      ),
    );
  }
}

/// Shows a HyperOS-styled modal bottom sheet (replaces Forui `showFSheet`).
///
/// Content should use [HyperosSheetFrame] / [HyperosSheet] / [HyperosDialog].
/// Default chrome is [HyperosSheetChrome.floating] unless [chrome] or a
/// [HyperosSheetChromeScope] says otherwise.
///
/// When [padForKeyboard] is true (default), the sheet is lifted by
/// [MediaQuery.viewInsets] so it sits above the IME. Set it to false when the
/// sheet body manages keyboard avoidance itself (e.g. scroll-to-field).
Future<T?> showHyperosSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useRootNavigator = false,
  bool padForKeyboard = true,
  Color? barrierColor,
  HyperosSheetChrome chrome = HyperosSheetChrome.floating,
}) async {
  final appearance = FrostedAppearanceScope.of(context);
  final dimColor =
      barrierColor ?? HyperosBlurredHeader.modalBarrierColor(context);
  final transitionDuration = HyperosMotionScope.of(context).scaledDuration(280);
  final reverseDuration = HyperosMotionScope.of(context).scaledDuration(360);
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final barrierLabel = MaterialLocalizations.of(
    context,
  ).modalBarrierDismissLabel;

  return navigator.push<T>(
    _HyperosSheetRoute<T>(
      barrierDismissible: isDismissible,
      barrierLabel: barrierLabel,
      barrierColor: Colors.transparent,
      transitionDuration: transitionDuration,
      reverseDuration: reverseDuration,
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final keyboardInset = padForKeyboard
            ? MediaQuery.viewInsetsOf(dialogContext).bottom
            : 0.0;
        final sheetContent = FrostedAppearanceScope(
          appearance: appearance,
          child: HyperosSheetChromeScope(
            chrome: chrome,
            child: builder(dialogContext),
          ),
        );

        // Wrap drag-to-dismiss around the sheet content (not the full-screen
        // Align) so LayoutBuilder measures the actual sheet height.
        final sheet = enableDrag
            ? _DragDismissableSheet(child: sheetContent)
            : sheetContent;
        final sheetRoute =
            ModalRoute.of(dialogContext) as _HyperosSheetRoute<dynamic>?;
        final sheetAnimation = sheetRoute?.sheetController ?? animation;
        double? exitStartValue() => sheetRoute?.exitStartValue;

        return BackdropGroup(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: _SheetScrim(
                  animation: sheetAnimation,
                  color: dimColor,
                  exitStart: exitStartValue,
                ),
              ),
              Positioned.fill(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: _SheetSlideUp(
                    animation: sheetAnimation,
                    exitStart: exitStartValue,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: keyboardInset),
                      child: sheet,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Home timetable sheets: edge-flush chrome + lighter barrier.
/// Nested [HyperosSheetFrame]s default to frosted glass.
Future<T?> showHomeHyperosSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useRootNavigator = false,
  bool padForKeyboard = true,
  Color? barrierColor,
  HyperosSheetChrome chrome = HyperosSheetChrome.edge,
}) {
  return showHyperosSheet<T>(
    context: context,
    builder: builder,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useRootNavigator: useRootNavigator,
    padForKeyboard: padForKeyboard,
    chrome: chrome,
    barrierColor:
        barrierColor ?? HyperosBlurredHeader.modalBarrierColor(context),
  );
}
