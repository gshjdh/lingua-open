import 'dart:convert';
import 'package:http/http.dart' as http;

class Language {
  final String code;
  final String name;
  final List<String> targets;
  const Language(this.code, this.name, this.targets);
  factory Language.fromJson(Map<String, dynamic> json) => Language(
    json['code'] as String, json['name'] as String,
    (json['targets'] as List? ?? []).cast<String>(),
  );
}

abstract interface class TranslationEngine {
  Future<List<Language>> languages();
  Future<String> translate(String text, String source, String target);
}

class TranslationFailure implements Exception {
  final String message;
  const TranslationFailure(this.message);
  @override
  String toString() => message;
}

class LibreTranslateEngine implements TranslationEngine {
  final http.Client client;
  final Uri base;
  final String apiKey;
  LibreTranslateEngine(this.client, String endpoint, {this.apiKey = ''})
      : base = validateEndpoint(endpoint);

  static Uri validateEndpoint(String endpoint) {
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw const TranslationFailure('请输入 HTTPS 服务根地址，不含密码、查询参数或片段。');
    }
    return uri;
  }

  Uri _url(String path) => base.replace(
    path: '${base.path.replaceFirst(RegExp(r'/+$'), '')}/$path',
  );

  dynamic _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TranslationFailure(switch (response.statusCode) {
        401 || 403 => '访问被拒绝，请检查 API 密钥和服务权限。',
        429 => '请求过于频繁，请稍后再试。',
        400 => '服务拒绝请求，请检查语言组合及文本长度。',
        _ => '翻译服务返回错误（${response.statusCode}）。',
      });
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const TranslationFailure('服务返回了无效数据，请确认地址指向 LibreTranslate。');
    }
  }

  @override
  Future<List<Language>> languages() async {
    final body = _decode(await client.get(_url('languages'))
        .timeout(const Duration(seconds: 20)));
    if (body is! List || body.isEmpty) {
      throw const TranslationFailure('服务没有提供可用语言。');
    }
    try {
      final result = body.map((item) => Language.fromJson(
          Map<String, dynamic>.from(item as Map))).toList();
      if (result.any((l) => l.code.isEmpty || l.code == 'auto') ||
          result.map((l) => l.code).toSet().length != result.length) {
        throw const FormatException();
      }
      return result;
    } catch (_) {
      throw const TranslationFailure('服务返回的语言列表格式无效。');
    }
  }

  @override
  Future<String> translate(String text, String source, String target) async {
    if (text.trim().isEmpty) throw const TranslationFailure('请先输入文本。');
    final body = _decode(await client.post(_url('translate'), body: {
      'q': text, 'source': source, 'target': target, 'format': 'text',
      if (apiKey.isNotEmpty) 'api_key': apiKey,
    }).timeout(const Duration(seconds: 45)));
    if (body is! Map || body['translatedText'] is! String) {
      throw const TranslationFailure('服务返回的译文格式无效。');
    }
    return body['translatedText'] as String;
  }
}
