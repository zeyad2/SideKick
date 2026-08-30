import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/providers/repository_providers.dart';
import 'package:sidekick/core/theme/app_theme_scope.dart';
import 'package:sidekick/features/inbox/application/inbox_providers.dart';
import 'package:sidekick/features/reminders/domain/task_reminder.dart';
import 'package:sidekick/features/reminders/presentation/reminder_formatters.dart';

final StreamProvider<List<TaskReminder>> allTaskRemindersProvider =
    StreamProvider<List<TaskReminder>>((Ref ref) {
      return ref.watch(taskRemindersRepositoryProvider).watchAll().map((
        List<TaskReminder> reminders,
      ) {
        final List<TaskReminder> sorted = List<TaskReminder>.of(reminders);
        sorted.sort(_compareReminders);
        return sorted;
      });
    });

int _compareReminders(TaskReminder left, TaskReminder right) {
  final DateTime? a = left.scheduledAt;
  final DateTime? b = right.scheduledAt;
  if (a != null && b != null) return a.compareTo(b);
  if (a != null) return -1;
  if (b != null) return 1;
  return right.updatedAt.compareTo(left.updatedAt);
}

class RemindersScreen extends ConsumerStatefulWidget {
  const RemindersScreen({super.key});

  @override
  ConsumerState<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends ConsumerState<RemindersScreen> {
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final AsyncValue<List<TaskReminder>> reminders = ref.watch(
      allTaskRemindersProvider,
    );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: theme.dimensions.maxReadableWidth,
            ),
            child: reminders.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) =>
                  const Center(child: Text('Reminders will be back shortly.')),
              data: (List<TaskReminder> items) => _buildContent(items),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(List<TaskReminder> items) {
    final theme = context.appTheme;
    final List<TaskReminder> upcoming = items.where(_isUpcoming).toList();
    final List<TaskReminder> selected = items
        .where(
          (TaskReminder reminder) =>
              reminder.scheduledAt != null &&
              isSameLocalDay(reminder.scheduledAt!, _selectedDay),
        )
        .toList();
    final List<TaskReminder> placeReminders = items
        .where(
          (TaskReminder reminder) =>
              reminder.triggerType == TaskReminderTriggerType.place &&
              (reminder.status == TaskReminderStatus.active ||
                  reminder.status == TaskReminderStatus.pendingAutoCommit),
        )
        .toList();
    final List<TaskReminder> inactive = items
        .where(
          (TaskReminder reminder) =>
              reminder.status != TaskReminderStatus.active &&
              reminder.status != TaskReminderStatus.pendingAutoCommit &&
              (reminder.scheduledAt == null ||
                  !isSameLocalDay(reminder.scheduledAt!, _selectedDay)),
        )
        .toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(
        theme.spacing.mobileMargin,
        theme.spacing.lg,
        theme.spacing.mobileMargin,
        theme.spacing.xl * 3,
      ),
      children: <Widget>[
        Text('Reminders', style: theme.textTheme.headlineLarge),
        SizedBox(height: theme.spacing.sm),
        Text(
          'See what is coming, move it forward, or pause it without losing it.',
          style: theme.textTheme.bodyMedium,
        ),
        SizedBox(height: theme.spacing.xl),
        _Section(
          title: 'NEXT UP',
          emptyText: 'Nothing upcoming yet.',
          reminders: upcoming,
        ),
        SizedBox(height: theme.spacing.xl),
        Card(
          margin: EdgeInsets.zero,
          child: CalendarDatePicker(
            initialDate: _selectedDay,
            firstDate: DateTime(2020),
            lastDate: DateTime(DateTime.now().year + 5, 12, 31),
            onDateChanged: (DateTime value) =>
                setState(() => _selectedDay = value),
          ),
        ),
        SizedBox(height: theme.spacing.lg),
        _Section(
          title: reminderDate(_selectedDay).toUpperCase(),
          emptyText: 'No reminders on this day.',
          reminders: selected,
        ),
        if (placeReminders.isNotEmpty) ...<Widget>[
          SizedBox(height: theme.spacing.xl),
          _Section(title: 'PLACE REMINDERS', reminders: placeReminders),
        ],
        if (inactive.isNotEmpty) ...<Widget>[
          SizedBox(height: theme.spacing.xl),
          _Section(title: 'INACTIVE', reminders: inactive),
        ],
      ],
    );
  }

  bool _isUpcoming(TaskReminder reminder) {
    if (reminder.status != TaskReminderStatus.active &&
        reminder.status != TaskReminderStatus.pendingAutoCommit) {
      return false;
    }
    if (reminder.triggerType == TaskReminderTriggerType.place) return false;
    final DateTime? scheduledAt = reminder.scheduledAt;
    return scheduledAt != null &&
        scheduledAt.isAfter(DateTime.now().toUtc()) &&
        !isSameLocalDay(scheduledAt, _selectedDay);
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.reminders,
    this.emptyText,
  });

  final String title;
  final List<TaskReminder> reminders;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: theme.textTheme.labelMedium),
        SizedBox(height: theme.spacing.sm),
        if (reminders.isEmpty)
          Text(emptyText ?? 'None', style: theme.textTheme.bodySmall)
        else
          for (int index = 0; index < reminders.length; index++) ...<Widget>[
            if (index > 0) SizedBox(height: theme.spacing.md),
            _ReminderDetailsCard(reminder: reminders[index]),
          ],
      ],
    );
  }
}

