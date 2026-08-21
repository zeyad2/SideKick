import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/core/capture/capture_permissions.dart';
import 'package:sidekick/core/capture/capture_providers.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/theme/app_theme_scope.dart';
import 'package:sidekick/core/theme/widgets/persona_orb.dart';
import 'package:sidekick/features/inbox/application/inbox_providers.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';
import 'package:sidekick/features/reminders/application/reminder_creation_service.dart';
import 'package:sidekick/features/reminders/application/reminder_draft_service.dart';
import 'package:sidekick/features/reminders/domain/task_reminder.dart';

class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  final TextEditingController _input = TextEditingController();
  final List<_ReviewDraftEntry> _reviewDrafts = <_ReviewDraftEntry>[];
  Timer? _autoCommitTimer;

  @override
  void initState() {
    super.initState();
    _autoCommitTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      ref.read(reminderCreationServiceProvider).activateDueAutoCommits();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _autoCommitTimer?.cancel();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final AsyncValue<List<Capture>> captures = ref.watch(inboxCapturesProvider);
    final AsyncValue<List<TaskReminder>> reminders = ref.watch(
      inboxTaskRemindersProvider,
    );

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
                          'Capture reminder',
                          style: theme.textTheme.headlineLarge,
                        ),
                        SizedBox(height: theme.spacing.sm),
                        Text(
                          'Type or record one reminder. Sidekick will infer the task, time, and place trigger.',
                          style: theme.textTheme.bodyMedium,
                        ),
                        SizedBox(height: theme.spacing.lg),
                        TextField(
                          controller: _input,
                          minLines: 2,
                          maxLines: 4,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Reminder',
                            hintText: 'Remind me to...',
                          ),
                        ),
                        SizedBox(height: theme.spacing.md),
                        FilledButton.icon(
                          onPressed: _queueTypedReminder,
                          icon: const Icon(Icons.send_rounded),
                          label: const Text('Draft reminder'),
                        ),
                        SizedBox(height: theme.spacing.xl),
                        Text('REMINDERS', style: theme.textTheme.labelMedium),
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
                              'No reminder drafts yet.',
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
                            itemCount: items.length,
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
                                setState(() => _reviewDrafts.removeAt(index)),
                          ),
                    ),
                  ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    theme.spacing.mobileMargin,
                    theme.spacing.lg,
                    theme.spacing.mobileMargin,
                    theme.spacing.md,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'AUDIO CAPTURES',
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                ),
                captures.when(
                  loading: () => const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: PersonaOrb(isPulsing: true)),
                  ),
                  error: (_, _) => const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text('Captures will be back shortly.'),
                    ),
                  ),
                  data: (List<Capture> items) => items.isEmpty
                      ? SliverFillRemaining(
                          hasScrollBody: false,
                          child: Padding(
                            padding: EdgeInsets.all(theme.spacing.xl),
                            child: Center(
                              child: Text(
                                'No captured audio waiting.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineSmall,
                              ),
                            ),
                          ),
                        )
                      : SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            theme.spacing.mobileMargin,
                            theme.spacing.sm,
                            theme.spacing.mobileMargin,
                            theme.spacing.xl * 3,
                          ),
                          sliver: SliverList.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, _) =>
                                SizedBox(height: theme.spacing.md),
                            itemBuilder: (BuildContext context, int index) =>
                                _CaptureCard(
                                  capture: items[index],
                                  onReviewDrafts: _addReviewDrafts,
                                ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _queueTypedReminder() async {
    final String text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    late final ReminderCreationResult result;
    try {
      result = await ref.read(reminderCreationServiceProvider).submitText(text);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Drafting failed: $error')));
      return;
    }
    if (!mounted) return;
    _addReviewDrafts(result, TaskReminderSource.typed);
    final String message = result.autoCommitted.isNotEmpty
        ? '${result.autoCommitted.length} reminder draft(s) auto-commit in 10 seconds.'
        : '${result.needsReview.length} reminder draft(s) need review.';
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

  void _addReviewDrafts(
    ReminderCreationResult result,
    TaskReminderSource source,
  ) {
    final String? captureId = result.captureId;
    if (captureId == null || result.needsReview.isEmpty) return;
    setState(() {
      _reviewDrafts.addAll(
        result.needsReview.map(
          (ParsedReminderDraft draft) => _ReviewDraftEntry(
            draft: draft,
            source: source,
            captureId: captureId,
          ),
        ),
      );
    });
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

class _CaptureCard extends ConsumerWidget {
  const _CaptureCard({required this.capture, required this.onReviewDrafts});

  final Capture capture;
  final void Function(ReminderCreationResult result, TaskReminderSource source)
  onReviewDrafts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.appTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(theme.spacing.card),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(_statusIcon(capture.status), color: theme.colors.primary),
            SizedBox(width: theme.spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _statusTitle(capture.status),
                    style: theme.textTheme.titleMedium,
                  ),
                  SizedBox(height: theme.spacing.xs),
                  Text(
                    capture.rawTranscript ??
                        capture.audioPath ??
                        'Audio is saved locally for reminder drafting.',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colors.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(height: theme.spacing.sm),
                  Text(
                    capture.status.name.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colors.secondary,
                    ),
                  ),
                  if (capture.status == CaptureStatus.pending ||
                      capture.status == CaptureStatus.failed) ...[
                    SizedBox(height: theme.spacing.md),
                    OutlinedButton.icon(
                      onPressed: () => _processAudio(context, ref),
                      icon: const Icon(Icons.replay_rounded),
                      label: Text(
                        capture.status == CaptureStatus.failed
                            ? 'Retry audio'
                            : 'Draft audio',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _statusIcon(CaptureStatus status) => switch (status) {
    CaptureStatus.pending => Icons.graphic_eq_rounded,
    CaptureStatus.processing => Icons.sync_rounded,
    CaptureStatus.failed => Icons.error_outline_rounded,
    _ => Icons.task_alt_rounded,
  };

  static String _statusTitle(CaptureStatus status) => switch (status) {
    CaptureStatus.pending => 'Audio queued',
    CaptureStatus.processing => 'Preparing reminder draft',
    CaptureStatus.failed => 'Audio needs retry',
    _ => 'Capture ready for POC drafting',
  };

  Future<void> _processAudio(BuildContext context, WidgetRef ref) async {
    final ReminderCreationResult result = await ref
        .read(reminderCreationServiceProvider)
        .processAudioCapture(capture);
    if (!context.mounted) return;
    onReviewDrafts(result, TaskReminderSource.audio);
    final String message = result.unclearAudio
        ? result.retryLimitReached
              ? 'Audio was unclear twice. Type the reminder instead.'
              : 'Audio was unclear. Try recording again.'
        : result.autoCommitted.isNotEmpty
        ? '${result.autoCommitted.length} reminder draft(s) auto-commit in 10 seconds.'
        : '${result.needsReview.length} reminder draft(s) need review.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
    await ref
        .read(reminderCreationServiceProvider)
        .editAutoCommit(
          reminder.id,
          title: edited.title,
          details: edited.details,
        );
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
