import 'dart:convert';
import 'dart:io';

const _sourceDirectory = 'lib/i18n';
const _sourceExtension = '.i18next.json';
const _outputFile = 'ios/HrtWidget/WidgetTranslations.json';

const widgetKeys = [
  'HrtCounterDescription',
  'iosWidgetNextIntake',
  'iosWidgetIntakeDue',
  'iosWidgetDue',
  'iosWidgetLate',
  'iosWidgetNoPlan',
  'iosWidgetNoSchedule',
  'iosWidgetNow',
  'iosWidgetFuture',
  'iosWidgetPast',
];

void main() {
  final translations = buildIosWidgetTranslations(Directory(_sourceDirectory));
  File(_outputFile).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(translations)}\n',
  );
  stdout.writeln(
      'Generated iOS widget copy for ${translations.length} locale(s).');
}

Map<String, Map<String, String>> buildIosWidgetTranslations(
  Directory sourceDirectory,
) {
  final sources = <String, Map<String, dynamic>>{};
  for (final file in sourceDirectory.listSync().whereType<File>()) {
    final name = file.uri.pathSegments.last;
    if (!name.endsWith(_sourceExtension)) continue;
    final locale = name.substring(0, name.length - _sourceExtension.length);
    sources[locale] =
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  final english = sources['en'];
  if (english == null) throw StateError('Missing English widget translations');

  final translations = <String, Map<String, String>>{};
  for (final locale in sources.keys.toList()..sort()) {
    final source = sources[locale]!;
    final strings = <String, String>{};
    for (final key in widgetKeys) {
      final value = source[key] ?? english[key];
      if (value is! String || value.isEmpty) {
        throw StateError('Missing widget translation for $key in $locale');
      }
      if ((key == 'iosWidgetFuture' || key == 'iosWidgetPast') &&
          !value.contains('{{duration}}')) {
        throw StateError('Missing duration placeholder for $key in $locale');
      }
      strings[key] = value;
    }
    translations[locale] = strings;
  }
  return translations;
}
