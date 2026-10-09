import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../widgets/common.dart';
import '../page_desc.dart';
import '../render_api.dart';
import '../template.dart';
import 'unknown.dart';
import '../../core/i18n.dart';

/// Values + errors of one rendered form (or search bar).
class FormController extends ChangeNotifier {
  FormController([Map<String, dynamic>? initial]) : values = {...?initial};

  final Map<String, dynamic> values;
  final Map<String, String> errors = {};
  final Map<String, TextEditingController> _text = {};

  Object? operator [](String name) => values[name];

  void set(String name, Object? value) {
    values[name] = value;
    errors.remove(name);
    notifyListeners();
  }

  /// Replaces all values (record loaded / reset); text inputs follow.
  void reset(Map<String, dynamic> next) {
    values
      ..clear()
      ..addAll(next);
    errors.clear();
    for (final e in _text.entries) {
      e.value.text = _asText(values[e.key]);
    }
    notifyListeners();
  }

  void setErrors(Map<String, String> next) {
    errors
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  TextEditingController text(String name) => _text.putIfAbsent(name, () => TextEditingController(text: _asText(values[name])));

  static String _asText(Object? v) => switch (v) {
        null => '',
        Map m => const JsonEncoder.withIndent('  ').convert(m),
        List l => l.join(','),
        _ => '$v',
      };

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }
}

/// Shared per form: API access + option cache (one request per optionsApi URL).
/// [context] returns the current record / params (used by `props.excludeSubtreeOf`).
class FieldEnv {
  FieldEnv(this.api, {this.context});

  final RenderApi api;
  Map<String, dynamic> Function()? context;
  final Map<String, Future<List<OptionItem>>> _options = {};
  final Map<String, Future<List<OptionItem>>> _merged = {};

  /// Static `options` and / or `optionsApi` (static ones first, e.g. a `（顶级）` root before the
  /// API tree). treeSelect `props.excludeSubtreeOf: 'id'` drops the node whose value equals the
  /// record's `id` and all its descendants (a department cannot become its own parent).
  Future<List<OptionItem>> options(Json field) {
    final static = field['options'] is List ? OptionItem.listFrom(field['options']) : const <OptionItem>[];
    final api = asJson(field['optionsApi'])['api'] ?? field['optionsApi'];
    final excludeKey = asJson(field['props'])['excludeSubtreeOf'];
    final exclude = excludeKey is String ? context?.call()[excludeKey] : null;
    if (api is! String) return Future.value(excludeSubtree(static, exclude));
    final loaded = _options.putIfAbsent(api, () async {
      try {
        final data = await this.api.get(api);
        return OptionItem.listFrom(data is Map ? (data['list'] ?? data['options'] ?? const []) : data);
      } catch (_) {
        _options.remove(api);
        return const <OptionItem>[];
      }
    });
    if (static.isEmpty && exclude == null) return loaded;
    return _merged.putIfAbsent('${field['name']}|$api|$exclude', () async => excludeSubtree([...static, ...await loaded], exclude));
  }
}

/// Flattened tree options without the option [value] and the options nested below it.
List<OptionItem> excludeSubtree(List<OptionItem> options, Object? value) {
  if (value == null || value == '') return options;
  final out = <OptionItem>[];
  int? skipBelow;
  for (final o in options) {
    if (skipBelow != null) {
      if (o.depth > skipBelow) continue;
      skipBelow = null;
    }
    if (sameValue(o.value, value)) {
      skipBelow = o.depth;
      continue;
    }
    out.add(o);
  }
  return out;
}

/// Field state: editable, read-only (readonly / masked) — `hidden` never reaches the client.
bool fieldReadonly(Json f) => f['readonly'] == true || f['masked'] == true;

typedef FieldBuilder = Widget Function(BuildContext context, Json field, FormController form, FieldEnv env, {bool dense});

const Set<String> _textual = {'text', 'password', 'textarea', 'number', 'money', 'date', 'datetime', 'time', 'dateRange', 'json'};

