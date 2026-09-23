import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import 'package:mona/controllers/next_intake_resolver.dart';
import 'package:mona/controllers/slots_builder.dart';
import 'package:mona/data/model/date.dart';
import 'package:mona/data/providers/medication_intake_provider.dart';
import 'package:mona/data/providers/medication_schedule_provider.dart';
import 'package:mona/distribution.dart';
import 'package:mona/i18n/locale_provider.dart';

typedef SaveWidgetData = Future<void> Function(String id, String? data);
typedef SetAppGroupId = Future<void> Function(String groupId);
typedef UpdateWidget = Future<void> Function({
  String? iOSName,
  String? qualifiedAndroidName,
});

class HomeWidgetService {
  static const String appGroupId = 'group.com.deliacheminot.mona';
  static const String _iOSName = 'HrtWidget';
  static const String _qualifiedAndroidName =
      'com.deliacheminot.mona.HrtGlanceReceiver';

  static bool Function()? isPlatformSupported = () => isMobile;
  static bool Function()? isIOSPlatform = () => isIOS;

  static bool isHomeWidgetUrl(Uri? uri) =>
      uri?.scheme == 'mona-widget' &&
      uri?.host == 'home' &&
      uri?.queryParameters['homeWidget'] == 'true';

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
    MedicationScheduleProvider medicationScheduleProvider,
    LocaleProvider localeProvider,
  ) async {
    if (medicationIntakeProvider.isLoading ||
        medicationScheduleProvider.isLoading) {
      return;
    }
    final isIOS = isIOSPlatform?.call() ?? false;
    final nextIntake = isIOS
        ? resolveNextIntake(
            SlotsBuilder(medicationIntakeProvider, medicationScheduleProvider)
                .intakeSlots(),
            clock.now(),
          )
        : null;
    await syncHrtTimeWidget(
      firstDate: medicationIntakeProvider.firstTakenLocalDate,
      locale: localeProvider.locale,
      intakeCount: medicationIntakeProvider.takenIntakes.length,
      recentIntakeCounts: _recentIntakeCounts(medicationIntakeProvider),
      nextIntake: nextIntake,
    );
  }

  List<int> _recentIntakeCounts(
    MedicationIntakeProvider medicationIntakeProvider,
  ) {
    final today = Date.today();
    return List.generate(7, (index) {
      final date = today.subtract(Duration(days: 6 - index));
      return medicationIntakeProvider.takenIntakes
          .where((intake) => intake.takenLocalDate == date)
          .length;
    });
  }

  Future<void> syncHrtTimeWidget({
    required Date? firstDate,
    required Locale locale,
    required int intakeCount,
    required List<int> recentIntakeCounts,
    NextIntake? nextIntake,
  }) async {
    final supported = isPlatformSupported?.call() ?? isMobile;
    if (!supported) return;

    final isIOS = isIOSPlatform?.call() ?? false;
    if (isIOS) {
      await _setAppGroupId(appGroupId);
      await _saveWidgetData('next_intake_date', _dateString(nextIntake?.date));
      await _saveWidgetData(
        'next_intake_due_at_ms',
        nextIntake?.time == null
            ? null
            : nextIntake!.date
                .toDateTimeAt(nextIntake.time!)
                .millisecondsSinceEpoch
                .toString(),
      );
      await _saveWidgetData(
        'next_intake_interval_minutes',
        nextIntake?.interval.inMinutes.toString(),
      );
    }

    await _saveWidgetData('hrt_first_date', _dateString(firstDate));
    await _saveWidgetData('app_locale', locale.toLanguageTag());
    await _saveWidgetData('hrt_intake_count', intakeCount.toString());
    await _saveWidgetData(
      'hrt_recent_intake_counts',
      recentIntakeCounts.join(','),
    );
    await _updateWidget(
      iOSName: _iOSName,
      qualifiedAndroidName: _qualifiedAndroidName,
    );
  }

  String? _dateString(Date? date) => date == null
      ? null
      : '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
}
