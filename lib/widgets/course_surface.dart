import 'package:flutter/material.dart';

/// Paints the solid course-card surface behind [child].
///
/// Single source of truth for course surface material, shared by the week grid
/// ([CourseCard]) and the day view agenda cards, so the two cannot drift.
class CourseSurface extends StatelessWidget {
  const CourseSurface({
    required this.color,
    required this.borderRadius,
    required this.child,
    this.opacityScale = 1.0,
    this.solidGradient,
    this.border,
    this.boxShadow,
    this.outerShadow,
    super.key,
  });

  /// Course hue. Drives the solid gradient.
  final Color color;

  final double borderRadius;
  final Widget child;

  /// Dim factor for conflict / holiday / suspended states (0–1).
  ///
  /// Multiplied into every fill and tint alpha.
  final double opacityScale;

  /// Overrides the default two-stop hue gradient.
  final Gradient? solidGradient;

  /// Emphasis border. Drawn inside the decoration.
  final Border? border;

  /// Shadow on the opaque decoration, matching legacy card behaviour.
  final List<BoxShadow>? boxShadow;

  /// Shadow painted beneath the surface.
  final List<BoxShadow>? outerShadow;

  /// Second stop of the default solid gradient.
  static Color secondaryFillColor(Color color) {
    return Color.lerp(color, Colors.white, 0.08) ?? color;
  }

  double _scaledAlpha(double baseAlpha) {
    return (baseAlpha * opacityScale).clamp(0.04, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);

    final surface = _buildSolid(radius);

    final outer = outerShadow;
    if (outer == null || outer.isEmpty) {
      return surface;
    }
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: outer),
      child: surface,
    );
  }

  Widget _buildSolid(BorderRadius radius) {
    final gradient =
        solidGradient ??
        LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: _scaledAlpha(1)),
            secondaryFillColor(color).withValues(alpha: _scaledAlpha(1)),
          ],
        );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: gradient,
        border: border,
        boxShadow: boxShadow,
      ),
      child: child,
    );
  }
}