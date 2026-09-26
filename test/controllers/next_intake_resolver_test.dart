import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mona/controllers/next_intake_resolver.dart';
import 'package:mona/controllers/slots_builder.dart';
import 'package:mona/data/model/date.dart';
import 'package:mona/data/model/medication_intake.dart';
import 'package:mona/data/model/medication_schedule.dart';

import '../fixtures.dart';
import '../mocks/mocks.mocks.dart';

// Build real slots at the same instant used by the resolver. Each fixture may
// supply the latest recorded intake for a schedule instead of inventing statuses.
NextIntake? resolveSchedules(
  List<MedicationSchedule> schedules,
  DateTime now, {
  Map<int, MedicationIntake> latest = const {},
}) {
  final intakes = MockMedicationIntakeProvider();
  final scheduleProvider = MockMedicationScheduleProvider();
  when(scheduleProvider.schedules).thenReturn(schedules);
  for (final schedule in schedules) {
    final intake = latest[schedule.id];
    when(intakes.getLastTakenIntakeForSchedule(schedule.id)).thenReturn(intake);
    when(intakes.getLastIntakeLocalDateForSchedule(schedule.id))
        .thenReturn(intake?.takenLocalDate);
    when(intakes.getTakenIntakesForScheduleOn(schedule.id, any))
        .thenAnswer((call) => [
              if (intake != null &&
                  intake.takenLocalDate == call.positionalArguments[1])
                intake,
            ]);
  }
  return withClock(Clock.fixed(now), () {
    final slots = SlotsBuilder(intakes, scheduleProvider).intakeSlots();
    return resolveNextIntake(slots, now);
  });
}

