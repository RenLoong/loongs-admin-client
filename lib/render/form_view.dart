import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/api.dart';
import '../widgets/common.dart';
import 'action_runner.dart';
import 'components/fields.dart';
import 'page_desc.dart';
import 'render_api.dart';
import 'template.dart';
import '../core/i18n.dart';

/// Form page (RENDER.md §6.2): one description for create and edit. With all `load` placeholders
/// present in [params] the record is loaded and `submit.update` is used, otherwise defaults +
/// `submit.create`. Read-only / masked fields are shown but never submitted. In create mode params
/// named like a field pre-fill it (R4, e.g. `parent_id` of 新增下级).
class FormView extends ConsumerStatefulWidget {
  const FormView({super.key, required this.desc, this.params = const {}, this.mode = 'page', this.onClose});

  final PageDesc desc;
  final Map<String, dynamic> params;

  /// dialog | drawer | page
  final String mode;
  final void Function(bool saved)? onClose;

  @override
  ConsumerState<FormView> createState() => _FormViewState();
}

class _FormViewState extends ConsumerState<FormView> {
  late final FormController _form = FormController(_editing ? _defaults() : {..._defaults(), ..._prefill()});
  late final FieldEnv _env = FieldEnv(ref.read(renderApiProvider), context: () => _data);
  Json _record = const {};
  bool _loading = false;
  bool _saving = false;
  String? _loadError;

  Json get _body => widget.desc.body;

  List<Json> get _sections {
    final s = asJsonList(_body['sections']);
    if (s.isNotEmpty) return s;
    return [
      {'fields': _body['fields'] ?? const []},
    ];
  }

  List<Json> get _fields => [for (final s in _sections) ...asJsonList(s['fields'])];

  String? get _loadPath => _body['load'] is String ? fillPath(_body['load'] as String, widget.params) : null;

  bool get _editing => _loadPath != null;

  Json get _data => {...widget.params, ..._record, ..._form.values};

  Map<String, dynamic> _defaults() => {
        for (final f in _fields)
          if (f.containsKey('default')) '${f['name']}': f['default'],
      };

  /// Create mode: route / openForm params named like a field pre-fill it (新增下级 → parent_id).
  /// Params arrive as strings (URL query); integer-looking values become ints.
  Map<String, dynamic> _prefill() {
    final names = {for (final f in _fields) '${f['name']}'};
    return {
      for (final e in widget.params.entries)
        if (names.contains(e.key) && e.value != null && '${e.value}' != '')
          e.key: e.value is String && RegExp(r'^-?\d{1,15}$').hasMatch(e.value as String) ? int.parse(e.value as String) : e.value,
    };
  }