Widget _textInput(BuildContext context, Json f, FormController form, FieldEnv env, {bool dense = false}) {
  final name = '${f['name']}';
  final comp = '${f['component']}';
  final ro = fieldReadonly(f) || comp == 'json';
  final numeric = comp == 'number' || comp == 'money';
  final hint = switch (comp) {
    'date' => 'yyyy-MM-dd',
    'datetime' => 'yyyy-MM-dd HH:mm:ss',
    'time' => 'HH:mm',
    'dateRange' => 'yyyy-MM-dd ~ yyyy-MM-dd',
    _ => null,
  };
  return ShadInput(
    key: ValueKey('field-$name'),
    controller: form.text(name),
    readOnly: ro,
    enabled: !ro,
    obscureText: comp == 'password',
    maxLines: comp == 'textarea' || comp == 'json' ? 4 : 1,
    minLines: comp == 'textarea' || comp == 'json' ? 2 : null,
    inputFormatters: numeric ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))] : null,
    placeholder: Text(dense ? '${f['label'] ?? name}' : '${f['placeholder'] ?? hint ?? ''}'),
    onChanged: (v) => form.set(name, numeric ? (v.trim().isEmpty ? null : num.tryParse(v.trim()) ?? v) : v),
  );
}

/// Single select over options (also treeSelect / cascader: tree flattened with indentation).
class _SelectField extends StatelessWidget {
  const _SelectField(this.f, this.form, this.env, {this.dense = false});

  final Json f;
  final FormController form;
  final FieldEnv env;
  final bool dense;

  static const _all = '\u0000all';

  @override
  Widget build(BuildContext context) {
    final name = '${f['name']}';
    return FutureBuilder<List<OptionItem>>(
      future: env.options(f),
      builder: (context, snap) {
        final opts = snap.data ?? const <OptionItem>[];
        final current = form[name];
        final selected = opts.where((o) => sameValue(o.value, current)).firstOrNull;
        final items = <(String, String)>[
          if (dense) (_all, tr('全部{label}', {'label': f['label'] ?? ''})),
          for (final o in opts) ('${o.value}', '${'　' * o.depth}${o.label}'),
        ];
        return OptionSelect<String>(
          key: ValueKey('field-$name-${opts.length}-${selected?.value}'),
          options: items,
          value: selected == null ? (dense ? _all : null) : '${selected.value}',
          enabled: !fieldReadonly(f) && snap.connectionState == ConnectionState.done,
          placeholder: dense ? '${f['label'] ?? name}' : '${f['placeholder'] ?? tr('请选择')}',
          onChanged: (v) => form.set(name, v == null || v == _all ? null : opts.firstWhere((o) => '${o.value}' == v).value),
        );
      },
    );
  }
}

/// Multiple choice: checkbox list (select multiple / checkbox with options).
class _MultiField extends StatelessWidget {
  const _MultiField(this.f, this.form, this.env);

  final Json f;
  final FormController form;
  final FieldEnv env;

  @override
  Widget build(BuildContext context) {
    final name = '${f['name']}';
    final ro = fieldReadonly(f);
    return FutureBuilder<List<OptionItem>>(
      future: env.options(f),
      builder: (context, snap) {
        final opts = snap.data ?? const <OptionItem>[];
        final cur = [...((form[name] as List?) ?? const [])];
        if (snap.connectionState != ConnectionState.done) return SizedBox(height: 24, child: Text(tr('加载中…')));
        if (opts.isEmpty) return Text(tr('无可选项'), style: ShadTheme.of(context).textTheme.muted);
        return Wrap(spacing: 12, runSpacing: 6, children: [
          for (final o in opts)
            Builder(builder: (context) {
              final on = cur.any((v) => sameValue(v, o.value));
              void toggle(bool next) {
                final list = [...cur]..removeWhere((v) => sameValue(v, o.value));
                if (next) list.add(o.value);
                form.set(name, list);
              }

              return MouseRegion(
                cursor: ro ? SystemMouseCursors.basic : SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: ro ? null : () => toggle(!on),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    ShadCheckbox(value: on, enabled: !ro, onChanged: toggle),
                    const SizedBox(width: 4),
                    Text(o.label),
                  ]),
                ),
              );
            }),
        ]);
      },
    );
  }
}

class _RadioField extends StatelessWidget {
  const _RadioField(this.f, this.form, this.env);

  final Json f;
  final FormController form;
  final FieldEnv env;