class _ReminderDetailsCard extends ConsumerWidget {
  const _ReminderDetailsCard({required this.reminder});

  final TaskReminder reminder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.appTheme;
    final bool pending =
        reminder.status == TaskReminderStatus.pendingAutoCommit;
    final bool active = reminder.status == TaskReminderStatus.active;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(theme.spacing.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  reminder.triggerType == TaskReminderTriggerType.time
                      ? Icons.schedule_rounded
                      : Icons.place_rounded,
                  color: theme.colors.primary,
                ),
                SizedBox(width: theme.spacing.sm),
                Expanded(
                  child: Text(
                    reminder.title,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                _StatusPill(status: reminder.status),
              ],
            ),
            SizedBox(height: theme.spacing.sm),
            Text(
              reminderScheduleLabel(reminder),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colors.primary,
              ),
            ),
            if (reminder.details?.isNotEmpty ?? false) ...<Widget>[
              SizedBox(height: theme.spacing.sm),
              Text(reminder.details!, style: theme.textTheme.bodySmall),
            ],
            SizedBox(height: theme.spacing.sm),
            Text(
              'Created from ${reminder.source.wire} • ${_triggerDescription(reminder)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colors.onSurfaceVariant,
              ),
            ),
            SizedBox(height: theme.spacing.md),
            if (pending)
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => ref
                          .read(reminderCreationServiceProvider)
                          .approveAutoCommit(reminder.id),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Approve now'),
                    ),
                  ),
                  SizedBox(width: theme.spacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => ref
                          .read(reminderCreationServiceProvider)
                          .cancelReminder(reminder.id),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Cancel'),
                    ),
                  ),
                ],
              )
            else if (active)
              Row(
                children: <Widget>[
                  if (reminder.triggerType == TaskReminderTriggerType.time) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _move(context, ref),
                        icon: const Icon(Icons.event_repeat_rounded),
                        label: const Text('Move'),
                      ),
                    ),
                    SizedBox(width: theme.spacing.sm),
                  ],
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => ref
                          .read(reminderCreationServiceProvider)
                          .cancelReminder(reminder.id),
                      icon: const Icon(Icons.notifications_off_outlined),
                      label: const Text('Cancel'),
                    ),
                  ),
                ],
              )
            else
              FilledButton.icon(
                onPressed: () => _reenable(context, ref),
                icon: const Icon(Icons.replay_rounded),
                label: const Text('Re-enable'),
              ),
          ],
        ),
      ),
    );
  }

  String _triggerDescription(TaskReminder reminder) =>
      reminder.triggerType == TaskReminderTriggerType.time
      ? 'time reminder'
      : 'place reminder';

  Future<void> _move(BuildContext context, WidgetRef ref) async {
    final DateTime? chosen = await _pickFutureDateTime(
      context,
      reminder.scheduledAt,
    );
    if (chosen == null || !context.mounted) return;
    await ref
        .read(reminderCreationServiceProvider)
        .rescheduleReminder(reminder.id, chosen.toUtc());
  }

  Future<void> _reenable(BuildContext context, WidgetRef ref) async {
    DateTime? chosen;
    if (reminder.triggerType == TaskReminderTriggerType.time) {
      chosen = await _pickFutureDateTime(context, reminder.scheduledAt);
      if (chosen == null || !context.mounted) return;
    }
    await ref
        .read(reminderCreationServiceProvider)
        .reenableReminder(reminder.id, scheduledAt: chosen?.toUtc());
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final TaskReminderStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final String label = switch (status) {
      TaskReminderStatus.pendingAutoCommit => 'REVIEW',
      TaskReminderStatus.active => 'ACTIVE',
      TaskReminderStatus.done => 'DONE',
      TaskReminderStatus.dismissed => 'DISMISSED',
      TaskReminderStatus.cancelled => 'CANCELLED',
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: theme.spacing.sm,
        vertical: theme.spacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(theme.radii.pill),
      ),
      child: Text(label, style: theme.textTheme.labelSmall),
    );
  }
}

Future<DateTime?> _pickFutureDateTime(
  BuildContext context,
  DateTime? current,
) async {
  final DateTime now = DateTime.now();
  final DateTime localCurrent =
      current?.toLocal() ?? now.add(const Duration(days: 1));
  final DateTime initial = localCurrent.isAfter(now)
      ? localCurrent
      : now.add(const Duration(days: 1));
  final DateTime? date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(now.year, now.month, now.day),
    lastDate: DateTime(now.year + 5, 12, 31),
    helpText: 'Choose reminder day',
  );
  if (date == null || !context.mounted) return null;
  final TimeOfDay? time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
    helpText: 'Choose reminder time',
  );
  if (time == null) return null;
  final DateTime result = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  if (!result.isAfter(now) && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Choose a time in the future.')),
    );
    return null;
  }
  return result;
}
