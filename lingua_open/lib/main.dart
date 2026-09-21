import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'translation.dart';

void main() => runApp(const LinguaApp());

class LinguaApp extends StatelessWidget {
  const LinguaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Lingua Open', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xff176B61)),
    darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xff176B61)),
    home: const TranslatorPage(),
  );
}

class TranslatorPage extends StatefulWidget {
  const TranslatorPage({super.key});
  @override
  State<TranslatorPage> createState() => _TranslatorPageState();
}

class _TranslatorPageState extends State<TranslatorPage> {
  final _text = TextEditingController();
  final _client = http.Client();
  SharedPreferences? _prefs;
  LibreTranslateEngine? _engine;
  List<Language> _languages = [];
  List<Map<String, dynamic>> _history = [];
  String _endpoint = '', _key = '', _source = 'auto', _target = '';
  String _result = '', _error = '';
  bool _ready = false, _busy = false, _remember = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final records = jsonDecode(prefs.getString('history') ?? '[]');
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _endpoint = prefs.getString('endpoint') ?? '';
        _remember = prefs.getBool('remember') ?? false;
        if (records is List) {
          _history = records.whereType<Map>().where((e) =>
            ['input', 'output', 'source', 'target'].every((k) => e[k] is String))
            .take(50).map((e) => Map<String, dynamic>.from(e)).toList();
        }
      });
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取本地记录，仍可配置服务进行翻译。');
    } finally {
      if (mounted) setState(() => _ready = true);
    }
  }

  void _fail(Object error) {
    if (!mounted) return;
    setState(() => _error = error is TranslationFailure ? error.message :
      error is TimeoutException ? '请求超时，请稍后重试。' : '连接失败，请检查网络和服务地址。');
  }

  Future<void> _settings() async {
    final address = TextEditingController(text: _endpoint);
    final secret = TextEditingController(text: _key);
    String? validation;
    final accepted = await showDialog<bool>(context: context, builder: (context) =>
      StatefulBuilder(builder: (context, update) => AlertDialog(
        title: const Text('翻译服务'),
        content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('接入你选择的 LibreTranslate 服务。点击连接会读取语言列表；点击翻译会将原文发送至该服务。'),
            const SizedBox(height: 16),
            TextField(controller: address, decoration: InputDecoration(
              labelText: 'HTTPS 服务根地址', hintText: 'https://translate.example.com',
              errorText: validation)),
            const SizedBox(height: 12),
            TextField(controller: secret, obscureText: true, autocorrect: false,
              enableSuggestions: false, decoration: const InputDecoration(
                labelText: 'API 密钥（服务需要时填写）')),
            const SizedBox(height: 12),
            const Text('密钥仅保留在当前会话，重启后需重新填写。服务可能收费。'),
          ],
        ))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () {
            try { LibreTranslateEngine.validateEndpoint(address.text); }
            catch (e) { update(() => validation = e.toString()); return; }
            Navigator.pop(context, true);
          }, child: const Text('连接')),
        ],
      )),
    );
    final endpoint = address.text.trim(), key = secret.text.trim();
    // Controllers are disposed after the dialog's closing transition.
    Future<void>.delayed(const Duration(seconds: 1), () { address.dispose(); secret.dispose(); });
    if (accepted != true || !mounted) return;
    setState(() { _busy = true; _error = ''; });
    try {
      final engine = LibreTranslateEngine(_client, endpoint, apiKey: key);
      final languages = await engine.languages();
      if (!mounted) return;
      setState(() {
        _engine = engine; _endpoint = endpoint; _key = key; _languages = languages;
        _source = 'auto';
        _target = languages.any((l) => l.code == 'zh') ? 'zh' : languages.first.code;
        _result = '';
      });
      try {
        if (_prefs != null && !await _prefs!.setString('endpoint', endpoint)) {
          throw StateError('write failed');
        }
      } catch (_) { if (mounted) setState(() => _error = '已连接，但服务地址未能保存。'); }
    } catch (e) { _fail(e); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  List<Language> get _targets {
    if (_source == 'auto') return _languages;
    final allowed = _languages.firstWhere((l) => l.code == _source).targets;
    return allowed.isEmpty ? _languages : _languages.where((l) => allowed.contains(l.code)).toList();
  }

  void _changeSource(String value) {
    setState(() {
      _source = value;
      final targets = _targets;
      if (!targets.any((l) => l.code == _target)) _target = targets.isEmpty ? '' : targets.first.code;
      _result = '';
    });
  }

  Future<void> _translate() async {
    if (_busy || _engine == null || _target.isEmpty || _text.text.trim().isEmpty) return;
    final input = _text.text, source = _source, target = _target;
    setState(() { _busy = true; _error = ''; _result = ''; });
    try {
      final result = await _engine!.translate(input, source, target);
      if (!mounted) return;
      setState(() {
        _result = result;
        if (_remember) {
          _history.insert(0, {'input': input, 'output': result, 'source': source, 'target': target});
          _history = _history.take(50).toList();
        }
      });
      if (_remember) await _saveHistory();
    } catch (e) { _fail(e); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _saveHistory() async {
    try {
      if (_prefs == null || !await _prefs!.setString('history', jsonEncode(_history))) {
        throw StateError('write failed');
      }
    } catch (_) { if (mounted) setState(() => _error = '本地历史记录保存失败。'); }
  }

  Future<void> _toggleHistory(bool enabled) async {
    setState(() { _busy = true; _remember = enabled; });
    try {
      if (_prefs == null || !await _prefs!.setBool('remember', enabled)) throw StateError('write failed');
    } catch (_) {
      if (mounted) setState(() { _remember = false; _error = '历史记录设置保存失败，已关闭记录。'; });
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('清空历史记录？'), content: const Text('将删除此设备上保存的全部翻译记录。'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('清空'))],
    ));
    if (confirmed != true || !mounted) return;
    setState(() { _busy = true; _history.clear(); });
    await _saveHistory();
    if (mounted) setState(() => _busy = false);
  }

  Widget _languagePicker(String value, List<Language> languages, String label,
      ValueChanged<String> changed, {bool auto = false}) => DropdownButtonFormField<String>(
    value: value.isEmpty ? null : value, isExpanded: true,
    decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    items: [if (auto) const DropdownMenuItem(value: 'auto', child: Text('自动识别')),
      ...languages.map((l) => DropdownMenuItem(value: l.code, child: Text('${l.name} (${l.code})', overflow: TextOverflow.ellipsis)))],
    onChanged: _busy || _engine == null ? null : (v) { if (v != null) changed(v); },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Lingua Open · 开源翻译'), actions: [
      IconButton(tooltip: '配置翻译服务', onPressed: !_ready || _busy ? null : _settings, icon: const Icon(Icons.settings_outlined)),
    ]),
    body: !_ready ? const Center(child: CircularProgressIndicator()) : Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1080),
      child: ListView(padding: const EdgeInsets.all(20), children: [
        Text('让语言不再成为距离', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(_engine == null ? '先配置翻译服务，再开始多语言互译。' : '当前服务：$_endpoint'),
        if (_engine == null) Align(alignment: Alignment.centerLeft, child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: FilledButton.icon(onPressed: _busy ? null : _settings,
            icon: const Icon(Icons.link), label: const Text('配置并连接')))),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: _languagePicker(_source, _languages, '原文语言', _changeSource, auto: true)),
          const SizedBox(width: 12),
          Expanded(child: _languagePicker(_target, _targets, '目标语言', (v) => setState(() { _target = v; _result = ''; }))),
        ]),
        const SizedBox(height: 20),
        LayoutBuilder(builder: (context, size) {
          final input = TextField(controller: _text, readOnly: _busy, maxLength: 5000,
            minLines: 7, maxLines: 12, onChanged: (_) => setState(() => _result = ''),
            decoration: const InputDecoration(labelText: '输入原文', alignLabelWithHint: true, border: OutlineInputBorder()));
          final output = Container(padding: const EdgeInsets.all(16), constraints: const BoxConstraints(minHeight: 210),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [const Expanded(child: Text('译文')), IconButton(tooltip: '复制译文',
                onPressed: _result.isEmpty ? null : () async {
                  try {
                    await Clipboard.setData(ClipboardData(text: _result));
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('译文已复制')));
                  } catch (_) { if (mounted) setState(() => _error = '复制失败，请手动选择译文复制。'); }
                }, icon: const Icon(Icons.copy_outlined))]),
              SelectableText(_result.isEmpty ? '翻译结果会显示在这里' : _result),
            ]));
          return size.maxWidth >= 720 ? Row(crossAxisAlignment: CrossAxisAlignment.start,
            children: [Expanded(child: input), const SizedBox(width: 20), Expanded(child: output)]) :
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [input, const SizedBox(height: 12), output]);
        }),
        const SizedBox(height: 12),
        if (_busy) const LinearProgressIndicator(),
        if (_error.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(_error, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        Align(alignment: Alignment.centerRight, child: FilledButton.icon(
          onPressed: _busy || _engine == null || _target.isEmpty || _text.text.trim().isEmpty ? null : _translate,
          icon: const Icon(Icons.translate), label: const Text('翻译'))),
        const Divider(height: 40),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('保存本地历史记录'),
          subtitle: const Text('默认关闭；开启后保留最近 50 条。关闭不会删除已有记录。记录未加密。'),
          value: _remember, onChanged: _busy ? null : _toggleHistory),
        Row(children: [Expanded(child: Text('历史记录（${_history.length}）')),
          TextButton(onPressed: _busy || _history.isEmpty ? null : _clearHistory, child: const Text('清空'))]),
        ..._history.map((record) => Card(child: ExpansionTile(
          title: Text(record['input'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${record['source']} → ${record['target']}'),
          childrenPadding: const EdgeInsets.all(16), expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [SelectableText(record['input'] as String), const Divider(), SelectableText(record['output'] as String)],
        ))),
      ]),
    )),
  );

  @override
  void dispose() { _text.dispose(); _client.close(); super.dispose(); }
}
