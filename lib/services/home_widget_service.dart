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
  Future<void> _pendingSync = Future.value();
  String? _lastPublishedData;
  bool? _lastPublishedOnIOS;

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
    if (!(isPlatformSupported?.call() ?? isMobile) ||
        medicationIntakeProvider.isLoading ||
        medicationScheduleProvider.isLoading) {
      return;
    }
    final isIOS = isIOSPlatform?.call() ?? false;
    final today = Date.today();
    final locale = localeProvider.locale.toLanguageTag();
    final intakeCount = medicationIntakeProvider.takenIntakes.length;
    final data = <String, Object?>{
      'hrt_first_date':
          _dateString(medicationIntakeProvider.firstTakenLocalDate),
      'app_locale': locale,
      'hrt_intake_count': intakeCount.toString(),
      'hrt_recent_intake_counts':
          _recentIntakeCounts(medicationIntakeProvider, today).join(','),
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

  List<int> _recentIntakeCounts(
    MedicationIntakeProvider medicationIntakeProvider,
    Date today,
  ) {
    return List.generate(7, (index) {
      final date = today.subtract(Duration(days: 6 - index));
      return medicationIntakeProvider.takenIntakes
          .where((intake) => intake.takenLocalDate == date)
          .length;
    });
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
    // Capture the complete value before yielding to another provider callback.
    final encoded = jsonEncode(data);
    final publication = _pendingSync.then((_) async {
      if (_lastPublishedOnIOS == isIOS && _lastPublishedData == encoded) return;

      // A failed write/reload must not suppress the next attempt, even if the
      // caller changes back to the last successfully published value.
      _lastPublishedData = null;
      if (isIOS) {
        await _setAppGroupId(appGroupId);
        await _saveWidgetData('widget_snapshot_v1', encoded);
      } else {
        // Keep the existing Glance storage contract on Android.
        for (final entry in data.entries) {
          await _saveWidgetData(entry.key, entry.value as String?);
        }
      }
      await _updateWidget(
        iOSName: _iOSName,
        qualifiedAndroidName: _qualifiedAndroidName,
      );
      _lastPublishedData = encoded;
      _lastPublishedOnIOS = isIOS;
    });
    // Recover the queue, but keep the failure visible to this call's caller.
    _pendingSync = publication.catchError((Object _) {});
    return publication;
  }

  String? _dateString(Date? date) => date == null
      ? null
      : '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
}
