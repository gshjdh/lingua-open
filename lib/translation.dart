import 'dart:convert';
import 'package:crypto/crypto.dart';
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

/// Tencent Cloud TMT TextTranslate API client using TC3-HMAC-SHA256.
/// SecretId/SecretKey remain in memory and are never persisted by this app.
class TencentCloudEngine implements TranslationEngine {
  static const _host = 'tmt.tencentcloudapi.com';
  static const _service = 'tmt';
  static const _version = '2018-03-21';
  static const _action = 'TextTranslate';
  final http.Client client;
  final String secretId;
  final String secretKey;
  final String region;

  TencentCloudEngine(this.client, {required this.secretId, required this.secretKey,
      this.region = 'ap-beijing'}) {
    if (secretId.trim().isEmpty || secretKey.trim().isEmpty) {
      throw const TranslationFailure('请填写腾讯云 SecretId 和 SecretKey。');
    }
  }

  static final _languages = <Language>[
    const Language('zh', '中文', []), const Language('en', 'English', []),
    const Language('ja', '日本語', []), const Language('ko', '한국어', []),
    const Language('fr', 'Français', []), const Language('de', 'Deutsch', []),
    const Language('es', 'Español', []), const Language('ru', 'Русский', []),
    const Language('pt', 'Português', []), const Language('it', 'Italiano', []),
    const Language('th', 'ไทย', []), const Language('vi', 'Tiếng Việt', []),
    const Language('id', 'Bahasa Indonesia', []), const Language('ms', 'Bahasa Melayu', []),
    const Language('tr', 'Türkçe', []), const Language('ar', 'العربية', []),
    const Language('hi', 'हिन्दी', []),
  ];

  @override
  Future<List<Language>> languages() async => _languages;

  List<int> _hmac(List<int> key, String value) =>
      Hmac(sha256, key).convert(utf8.encode(value)).bytes;
  String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  String _sha256(String value) => _hex(sha256.convert(utf8.encode(value)).bytes);

  String _authorization(String payload, int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true)
        .toIso8601String().substring(0, 10);
    const contentType = 'application/json; charset=utf-8';
    final canonicalHeaders = 'content-type:$contentType\nhost:$_host\n';
    final signedHeaders = 'content-type;host';
    final canonicalRequest = 'POST\n/\n\n$canonicalHeaders\n$signedHeaders\n${_sha256(payload)}';
    final credentialScope = '$date/$_service/tc3_request';
    final stringToSign = 'TC3-HMAC-SHA256\n$timestamp\n$credentialScope\n${_sha256(canonicalRequest)}';
    final secretDate = _hmac(utf8.encode('TC3$secretKey'), date);
    final secretService = _hmac(secretDate, _service);
    final secretSigning = _hmac(secretService, 'tc3_request');
    final signature = _hex(_hmac(secretSigning, stringToSign));
    return 'TC3-HMAC-SHA256 Credential=$secretId/$credentialScope, '
        'SignedHeaders=$signedHeaders, Signature=$signature';
  }

  @override
  Future<String> translate(String text, String source, String target) async {
    if (text.trim().isEmpty) throw const TranslationFailure('请先输入文本。');
    final payload = jsonEncode({
      'SourceText': text, 'Source': source == 'auto' ? 'auto' : source,
      'Target': target, 'ProjectId': 0,
    });
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final response = await client.post(Uri.https(_host, '/'), headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Host': _host, 'X-TC-Action': _action, 'X-TC-Version': _version,
      'X-TC-Region': region, 'X-TC-Timestamp': '$timestamp',
      'Authorization': _authorization(payload, timestamp),
    }, body: payload).timeout(const Duration(seconds: 45));
    dynamic body;
    try { body = jsonDecode(utf8.decode(response.bodyBytes)); }
    on FormatException { throw const TranslationFailure('腾讯云返回了无效数据。'); }
    final error = body is Map && body['Response'] is Map ? body['Response']['Error'] : null;
    if (response.statusCode < 200 || response.statusCode >= 300 || error != null) {
      final message = error is Map ? '${error['Code'] ?? '错误'}：${error['Message'] ?? '请求失败'}' : 'HTTP ${response.statusCode}';
      throw TranslationFailure('腾讯云翻译失败：$message');
    }
    final result = body is Map && body['Response'] is Map ? body['Response']['TargetText'] : null;
    if (result is! String) throw const TranslationFailure('腾讯云返回的译文格式无效。');
    return result;
  }
}
