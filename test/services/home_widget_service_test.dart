import 'dart:async';
import 'dart:convert';

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
    // Arrange
    final home = Uri.parse('mona-widget://home?homeWidget=true');

    // Act
    final recognized = HomeWidgetService.isHomeWidgetUrl(home);

    // Assert
    expect(recognized, isTrue);
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

    HomeWidgetService makeService({
      SaveWidgetData? saveWidgetData,
      UpdateWidget? updateWidget,
    }) =>
        HomeWidgetService(
          saveWidgetData: saveWidgetData ??
              (id, data) async => saved.add({'id': id, 'data': data}),
          setAppGroupId: (groupId) async => appGroups.add(groupId),
          updateWidget: updateWidget ??
              ({iOSName, qualifiedAndroidName}) async => updated.add((
                    iOSName: iOSName,
                    qualifiedAndroidName: qualifiedAndroidName,
                  )),
        );

    Map<String, dynamic> snapshot() =>
        jsonDecode(saved.last['data']!) as Map<String, dynamic>;

    Map<String, dynamic> stateAt(DateTime at) => (snapshot()['intake_timeline']
            as List)
        .cast<Map<String, dynamic>>()
        .lastWhere((state) =>
            int.parse(state['from_ms'] as String) <= at.millisecondsSinceEpoch);

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
      when(intakeProvider.getTakenIntakesForScheduleOn(any, any))
          .thenReturn([]);
      when(intakeProvider.getLastIntakeLocalDateForSchedule(any))
          .thenReturn(null);
      when(intakeProvider.getLastTakenIntakeForSchedule(any)).thenReturn(null);
      when(intakeProvider.firstTakenLocalDate)
          .thenReturn(Date(year: 2026, month: 1, day: 5));
      when(intakeProvider.takenIntakes)
          .thenReturn(List.filled(3, aMedicationIntake()));
      when(localeProvider.locale).thenReturn(const Locale('fr'));
      when(localeProvider.followsSystemLocale).thenReturn(false);
    });

    tearDown(() {
      HomeWidgetService.isPlatformSupported = null;
      HomeWidgetService.isIOSPlatform = null;
    });

    test('publishes the Android widget keys while schedules are loading',
        () async {
      // Arrange
      final service = makeService();
      when(scheduleProvider.isLoading).thenReturn(true);

      // Act
      await service.sync(intakeProvider, scheduleProvider, localeProvider);

      // Assert
      expect(saved, [
        {'id': 'hrt_first_date', 'data': '2026-01-05'},
        {'id': 'app_locale', 'data': 'fr'},
        {'id': 'hrt_intake_count', 'data': '3'},
      ]);
      expect(updated, hasLength(1));
      verifyNever(scheduleProvider.schedules);
    });

    test('updates the Glance receiver', () async {
      // Arrange
      final service = makeService();
      // Act
      await service.sync(intakeProvider, scheduleProvider, localeProvider);
      // Assert
      expect(updated, [
        (
          iOSName: null,
          qualifiedAndroidName: 'com.deliacheminot.mona.HrtGlanceReceiver',
        ),
      ]);
    });

    test('configures the shared App Group on iOS', () async {
      // Arrange
      final service = makeService();
      HomeWidgetService.isIOSPlatform = () => true;
      // Act
      await service.sync(intakeProvider, scheduleProvider, localeProvider);
      // Assert
      expect(appGroups, ['group.com.deliacheminot.mona']);
    });

    test('shares the configured day start and republishes changes', () async {
      // Arrange
      HomeWidgetService.isIOSPlatform = () => true;
      final previousDayStart = logicalDayStartMinutes;
      addTearDown(() => logicalDayStartMinutes = previousDayStart);
      final service = makeService();
      final snapshots = <Map<String, dynamic>>[];

      // Act
      await withClock(Clock.fixed(DateTime(2026, 6, 1, 12)), () async {
        for (final minutes in [390, 0]) {
          logicalDayStartMinutes = minutes;
          await service.sync(intakeProvider, scheduleProvider, localeProvider);
          snapshots.add(snapshot());
        }
      });

      // Assert
      expect(
          snapshots.map((data) => data['logical_day_start_minutes']), [390, 0]);
      expect(
        snapshots
            .map((data) => (data['intake_timeline'] as List).first['from_ms']),
        [
          DateTime(2026, 6, 1, 6, 30).millisecondsSinceEpoch.toString(),
          DateTime(2026, 6, 1).millisecondsSinceEpoch.toString(),
        ],
      );
      expect(updated, hasLength(2));
    });

    test(
      'shares translated Home Screen copy for the real intake count',
      () async {
        // Arrange
        HomeWidgetService.isIOSPlatform = () => true;
        final service = makeService();

        // Act
        await service.sync(intakeProvider, scheduleProvider, localeProvider);

        // Assert
        final intakeTexts = snapshot()['widget_home_intakes'];
        expect(intakeTexts['en'], '3 intakes logged');
        expect(intakeTexts['fr'], '3 prises enregistrées');
      },
    );

    test('shares an exact due instant for a timed daily intake', () async {
      // Arrange
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
      final service = makeService();

      // Act
      await withClock(
        Clock.fixed(DateTime(2026, 6, 1, 12)),
        () => service.sync(intakeProvider, scheduleProvider, localeProvider),
      );

      // Assert
      final state = stateAt(DateTime(2026, 6, 1, 12));
      expect(state['next_intake_date'], '2026-06-01');
      expect(
        state['next_intake_due_at_ms'],
        DateTime(2026, 6, 1, 15).millisecondsSinceEpoch.toString(),
      );
      expect(state['next_intake_interval_minutes'], '1440');
    });

    test('counts overdue intakes alongside pending intakes for today',
        () async {
      // Arrange
      HomeWidgetService.isIOSPlatform = () => true;
      final date = Date(year: 2026, month: 6, day: 1);
      const morning = TimeOfDay(hour: 9, minute: 0);
      const noon = TimeOfDay(hour: 12, minute: 0);
      const evening = TimeOfDay(hour: 18, minute: 0);
      final daily = aMedicationSchedule(
        scheduling: aDailyStrategy(intakeTimes: const [morning, noon, evening]),
        startDate: date,
      );
      final asNeeded = aMedicationSchedule(
        scheduling: anAsNeededStrategy(),
        startDate: date,
      );
      final overdue = aMedicationSchedule(
        scheduling: aDynamicIntervalStrategy(),
        startDate: date.subtract(const Duration(days: 1)),
      );
      final upcoming = aMedicationSchedule(
        scheduling: anIntervalStrategy(),
        startDate: date.add(const Duration(days: 3)),
      );
      when(scheduleProvider.schedules)
          .thenReturn([daily, asNeeded, overdue, upcoming]);
      when(intakeProvider.getTakenIntakesForScheduleOn(daily.id, date))
          .thenReturn([
        aMedicationIntake(
          time: morning,
          scheduleId: daily.id,
          takenDateTime: DateTime.utc(2026, 6, 1, 9),
        ),
      ]);
      final operations = <String>[];
      final service = HomeWidgetService(
        saveWidgetData: (id, data) async {
          saved.add({'id': id, 'data': data});
          operations.add('save:$id');
        },
        setAppGroupId: (groupId) async => appGroups.add(groupId),
        updateWidget: ({iOSName, qualifiedAndroidName}) async {
          updated.add((
            iOSName: iOSName,
            qualifiedAndroidName: qualifiedAndroidName,
          ));
          operations.add('update');
        },
      );

      // Act
      await withClock(
        Clock.fixed(DateTime(2026, 6, 1, 12)),
        () => service.sync(intakeProvider, scheduleProvider, localeProvider),
      );

      // Assert
      expect(stateAt(DateTime(2026, 6, 1, 12))['next_intake_today_count'], '3');
      expect(stateAt(DateTime(2026, 6, 2, 4))['next_intake_today_count'], '4');
      expect(operations, ['save:widget_snapshot', 'update']);
      expect(snapshot()['hrt_first_date'], '2026-01-05');
      expect(snapshot()['app_locale'], 'fr');
      expect(snapshot()['hrt_intake_count'], '3');
    });

    test('keeps an untimed interval intake date-only', () async {
      // Arrange
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
      final service = makeService();

      // Act
      await withClock(
        Clock.fixed(DateTime(2026, 6, 1, 12)),
        () => service.sync(intakeProvider, scheduleProvider, localeProvider),
      );

      // Assert
      final state = stateAt(DateTime(2026, 6, 1, 12));
      expect(state['next_intake_date'], '2026-06-06');
      expect(state['next_intake_due_at_ms'], isNull);
      expect(state['next_intake_interval_minutes'], '10080');
    });

    test('clears iOS countdown data when no intake is scheduled', () async {
      // Arrange
      HomeWidgetService.isIOSPlatform = () => true;
      final service = makeService();

      // Act
      await service.sync(intakeProvider, scheduleProvider, localeProvider);

      // Assert
      final state = stateAt(clock.now());
      expect(state['next_intake_date'], isNull);
      expect(state['next_intake_due_at_ms'], isNull);
      expect(state['next_intake_interval_minutes'], isNull);
      expect(state['next_intake_today_count'], isNull);
    });

    test('preserves the locale region for widget localization', () async {
      // Arrange
      HomeWidgetService.isIOSPlatform = () => true;
      final service = makeService();
      when(localeProvider.locale).thenReturn(
        const Locale.fromSubtags(languageCode: 'pt', countryCode: 'BR'),
      );
      // Act
      await service.sync(intakeProvider, scheduleProvider, localeProvider);
      // Assert
      expect(snapshot()['app_locale'], 'pt-BR');
    });

    test('keeps Android language codes and refreshes unchanged data', () async {
      // Arrange
      final service = makeService();
      when(localeProvider.locale).thenReturn(const Locale('pt', 'BR'));

      // Act
      await service.sync(intakeProvider, scheduleProvider, localeProvider);
      await service.sync(intakeProvider, scheduleProvider, localeProvider);

      // Assert
      expect(saved, hasLength(6));
      expect(saved.where((entry) => entry['id'] == 'app_locale'), [
        {'id': 'app_locale', 'data': 'pt'},
        {'id': 'app_locale', 'data': 'pt'},
      ]);
      expect(updated, hasLength(2));
      expect(appGroups, isEmpty);
    });

    test(
      'refreshes iOS widget language after the app locale changes',
      () async {
        // Arrange
        HomeWidgetService.isIOSPlatform = () => true;
        final service = makeService();

        // Act
        await service.sync(intakeProvider, scheduleProvider, localeProvider);
        when(localeProvider.locale).thenReturn(const Locale('de'));
        await service.sync(intakeProvider, scheduleProvider, localeProvider);

        // Assert
        expect(saved.map((entry) => jsonDecode(entry['data']!)['app_locale']),
            ['fr', 'de']);
        expect(updated, hasLength(2));
      },
    );

    test('does not freeze the resolved language when following the system',
        () async {
      // Arrange
      HomeWidgetService.isIOSPlatform = () => true;
      when(localeProvider.followsSystemLocale).thenReturn(true);
      final service = makeService();

      // Act
      await service.sync(intakeProvider, scheduleProvider, localeProvider);
      when(localeProvider.locale).thenReturn(const Locale('de'));
      await service.sync(intakeProvider, scheduleProvider, localeProvider);

      // Assert
      expect(snapshot()['app_locale'], isNull);
      expect(saved, hasLength(1));
      expect(updated, hasLength(1));
    });

    test('pushes a null first date to clear the widget', () async {
      // Arrange
      final service = makeService();
      when(intakeProvider.firstTakenLocalDate).thenReturn(null);
      // Act
      await service.sync(intakeProvider, scheduleProvider, localeProvider);
      // Assert
      expect(saved, contains(equals({'id': 'hrt_first_date', 'data': null})));
    });

    test('serializes overlapping snapshots in capture order', () async {
      // Arrange
      HomeWidgetService.isIOSPlatform = () => true;
      final firstSaveStarted = Completer<void>();
      final releaseFirstSave = Completer<void>();
      final operations = <String>[];
      final service = makeService(
        saveWidgetData: (id, data) async {
          final locale = jsonDecode(data!)['app_locale'];
          operations.add('save:$locale');
          saved.add({'id': id, 'data': data});
          if (saved.length == 1) {
            firstSaveStarted.complete();
            await releaseFirstSave.future;
          }
          operations.add('saved:$locale');
        },
        updateWidget: ({iOSName, qualifiedAndroidName}) async {
          operations.add('reload');
          updated.add(
              (iOSName: iOSName, qualifiedAndroidName: qualifiedAndroidName));
        },
      );

      // Act
      final first =
          service.sync(intakeProvider, scheduleProvider, localeProvider);
      await firstSaveStarted.future;
      when(localeProvider.locale).thenReturn(const Locale('de'));
      final second =
          service.sync(intakeProvider, scheduleProvider, localeProvider);
      await Future<void>.delayed(Duration.zero);
      final writesWhileBlocked = saved.length;
      final reloadsWhileBlocked = updated.length;
      releaseFirstSave.complete();
      await Future.wait([first, second]);

      // Assert
      expect(writesWhileBlocked, 1);
      expect(reloadsWhileBlocked, 0);
      expect(saved.map((entry) => jsonDecode(entry['data']!)['app_locale']),
          ['fr', 'de']);
      expect(updated, hasLength(2));
      expect(operations,
          ['save:fr', 'saved:fr', 'reload', 'save:de', 'saved:de', 'reload']);
    });

    test('does not republish an identical successful snapshot', () async {
      // Arrange
      HomeWidgetService.isIOSPlatform = () => true;
      final service = makeService();

      // Act
      await Future.wait([
        service.sync(intakeProvider, scheduleProvider, localeProvider),
        service.sync(intakeProvider, scheduleProvider, localeProvider),
      ]);
      await service.sync(intakeProvider, scheduleProvider, localeProvider);

      // Assert
      expect(saved, hasLength(1));
      expect(updated, hasLength(1));
    });

    for (final failure in ['save', 'reload']) {
      test('retries the same snapshot after a failed $failure', () async {
        // Arrange
        HomeWidgetService.isIOSPlatform = () => true;
        var shouldFail = true;
        final service = makeService(
          saveWidgetData: (id, data) async {
            if (shouldFail && failure == 'save') {
              throw StateError('save failed');
            }
            saved.add({'id': id, 'data': data});
          },
          updateWidget: ({iOSName, qualifiedAndroidName}) async {
            if (shouldFail && failure == 'reload') {
              throw StateError('reload failed');
            }
            updated.add(
                (iOSName: iOSName, qualifiedAndroidName: qualifiedAndroidName));
          },
        );

        // Act
        final failed =
            service.sync(intakeProvider, scheduleProvider, localeProvider);
        // Observe the failure before retrying so it cannot become unhandled.
        await expectLater(failed, throwsStateError);
        shouldFail = false;
        await service.sync(intakeProvider, scheduleProvider, localeProvider);
        await service.sync(intakeProvider, scheduleProvider, localeProvider);

        // Assert
        expect(saved, hasLength(failure == 'save' ? 1 : 2));
        expect(updated, hasLength(1));
        expect(snapshot()['app_locale'], 'fr');
      });
    }

    test('does nothing when the platform is unsupported', () async {
      // Arrange
      final service = makeService();
      HomeWidgetService.isPlatformSupported = () => false;
      // Act
      await service.sync(intakeProvider, scheduleProvider, localeProvider);
      // Assert
      expect(saved, isEmpty);
    });

    test('does nothing while the intake provider is loading', () async {
      // Arrange
      final service = makeService();
      when(intakeProvider.isLoading).thenReturn(true);
      // Act
      await service.sync(intakeProvider, scheduleProvider, localeProvider);
      // Assert
      expect(saved, isEmpty);
    });

    test('does nothing on iOS while the schedule provider is loading',
        () async {
      // Arrange
      HomeWidgetService.isIOSPlatform = () => true;
      final service = makeService();
      when(scheduleProvider.isLoading).thenReturn(true);

      // Act
      await service.sync(intakeProvider, scheduleProvider, localeProvider);

      // Assert
      expect(saved, isEmpty);
    });
  });
}
