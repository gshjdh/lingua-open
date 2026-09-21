import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_open/translation.dart';

void main() {
  test('only accepts HTTPS service roots', () {
    expect(() => LibreTranslateEngine.validateEndpoint('http://example.com'), throwsA(isA<TranslationFailure>()));
    expect(() => LibreTranslateEngine.validateEndpoint('https://example.com?key=x'), throwsA(isA<TranslationFailure>()));
    expect(LibreTranslateEngine.validateEndpoint('https://example.com/').scheme, 'https');
  });
}
