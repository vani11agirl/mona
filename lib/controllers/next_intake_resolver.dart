import 'package:flutter/material.dart';
import 'package:mona/data/model/date.dart';
import 'package:mona/data/model/intake_slot.dart';
import 'package:mona/data/model/scheduling_strategy.dart';

/// A date-only schedule has no exact due time; notification times are reminders.
typedef NextIntake = ({
  Date date,
  TimeOfDay? time,
  Duration interval,
  bool isOverdue,
});

/// Chooses the oldest missed intake, or the soonest upcoming one.
///
/// The slots come from `SlotsBuilder`, so intake history and schedule status
/// follow the same rules as the home page. Completed slots advance to their
/// next occurrence instead of making the widget appear empty until tomorrow.
NextIntake? resolveNextIntake(Iterable<IntakeSlot> slots, DateTime now) {
  NextIntake? selected;
  for (final slot in slots) {
    final candidate = _candidate(slot, now);
    if (candidate != null &&
        (selected == null || _compare(candidate, selected) < 0)) {
      selected = candidate;
    }
  }
  return selected;
}

NextIntake? _candidate(IntakeSlot slot, DateTime now) {
  final taken = slot.status == ScheduleStatus.taken;
  final statusOverdue = slot.status == ScheduleStatus.overdue ||
      slot.status == ScheduleStatus.todayOverdue;

  switch (slot.schedule.scheduling) {
    case AsNeededSchedule _:
      return null;
    case DailySchedule scheduling:
      final time = slot.time;
      if (time == null) return null;
      final date = taken ? slot.date.add(const Duration(days: 1)) : slot.date;
      return (
        date: date,
        time: time,
        interval: _dailyInterval(scheduling.intakeTimes, time),
        isOverdue: !taken && date.toDateTimeAt(time).isBefore(now),
      );
    case IntervalDaysSchedule scheduling:
      final interval = Duration(days: scheduling.intervalDays);
      return (
        date: taken
            ? slot.date.add(interval)
            : slot.status == ScheduleStatus.todayOverdue
                ? slot.date.subtract(interval)
                : slot.date,
        time: null,
        interval: interval,
        isOverdue: statusOverdue,
      );
    case DynamicIntervalSchedule scheduling:
      return (
        date: slot.date,
        time: null,
        interval: Duration(days: scheduling.intervalDays),
        isOverdue: statusOverdue,
      );
    case WeeklySchedule scheduling:
      if (!scheduling.daysOfWeek.any(
        (day) => day >= DateTime.monday && day <= DateTime.sunday,
      )) {
        return null;
      }
      final date = taken
          ? _nextWeekday(slot.date, scheduling.daysOfWeek)
          : slot.status == ScheduleStatus.todayOverdue
              ? slot.date.subtract(
                  _weeklyInterval(slot.date, scheduling.daysOfWeek),
                )
              : slot.date;
      return (
        date: date,
        time: null,
        interval: _weeklyInterval(date, scheduling.daysOfWeek),
        isOverdue: statusOverdue && !taken,
      );
    case MonthlySchedule scheduling:
      final date = taken
          ? slot.date.addMonths(scheduling.intervalMonths)
          : slot.status == ScheduleStatus.todayOverdue
              ? slot.date.addMonths(-scheduling.intervalMonths)
              : slot.date;
      return (
        date: date,
        time: null,
        interval: date.value.difference(
          date.addMonths(-scheduling.intervalMonths).value,
        ),
        isOverdue: statusOverdue && !taken,
      );
  }
}

Date _nextWeekday(Date date, List<int> weekdays) {
  for (var days = 1; days < 7; days++) {
    final candidate = date.add(Duration(days: days));
    if (weekdays.contains(candidate.weekday)) return candidate;
  }
  // The caller guarantees a valid weekday; only this weekday remains.
  return date.add(const Duration(days: 7));
}

Duration _weeklyInterval(Date date, List<int> weekdays) {
  for (var days = 1; days < 7; days++) {
    if (weekdays.contains(date.subtract(Duration(days: days)).weekday)) {
      return Duration(days: days);
    }
  }
  // The caller guarantees a valid weekday; only this weekday remains.
  return const Duration(days: 7);
}

Duration _dailyInterval(List<TimeOfDay> times, TimeOfDay dueTime) {
  final dueMinute = _logicalMinute(dueTime);
  final previous = times
      .map(_logicalMinute)
      .where((minute) => minute < dueMinute)
      .fold<int?>(
          null,
          (latest, minute) =>
              latest == null || minute > latest ? minute : latest);
  final wraparound = times.map(_logicalMinute).reduce((a, b) => a > b ? a : b);
  return Duration(minutes: dueMinute - (previous ?? wraparound - 1440));
}

int _logicalMinute(TimeOfDay time) =>
    (time.hour * 60 + time.minute - logicalDayStartMinutes + 1440) % 1440;

int _compare(NextIntake a, NextIntake b) {
  if (a.isOverdue != b.isOverdue) return a.isOverdue ? -1 : 1;
  final dateOrder = a.date.value.compareTo(b.date.value);
  if (dateOrder != 0) return dateOrder;
  if (a.time == null) return b.time == null ? 0 : -1;
  if (b.time == null) return 1;
  return _logicalMinute(a.time!).compareTo(_logicalMinute(b.time!));
}
