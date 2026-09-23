import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mona/data/model/date.dart';
import 'package:mona/services/home_widget_service.dart';

import '../fixtures.dart';
import '../mocks/mocks.mocks.dart';

void main() {
  test('recognizes only Mona Home widget links', () {
    expect(
      HomeWidgetService.isHomeWidgetUrl(
        Uri.parse('mona-widget://home?homeWidget=true'),
      ),
      isTrue,
    );
    expect(HomeWidgetService.isHomeWidgetUrl(null), isFalse);
    expect(
      HomeWidgetService.isHomeWidgetUrl(Uri.parse('mona-widget://home')),
      isFalse,
    );
    expect(
      HomeWidgetService.isHomeWidgetUrl(
        Uri.parse('mona-widget://other?homeWidget=true'),
      ),
      isFalse,
    );
  });

  group('HomeWidgetService.sync', () {
    late List<Map<String, String?>> saved;
    late List<String> appGroups;
    late List<({String? iOSName, String? qualifiedAndroidName})> updated;
    late MockMedicationIntakeProvider intakeProvider;
    late MockMedicationScheduleProvider scheduleProvider;
    late MockLocaleProvider localeProvider;

    setUp(() {
      saved = [];
      appGroups = [];
      updated = [];
      HomeWidgetService.isPlatformSupported = () => true;
      HomeWidgetService.isIOSPlatform = () => false;
      intakeProvider = MockMedicationIntakeProvider();
      scheduleProvider = MockMedicationScheduleProvider();
      localeProvider = MockLocaleProvider();
      when(intakeProvider.isLoading).thenReturn(false);
      when(scheduleProvider.isLoading).thenReturn(false);
      when(scheduleProvider.schedules).thenReturn([]);
      when(intakeProvider.firstTakenLocalDate)
          .thenReturn(Date(year: 2026, month: 1, day: 5));
      when(intakeProvider.takenIntakes)
          .thenReturn(List.filled(3, aMedicationIntake()));
      when(localeProvider.locale).thenReturn(const Locale('fr'));
    });

    tearDown(() {
      HomeWidgetService.isPlatformSupported = null;
      HomeWidgetService.isIOSPlatform = null;
    });

    final keyCases = [
      (name: 'first date', id: 'hrt_first_date', data: '2026-01-05'),
      (name: 'locale', id: 'app_locale', data: 'fr'),
      (name: 'intake count', id: 'hrt_intake_count', data: '3'),
      (
        name: 'recent intake counts',
        id: 'hrt_recent_intake_counts',
        data: '0,0,0,0,0,0,0'
      ),
    ];
    for (final c in keyCases) {
      test('saves the ${c.name} under its shared key', () async {
        // Arrange
        final service = HomeWidgetService(
          saveWidgetData: (id, data) async =>
              saved.add({'id': id, 'data': data}),
          setAppGroupId: (groupId) async => appGroups.add(groupId),
          updateWidget: ({iOSName, qualifiedAndroidName}) async => updated.add(
            (iOSName: iOSName, qualifiedAndroidName: qualifiedAndroidName),
          ),
        );
        // Act
        await service.sync(intakeProvider, scheduleProvider, localeProvider);
        // Assert
        expect(saved, contains(equals({'id': c.id, 'data': c.data})));
      });
    }

    test('saves seven daily intake counts from oldest to newest', () async {
      // Arrange
      final service = HomeWidgetService(
        saveWidgetData: (id, data) async => saved.add({'id': id, 'data': data}),
        setAppGroupId: (groupId) async => appGroups.add(groupId),
        updateWidget: ({iOSName, qualifiedAndroidName}) async => updated.add(
          (iOSName: iOSName, qualifiedAndroidName: qualifiedAndroidName),
        ),
      );
      when(intakeProvider.takenIntakes).thenReturn([
        aMedicationIntake(),
        aMedicationIntake(),
        aMedicationIntake(),
      ]);

      // Act
      await withClock(
        Clock.fixed(DateTime.utc(2025, 1, 6, 12)),
        () => service.sync(intakeProvider, scheduleProvider, localeProvider),
      );

      // Assert
      expect(
        saved,
        contains(equals({
          'id': 'hrt_recent_intake_counts',
          'data': '3,0,0,0,0,0,0',
        })),
      );
    });

    test('updates the Glance receiver', () async {
      // Arrange
      final service = HomeWidgetService(
        saveWidgetData: (id, data) async => saved.add({'id': id, 'data': data}),
        setAppGroupId: (groupId) async => appGroups.add(groupId),
        updateWidget: ({iOSName, qualifiedAndroidName}) async => updated.add(
          (iOSName: iOSName, qualifiedAndroidName: qualifiedAndroidName),
        ),
      );
      // Act
      await service.sync(intakeProvider, scheduleProvider, localeProvider);
      // Assert
      expect(updated, [
        (
          iOSName: 'HrtWidget',
          qualifiedAndroidName: 'com.deliacheminot.mona.HrtGlanceReceiver',
        ),
      ]);
    });

    test('configures the shared App Group on iOS', () async {
      // Arrange
      final service = HomeWidgetService(
        saveWidgetData: (id, data) async => saved.add({'id': id, 'data': data}),
        setAppGroupId: (groupId) async => appGroups.add(groupId),
        updateWidget: ({iOSName, qualifiedAndroidName}) async => updated.add(
          (iOSName: iOSName, qualifiedAndroidName: qualifiedAndroidName),
        ),
      );
      HomeWidgetService.isIOSPlatform = () => true;
      // Act
      await service.sync(intakeProvider, scheduleProvider, localeProvider);
      // Assert
      expect(appGroups, ['group.com.deliacheminot.mona']);
    });

    test('shares an exact due instant for a timed daily intake', () async {
      HomeWidgetService.isIOSPlatform = () => true;
      final date = Date(year: 2026, month: 6, day: 1);
      final schedule = aMedicationSchedule(
        scheduling: aDailyStrategy(
          intakeTimes: const [TimeOfDay(hour: 15, minute: 0)],
        ),
        startDate: date,
      );
      when(scheduleProvider.schedules).thenReturn([schedule]);
      when(intakeProvider.getTakenIntakesForScheduleOn(schedule.id, date))
          .thenReturn([]);
      final service = HomeWidgetService(
        saveWidgetData: (id, data) async => saved.add({'id': id, 'data': data}),
        setAppGroupId: (groupId) async => appGroups.add(groupId),
        updateWidget: ({iOSName, qualifiedAndroidName}) async => updated.add(
          (iOSName: iOSName, qualifiedAndroidName: qualifiedAndroidName),
        ),
      );

      await withClock(
        Clock.fixed(DateTime(2026, 6, 1, 12)),
        () => service.sync(intakeProvider, scheduleProvider, localeProvider),
      );

      expect(saved,
          contains(equals({'id': 'next_intake_date', 'data': '2026-06-01'})));
      expect(
        saved,
        contains(equals({
          'id': 'next_intake_due_at_ms',
          'data': DateTime(2026, 6, 1, 15).millisecondsSinceEpoch.toString(),
        })),
      );
      expect(
          saved,
          contains(
              equals({'id': 'next_intake_interval_minutes', 'data': '1440'})));
    });

    test('keeps an untimed interval intake date-only', () async {
      HomeWidgetService.isIOSPlatform = () => true;
      final due = Date(year: 2026, month: 6, day: 6);
      final schedule = aMedicationSchedule(
        scheduling: anIntervalStrategy(intervalDays: 7),
        startDate: due,
      );
      when(scheduleProvider.schedules).thenReturn([schedule]);
      when(intakeProvider.getLastIntakeLocalDateForSchedule(schedule.id))
          .thenReturn(null);
      when(intakeProvider.getLastTakenIntakeForSchedule(schedule.id))
          .thenReturn(null);
      final service = HomeWidgetService(
        saveWidgetData: (id, data) async => saved.add({'id': id, 'data': data}),
        setAppGroupId: (groupId) async => appGroups.add(groupId),
        updateWidget: ({iOSName, qualifiedAndroidName}) async => updated.add(
          (iOSName: iOSName, qualifiedAndroidName: qualifiedAndroidName),
        ),
      );

      await withClock(
        Clock.fixed(DateTime(2026, 6, 1, 12)),
        () => service.sync(intakeProvider, scheduleProvider, localeProvider),
      );

      expect(saved,
          contains(equals({'id': 'next_intake_date', 'data': '2026-06-06'})));
      expect(saved,
          contains(equals({'id': 'next_intake_due_at_ms', 'data': null})));
      expect(
          saved,
          contains(
              equals({'id': 'next_intake_interval_minutes', 'data': '10080'})));
    });

    test('clears iOS countdown data when no intake is scheduled', () async {
      HomeWidgetService.isIOSPlatform = () => true;
      final service = HomeWidgetService(
        saveWidgetData: (id, data) async => saved.add({'id': id, 'data': data}),
        setAppGroupId: (groupId) async => appGroups.add(groupId),
        updateWidget: ({iOSName, qualifiedAndroidName}) async => updated.add(
          (iOSName: iOSName, qualifiedAndroidName: qualifiedAndroidName),
        ),
      );

      await service.sync(intakeProvider, scheduleProvider, localeProvider);

      expect(saved, contains(equals({'id': 'next_intake_date', 'data': null})));
      expect(saved,
          contains(equals({'id': 'next_intake_due_at_ms', 'data': null})));
      expect(
          saved,
          contains(
              equals({'id': 'next_intake_interval_minutes', 'data': null})));
    });

    test('preserves the locale region for widget localization', () async {
      // Arrange
      final service = HomeWidgetService(
        saveWidgetData: (id, data) async => saved.add({'id': id, 'data': data}),
        setAppGroupId: (groupId) async => appGroups.add(groupId),
        updateWidget: ({iOSName, qualifiedAndroidName}) async => updated.add(
          (iOSName: iOSName, qualifiedAndroidName: qualifiedAndroidName),
        ),
      );
      when(localeProvider.locale).thenReturn(
          const Locale.fromSubtags(languageCode: 'pt', countryCode: 'BR'));
      // Act
      await service.sync(intakeProvider, scheduleProvider, localeProvider);
      // Assert
      expect(
        saved,
        contains(equals({'id': 'app_locale', 'data': 'pt-BR'})),
      );
    });

    test('pushes a null first date to clear the widget', () async {
      // Arrange
      final service = HomeWidgetService(
        saveWidgetData: (id, data) async => saved.add({'id': id, 'data': data}),
        setAppGroupId: (groupId) async => appGroups.add(groupId),
        updateWidget: ({iOSName, qualifiedAndroidName}) async => updated.add(
          (iOSName: iOSName, qualifiedAndroidName: qualifiedAndroidName),
        ),
      );
      when(intakeProvider.firstTakenLocalDate).thenReturn(null);
      // Act
      await service.sync(intakeProvider, scheduleProvider, localeProvider);
      // Assert
      expect(saved, contains(equals({'id': 'hrt_first_date', 'data': null})));
    });

    test('does nothing when the platform is unsupported', () async {
      // Arrange
      final service = HomeWidgetService(
        saveWidgetData: (id, data) async => saved.add({'id': id, 'data': data}),
        setAppGroupId: (groupId) async => appGroups.add(groupId),
        updateWidget: ({iOSName, qualifiedAndroidName}) async => updated.add(
          (iOSName: iOSName, qualifiedAndroidName: qualifiedAndroidName),
        ),
      );
      HomeWidgetService.isPlatformSupported = () => false;
      // Act
      await service.sync(intakeProvider, scheduleProvider, localeProvider);
      // Assert
      expect(saved, isEmpty);
    });

    test('does nothing while the intake provider is loading', () async {
      // Arrange
      final service = HomeWidgetService(
        saveWidgetData: (id, data) async => saved.add({'id': id, 'data': data}),
        setAppGroupId: (groupId) async => appGroups.add(groupId),
        updateWidget: ({iOSName, qualifiedAndroidName}) async => updated.add(
          (iOSName: iOSName, qualifiedAndroidName: qualifiedAndroidName),
        ),
      );
      when(intakeProvider.isLoading).thenReturn(true);
      // Act
      await service.sync(intakeProvider, scheduleProvider, localeProvider);
      // Assert
      expect(saved, isEmpty);
    });

    test('does nothing while the schedule provider is loading', () async {
      final service = HomeWidgetService(
        saveWidgetData: (id, data) async => saved.add({'id': id, 'data': data}),
        setAppGroupId: (groupId) async => appGroups.add(groupId),
        updateWidget: ({iOSName, qualifiedAndroidName}) async => updated.add(
          (iOSName: iOSName, qualifiedAndroidName: qualifiedAndroidName),
        ),
      );
      when(scheduleProvider.isLoading).thenReturn(true);

      await service.sync(intakeProvider, scheduleProvider, localeProvider);

      expect(saved, isEmpty);
    });
  });
}
