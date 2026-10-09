/// Registered custom pages (RENDER.md §9): `page_type: custom` descriptions carry
/// `body: {component, config}`; the client looks the component up here. Unregistered components
/// degrade to [UnknownComponent] (never throws). Custom pages are the only hand-written P1 pages
/// left after R4 (e.g. `role-permission-editor`); every other page is rendered from its description.
library;

import 'package:flutter/material.dart';

import 'components/unknown.dart';
import 'page_desc.dart';
import 'template.dart';
import '../core/i18n.dart';

/// What a custom page gets: its description, the backend `config` (with `{param}` placeholders
/// filled from [params] where a whole string is a template), the route / openForm params, the host
/// mode (`page` | `dialog` | `drawer`) and [close] (`saved: true` refreshes the opener's table).
class CustomPageContext {
  const CustomPageContext({required this.desc, required this.params, this.mode = 'page', this.onClose});

  final PageDesc desc;
  final Map<String, dynamic> params;
  final String mode;
  final void Function(bool saved)? onClose;

  String get component => '${desc.body['component'] ?? ''}';

  /// Raw backend config (no placeholders filled).
  Json get rawConfig => asJson(desc.body['config']);

  /// Config string [key] as an API path with params filled; null when missing or a placeholder has no value.
  String? path(String key) {
    final v = rawConfig[key];
    return v is String ? fillPath(v, params) : null;
  }

  void close(bool saved) => onClose?.call(saved);
}

typedef CustomPageBuilder = Widget Function(BuildContext context, CustomPageContext page);

final Map<String, CustomPageBuilder> _registry = {};

/// Registers [builder] for custom component [name] (call once at startup; re-registering replaces).
void registerCustomPage(String name, CustomPageBuilder builder) => _registry[name] = builder;

/// Removes a registration (tests).
void unregisterCustomPage(String name) => _registry.remove(name);

bool isCustomPageRegistered(String name) => _registry.containsKey(name);

Set<String> get registeredCustomPages => {..._registry.keys};

/// Builds the custom page of [desc] (type `custom`) or an [UnknownComponent] placeholder.
Widget buildCustomPage(BuildContext context, PageDesc desc, {Map<String, dynamic> params = const {}, String mode = 'page', void Function(bool saved)? onClose}) {
  final page = CustomPageContext(desc: desc, params: params, mode: mode, onClose: onClose);
  final b = _registry[page.component];
  if (b == null) return Center(child: UnknownComponent(tr('页面'), 'custom:${page.component}'));
  return KeyedSubtree(key: ValueKey('custom-${page.component}'), child: b(context, page));
}
