import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import 'ui_settings.dart';

Future<void> showSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x73000000),
    builder: (context) => const SettingsDialog(),
  );
}

/// Settings sheet: left nav + grouped rows (language and appearance live here, not in the sidebar).
class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final c = AppleColors.of(context);
    final dark = t.brightness == Brightness.dark;
    return Dialog(
      backgroundColor: dark ? c.elevated : Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 480),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: 180,
              color: dark ? const Color(0xFF161618) : const Color(0xFFF5F5F7),
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _NavItem(label: tr('通用'), icon: LucideIcons.settings, selected: true),
              ]),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 16, 16, 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Text(tr('通用'), style: t.textTheme.h4.copyWith(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    ShadIconButton.ghost(
                      icon: const Icon(LucideIcons.x, size: 16),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ]),
                  const SizedBox(height: 22),
                  Text(tr('外观'), style: t.textTheme.small.copyWith(color: c.secondaryLabel, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.separator.withValues(alpha: dark ? 0.6 : 1)),
                    ),
                    child: Column(children: [
                      _Row(label: tr('主题'), child: const ThemeModeSwitch()),
                      Divider(height: 1, thickness: 0.5, color: c.separator.withValues(alpha: 0.7)),
                      _Row(label: tr('语言'), child: const LanguageSwitch()),
                    ]),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.label, required this.icon, required this.selected});

  final String label;
  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final c = AppleColors.of(context);
    final dark = t.brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? (dark ? const Color(0xFF2C2C2E) : Colors.white) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(children: [
          Icon(icon, size: 15, color: selected ? c.label : c.secondaryLabel),
          const SizedBox(width: 8),
          Text(label, style: t.textTheme.small.copyWith(fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
        ]),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Text(label, style: t.textTheme.small),
        const Spacer(),
        child,
      ]),
    );
  }
}
