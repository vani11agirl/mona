import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mona/controllers/next_intake_resolver.dart';
import 'package:mona/data/model/date.dart';
import 'package:mona/data/model/intake_slot.dart';
import 'package:mona/data/model/scheduling_strategy.dart';

import '../fixtures.dart';

void main() {
  final monday = Date(year: 2026, month: 6, day: 1);
  final noon = DateTime(2026, 6, 1, 12);

  test('ignores as-needed schedules and returns null without a due intake', () {
    final schedule = aMedicationSchedule(
      scheduling: anAsNeededStrategy(),
      startDate: monday,
    );
    final slots = [
      IntakeSlot(
        schedule: schedule,
        status: ScheduleStatus.asNeeded,
        date: monday,
      ),
    ];

    expect(resolveNextIntake([], noon), isNull);
    expect(resolveNextIntake(slots, noon), isNull);
  });

  test('oldest missed intake takes priority over upcoming intakes', () {
    final schedule = aMedicationSchedule(
      scheduling: anIntervalStrategy(intervalDays: 7),
      startDate: monday,
    );
    final overdue = monday.subtract(const Duration(days: 7));
    final upcoming = monday.add(const Duration(days: 5));
    final slots = [
      IntakeSlot(
        schedule: schedule,
        status: ScheduleStatus.upcoming,
        date: upcoming,
      ),
      IntakeSlot(
        schedule: schedule,
        status: ScheduleStatus.overdue,
        date: overdue,
      ),
    ];

    final result = resolveNextIntake(slots, noon)!;
    expect(result.date, overdue);
    expect(result.time, isNull);
    expect(result.interval, const Duration(days: 7));
    expect(result.isOverdue, isTrue);
  });

  test('daily schedules use intake times, not just the calendar day', () {
    final schedule = aMedicationSchedule(
      scheduling: aDailyStrategy(intakeTimes: const [morning, afternoon]),
      startDate: monday,
    );
    final slots = [
      IntakeSlot(
        schedule: schedule,
        status: ScheduleStatus.today,
        date: monday,
        time: afternoon,
      ),
      IntakeSlot(
        schedule: schedule,
        status: ScheduleStatus.today,
        date: monday,
        time: morning,
      ),
    ];

    final result = resolveNextIntake(slots, noon)!;
    expect(result.time, morning);
    expect(result.interval, const Duration(hours: 18));
    expect(result.isOverdue, isTrue);
  });

  test('completed daily intake advances to its next occurrence', () {
    final schedule = aMedicationSchedule(
      scheduling: aDailyStrategy(intakeTimes: const [morning]),
      startDate: monday,
    );
    final slot = IntakeSlot(
      schedule: schedule,
      status: ScheduleStatus.taken,
      date: monday,
      time: morning,
    );

    final result = resolveNextIntake([slot], noon)!;
    expect(result.date, monday.add(const Duration(days: 1)));
    expect(result.time, morning);
    expect(result.interval, const Duration(days: 1));
    expect(result.isOverdue, isFalse);
  });

  test('completed interval intake advances by its configured interval', () {
    final schedule = aMedicationSchedule(
      scheduling: anIntervalStrategy(intervalDays: 5),
      startDate: monday,
    );
    final slot = IntakeSlot(
      schedule: schedule,
      status: ScheduleStatus.taken,
      date: monday,
    );

    final result = resolveNextIntake([slot], noon)!;
    expect(result.date, monday.add(const Duration(days: 5)));
    expect(result.interval, const Duration(days: 5));
    expect(result.isOverdue, isFalse);
  });

  test('today-overdue interval points to the missed previous date', () {
    final previous = monday.subtract(const Duration(days: 7));
    final schedule = aMedicationSchedule(
      scheduling: anIntervalStrategy(intervalDays: 7),
      startDate: previous,
    );
    final slot = IntakeSlot(
      schedule: schedule,
      status: ScheduleStatus.todayOverdue,
      date: monday,
    );

    final result = resolveNextIntake([slot], noon)!;
    expect(result.date, previous);
    expect(result.isOverdue, isTrue);
  });

  test('dynamic interval already contains the post-intake due date', () {
    final schedule = aMedicationSchedule(
      scheduling: aDynamicIntervalStrategy(intervalDays: 5),
      startDate: monday,
    );
    final dueDate = monday.add(const Duration(days: 5));
    final slot = IntakeSlot(
      schedule: schedule,
      status: ScheduleStatus.taken,
      date: dueDate,
    );

    final result = resolveNextIntake([slot], noon)!;
    expect(result.date, dueDate);
    expect(result.interval, const Duration(days: 5));
  });

  test('completed weekly intake advances to the next configured weekday', () {
    final schedule = aMedicationSchedule(
      scheduling: aWeeklyStrategy(daysOfWeek: const [1, 4]),
      startDate: monday,
    );
    final slot = IntakeSlot(
      schedule: schedule,
      status: ScheduleStatus.taken,
      date: monday,
    );

    final result = resolveNextIntake([slot], noon)!;
    expect(result.date, monday.add(const Duration(days: 3)));
    expect(result.interval, const Duration(days: 3));
  });

  test('today-overdue weekly intake points to the previous weekday', () {
    final schedule = aMedicationSchedule(
      scheduling: aWeeklyStrategy(daysOfWeek: const [1, 4]),
      startDate: monday.subtract(const Duration(days: 7)),
    );
    final slot = IntakeSlot(
      schedule: schedule,
      status: ScheduleStatus.todayOverdue,
      date: monday,
    );

    final result = resolveNextIntake([slot], noon)!;
    expect(result.date, monday.subtract(const Duration(days: 4)));
    expect(result.interval, const Duration(days: 3));
    expect(result.isOverdue, isTrue);
  });

  test('monthly interval uses the actual number of calendar days', () {
    final due = Date(year: 2026, month: 6, day: 21);
    final schedule = aMedicationSchedule(
      scheduling: aMonthlyStrategy(dayOfMonth: 21),
      startDate: due,
    );
    final slot = IntakeSlot(
      schedule: schedule,
      status: ScheduleStatus.taken,
      date: due,
    );

    final result = resolveNextIntake([slot], noon)!;
    expect(result.date, Date(year: 2026, month: 7, day: 21));
    expect(result.interval, const Duration(days: 30));
  });

  test('monthly interval respects a short February', () {
    final due = Date(year: 2026, month: 3, day: 21);
    final schedule = aMedicationSchedule(
      scheduling: aMonthlyStrategy(dayOfMonth: 21),
      startDate: due,
    );
    final slot = IntakeSlot(
      schedule: schedule,
      status: ScheduleStatus.upcoming,
      date: due,
    );

    expect(resolveNextIntake([slot], noon)!.interval, const Duration(days: 28));
  });

  test('today-overdue monthly intake points to the previous month', () {
    final due = Date(year: 2026, month: 6, day: 21);
    final schedule = aMedicationSchedule(
      scheduling: aMonthlyStrategy(dayOfMonth: 21),
      startDate: Date(year: 2026, month: 5, day: 21),
    );
    final slot = IntakeSlot(
      schedule: schedule,
      status: ScheduleStatus.todayOverdue,
      date: due,
    );

    final result = resolveNextIntake([slot], noon)!;
    expect(result.date, Date(year: 2026, month: 5, day: 21));
    expect(result.isOverdue, isTrue);
  });

  test('an intake before 4am belongs to the preceding logical day', () {
    const late = TimeOfDay(hour: 1, minute: 0);
    final schedule = aMedicationSchedule(
      scheduling: aDailyStrategy(intakeTimes: const [late]),
      startDate: monday,
    );
    final slot = IntakeSlot(
      schedule: schedule,
      status: ScheduleStatus.today,
      date: monday,
      time: late,
    );

    expect(resolveNextIntake([slot], DateTime(2026, 6, 2, 0, 30))!.isOverdue,
        isFalse);
    expect(resolveNextIntake([slot], DateTime(2026, 6, 2, 1, 30))!.isOverdue,
        isTrue);
  });
}