void main() {
  final monday = Date(year: 2026, month: 6, day: 1);
  final noon = DateTime(2026, 6, 1, 12);

  test('ignores as-needed schedules and returns null without a due intake', () {
    // Arrange
    final schedule = aMedicationSchedule(
      scheduling: anAsNeededStrategy(),
      startDate: monday,
    );

    // Act
    final withoutSlots = resolveSchedules([], noon);
    final withAsNeededSlot = resolveSchedules([schedule], noon);

    // Assert
    expect(withoutSlots, isNull);
    expect(withAsNeededSlot, isNull);
  });

  test('oldest missed intake takes priority over upcoming intakes', () {
    // Arrange
    final overdue = monday.subtract(const Duration(days: 5));
    final schedules = [
      aMedicationSchedule(
        scheduling: anIntervalStrategy(),
        startDate: monday.add(const Duration(days: 5)),
      ),
      aMedicationSchedule(
        scheduling: anIntervalStrategy(),
        startDate: monday.subtract(const Duration(days: 2)),
      ),
      aMedicationSchedule(
        scheduling: anIntervalStrategy(),
        startDate: overdue,
      ),
    ];

    // Act
    final result = resolveSchedules(schedules, noon)!;

    // Assert
    expect(result.date, overdue);
    expect(result.time, isNull);
    expect(result.interval, const Duration(days: 7));
    expect(result.isOverdue, isTrue);
  });

  test('daily schedules use intake times, not just the calendar day', () {
    // Arrange
    final schedule = aMedicationSchedule(
      scheduling: aDailyStrategy(intakeTimes: const [morning, afternoon]),
      startDate: monday,
    );

    // Act
    final result = resolveSchedules([schedule], noon)!;

    // Assert
    expect(result.time, morning);
    expect(result.interval, const Duration(hours: 18));
    expect(result.isOverdue, isTrue);
  });

  test('completed daily intake advances to its next occurrence', () {
    // Arrange
    final schedule = aMedicationSchedule(
      scheduling: aDailyStrategy(intakeTimes: const [morning]),
      startDate: monday,
    );
    final intake = aMedicationIntake(
      scheduleId: schedule.id,
      time: morning,
      takenDateTime: DateTime.utc(2026, 6, 1, 9),
    );

    // Act
    final result =
        resolveSchedules([schedule], noon, latest: {schedule.id: intake})!;

    // Assert
    expect(result.date, monday.add(const Duration(days: 1)));
    expect(result.time, morning);
    expect(result.interval, const Duration(days: 1));
    expect(result.isOverdue, isFalse);
  });

  for (final entry in [
    (
      name: 'fixed interval',
      strategy: anIntervalStrategy(intervalDays: 5),
      days: 5
    ),
    (
      name: 'dynamic interval',
      strategy: aDynamicIntervalStrategy(intervalDays: 5),
      days: 5
    ),
    (
      name: 'weekly',
      strategy: aWeeklyStrategy(daysOfWeek: const [1, 4]),
      days: 3
    ),
  ]) {
    test('completed ${entry.name} intake advances only once', () {
      // Arrange
      final schedule = aMedicationSchedule(
        scheduling: entry.strategy,
        startDate: monday,
      );
      final intake = aMedicationIntake(
        scheduleId: schedule.id,
        takenDateTime: DateTime.utc(2026, 6, 1, 9),
      );

      // Act
      final result =
          resolveSchedules([schedule], noon, latest: {schedule.id: intake})!;

      // Assert
      expect(result.date, monday.add(Duration(days: entry.days)));
      expect(result.interval, Duration(days: entry.days));
      expect(result.isOverdue, isFalse);
    });
  }

  for (final entry in [
    (
      name: 'interval',
      strategy: anIntervalStrategy(),
      start: monday.subtract(const Duration(days: 7)),
      now: noon,
      missed: monday.subtract(const Duration(days: 7)),
      interval: const Duration(days: 7),
    ),
    (
      name: 'weekly',
      strategy: aWeeklyStrategy(daysOfWeek: const [1, 4]),
      start: monday.subtract(const Duration(days: 7)),
      now: noon,
      missed: monday.subtract(const Duration(days: 4)),
      interval: const Duration(days: 3),
    ),
    (
      name: 'monthly',
      strategy: aMonthlyStrategy(dayOfMonth: 21),
      start: Date(year: 2026, month: 5, day: 21),
      now: DateTime(2026, 6, 21, 12),
      missed: Date(year: 2026, month: 5, day: 21),
      interval: const Duration(days: 30),
    ),
  ]) {
    test('today-overdue ${entry.name} points to the previous occurrence', () {
      // Arrange
      final schedule = aMedicationSchedule(
        scheduling: entry.strategy,
        startDate: entry.start,
      );

      // Act
      final result = resolveSchedules([schedule], entry.now)!;

      // Assert
      expect(result.date, entry.missed);
      expect(result.interval, entry.interval);
      expect(result.isOverdue, isTrue);
    });
  }

  test('monthly interval uses the actual number of calendar days', () {
    // Arrange
    final due = Date(year: 2026, month: 6, day: 21);
    final schedule = aMedicationSchedule(
      scheduling: aMonthlyStrategy(dayOfMonth: 21),
      startDate: due,
    );
    final intake = aMedicationIntake(
      scheduleId: schedule.id,
      takenDateTime: DateTime.utc(2026, 6, 21, 9),
    );

    // Act
    final result = resolveSchedules([schedule], DateTime(2026, 6, 21, 12),
        latest: {schedule.id: intake})!;

    // Assert
    expect(result.date, Date(year: 2026, month: 7, day: 21));
    expect(result.interval, const Duration(days: 30));
  });

  test('monthly interval respects a short February', () {
    // Arrange
    final schedule = aMedicationSchedule(
      scheduling: aMonthlyStrategy(dayOfMonth: 21),
      startDate: Date(year: 2026, month: 3, day: 21),
    );

    // Act
    final result = resolveSchedules([schedule], DateTime(2026, 3, 1, 12))!;

    // Assert
    expect(result.date, Date(year: 2026, month: 3, day: 21));
    expect(result.interval, const Duration(days: 28));
    expect(result.isOverdue, isFalse);
  });

  test('an intake before 4am belongs to the preceding logical day', () {
    // Arrange
    const late = TimeOfDay(hour: 1, minute: 0);
    final schedule = aMedicationSchedule(
      scheduling: aDailyStrategy(intakeTimes: const [late]),
      startDate: monday,
    );

    // Act
    final beforeIntake =
        resolveSchedules([schedule], DateTime(2026, 6, 2, 0, 30))!;
    final afterIntake =
        resolveSchedules([schedule], DateTime(2026, 6, 2, 1, 30))!;

    // Assert
    expect(beforeIntake.isOverdue, isFalse);
    expect(afterIntake.isOverdue, isTrue);
  });
}
