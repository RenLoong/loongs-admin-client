/// Apple-style (HIG) look for shadcn_ui: systemBlue accent, grouped backgrounds, large radii,
/// grouped backgrounds with little or no divider lines, subtle shadows, iOS-green switches, sheet-like dialogs. Light and dark use
/// the same semantic names, so widgets only ever read the theme (README §19).
library;

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Apple system colors per brightness.
@immutable
class AppleColors {
  const AppleColors._({
    required this.blue,
    required this.green,
    required this.orange,
    required this.red,
    required this.teal,
    required this.groupedBackground,
    required this.card,
    required this.elevated,
    required this.label,
    required this.secondaryLabel,
    required this.separator,
    required this.fill,
    required this.sidebar,
  });

  static const light = AppleColors._(
    blue: Color(0xFF1966FF),
    green: Color(0xFF34C759),
    orange: Color(0xFFFF9500),
    red: Color(0xFFFF3B30),
    teal: Color(0xFF30B0C7),
    groupedBackground: Color(0xFFF5F6FA),
    card: Color(0xFFFFFFFF),
    elevated: Color(0xFFFFFFFF),
    label: Color(0xFF1D1D1F),
    secondaryLabel: Color(0xFF6E6E73),
    separator: Color(0xFFD1D1D6),
    fill: Color(0xFFE9E9EE),
    sidebar: Color(0xFFFFFFFF),
  );

  static const dark = AppleColors._(
    blue: Color(0xFF0A84FF),
    green: Color(0xFF30D158),
    orange: Color(0xFFFF9F0A),
    red: Color(0xFFFF453A),
    teal: Color(0xFF40C8E0),
    groupedBackground: Color(0xFF000000),
    card: Color(0xFF1C1C1E),
    elevated: Color(0xFF2C2C2E),
    label: Color(0xFFF5F5F7),
    secondaryLabel: Color(0xFF98989D),
    separator: Color(0xFF38383A),
    fill: Color(0xFF2C2C2E),
    sidebar: Color(0xB81C1C1E),
  );

  final Color blue, green, orange, red, teal;
  final Color groupedBackground, card, elevated, label, secondaryLabel, separator, fill, sidebar;

  static AppleColors of(BuildContext context) =>
      ShadTheme.of(context).brightness == Brightness.dark ? dark : light;

  /// Semantic token (success | warning | danger | error | info | primary) → color; null otherwise.
  Color? semantic(String? token) => switch (token) {
        'success' => green,
        'warning' => orange,
        'danger' || 'error' => red,
        'info' || 'primary' => blue,
        _ => null,
      };
}

/// Hairline width (0.5 logical px; 1 device px on 2x screens).
const double kHairline = 0.5;

ShadColorScheme appleColorScheme(Brightness b) {
  final c = b == Brightness.dark ? AppleColors.dark : AppleColors.light;
  final dark = b == Brightness.dark;
  return ShadColorScheme(
    background: c.groupedBackground,
    foreground: c.label,
    card: c.card,
    cardForeground: c.label,
    popover: c.elevated,
    popoverForeground: c.label,
    primary: c.blue,
    primaryForeground: Colors.white,
    secondary: c.fill,
    secondaryForeground: c.label,
    muted: dark ? const Color(0xFF1C1C1E) : const Color(0xFFF5F5F7),
    mutedForeground: c.secondaryLabel,
    accent: dark ? const Color(0xFF3A3A3C) : const Color(0xFFE8E8ED),
    accentForeground: c.label,
    destructive: c.red,
    destructiveForeground: Colors.white,
    border: c.separator,
    input: dark ? const Color(0xFF48484A) : const Color(0xFFC7C7CC),
    ring: c.blue,
    selection: c.blue.withValues(alpha: dark ? 0.45 : 0.25),
    custom: {
      'success': c.green,
      'warning': c.orange,
      'info': c.teal,
      'sidebar': c.sidebar,
    },
  );
}

List<BoxShadow> appleShadow(Brightness b) => b == Brightness.dark
    ? const [BoxShadow(color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 4))]
    : const [
        BoxShadow(color: Color(0x0F000000), blurRadius: 1, offset: Offset(0, 0.5)),
        BoxShadow(color: Color(0x0D000000), blurRadius: 12, offset: Offset(0, 4)),
      ];

ShadThemeData appleTheme(Brightness b) {
  final cs = appleColorScheme(b);
  final c = b == Brightness.dark ? AppleColors.dark : AppleColors.light;
  const r10 = BorderRadius.all(Radius.circular(10));
  const r8 = BorderRadius.all(Radius.circular(8));
  const r14 = BorderRadius.all(Radius.circular(14));
  return ShadThemeData(
    brightness: b,
    colorScheme: cs,
    radius: r10,
    textTheme: ShadTextTheme(family: 'PingFangSC'),
    cardTheme: ShadCardTheme(
      radius: r8,
      backgroundColor: c.card,
      // no outline between cards: grouped background + spacing, not a hairline (README §19)
      border: ShadBorder.all(color: Color(0x00000000), width: 0, radius: r8),
      shadows: appleShadow(b),
    ),
    switchTheme: ShadSwitchTheme(
      checkedTrackColor: c.green,
      uncheckedTrackColor: b == Brightness.dark ? const Color(0xFF39393D) : const Color(0xFFE9E9EA),
      thumbColor: Colors.white,
      width: 46,
      height: 28,
    ),
    primaryDialogTheme: ShadDialogTheme(radius: r14, backgroundColor: c.elevated, shadows: appleShadow(b)),
    alertDialogTheme: ShadDialogTheme(radius: r14, backgroundColor: c.elevated, shadows: appleShadow(b)),
    sheetTheme: ShadSheetTheme(radius: r14, backgroundColor: c.elevated),
    popoverTheme: ShadPopoverTheme(shadows: appleShadow(b)),
  );
}