  @override
  void initState() {
    super.initState();
    _form.addListener(_changed);
    if (_editing) _load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _form.removeListener(_changed);
    _form.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final r = await ref.read(renderApiProvider).get(_loadPath!);
      _record = asJson(r);
      _form.reset({..._defaults(), for (final f in _fields) if (_record.containsKey(f['name'])) '${f['name']}': _record[f['name']]});
    } on ApiException catch (e) {
      _loadError = e.message;
    }
    if (mounted) setState(() => _loading = false);
  }

  Json? get _submitSpec {
    final s = asJson(_body['submit']);
    if (s['api'] is String) return s;
    final create = s['create'], update = s['update'];
    return asJson(_editing ? (update ?? create) : (create ?? update));
  }

  Future<bool> _submit(Json action) async {
    final spec = _submitSpec;
    if (spec == null || spec['api'] is! String) {
      showToast(context, tr('表单未配置提交接口'), error: true);
      return false;
    }
    final errors = <String, String>{};
    final body = <String, dynamic>{};
    for (final f in _fields) {
      final name = '${f['name']}';
      if (!fieldVisible(f, _form.values) || fieldReadonly(f) || f['component'] == 'json') continue;
      if (!fieldRegistry.containsKey('${f['component']}')) continue; // unknown component: shown as placeholder, never sent
      final v = _form[name];
      final err = validateField(f, v);
      if (err != null) errors[name] = err;
      if (v == null) continue; // untouched optional field (no default, not in the loaded record)
      body[name] = v is String && f['component'] != 'password' ? v.trim() : v;
    }
    if (errors.isNotEmpty) {
      _form.setErrors(errors);
      return false;
    }
    final api = fillPath(spec['api'] as String, _data);
    if (api == null) {
      showToast(context, tr('缺少参数，无法提交'), error: true);
      return false;
    }
    setState(() => _saving = true);
    var ok = false;
    try {
      await ref.read(renderApiProvider).send('${spec['method'] ?? 'POST'}', api, body: body);
      ok = true;
      if (mounted) showToast(context, '${action['message'] ?? tr('已保存')}');
    } on ApiException catch (e) {
      final fieldErrors = {for (final en in e.errors.entries) if (en.value.isNotEmpty) en.key: en.value.first};
      _form.setErrors(fieldErrors);
      if (mounted) {
        final details = fieldErrors.isEmpty ? '' : '：${fieldErrors.values.join('；')}';
        showToast(context, '${e.message}$details', error: true);
      }
    }
    if (!mounted) return ok;
    setState(() => _saving = false);
    if (ok) {
      switch (action['then'] ?? 'close') {
        case 'close':
          widget.onClose?.call(true);
        case 'refresh':
          if (_editing) _load();
      }
    }
    return ok;
  }

  Widget _field(BuildContext context, Json f) {
    final t = ShadTheme.of(context);
    final name = '${f['name']}';
    final err = _form.errors[name];
    final hint = f['masked'] == true ? tr('脱敏显示，无权修改') : (f['readonly'] == true ? tr('只读') : null);
    final help = [if (f['help'] != null) '${f['help']}', ?hint].join(' · ');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text.rich(TextSpan(children: [
        if (f['required'] == true) TextSpan(text: '* ', style: TextStyle(color: t.colorScheme.destructive)),
        TextSpan(text: '${f['label'] ?? name}'),
      ]), style: t.textTheme.small),
      const SizedBox(height: 6),
      buildField(context, f, _form, _env),
      if (err != null)
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(err, style: t.textTheme.small.copyWith(color: t.colorScheme.destructive, fontWeight: FontWeight.normal))),
      if (err == null && help.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(help, style: t.textTheme.muted)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_loadError!),
          const SizedBox(height: 8),
          ShadButton.outline(onPressed: _load, child: Text(tr('重试'))),
        ]),
      );
    }
    final t = ShadTheme.of(context);
    final columns = ((_body['columns'] as num?)?.toInt() ?? 1).clamp(1, 4);
    final runner = ActionRunner(
      context: context,
      ref: ref,
      onClose: () => widget.onClose?.call(false),
      onSubmit: _submit,
      onRefresh: _editing ? _load : null,
    );
    final actions = asJsonList(_body['actions']).isEmpty
        ? <Json>[
            {'label': tr('保存'), 'action': 'submit', 'primary': true, 'then': 'close'},
            {'label': tr('取消'), 'action': 'close'},
          ]
        : asJsonList(_body['actions']);
    final form = LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth.isFinite ? box.maxWidth : 560.0;
      const gap = 16.0;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        for (final s in _sections) ...[
          if (s['title'] != null)
            Padding(padding: const EdgeInsets.only(top: 8, bottom: 8), child: Text('${s['title']}', style: t.textTheme.large)),
          Wrap(spacing: gap, runSpacing: 12, children: [
            for (final f in asJsonList(s['fields']))
              if (fieldVisible(f, _form.values))
                SizedBox(
                  width: ((w + gap) * (((f['span'] as num?)?.toInt() ?? (24 ~/ columns)).clamp(1, 24) / 24) - gap).clamp(120.0, w),
                  child: _field(context, f),
                ),
          ]),
        ],
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          for (final a in actions)
            if (actionVisible(a, _data))
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: actionButton(a, _saving ? null : () => runner.run(a, _data)),
              ),
        ]),
      ]);
    });
    if (widget.mode != 'page') return form;
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PageHeader(title: widget.desc.title),
        ConstrainedBox(constraints: BoxConstraints(maxWidth: columns > 1 ? 960 : 560), child: form),
      ]),
    );
  }
}
