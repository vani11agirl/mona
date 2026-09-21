import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import 'package:mona/data/model/date.dart';
import 'package:mona/data/providers/medication_intake_provider.dart';
import 'package:mona/distribution.dart';
import 'package:mona/i18n/locale_provider.dart';

typedef SaveWidgetData = Future<void> Function(String id, String? data);
typedef SetAppGroupId = Future<void> Function(String groupId);
typedef UpdateWidget = Future<void> Function({
  String? iOSName,
  String? qualifiedAndroidName,
});

class HomeWidgetService {
  static const String _appGroupId = 'group.com.deliacheminot.mona';
  static const String _iOSName = 'HrtWidget';
  static const String _qualifiedAndroidName =
      'com.deliacheminot.mona.HrtGlanceReceiver';

  static bool Function()? isPlatformSupported = () => isMobile;
  static bool Function()? isIOSPlatform = () => isIOS;

  final SaveWidgetData _saveWidgetData;
  final SetAppGroupId _setAppGroupId;
  final UpdateWidget _updateWidget;

  HomeWidgetService({
    SaveWidgetData? saveWidgetData,
    SetAppGroupId? setAppGroupId,
    UpdateWidget? updateWidget,
  })  : _saveWidgetData = saveWidgetData ??
            ((id, data) => HomeWidget.saveWidgetData<String>(id, data)),
        _setAppGroupId = setAppGroupId ??
            ((groupId) async {
              await HomeWidget.setAppGroupId(groupId);
            }),
        _updateWidget = updateWidget ??
            (({iOSName, qualifiedAndroidName}) async {
              await HomeWidget.updateWidget(
                iOSName: iOSName,
                qualifiedAndroidName: qualifiedAndroidName,
              );
            });

  Future<void> sync(
    MedicationIntakeProvider medicationIntakeProvider,
    LocaleProvider localeProvider,
  ) async {
    if (medicationIntakeProvider.isLoading) return;
    await syncHrtTimeWidget(
      firstDate: medicationIntakeProvider.firstTakenLocalDate,
      locale: localeProvider.locale,
      intakeCount: medicationIntakeProvider.takenIntakes.length,
    );
  }

  Future<void> syncHrtTimeWidget({
    required Date? firstDate,
    required Locale locale,
    required int intakeCount,
  }) async {
    final supported = isPlatformSupported?.call() ?? isMobile;
    if (!supported) return;

    final isIOS = isIOSPlatform?.call() ?? false;
    if (isIOS) await _setAppGroupId(_appGroupId);

    final firstDateIso = firstDate == null
        ? null
        : '${firstDate.year.toString().padLeft(4, '0')}-'
            '${firstDate.month.toString().padLeft(2, '0')}-'
            '${firstDate.day.toString().padLeft(2, '0')}';
    await _saveWidgetData('hrt_first_date', firstDateIso);
    await _saveWidgetData('app_locale', locale.toLanguageTag());
    await _saveWidgetData('hrt_intake_count', intakeCount.toString());
    await _updateWidget(
      iOSName: _iOSName,
      qualifiedAndroidName: _qualifiedAndroidName,
    );
  }
}
