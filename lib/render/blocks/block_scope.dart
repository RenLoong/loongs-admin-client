import 'dart:async';

import 'package:flutter/widgets.dart';

import '../page_desc.dart';

/// Refresh signal of one dashboard / detail page: `refresh()` reloads every block,
/// `refresh('stat_admins')` only the block with that id (RENDER.md §5.3 refresh `target`).
class RefreshBus extends ChangeNotifier {
  int generation = 0;

  /// Target of the last refresh; null = everything.
  String? target;

  void refresh([String? target]) {
    generation++;
    this.target = target;
    notifyListeners();
  }
}

/// Loads block APIs for one page and shares in-flight / completed requests by resolved path, so
/// four stat blocks on `/stats` make one request. A request is reused while its generation is not
/// older than the asked one (`RefreshBus.generation`); [force] always asks again (timers).
class BlockDataLoader {
  BlockDataLoader(this._fetch);

  final Future<dynamic> Function(String path) _fetch;
  final Map<String, (int, Future<dynamic>)> _cache = {};

  /// Requests actually sent (tests / diagnostics).
  int requests = 0;

  Future<dynamic> load(String path, {int generation = 0, bool force = false}) {
    final hit = _cache[path];
    if (hit != null && !force && hit.$1 >= generation) return hit.$2;
    requests++;
    final f = _fetch(path);
    _cache[path] = (generation, f);
    // Failed requests are not kept: the retry button / next refresh asks again.
    f.then((_) {}, onError: (Object _) {
      if (identical(_cache[path]?.$2, f)) _cache.remove(path);
    });
    return f;
  }

  void clear() => _cache.clear();
}

/// Data context (record ∪ route params) + refresh bus + loader shared by the blocks of a page.
class BlockScope extends InheritedWidget {
  const BlockScope({super.key, required this.data, required this.bus, required this.loader, required this.onAction, required super.child});

  /// `{field}` values for block APIs / texts (detail record, route params).
  final Json data;
  final RefreshBus bus;
  final BlockDataLoader loader;

  /// Runs an action (shortcuts, …) in the page's context.
  final Future<bool> Function(Json action, Json data) onAction;

  static BlockScope of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<BlockScope>();
    assert(s != null, 'blocks must be built inside a BlockScope');
    return s!;
  }

  @override
  bool updateShouldNotify(BlockScope old) => old.data != data || old.bus != bus || old.loader != loader;
}
