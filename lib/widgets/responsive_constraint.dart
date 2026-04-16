import 'package:flutter/material.dart';
import '../utils/app_breakpoints.dart';

/// Constrains [child] to [maxWidth] and centres it horizontally on wide screens.
///
/// On compact (< 600dp) screens [child] is returned unchanged.
/// Use [maxWidth] 720 for list screens and 560 for form/settings screens.
class ResponsiveConstraint extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ResponsiveConstraint({
    super.key,
    required this.child,
    this.maxWidth = 720,
  });

  @override
  Widget build(BuildContext context) {
    if (!AppBreakpoints.isWide(context)) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
