import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/features/reminders/domain/task_reminder.dart';

const List<String> _months = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> _shortWeekdays = <String>[
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

String reminderDate(DateTime value) {
  final DateTime local = value.toLocal();
  return '${_shortWeekdays[local.weekday - 1]}, ${_months[local.month - 1]} ${local.day}';
}

String reminderTime(DateTime value) {
  final DateTime local = value.toLocal();
  final int hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final String minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${local.hour < 12 ? 'AM' : 'PM'}';
}

String reminderScheduleLabel(TaskReminder reminder) {
  if (reminder.triggerType == TaskReminderTriggerType.place) {
    final String transition = switch (reminder.geofenceTransition) {
      GeofenceTransition.enter => 'when you arrive',
      GeofenceTransition.exit => 'when you leave',
      null => 'at a saved place',
    };
    return reminder.placeId == null ? transition : '$transition • saved place';
  }
  final DateTime? scheduledAt = reminder.scheduledAt;
  if (scheduledAt == null) return 'Time not set';
  return '${reminderDate(scheduledAt)} at ${reminderTime(scheduledAt)}';
}

bool isSameLocalDay(DateTime left, DateTime right) {
  final DateTime a = left.toLocal();
  final DateTime b = right.toLocal();
  return a.year == b.year && a.month == b.month && a.day == b.day;
}
