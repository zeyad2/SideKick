import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sidekick/core/capture/capture_permissions.dart';
import 'package:sidekick/core/capture/capture_providers.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/router/app_routes.dart';
import 'package:sidekick/core/theme/app_theme_scope.dart';
import 'package:sidekick/core/theme/widgets/persona_orb.dart';
import 'package:sidekick/features/inbox/application/inbox_providers.dart';
import 'package:sidekick/features/places/domain/place.dart';
import 'package:sidekick/features/reminders/application/reminder_creation_service.dart';
import 'package:sidekick/features/reminders/application/reminder_draft_service.dart';
import 'package:sidekick/features/reminders/application/reminder_scheduler.dart';
import 'package:sidekick/features/reminders/domain/task_reminder.dart';
import 'package:sidekick/features/reminders/presentation/reminder_formatters.dart';

class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key, this.editReminderId});

  final String? editReminderId;

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _details = TextEditingController();
  final List<_ReviewDraftEntry> _reviewDrafts = <_ReviewDraftEntry>[];
  TaskReminderTriggerType _manualTrigger = TaskReminderTriggerType.time;
  DateTime? _manualScheduledAt;
  String? _manualPlaceId;
  GeofenceTransition _manualTransition = GeofenceTransition.enter;
  bool _creatingManualReminder = false;
  Timer? _autoCommitTimer;
  String? _openedEditReminderId;
  String? _requestedEditReminderId;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreReviewDrafts());
    ReminderEditDispatcher.attach(_onReminderEditRequested);
    _autoCommitTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _restoreReviewDrafts() async {
    late final List<PendingReviewDraft> drafts;
    try {
      drafts = await ref
          .read(reminderCreationServiceProvider)
          .pendingReviewDrafts();
    } catch (_) {
      return;
    }
    if (!mounted || drafts.isEmpty) return;
    setState(() {
      _reviewDrafts
        ..clear()
        ..addAll(
          drafts.map(
            (PendingReviewDraft draft) => _ReviewDraftEntry(
              draft: draft.draft,
              source: draft.source,
              captureId: draft.captureId,
            ),
          ),
        );
    });
  }

  @override
  void dispose() {
    ReminderEditDispatcher.detach(_onReminderEditRequested);
    _autoCommitTimer?.cancel();
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final AsyncValue<List<TaskReminder>> reminders = ref.watch(
      inboxTaskRemindersProvider,
    );
    final List<Place> places =
        ref.watch(homePlacesProvider).asData?.value ?? <Place>[];
    _maybeOpenLinkedEdit(reminders.asData?.value);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        tooltip: 'Start audio capture',
        onPressed: _startCapture,
        child: const Icon(Icons.mic_rounded),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: theme.dimensions.maxReadableWidth,
            ),
            child: CustomScrollView(
              slivers: <Widget>[
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    theme.spacing.mobileMargin,
                    theme.spacing.lg,
                    theme.spacing.mobileMargin,
                    theme.spacing.md,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const PersonaOrb(),
                        SizedBox(height: theme.spacing.lg),
                        Text(
                          'What’s next',
                          style: theme.textTheme.headlineLarge,
                        ),
                        SizedBox(height: theme.spacing.sm),
                        Text(
                          'Set it manually, or tap the microphone and say it naturally.',
                          style: theme.textTheme.bodyMedium,
                        ),
                        SizedBox(height: theme.spacing.lg),
                        TextField(
                          controller: _title,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'What should I remind you about?',
                            hintText: 'Call the dentist',
                          ),
                        ),
                        SizedBox(height: theme.spacing.md),
                        TextField(
                          controller: _details,
                          minLines: 1,
                          maxLines: 3,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Notes (optional)',
                          ),
                        ),
                        SizedBox(height: theme.spacing.md),
                        SegmentedButton<TaskReminderTriggerType>(
                          segments:
                              const <ButtonSegment<TaskReminderTriggerType>>[
                                ButtonSegment<TaskReminderTriggerType>(
                                  value: TaskReminderTriggerType.time,
                                  icon: Icon(Icons.schedule_rounded),
                                  label: Text('Date & time'),
                                ),
                                ButtonSegment<TaskReminderTriggerType>(
                                  value: TaskReminderTriggerType.place,
                                  icon: Icon(Icons.place_rounded),
                                  label: Text('Place'),
                                ),
                              ],
                          selected: <TaskReminderTriggerType>{_manualTrigger},
                          onSelectionChanged:
                              (Set<TaskReminderTriggerType> selection) =>
                                  setState(
                                    () => _manualTrigger = selection.single,
                                  ),
                        ),
                        SizedBox(height: theme.spacing.md),
                        if (_manualTrigger == TaskReminderTriggerType.time)
                          OutlinedButton.icon(
                            onPressed: _chooseManualDateTime,
                            icon: const Icon(Icons.event_rounded),
                            label: Text(
                              _manualScheduledAt == null
                                  ? 'Choose date and time'
                                  : '${reminderDate(_manualScheduledAt!)} at ${reminderTime(_manualScheduledAt!)}',
                            ),
                          )
                        else ...<Widget>[
                          if (places.isEmpty)
                            Text(
                              'No saved places yet. Add one in the Places tab first.',
                              style: theme.textTheme.bodySmall,
                            )
                          else
                            DropdownButtonFormField<String>(
                              initialValue:
                                  places.any(
                                    (Place place) => place.id == _manualPlaceId,
                                  )
                                  ? _manualPlaceId
                                  : null,
                              decoration: const InputDecoration(
                                labelText: 'Saved place',
                              ),
                              items: places
                                  .map(
                                    (Place place) => DropdownMenuItem<String>(
                                      value: place.id,
                                      child: Text(place.name),
                                    ),
                                  )
                                  .toList(growable: false),
                              onChanged: (String? value) =>
                                  setState(() => _manualPlaceId = value),
                            ),
                          SizedBox(height: theme.spacing.sm),
                          SegmentedButton<GeofenceTransition>(
                            segments: const <ButtonSegment<GeofenceTransition>>[
                              ButtonSegment<GeofenceTransition>(
                                value: GeofenceTransition.enter,
                                label: Text('When I arrive'),
                              ),
                              ButtonSegment<GeofenceTransition>(
                                value: GeofenceTransition.exit,
                                label: Text('When I leave'),
                              ),
                            ],
                            selected: <GeofenceTransition>{_manualTransition},
                            onSelectionChanged:
                                (Set<GeofenceTransition> selection) => setState(
                                  () => _manualTransition = selection.single,
                                ),
                          ),
                        ],
                        SizedBox(height: theme.spacing.md),
                        FilledButton.icon(
                          onPressed: _creatingManualReminder
                              ? null
                              : _createManualReminder,
                          icon: const Icon(Icons.alarm_add_rounded),
                          label: Text(
                            _creatingManualReminder
                                ? 'Creating reminder…'
                                : 'Create reminder',
                          ),
                        ),
                        SizedBox(height: theme.spacing.sm),
                        OutlinedButton.icon(
                          onPressed: _startCapture,
                          icon: const Icon(Icons.mic_rounded),
                          label: const Text('Say it instead'),
                        ),
                        SizedBox(height: theme.spacing.xl),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                'UPCOMING',
                                style: theme.textTheme.labelMedium,
                              ),
                            ),
                            TextButton(
                              onPressed: () => context.go(AppRoutes.reminders),
                              child: const Text('See all'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                reminders.when(
                  loading: () =>
                      const SliverToBoxAdapter(child: SizedBox.shrink()),
                  error: (_, _) =>
                      const SliverToBoxAdapter(child: SizedBox.shrink()),
                  data: (List<TaskReminder> items) => items.isEmpty
                      ? SliverPadding(
                          padding: EdgeInsets.symmetric(
                            horizontal: theme.spacing.mobileMargin,
                          ),
                          sliver: SliverToBoxAdapter(
                            child: Text(
                              'Nothing upcoming yet.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        )
                      : SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            theme.spacing.mobileMargin,
                            theme.spacing.sm,
                            theme.spacing.mobileMargin,
                            theme.spacing.xl,
                          ),
                          sliver: SliverList.separated(
                            itemCount: items.take(3).length,
                            separatorBuilder: (_, _) =>
                                SizedBox(height: theme.spacing.md),
                            itemBuilder: (BuildContext context, int index) =>
                                _ReminderCard(reminder: items[index]),
                          ),
                        ),
                ),
                if (_reviewDrafts.isNotEmpty)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      theme.spacing.mobileMargin,
                      theme.spacing.sm,
                      theme.spacing.mobileMargin,
                      theme.spacing.xl,
                    ),
                    sliver: SliverList.separated(
                      itemCount: _reviewDrafts.length,
                      separatorBuilder: (_, _) =>
                          SizedBox(height: theme.spacing.md),
                      itemBuilder: (BuildContext context, int index) =>
                          _ReviewDraftCard(
                            entry: _reviewDrafts[index],
                            onApprove:
                                ({
                                  required String title,
                                  String? details,
                                  DateTime? scheduledAt,
                                }) => _approveReviewDraft(
                                  _reviewDrafts[index],
                                  title: title,
                                  details: details,
                                  scheduledAt: scheduledAt,
                                ),
                            onDismiss: () =>
                                _dismissReviewDraft(_reviewDrafts[index]),
                          ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: SizedBox(height: theme.spacing.xl * 3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onReminderEditRequested(String reminderId) {
    if (!mounted) return;
    setState(() => _requestedEditReminderId = reminderId);
  }

  void _maybeOpenLinkedEdit(List<TaskReminder>? reminders) {
    final String? id = widget.editReminderId ?? _requestedEditReminderId;
    if (id == null || id.isEmpty || _openedEditReminderId == id) return;
    TaskReminder? reminder;
    for (final TaskReminder row in reminders ?? const <TaskReminder>[]) {
      if (row.id == id) {
        reminder = row;
        break;
      }
    }
    if (reminder == null) return;
    final TaskReminder linkedReminder = reminder;
    _openedEditReminderId = id;
    if (_requestedEditReminderId == id) {
      _requestedEditReminderId = null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final _EditedReminder? edited = await showDialog<_EditedReminder>(
        context: context,
        builder: (BuildContext dialogContext) =>
            _EditAutoCommitDialog(reminder: linkedReminder),
      );
      if (!mounted || edited == null) return;
      await ref
          .read(reminderCreationServiceProvider)
          .editReminder(
            linkedReminder.id,
            title: edited.title,
            details: edited.details,
          );
    });
  }

  Future<void> _createManualReminder() async {
    if (_title.text.trim().isEmpty) {
      _showMessage('Add a reminder title first.');
      return;
    }
    if (_manualTrigger == TaskReminderTriggerType.time &&
        _manualScheduledAt == null) {
      _showMessage('Choose a date and time.');
      return;
    }
    if (_manualTrigger == TaskReminderTriggerType.place &&
        _manualPlaceId == null) {
      _showMessage('Choose a saved place.');
      return;
    }
    if (_manualTrigger == TaskReminderTriggerType.place) {
      final CapturePermissions permissions = CapturePermissions(
        ref.read(nativeCaptureApiProvider),
      );
      final bool foreground = await permissions.requestLocation();
      final bool background = foreground
          ? await permissions.requestBackgroundLocation()
          : false;
      if (!mounted) return;
      if (!foreground || !background) {
        _showMessage('Location access is needed for place reminders.');
        return;
      }
    }
    setState(() => _creatingManualReminder = true);
    try {
      await ref
          .read(reminderCreationServiceProvider)
          .createManualReminder(
            title: _title.text,
            details: _details.text,
            triggerType: _manualTrigger,
            scheduledAt: _manualScheduledAt?.toUtc(),
            placeId: _manualPlaceId,
            geofenceTransition: _manualTransition,
          );
    } catch (error) {
      if (!mounted) return;
      _showMessage('Could not create reminder: $error');
      return;
    } finally {
      if (mounted) setState(() => _creatingManualReminder = false);
    }
    if (!mounted) return;
    _title.clear();
    _details.clear();
    setState(() {
      _manualScheduledAt = null;
      _manualPlaceId = null;
    });
    _showMessage('Reminder created.');
  }

  Future<void> _chooseManualDateTime() async {
    final DateTime now = DateTime.now();
    final DateTime initial =
        _manualScheduledAt ?? now.add(const Duration(hours: 1));
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: 'Choose reminder day',
    );
    if (date == null || !mounted) return;
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Choose reminder time',
    );
    if (time == null) return;
    final DateTime selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!selected.isAfter(now)) {
      _showMessage('Choose a time in the future.');
      return;
    }
    setState(() => _manualScheduledAt = selected);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _startCapture() async {
    final permissions = CapturePermissions(ref.read(nativeCaptureApiProvider));
    final bool microphone = await permissions.requestMicrophone();
    final bool notifications = await permissions.requestNotifications();
    if (!mounted) return;
    if (!microphone || !notifications) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone and notification access are needed.'),
        ),
      );
      return;
    }
    await ref.read(captureCoordinatorProvider)?.startCapture();
  }

  Future<void> _approveReviewDraft(
    _ReviewDraftEntry entry, {
    required String title,
    String? details,
    DateTime? scheduledAt,
  }) async {
    await ref
        .read(reminderCreationServiceProvider)
        .approveReviewedDraft(
          entry.draft,
          source: entry.source,
          captureId: entry.captureId,
          title: title,
          details: details,
          scheduledAt: scheduledAt,
        );
    if (!mounted) return;
    setState(() => _reviewDrafts.remove(entry));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reviewed reminder activated.')),
    );
  }

  Future<void> _dismissReviewDraft(_ReviewDraftEntry entry) async {
    await ref
        .read(reminderCreationServiceProvider)
        .dismissReviewedDraft(
          PendingReviewDraft(
            captureId: entry.captureId,
            source: entry.source,
            draft: entry.draft,
          ),
        );
    if (!mounted) return;
    setState(() => _reviewDrafts.remove(entry));
  }
}

