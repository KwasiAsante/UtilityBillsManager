import 'package:flutter/material.dart';

/// Single-breakpoint helper used throughout the app.
///
/// Compact: < 600dp  — phone portrait, small phone landscape
/// Wide:   ≥ 600dp  — tablet, phone landscape, desktop, web
class AppBreakpoints {
  AppBreakpoints._();

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 600;
}
