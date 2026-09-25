import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/i18next_to_ios_widget_res.dart';

void main() {
  test('every app locale has complete iOS widget copy', () {
    // Arrange
    final sourceDirectory = Directory('lib/i18n');
    final localeCount = sourceDirectory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.i18next.json'))
        .length;

    // Act
    final translations = buildIosWidgetTranslations(sourceDirectory);

    // Assert
    expect(translations, hasLength(localeCount));
    for (final words in translations.values) {
      expect(words.keys, containsAll(widgetKeys));
      expect(words.values, everyElement(isNotEmpty));
      expect(words['iosWidgetFuture'], contains('{{duration}}'));
      expect(words['iosWidgetCountToday'], contains('{{count}}'));
    }
  });

  test('regional copy and intentional English fallback stay in sync', () {
    // Arrange
    final sourceDirectory = Directory('lib/i18n');

    // Act
    final translations = buildIosWidgetTranslations(sourceDirectory);

    // Assert
    expect(
      translations['pt-BR']!['iosWidgetNextIntake'],
      isNot(translations['pt']!['iosWidgetNextIntake']),
    );
    expect(
      translations['tok']!['iosWidgetNextIntake'],
      translations['en']!['iosWidgetNextIntake'],
    );
    expect(translations['fr']!['iosWidgetFuture'], contains('{{duration}}'));
    expect(
      translations['fr']!['iosWidgetCountToday'],
      translations['en']!['iosWidgetCountToday'],
    );
  });

  test('bundled iOS widget resource matches the translation sources', () {
    // Arrange
    final sourceDirectory = Directory('lib/i18n');
    final resource = File('ios/HrtWidget/WidgetTranslations.json');

    // Act
    final generated = buildIosWidgetTranslations(sourceDirectory);
    final bundled = jsonDecode(resource.readAsStringSync());

    // Assert
    expect(bundled, equals(generated));
  });
}
