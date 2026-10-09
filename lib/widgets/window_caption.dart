import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:window_manager/window_manager.dart' hide WindowCaption;

import '../core/i18n.dart';
import 'settings_dialog.dart';

/// Windows desktop only. Web and other desktops keep the native frame.
bool get kWindowsDesktop => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

const double kWindowCaptionHeight = 36;

/// Custom caption: drag to move, settings, minimize, maximize, close.
class WindowCaption extends StatefulWidget {
  const WindowCaption({super.key});

  @override
  State<WindowCaption> createState() => _WindowCaptionState();
}

class _WindowCaptionState extends State<WindowCaption> with WindowListener {
  bool _max = false;

  @override
  void initState() {
    super.initState();
    if (!kWindowsDesktop) return;
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _max = v);
    });
  }

  @override
  void dispose() {
    if (kWindowsDesktop) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _max = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _max = false);
  }

  Future<void> _toggleMax() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kWindowsDesktop) return const SizedBox.shrink();
    final t = ShadTheme.of(context);
    return Material(
      color: t.colorScheme.card,
      child: SizedBox(
        height: kWindowCaptionHeight,
        width: double.infinity,
        child: Row(children: [
          Expanded(
            child: DragToMoveArea(
              child: Padding(
                padding: const EdgeInsets.only(left: 14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(tr('LOONGS 平台'), style: t.textTheme.small.copyWith(fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ),
          _Btn(icon: LucideIcons.settings, tip: tr('设置'), onTap: () async => showSettingsDialog(context)),
          _Btn(icon: LucideIcons.minus, tip: tr('最小化'), onTap: () async => windowManager.minimize()),
          _Btn(
            icon: _max ? LucideIcons.copy : LucideIcons.square,
            tip: _max ? tr('还原') : tr('最大化'),
            onTap: _toggleMax,
          ),
          _Btn(icon: LucideIcons.x, tip: tr('关闭'), close: true, onTap: () async => windowManager.close()),
        ]),
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({required this.icon, required this.tip, required this.onTap, this.close = false});

  final IconData icon;
  final String tip;
  final Future<void> Function() onTap;
  final bool close;

  @override
  Widget build(BuildContext context) {
    final fg = ShadTheme.of(context).colorScheme.foreground;
    return Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(onTap()),
          child: ColoredBox(
            color: close ? const Color(0x00E81123) : Colors.transparent,
            child: SizedBox(
              width: 46,
              height: kWindowCaptionHeight,
              child: Center(child: Icon(icon, size: 14, color: fg)),
            ),
          ),
        ),
      ),
    );
  }
}