  @override
  Widget build(BuildContext context) {
    final name = '${f['name']}';
    return FutureBuilder<List<OptionItem>>(
      future: env.options(f),
      builder: (context, snap) {
        final opts = snap.data ?? const <OptionItem>[];
        final current = opts.where((o) => sameValue(o.value, form[name])).firstOrNull;
        return ShadRadioGroup<String>(
          key: ValueKey('field-$name-${opts.length}-${current?.value}'),
          initialValue: current == null ? null : '${current.value}',
          enabled: !fieldReadonly(f),
          axis: Axis.horizontal,
          spacing: 16,
          onChanged: (v) => form.set(name, opts.firstWhere((o) => '${o.value}' == v).value),
          items: [for (final o in opts) ShadRadio<String>(value: '${o.value}', label: Text(o.label))],
        );
      },
    );
  }
}

Widget _switch(BuildContext context, Json f, FormController form, FieldEnv env, {bool dense = false}) {
  final name = '${f['name']}';
  final v = form[name] ?? f['default'];
  final numeric = v is num;
  return Align(
    alignment: Alignment.centerLeft,
    child: ShadSwitch(
      value: sameValue(v, true),
      enabled: !fieldReadonly(f),
      onChanged: (on) => form.set(name, numeric ? (on ? 1 : 0) : on),
    ),
  );
}

/// Field renderers (RENDER.md §7 输入). Unknown components → [UnknownComponent].
final Map<String, FieldBuilder> fieldRegistry = {
  for (final c in _textual) c: _textInput,
  'select': (ctx, f, form, env, {bool dense = false}) =>
      f['multiple'] == true && !dense ? _MultiField(f, form, env) : _SelectField(f, form, env, dense: dense),
  'treeSelect': (ctx, f, form, env, {bool dense = false}) => _SelectField(f, form, env, dense: dense),
  'cascader': (ctx, f, form, env, {bool dense = false}) => _SelectField(f, form, env, dense: dense),
  'radio': (ctx, f, form, env, {bool dense = false}) => dense ? _SelectField(f, form, env, dense: true) : _RadioField(f, form, env),
  'checkbox': (ctx, f, form, env, {bool dense = false}) => f['options'] != null || f['optionsApi'] != null
      ? _MultiField(f, form, env)
      : _switch(ctx, f, form, env),
  'switch': _switch,
};

Widget buildField(BuildContext context, Json field, FormController form, FieldEnv env, {bool dense = false}) {
  final b = fieldRegistry['${field['component']}'];
  if (b == null) return UnknownComponent(tr('字段'), '${field['component']}');
  return b(context, field, form, env, dense: dense);
}

/// Client-side check of `required` + `rules` (the server validates again; 422 errors are shown per field).
String? validateField(Json f, Object? v) {
  if (fieldReadonly(f)) return null;
  final empty = v == null || (v is String && v.trim().isEmpty) || (v is List && v.isEmpty);
  if (f['required'] == true && empty) return tr('请填写{label}', {'label': f['label'] ?? ''});
  if (empty) return null;
  final s = '$v';
  for (final r in asJsonList(f['rules'])) {
    final value = r['value'];
    final custom = r['message'] as String?;
    String? err;
    switch ('${r['rule']}') {
      case 'regex':
        try {
          if (!RegExp('$value').hasMatch(s)) err = tr('格式不正确');
        } catch (_) {}
      case 'email':
        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) err = tr('邮箱格式不正确');
      case 'minLength':
        if (s.runes.length < (value as num).toInt()) err = tr('至少 {n} 个字符', {'n': value});
      case 'maxLength':
        if (s.runes.length > (value as num).toInt()) err = tr('最多 {n} 个字符', {'n': value});
      case 'min':
        if ((num.tryParse(s) ?? double.negativeInfinity) < (value as num)) err = tr('不能小于 {n}', {'n': value});
      case 'max':
        if ((num.tryParse(s) ?? double.infinity) > (value as num)) err = tr('不能大于 {n}', {'n': value});
    }
    if (err != null) return custom ?? err;
  }
  return null;
}

/// Visible in the current form state (`visibleWhen` against the other values).
bool fieldVisible(Json f, Map<String, dynamic> values) => f['visibleWhen'] == null || matchCondition(f['visibleWhen'], values);
