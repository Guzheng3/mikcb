import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../ui/hyperos/hyperos_motion.dart';

class CourseDetailReveal extends StatefulWidget {
  const CourseDetailReveal({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  State<CourseDetailReveal> createState() => _CourseDetailRevealState();
}

class _CourseDetailRevealState extends State<CourseDetailReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  late final CurvedAnimation _animation = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      (widget.index * 0.04).clamp(0.0, 0.24).toDouble(),
      1,
      curve: Curves.easeOutCubic,
    ),
  );
  ScrollPosition? _position;
  bool _revealed = false;
  bool _motionDisabled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = HyperosMotionScope.of(context).scaledDuration(280);
    _motionDisabled = MediaQuery.disableAnimationsOf(context);
    _attachScrollPosition();
    if (_motionDisabled) {
      _revealed = true;
      _controller.value = 1;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateReveal();
      }
    });
  }

  @override
  void dispose() {
    _position?.removeListener(_updateReveal);
    _controller.dispose();
    super.dispose();
  }

  void _attachScrollPosition() {
    final position = Scrollable.maybeOf(context)?.position;
    if (identical(position, _position)) {
      return;
    }
    _position?.removeListener(_updateReveal);
    _position = position;
    _position?.addListener(_updateReveal);
  }

  void _updateReveal() {
    final position = _position;
    final box = context.findRenderObject();
    if (position == null ||
        !position.hasPixels ||
        !position.hasViewportDimension ||
        box is! RenderBox ||
        !box.attached ||
        !box.hasSize) {
      return;
    }

    final viewport = RenderAbstractViewport.of(box);
    final viewportTransform = box.getTransformTo(viewport);
    final top = MatrixUtils.transformPoint(viewportTransform, Offset.zero).dy;
    final bottom = top + box.size.height;
    final viewHeight = position.viewportDimension;
    final hasEntered = top <= viewHeight - 24 && bottom >= 8;

    if (hasEntered == _revealed) {
      return;
    }

    _revealed = hasEntered;
    if (hasEntered) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_motionDisabled) {
      return widget.child;
    }

    return FadeTransition(
      opacity: _animation,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, 18 * (1 - _animation.value)),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
