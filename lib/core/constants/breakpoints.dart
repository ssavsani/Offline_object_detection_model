import 'package:flutter/widgets.dart';

/// Single source of truth for the phone/tablet layout split.
class Breakpoints {
  Breakpoints._();

  /// Matches the Android `sw600dp` convention (7"+ tablets).
  static const double tablet = 600;

  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).shortestSide >= tablet;
}
