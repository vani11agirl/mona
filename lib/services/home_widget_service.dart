import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:home_widget/home_widget.dart';
import 'package:mona/controllers/next_intake_resolver.dart';
import 'package:mona/controllers/slots_builder.dart';
import 'package:mona/data/model/date.dart';
import 'package:mona/data/model/scheduling_strategy.dart';
import 'package:mona/data/providers/medication_intake_provider.dart';
import 'package:mona/data/providers/medication_schedule_provider.dart';
import 'package:mona/distribution.dart';
import 'package:mona/i18n/locale_provider.dart';
import 'package:mona/i18n/translations.g.dart';

typedef SaveWidgetData = Future<void> Function(String id, String? data);
typedef SetAppGroupId = Future<void> Function(String groupId);
typedef UpdateWidget = Future<void> Function({
  String? iOSName,
  String? qualifiedAndroidName,
});

class HomeWidgetService {
  // Test builds may be re-signed into a different App Group. The extension's
  // MonaWidgetAppGroup Info.plist value and both entitlements must match it.
  static const String appGroupId = String.fromEnvironment(
    'MONA_WIDGET_APP_GROUP',
    defaultValue: 'group.com.deliacheminot.mona',
  );
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
  Future<void> _pendingSync = Future.value();
  String? _lastPublishedData;

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
    final isIOS = isIOSPlatform?.call() ?? false;
    if (!(isPlatformSupported?.call() ?? isMobile) ||
        medicationIntakeProvider.isLoading ||
        (isIOS && medicationScheduleProvider.isLoading)) {
      return;
    }
    final today = Date.today();
    final locale = isIOS
        ? localeProvider.locale.toLanguageTag()
        : localeProvider.locale.languageCode;
    final intakeCount = medicationIntakeProvider.takenIntakes.length;
    final data = <String, Object?>{
      'hrt_first_date':
          _dateString(medicationIntakeProvider.firstTakenLocalDate),
      'app_locale': locale,
      'hrt_intake_count': intakeCount.toString(),
    };
    if (isIOS) {
      final strings = AppLocaleUtils.parse(locale).buildSync();
      data.addAll({
        'widget_home_title': strings.HrtCounter,
        'widget_home_intakes': strings.intakesLoggedCount(count: intakeCount),
        'widget_home_empty': strings.neverTakenYet,
        ..._intakeTimeline(
            medicationIntakeProvider, medicationScheduleProvider, today),
      });
    }
    await _publish(data, isIOS: isIOS);
  }

  Map<String, Object?> _intakeTimeline(
    MedicationIntakeProvider intakes,
    MedicationScheduleProvider schedules,
    Date today,
  ) {
    final timeline = <Map<String, String?>>[];
    DateTime boundary(int offset) => DateTime(
          today.year,
          today.month,
          today.day + offset,
          logicalDayStartMinutes ~/ 60,
          logicalDayStartMinutes % 60,
        );

    // Reuse the app's scheduling rules for today and the next seven days.
    // Predictions assume no further intakes are recorded; any edit republishes
    // the timeline. Calendar construction preserves the 04:00 boundary at DST.
    for (var day = 0; day <= 7; day++) {
      final start = boundary(day);
      final end = boundary(day + 1);
      withClock(Clock.fixed(start), () {
        final slots = SlotsBuilder(intakes, schedules).intakeSlots();
        // Carry overdue slots forward, but exclude future logical days.
        final pendingTodayCount = slots
            .where((slot) =>
                slot.status != ScheduleStatus.taken &&
                slot.status != ScheduleStatus.asNeeded &&
                !slot.date.isAfterToday)
            .length;
        final changes = <DateTime>{start};
        for (final slot in slots) {
          if (slot.time == null || slot.status == ScheduleStatus.taken) {
            continue;
          }
          final due = slot.date.toDateTimeAt(slot.time!);
          if (!due.isBefore(start) && due.isBefore(end)) changes.add(due);
        }
        for (final at in changes.toList()..sort()) {
          // At the due instant, treat that intake as due, not still upcoming.
          final next = resolveNextIntake(
            slots,
            at.add(const Duration(microseconds: 1)),
          );
          timeline.add({
            'from_ms': at.millisecondsSinceEpoch.toString(),
            'next_intake_date': _dateString(next?.date),
            'next_intake_due_at_ms': next?.time == null
                ? null
                : next!.date
                    .toDateTimeAt(next.time!)
                    .millisecondsSinceEpoch
                    .toString(),
            'next_intake_interval_minutes': next?.interval.inMinutes.toString(),
            'next_intake_today_count':
                next == null ? null : pendingTodayCount.toString(),
          });
        }
      });
    }
    return {
      'intake_timeline': timeline,
      'intake_timeline_end_ms': boundary(8).millisecondsSinceEpoch.toString(),
    };
  }

  Future<void> _publish(Map<String, Object?> data, {required bool isIOS}) {
    if (!isIOS) return _publishAndroid(data);

    // Capture the complete value before yielding to another provider callback.
    final encoded = jsonEncode(data);
    final publication = _pendingSync.then((_) async {
      if (_lastPublishedData == encoded) return;

      // A failed write/reload must not suppress the next attempt, even if the
      // caller changes back to the last successfully published value.
      _lastPublishedData = null;
      await _setAppGroupId(appGroupId);
      await _saveWidgetData('widget_snapshot_v1', encoded);
      await _updateWidget(iOSName: _iOSName);
      _lastPublishedData = encoded;
    });
    // Recover the queue, but keep the failure visible to this call's caller.
    _pendingSync = publication.catchError((Object _) {});
    return publication;
  }

  Future<void> _publishAndroid(Map<String, Object?> data) async {
    // Preserve the pre-iOS Glance contract: three individual writes followed by
    // a refresh on every call, without iOS snapshot queuing or deduplication.
    await _saveWidgetData('hrt_first_date', data['hrt_first_date'] as String?);
    await _saveWidgetData('app_locale', data['app_locale'] as String?);
    await _saveWidgetData(
        'hrt_intake_count', data['hrt_intake_count'] as String?);
    await _updateWidget(qualifiedAndroidName: _qualifiedAndroidName);
  }

  String? _dateString(Date? date) => date == null
      ? null
      : '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
}