class _ReviewDraftEntry {
  const _ReviewDraftEntry({
    required this.draft,
    required this.source,
    required this.captureId,
  });

  final ParsedReminderDraft draft;
  final TaskReminderSource source;
  final String captureId;
}

class _ReviewDraftCard extends StatefulWidget {
  const _ReviewDraftCard({
    required this.entry,
    required this.onApprove,
    required this.onDismiss,
  });

  final _ReviewDraftEntry entry;
  final Future<void> Function({
    required String title,
    String? details,
    DateTime? scheduledAt,
  })
  onApprove;
  final VoidCallback onDismiss;

  @override
  State<_ReviewDraftCard> createState() => _ReviewDraftCardState();
}

class _ReviewDraftCardState extends State<_ReviewDraftCard> {
  late final TextEditingController _title;
  late final TextEditingController _details;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.entry.draft.title);
    _details = TextEditingController(text: widget.entry.draft.details ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final ParsedReminderDraft draft = widget.entry.draft;
    final bool hasTrigger = draft.hasConcreteTrigger;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(theme.spacing.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.rate_review_rounded, color: theme.colors.primary),
                SizedBox(width: theme.spacing.sm),
                Expanded(
                  child: Text(
                    'Review reminder',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            SizedBox(height: theme.spacing.sm),
            Text(draft.explanation, style: theme.textTheme.bodySmall),
            SizedBox(height: theme.spacing.md),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            SizedBox(height: theme.spacing.sm),
            TextField(
              controller: _details,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Details'),
            ),
            SizedBox(height: theme.spacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.onDismiss,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Dismiss'),
                  ),
                ),
                SizedBox(width: theme.spacing.sm),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => widget.onApprove(
                      title: _title.text.trim().isEmpty
                          ? draft.title
                          : _title.text.trim(),
                      details: _details.text.trim().isEmpty
                          ? null
                          : _details.text.trim(),
                      scheduledAt: hasTrigger
                          ? draft.scheduledAt
                          : _tomorrow9(),
                    ),
                    icon: const Icon(Icons.check_rounded),
                    label: Text(hasTrigger ? 'Approve' : 'Use tomorrow'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static DateTime _tomorrow9() {
    final DateTime now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day + 1, 9);
  }
}

class _ReminderCard extends ConsumerWidget {
  const _ReminderCard({required this.reminder});

  final TaskReminder reminder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.appTheme;
    final bool pending =
        reminder.status == TaskReminderStatus.pendingAutoCommit;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(theme.spacing.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  pending
                      ? Icons.hourglass_bottom_rounded
                      : Icons.alarm_on_rounded,
                  color: pending
                      ? theme.colors.primary
                      : theme.colors.secondary,
                ),
                SizedBox(width: theme.spacing.sm),
                Expanded(
                  child: Text(
                    reminder.title,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (reminder.aiExplanation != null) ...[
              SizedBox(height: theme.spacing.xs),
              Text(reminder.aiExplanation!, style: theme.textTheme.bodySmall),
            ],
            SizedBox(height: theme.spacing.sm),
            Text(
              reminderScheduleLabel(reminder),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colors.primary,
              ),
            ),
            SizedBox(height: theme.spacing.sm),
            Text(
              pending
                  ? 'AUTO-COMMIT COUNTDOWN'
                  : reminder.status.wire.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: pending ? theme.colors.primary : theme.colors.secondary,
              ),
            ),
            if (pending) ...[
              SizedBox(height: theme.spacing.md),
              Text(
                '${_secondsRemaining(reminder)}s remaining',
                style: theme.textTheme.bodySmall,
              ),
              SizedBox(height: theme.spacing.sm),
              FilledButton.icon(
                onPressed: () => ref
                    .read(reminderCreationServiceProvider)
                    .approveAutoCommit(reminder.id),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Approve now'),
              ),
              SizedBox(height: theme.spacing.sm),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showEditDialog(context, ref),
                      icon: const Icon(Icons.edit_rounded),
                      label: const Text('Edit'),
                    ),
                  ),
                  SizedBox(width: theme.spacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => ref
                          .read(reminderCreationServiceProvider)
                          .cancelAutoCommit(reminder.id),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              SizedBox(height: theme.spacing.md),
              OutlinedButton.icon(
                onPressed: () => _showEditDialog(context, ref),
                icon: const Icon(Icons.edit_rounded),
                label: const Text('Edit'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showEditDialog(BuildContext context, WidgetRef ref) async {
    final _EditedReminder? edited = await showDialog<_EditedReminder>(
      context: context,
      builder: (BuildContext dialogContext) =>
          _EditAutoCommitDialog(reminder: reminder),
    );
    if (edited == null) return;
    if (reminder.status == TaskReminderStatus.pendingAutoCommit) {
      await ref
          .read(reminderCreationServiceProvider)
          .editAutoCommit(
            reminder.id,
            title: edited.title,
            details: edited.details,
          );
    } else {
      await ref
          .read(reminderCreationServiceProvider)
          .editReminder(
            reminder.id,
            title: edited.title,
            details: edited.details,
          );
    }
  }

  static int _secondsRemaining(TaskReminder reminder) {
    final DateTime? deadline = reminder.autoCommitDeadlineAt;
    if (deadline == null) return 0;
    final int seconds = deadline.difference(DateTime.now().toUtc()).inSeconds;
    return seconds < 0 ? 0 : seconds;
  }
}

class _EditedReminder {
  const _EditedReminder({required this.title, this.details});

  final String title;
  final String? details;
}

class _EditAutoCommitDialog extends StatefulWidget {
  const _EditAutoCommitDialog({required this.reminder});

  final TaskReminder reminder;

  @override
  State<_EditAutoCommitDialog> createState() => _EditAutoCommitDialogState();
}

class _EditAutoCommitDialogState extends State<_EditAutoCommitDialog> {
  late final TextEditingController _title;
  late final TextEditingController _details;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.reminder.title);
    _details = TextEditingController(text: widget.reminder.details ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return AlertDialog(
      title: const Text('Edit reminder'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _title,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          SizedBox(height: theme.spacing.sm),
          TextField(
            controller: _details,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Details'),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final String title = _title.text.trim();
            if (title.isEmpty) return;
            final String details = _details.text.trim();
            Navigator.of(context).pop(
              _EditedReminder(
                title: title,
                details: details.isEmpty ? null : details,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
