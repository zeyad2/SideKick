import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/core/capture/capture_permissions.dart';
import 'package:sidekick/core/capture/capture_providers.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/providers/repository_providers.dart';
import 'package:sidekick/core/theme/app_theme_scope.dart';
import 'package:sidekick/core/theme/widgets/persona_orb.dart';
import 'package:sidekick/features/inbox/application/auto_commit_notifications.dart';
import 'package:sidekick/features/inbox/application/capture_processing_providers.dart';
import 'package:sidekick/features/inbox/application/capture_triage_service.dart';
import 'package:sidekick/features/inbox/application/inbox_providers.dart';
import 'package:sidekick/features/inbox/application/recent_auto_commits.dart';
import 'package:sidekick/features/inbox/domain/auto_commit_receipt.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';
import 'package:sidekick/features/inbox/domain/proposed_item.dart';
import 'package:sidekick/features/tasks/domain/task.dart';

class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? editCaptureId = ref.watch(autoCommitEditRequestProvider);
    if (editCaptureId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openAutoCommitEditor(context, ref, editCaptureId);
      });
    }
    final theme = context.appTheme;
    final AsyncValue<List<Capture>> captures = ref.watch(inboxCapturesProvider);
    final EnergyMode energy =
        ref.watch(energyModeProvider).asData?.value ?? EnergyMode.normal;
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        tooltip: 'Capture a thought',
        onPressed: () => _startCapture(context, ref),
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
                          'Your inbox',
                          style: theme.textTheme.headlineLarge,
                        ),
                        SizedBox(height: theme.spacing.sm),
                        Text(
                          'Thoughts land here safely. Sort them when you have the room.',
                          style: theme.textTheme.bodyMedium,
                        ),
                        SizedBox(height: theme.spacing.lg),
                        Text(
                          'ENERGY RIGHT NOW',
                          style: theme.textTheme.labelMedium,
                        ),
                        SizedBox(height: theme.spacing.sm),
                        _EnergySelector(
                          selected: energy,
                          onSelected: (EnergyMode mode) =>
                              ref.read(energyModeServiceProvider).setMode(mode),
                        ),
                        SizedBox(height: theme.spacing.xl),
                        Text('CAPTURES', style: theme.textTheme.labelMedium),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: _AutoAddedStrip()),
                captures.when(
                  loading: () => const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: PersonaOrb(isPulsing: true)),
                  ),
                  error: (Object error, StackTrace stack) =>
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Text('Your inbox will be back shortly.'),
                        ),
                      ),
                  data: (List<Capture> items) => items.isEmpty
                      ? SliverFillRemaining(
                          hasScrollBody: false,
                          child: Padding(
                            padding: EdgeInsets.all(theme.spacing.xl),
                            child: Center(
                              child: Text(
                                'Nothing waiting. Your mind can exhale.',
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
                            itemBuilder: (BuildContext context, int index) {
                              final Capture capture = items[index];
                              return _CaptureCard(
                                capture: capture,
                                onOpen: capture.status == CaptureStatus.ready
                                    ? () => _openTriage(context, ref, capture)
                                    : capture.status == CaptureStatus.failed
                                    ? () => ref
                                          .read(
                                            captureProcessingServiceProvider,
                                          )
                                          ?.retryNow()
                                    : null,
                                onDiscard: () =>
                                    _discard(context, ref, capture),
                              );
                            },
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

  Future<void> _openAutoCommitEditor(
    BuildContext context,
    WidgetRef ref,
    String captureId,
  ) async {
    if (ref.read(autoCommitEditRequestProvider) != captureId) return;
    ref.read(autoCommitEditRequestProvider.notifier).clear();
    final List<Capture> captures = await ref
        .read(capturesRepositoryProvider)
        .getByIds(<String>[captureId]);
    if (!context.mounted || captures.isEmpty) return;
    final Capture capture = captures.single;
    final List<ProposedItem>? items = capture.proposedItems;
    if (items == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AutoCommittedTasksEditSheet(
        receipt: AutoCommitReceipt(
          captureId: captureId,
          items: items,
          addedAt: capture.autoCommittedAt ?? capture.updatedAt,
        ),
      ),
    );
    await ref
        .read(captureTriageServiceProvider)
        .acknowledgeAutoCommit(captureId);
  }

  Future<void> _startCapture(BuildContext context, WidgetRef ref) async {
    final permissions = CapturePermissions(ref.read(nativeCaptureApiProvider));
    final bool microphone = await permissions.requestMicrophone();
    final bool notifications = await permissions.requestNotifications();
    if (!context.mounted) return;
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

  Future<void> _openTriage(
    BuildContext context,
    WidgetRef ref,
    Capture capture,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext context) => CaptureTriageSheet(capture: capture),
  );

  Future<void> _discard(
    BuildContext context,
    WidgetRef ref,
    Capture capture,
  ) async {
    await ref.read(captureTriageServiceProvider).discard(capture.id);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Capture discarded.')));
    }
  }
}

class _EnergySelector extends StatelessWidget {
  const _EnergySelector({required this.selected, required this.onSelected});
  final EnergyMode selected;
  final Future<void> Function(EnergyMode) onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(theme.radii.pill),
        border: Border.all(
          color: theme.colors.cardBorder,
          width: theme.dimensions.outlineWidth,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(theme.spacing.xs),
        child: Row(
          children: EnergyMode.values
              .map((EnergyMode mode) {
                final bool active = selected == mode;
                return Expanded(
                  child: Semantics(
                    selected: active,
                    button: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(theme.radii.pill),
                      onTap: () => onSelected(mode),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: EdgeInsets.symmetric(
                          vertical: theme.spacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: active
                              ? theme.colors.primaryContainer
                              : theme.colors.surface.withValues(alpha: 0),
                          borderRadius: BorderRadius.circular(theme.radii.pill),
                        ),
                        child: Text(
                          _energyLabel(mode),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: active
                                ? theme.colors.onPrimaryContainer
                                : theme.colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              })
              .toList(growable: false),
        ),
      ),
    );
  }

  static String _energyLabel(EnergyMode mode) => switch (mode) {
    EnergyMode.low => 'Low',
    EnergyMode.normal => 'Normal',
    EnergyMode.charged => 'Charged',
  };
}

class _CaptureCard extends StatelessWidget {
  const _CaptureCard({
    required this.capture,
    required this.onOpen,
    required this.onDiscard,
  });
  final Capture capture;
  final VoidCallback? onOpen;
  final Future<void> Function() onDiscard;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final bool busy =
        capture.status == CaptureStatus.pending ||
        capture.status == CaptureStatus.processing;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(theme.radii.card),
        onTap: onOpen,
        child: Padding(
          padding: EdgeInsets.all(theme.spacing.card),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (busy)
                const PersonaOrb(isPulsing: true)
              else
                Icon(
                  _typeIcon(capture.llmType),
                  color: capture.status == CaptureStatus.failed
                      ? theme.colors.error
                      : theme.colors.primary,
                ),
              SizedBox(width: theme.spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      capture.title ?? _statusTitle(capture.status),
                      style: theme.textTheme.titleMedium,
                    ),
                    SizedBox(height: theme.spacing.xs),
                    Text(
                      _supportingCopy(capture),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colors.onSurfaceVariant,
                      ),
                    ),
                    SizedBox(height: theme.spacing.sm),
                    Text(
                      _statusLabel(capture),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: capture.status == CaptureStatus.failed
                            ? theme.colors.error
                            : theme.colors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Discard capture',
                onPressed: onDiscard,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _typeIcon(LlmType type) => switch (type) {
    LlmType.task => Icons.check_box_outlined,
    LlmType.note => Icons.sticky_note_2_outlined,
    LlmType.habit => Icons.repeat_rounded,
    LlmType.uncategorized => Icons.graphic_eq_rounded,
  };

  static String _statusTitle(CaptureStatus status) => switch (status) {
    CaptureStatus.pending => 'Safely queued',
    CaptureStatus.processing => 'Making sense of it',
    CaptureStatus.failed => 'Couldn’t process it — tap to retry',
    _ => 'Untitled capture',
  };

  static String _supportingCopy(Capture capture) =>
      capture.details ??
      capture.rawTranscript ??
      'Your audio is safe on this device.';

  static String _statusLabel(Capture capture) => switch (capture.status) {
    CaptureStatus.pending => 'PENDING',
    CaptureStatus.processing => 'PROCESSING',
    CaptureStatus.failed => 'TAP TO RETRY',
    CaptureStatus.ready => '${capture.llmType.name.toUpperCase()} · REVIEW',
    _ => capture.status.name.toUpperCase(),
  };
}

/// Entry point for triaging a `ready` capture. New captures carry the decomposed
/// [Capture.proposedItems] draft list and get the multi-card bulk review; any
/// capture processed before the decomposition change (no drafts) falls back to
/// the legacy single-result editor so nothing already in an inbox is stranded.
class CaptureTriageSheet extends ConsumerWidget {
  const CaptureTriageSheet({required this.capture, super.key});
  final Capture capture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<ProposedItem>? drafts = capture.proposedItems;
    if (drafts != null && drafts.isNotEmpty) {
      final Set<String> done = capture.dispositionedItemIds.toSet();
      return _BulkReviewSheet(
        capture: capture,
        drafts: <ProposedItem>[
          for (final ProposedItem draft in drafts)
            if (!done.contains(draft.id)) draft,
        ],
      );
    }
    return _LegacyTriageSheet(capture: capture);
  }
}

class _LegacyTriageSheet extends ConsumerStatefulWidget {
  const _LegacyTriageSheet({required this.capture});
  final Capture capture;

  @override
  ConsumerState<_LegacyTriageSheet> createState() => _LegacyTriageSheetState();
}

class _LegacyTriageSheetState extends ConsumerState<_LegacyTriageSheet> {
  late final TextEditingController _title = TextEditingController(
    text: widget.capture.title,
  );
  late final TextEditingController _details = TextEditingController(
    text: widget.capture.details,
  );
  late ResultingType _type = switch (widget.capture.llmType) {
    LlmType.note => ResultingType.note,
    LlmType.habit => ResultingType.habit,
    _ => ResultingType.task,
  };
  HabitLevel _level = HabitLevel.mini;
  late DateTime? _scheduledAt = _parseSuggestedSchedule(widget.capture);
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Padding(
      padding: EdgeInsets.only(
        left: theme.spacing.mobileMargin,
        right: theme.spacing.mobileMargin,
        top: theme.spacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + theme.spacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Shape this thought', style: theme.textTheme.headlineMedium),
            SizedBox(height: theme.spacing.md),
            Text(
              widget.capture.rawTranscript ?? 'Transcript unavailable.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colors.onSurfaceVariant.withValues(alpha: 0.62),
              ),
            ),
            SizedBox(height: theme.spacing.lg),
            _ChoicePills<ResultingType>(
              values: ResultingType.values,
              selected: _type,
              label: (ResultingType value) => _resultLabel(value),
              onSelected: (ResultingType value) =>
                  setState(() => _type = value),
            ),
            SizedBox(height: theme.spacing.lg),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            SizedBox(height: theme.spacing.md),
            TextField(
              controller: _details,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Details'),
            ),
            if (_type == ResultingType.task) ...<Widget>[
              SizedBox(height: theme.spacing.md),
              ActionChip(
                avatar: const Icon(Icons.schedule_rounded),
                label: Text(
                  _scheduledAt == null
                      ? 'Add schedule'
                      : MaterialLocalizations.of(
                          context,
                        ).formatMediumDate(_scheduledAt!),
                ),
                onPressed: _pickSchedule,
              ),
            ],
            if (_type == ResultingType.habit) ...<Widget>[
              SizedBox(height: theme.spacing.lg),
              Text('STARTING LEVEL', style: theme.textTheme.labelMedium),
              SizedBox(height: theme.spacing.sm),
              _ChoicePills<HabitLevel>(
                values: HabitLevel.values,
                selected: _level,
                label: (HabitLevel value) => _habitLabel(value),
                onSelected: (HabitLevel value) =>
                    setState(() => _level = value),
              ),
            ],
            SizedBox(height: theme.spacing.xl),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickSchedule() async {
    final DateTime now = DateTime.now();
    final DateTime? date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: DateTime(now.year + 5),
      initialDate: _scheduledAt ?? now,
    );
    if (date == null || !mounted) return;
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt ?? now),
    );
    if (time == null) return;
    setState(() {
      _scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(captureTriageServiceProvider)
          .save(
            widget.capture.id,
            CaptureTriageDraft(
              type: _type,
              title: _title.text,
              details: _details.text,
              scheduledAt: _scheduledAt,
              habitLevel: _level,
            ),
          );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static DateTime? _parseSuggestedSchedule(Capture capture) {
    final Map<String, Object?>? suggestion = capture.suggestedSchedule;
    if (suggestion == null) return null;
    for (final String key in <String>[
      'scheduled_at',
      'datetime',
      'iso',
      'date',
    ]) {
      final Object? raw = suggestion[key];
      if (raw is String) {
        final DateTime? parsed = DateTime.tryParse(raw);
        if (parsed != null) return parsed.toLocal();
      }
    }
    final String? day = suggestion['day'] as String?;
    if (day == null) return null;
    final DateTime base = capture.capturedAt.toLocal();
    final DateTime date = switch (day.toLowerCase()) {
      'today' => base,
      'tomorrow' => base.add(const Duration(days: 1)),
      _ => DateTime.tryParse(day)?.toLocal() ?? base,
    };
    int hour = 9;
    int minute = 0;
    final Object? timeValue = suggestion['time'];
    if (timeValue is String) {
      final List<String> parts = timeValue.split(':');
      if (parts.length >= 2) {
        hour = int.tryParse(parts[0]) ?? hour;
        minute = int.tryParse(parts[1]) ?? minute;
      }
    }
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  static String _resultLabel(ResultingType type) => switch (type) {
    ResultingType.task => 'Task',
    ResultingType.note => 'Note',
    ResultingType.habit => 'Habit',
    ResultingType.goal => 'Goal',
  };

  static String _habitLabel(HabitLevel level) => switch (level) {
    HabitLevel.mini => 'Mini',
    HabitLevel.normal => 'Normal',
    HabitLevel.mega => 'Mega',
  };
}

/// The §12.5 durable in-app safety net: a strip listing captures that
/// were auto-added WITHOUT review in the recent past, each offering a bulk Undo
/// (remove the added items, return the capture to the inbox to review) or Edit
/// (open the created task rows without deleting them). Empty — and invisible —
/// when there are no persisted unacknowledged auto-commits.
class _AutoAddedStrip extends ConsumerWidget {
  const _AutoAddedStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.appTheme;
    final List<AutoCommitReceipt> receipts =
        ref.watch(recentAutoCommitsProvider).value ??
        const <AutoCommitReceipt>[];
    if (receipts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        theme.spacing.mobileMargin,
        theme.spacing.sm,
        theme.spacing.mobileMargin,
        theme.spacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final AutoCommitReceipt receipt in receipts)
            _AutoAddedCard(receipt: receipt),
        ],
      ),
    );
  }
}

class _AutoAddedCard extends ConsumerWidget {
  const _AutoAddedCard({required this.receipt});
  final AutoCommitReceipt receipt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.appTheme;
    final String titles = receipt.items
        .map((ProposedItem item) => item.title)
        .join(' · ');
    return Card(
      margin: EdgeInsets.only(bottom: theme.spacing.sm),
      color: theme.colors.primaryContainer,
      child: Padding(
        padding: EdgeInsets.all(theme.spacing.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.check_circle_rounded,
                  color: theme.colors.onPrimaryContainer,
                ),
                SizedBox(width: theme.spacing.sm),
                Expanded(
                  child: Text(
                    receipt.count == 1
                        ? 'Auto-added 1 task'
                        : 'Auto-added ${receipt.count} tasks',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colors.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: theme.spacing.xs),
            Text(
              titles,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colors.onPrimaryContainer.withValues(alpha: 0.82),
              ),
            ),
            SizedBox(height: theme.spacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: () => _undo(context, ref),
                  child: const Text('Undo'),
                ),
                SizedBox(width: theme.spacing.xs),
                TextButton(
                  onPressed: () => _edit(context, ref),
                  child: const Text('Edit'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _undo(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(captureTriageServiceProvider)
          .undoAutoCommit(receipt.captureId);
    } on StateError {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Undo expired. You can still edit the added tasks.'),
          ),
        );
      }
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            receipt.count == 1
                ? 'Removed. It’s back in your inbox to review.'
                : 'Removed. They’re back in your inbox to review.',
          ),
        ),
      );
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext context) =>
          _AutoCommittedTasksEditSheet(receipt: receipt),
    );
    await ref
        .read(captureTriageServiceProvider)
        .acknowledgeAutoCommit(receipt.captureId);
  }
}

/// Edits the already-created task rows in place. Opening this sheet never
/// invokes Undo, so the auto-commit contract remains non-destructive.
class _AutoCommittedTasksEditSheet extends ConsumerStatefulWidget {
  const _AutoCommittedTasksEditSheet({required this.receipt});
  final AutoCommitReceipt receipt;

  @override
  ConsumerState<_AutoCommittedTasksEditSheet> createState() =>
      _AutoCommittedTasksEditSheetState();
}

class _AutoCommittedTasksEditSheetState
    extends ConsumerState<_AutoCommittedTasksEditSheet> {
  List<_TaskEditRow>? _rows;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final Set<String> ids = widget.receipt.items.map((i) => i.id).toSet();
    final List<Task> tasks = await ref
        .read(tasksRepositoryProvider)
        .watchAll()
        .first;
    if (!mounted) return;
    setState(() {
      _rows = <_TaskEditRow>[
        for (final Task task in tasks)
          if (ids.contains(task.id)) _TaskEditRow(task),
      ];
    });
  }

  @override
  void dispose() {
    for (final _TaskEditRow row in _rows ?? const <_TaskEditRow>[]) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final List<_TaskEditRow>? rows = _rows;
    return Padding(
      padding: EdgeInsets.only(
        left: theme.spacing.mobileMargin,
        right: theme.spacing.mobileMargin,
        top: theme.spacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + theme.spacing.lg,
      ),
      child: rows == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Edit added tasks',
                    style: theme.textTheme.headlineMedium,
                  ),
                  SizedBox(height: theme.spacing.md),
                  for (final _TaskEditRow row in rows) ...<Widget>[
                    TextField(
                      controller: row.title,
                      decoration: const InputDecoration(
                        labelText: 'Task title',
                      ),
                    ),
                    SizedBox(height: theme.spacing.sm),
                    TextField(
                      controller: row.details,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Details'),
                    ),
                    SizedBox(height: theme.spacing.sm),
                    ActionChip(
                      avatar: const Icon(Icons.schedule_rounded),
                      label: Text(
                        row.scheduledAt == null
                            ? 'Add schedule'
                            : '${MaterialLocalizations.of(context).formatMediumDate(row.scheduledAt!)} '
                                  '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(row.scheduledAt!))}',
                      ),
                      onPressed: () => _pickSchedule(row),
                    ),
                    SizedBox(height: theme.spacing.md),
                  ],
                  FilledButton(
                    onPressed: _saving || rows.isEmpty ? null : _save,
                    child: Text(_saving ? 'Saving…' : 'Save changes'),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _save() async {
    final List<_TaskEditRow> rows = _rows ?? const <_TaskEditRow>[];
    if (rows.any((row) => row.title.text.trim().isEmpty)) return;
    setState(() => _saving = true);
    try {
      final TasksRepository repository = ref.read(tasksRepositoryProvider);
      for (final _TaskEditRow row in rows) {
        final String details = row.details.text.trim();
        await repository.update(
          row.task.copyWith(
            title: row.title.text.trim(),
            details: details.isEmpty ? null : details,
            scheduledAt: row.scheduledAt,
          ),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickSchedule(_TaskEditRow row) async {
    final DateTime now = DateTime.now();
    final DateTime initial = row.scheduledAt ?? now;
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (date == null || !mounted) return;
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    setState(() {
      row.scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }
}

class _TaskEditRow {
  _TaskEditRow(this.task)
    : title = TextEditingController(text: task.title),
      details = TextEditingController(text: task.details ?? ''),
      scheduledAt = task.scheduledAt;
  final Task task;
  final TextEditingController title;
  final TextEditingController details;
  DateTime? scheduledAt;
  void dispose() {
    title.dispose();
    details.dispose();
  }
}

/// The multi-card bulk review (docs/CAPTURE_DECOMPOSITION.md §6): one rant is
/// decomposed into N draft items, each independently editable — switch its kind,
/// edit title/details, drop it — then "Save all" materialises every survivor at
/// once via [CaptureTriageService.saveAll]. Dropping every item discards a new
/// capture, but dropping the last remaining drafts after a partial save records
/// those dispositions and terminally triages the capture.
class _BulkReviewSheet extends ConsumerStatefulWidget {
  const _BulkReviewSheet({required this.capture, required this.drafts});
  final Capture capture;
  final List<ProposedItem> drafts;

  @override
  ConsumerState<_BulkReviewSheet> createState() => _BulkReviewSheetState();
}

class _BulkReviewSheetState extends ConsumerState<_BulkReviewSheet> {
  late final List<_ItemEditor> _editors = <_ItemEditor>[
    for (final ProposedItem draft in widget.drafts) _ItemEditor(draft),
  ];
  bool _saving = false;

  @override
  void dispose() {
    for (final _ItemEditor editor in _editors) {
      editor.dispose();
    }
    super.dispose();
  }

  int get _selectedCount =>
      _editors.where((_ItemEditor e) => !e.dropped && !e.deferred).length;
  bool get _allDropped => _editors.every((_ItemEditor e) => e.dropped);

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Padding(
      padding: EdgeInsets.only(
        left: theme.spacing.mobileMargin,
        right: theme.spacing.mobileMargin,
        top: theme.spacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + theme.spacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Review your thoughts', style: theme.textTheme.headlineMedium),
            SizedBox(height: theme.spacing.sm),
            Text(
              _editors.length == 1
                  ? 'One item found. Shape it, then save.'
                  : '${_editors.length} items found. Keep, reshape, or drop each.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colors.onSurfaceVariant,
              ),
            ),
            if (widget.capture.rawTranscript != null) ...<Widget>[
              SizedBox(height: theme.spacing.md),
              Text(
                widget.capture.rawTranscript!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colors.onSurfaceVariant.withValues(alpha: 0.62),
                ),
              ),
            ],
            SizedBox(height: theme.spacing.lg),
            for (final _ItemEditor editor in _editors) ...<Widget>[
              _ItemCard(
                editor: editor,
                onChanged: () => setState(() {}),
                onPickSchedule: () => _pickSchedule(editor),
                onPickTargetDate: () => _pickTargetDate(editor),
              ),
              SizedBox(height: theme.spacing.md),
            ],
            SizedBox(height: theme.spacing.sm),
            if (_allDropped && widget.capture.dispositionedItemIds.isEmpty)
              OutlinedButton.icon(
                onPressed: _saving ? null : _discardAll,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Discard capture'),
              )
            else if (_allDropped)
              FilledButton(
                onPressed: _saving ? null : _saveAll,
                child: Text(_saving ? 'Saving…' : 'Drop remaining'),
              )
            else
              FilledButton(
                onPressed: _saving ? null : _saveAll,
                child: Text(
                  _saving
                      ? 'Saving…'
                      : _selectedCount == 0
                      ? 'Save for later'
                      : _selectedCount == 1
                      ? 'Save 1 item'
                      : 'Save all $_selectedCount items',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickSchedule(_ItemEditor editor) async {
    final DateTime now = DateTime.now();
    final DateTime? date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: DateTime(now.year + 5),
      initialDate: editor.schedule ?? now,
    );
    if (date == null || !mounted) return;
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(editor.schedule ?? now),
    );
    if (time == null) return;
    setState(() {
      editor.schedule = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _saveAll() async {
    final List<ProposedItem> editedItems = <ProposedItem>[
      for (final _ItemEditor editor in _editors) editor.build(),
    ];
    final List<ProposedItem> survivors = <ProposedItem>[
      for (int index = 0; index < _editors.length; index++)
        if (!_editors[index].dropped && !_editors[index].deferred)
          editedItems[index],
    ];
    if (editedItems.any((ProposedItem item) => item.title.isEmpty)) return;
    final Set<String> droppedIds = <String>{
      for (final _ItemEditor editor in _editors)
        if (editor.dropped) editor.original.id,
    };
    setState(() => _saving = true);
    try {
      await ref
          .read(captureTriageServiceProvider)
          .saveAll(
            widget.capture.id,
            survivors,
            droppedItemIds: droppedIds,
            editedItems: editedItems,
          );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTargetDate(_ItemEditor editor) async {
    final DateTime now = DateTime.now();
    final DateTime? date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: DateTime(now.year + 20),
      initialDate: editor.targetDate ?? now,
    );
    if (date != null && mounted) setState(() => editor.targetDate = date);
  }

  Future<void> _discardAll() async {
    setState(() => _saving = true);
    try {
      await ref.read(captureTriageServiceProvider).discard(widget.capture.id);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// Per-item editing state for the bulk review. Holds the immutable [original]
/// draft plus the mutable fields the UI can change; [build] folds the edits back
/// into a [ProposedItem] that keeps [original]'s stable id (so materialisation
/// stays idempotent) and its non-edited fields.
class _ItemEditor {
  _ItemEditor(this.original)
    : title = TextEditingController(text: original.title),
      details = TextEditingController(text: original.details ?? ''),
      location = TextEditingController(text: original.location?.name ?? ''),
      anchor = TextEditingController(text: original.anchor ?? ''),
      why = TextEditingController(text: original.why ?? ''),
      kind = original.kind,
      schedule = original.scheduledAt,
      level = original.level ?? HabitLevel.mini,
      reminder = original.reminder,
      transition = original.location?.transition ?? GeofenceTransition.enter,
      cadenceType = original.cadence?['type'] as String? ?? 'daily',
      cadenceDays = ((original.cadence?['days'] as List?) ?? const <Object>[])
          .whereType<String>()
          .toSet(),
      targetDate = original.targetDate;

  final ProposedItem original;
  final TextEditingController title;
  final TextEditingController details;
  final TextEditingController location;
  final TextEditingController anchor;
  final TextEditingController why;
  ResultingType kind;
  DateTime? schedule;
  HabitLevel level;
  bool reminder;
  GeofenceTransition transition;
  String cadenceType;
  Set<String> cadenceDays;
  DateTime? targetDate;
  bool dropped = false;
  bool deferred = false;

  bool get isLowConfidence => original.confidence == DraftConfidence.low;

  void dispose() {
    title.dispose();
    details.dispose();
    location.dispose();
    anchor.dispose();
    why.dispose();
  }

  ProposedItem build() {
    final String trimmedDetails = details.text.trim();
    final String trimmedLocation = location.text.trim();
    final String trimmedAnchor = anchor.text.trim();
    final String trimmedWhy = why.text.trim();
    return ProposedItem(
      id: original.id,
      kind: kind,
      title: title.text.trim(),
      confidence: original.confidence,
      details: trimmedDetails.isEmpty ? null : trimmedDetails,
      schedule: kind == ResultingType.task
          ? _draftScheduleFrom(schedule)
          : null,
      location: kind == ResultingType.task && trimmedLocation.isNotEmpty
          ? DraftLocation(name: trimmedLocation, transition: transition)
          : null,
      reminder: kind == ResultingType.task && reminder,
      anchor: kind == ResultingType.habit && trimmedAnchor.isNotEmpty
          ? trimmedAnchor
          : null,
      cadence: kind == ResultingType.habit ? _buildCadence() : null,
      level: kind == ResultingType.habit ? level : null,
      why: kind == ResultingType.goal && trimmedWhy.isNotEmpty
          ? trimmedWhy
          : null,
      targetDate: kind == ResultingType.goal ? targetDate : null,
    );
  }

  Map<String, Object?> _buildCadence() {
    final Map<String, Object?> cadence =
        original.cadence?['type'] == cadenceType
        ? Map<String, Object?>.from(original.cadence!)
        : <String, Object?>{};
    cadence['type'] = cadenceType;
    if (cadenceType == 'weekly') {
      cadence['days'] = cadenceDays.toList(growable: false);
    } else if (cadenceType == 'daily') {
      cadence.remove('days');
    }
    return cadence;
  }
}

DraftSchedule? _draftScheduleFrom(DateTime? at) {
  if (at == null) return null;
  final String date =
      '${at.year.toString().padLeft(4, '0')}-'
      '${at.month.toString().padLeft(2, '0')}-'
      '${at.day.toString().padLeft(2, '0')}';
  final String time =
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
  return DraftSchedule(date: date, time: time);
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.editor,
    required this.onChanged,
    required this.onPickSchedule,
    required this.onPickTargetDate,
  });
  final _ItemEditor editor;
  final VoidCallback onChanged;
  final VoidCallback onPickSchedule;
  final VoidCallback onPickTargetDate;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    if (editor.dropped) {
      return Card(
        margin: EdgeInsets.zero,
        color: theme.colors.surfaceContainerLow,
        child: Padding(
          padding: EdgeInsets.all(theme.spacing.card),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.delete_outline_rounded,
                color: theme.colors.onSurfaceVariant,
              ),
              SizedBox(width: theme.spacing.md),
              Expanded(
                child: Text(
                  'Dropped: ${editor.original.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colors.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  editor.dropped = false;
                  onChanged();
                },
                child: const Text('Undo'),
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(theme.spacing.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: _ChoicePills<ResultingType>(
                    values: ResultingType.values,
                    selected: editor.kind,
                    label: _resultLabel,
                    onSelected: (ResultingType value) {
                      editor.kind = value;
                      onChanged();
                    },
                  ),
                ),
                IconButton(
                  tooltip: editor.deferred ? 'Include now' : 'Save later',
                  onPressed: () {
                    editor.deferred = !editor.deferred;
                    onChanged();
                  },
                  icon: Icon(
                    editor.deferred
                        ? Icons.redo_rounded
                        : Icons.schedule_send_rounded,
                  ),
                ),
                IconButton(
                  tooltip: 'Drop this item',
                  onPressed: () {
                    editor.dropped = true;
                    onChanged();
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            if (editor.isLowConfidence) ...<Widget>[
              SizedBox(height: theme.spacing.xs),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.error_outline_rounded,
                    size: theme.dimensions.navigationIcon * 0.67,
                    color: theme.colors.secondary,
                  ),
                  SizedBox(width: theme.spacing.xs),
                  Text(
                    'Worth a second look',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colors.secondary,
                    ),
                  ),
                ],
              ),
            ],
            SizedBox(height: theme.spacing.md),
            TextField(
              controller: editor.title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            SizedBox(height: theme.spacing.sm),
            TextField(
              controller: editor.details,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Details'),
            ),
            if (editor.kind == ResultingType.task) ...<Widget>[
              SizedBox(height: theme.spacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  avatar: const Icon(Icons.schedule_rounded),
                  label: Text(
                    editor.schedule == null
                        ? 'Add schedule'
                        : MaterialLocalizations.of(
                            context,
                          ).formatMediumDate(editor.schedule!),
                  ),
                  onPressed: onPickSchedule,
                ),
              ),
              SizedBox(height: theme.spacing.sm),
              TextField(
                controller: editor.location,
                decoration: const InputDecoration(labelText: 'Location'),
              ),
              SizedBox(height: theme.spacing.xs),
              _ChoicePills<GeofenceTransition>(
                values: GeofenceTransition.values,
                selected: editor.transition,
                label: (value) =>
                    value == GeofenceTransition.enter ? 'Arriving' : 'Leaving',
                onSelected: (value) {
                  editor.transition = value;
                  onChanged();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Reminder'),
                value: editor.reminder,
                onChanged: (bool value) {
                  editor.reminder = value;
                  onChanged();
                },
              ),
            ],
            if (editor.kind == ResultingType.habit) ...<Widget>[
              SizedBox(height: theme.spacing.sm),
              TextField(
                controller: editor.anchor,
                decoration: const InputDecoration(labelText: 'Anchor routine'),
              ),
              SizedBox(height: theme.spacing.sm),
              _ChoicePills<String>(
                values: const <String>['daily', 'weekly'],
                selected: editor.cadenceType,
                label: (value) => value == 'daily' ? 'Daily' : 'Weekly',
                onSelected: (value) {
                  editor.cadenceType = value;
                  onChanged();
                },
              ),
              if (editor.cadenceType == 'weekly')
                Wrap(
                  spacing: theme.spacing.xs,
                  children:
                      const <String>[
                            'mon',
                            'tue',
                            'wed',
                            'thu',
                            'fri',
                            'sat',
                            'sun',
                          ]
                          .map(
                            (day) => FilterChip(
                              label: Text(day.toUpperCase()),
                              selected: editor.cadenceDays.contains(day),
                              onSelected: (selected) {
                                selected
                                    ? editor.cadenceDays.add(day)
                                    : editor.cadenceDays.remove(day);
                                onChanged();
                              },
                            ),
                          )
                          .toList(growable: false),
                ),
              SizedBox(height: theme.spacing.md),
              Text('STARTING LEVEL', style: theme.textTheme.labelMedium),
              SizedBox(height: theme.spacing.sm),
              _ChoicePills<HabitLevel>(
                values: HabitLevel.values,
                selected: editor.level,
                label: _habitLabel,
                onSelected: (HabitLevel value) {
                  editor.level = value;
                  onChanged();
                },
              ),
            ],
            if (editor.kind == ResultingType.goal) ...<Widget>[
              SizedBox(height: theme.spacing.sm),
              TextField(
                controller: editor.why,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Why this matters',
                ),
              ),
              SizedBox(height: theme.spacing.sm),
              ActionChip(
                avatar: const Icon(Icons.event_rounded),
                label: Text(
                  editor.targetDate == null
                      ? 'Add target date'
                      : MaterialLocalizations.of(
                          context,
                        ).formatMediumDate(editor.targetDate!),
                ),
                onPressed: onPickTargetDate,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _resultLabel(ResultingType type) => switch (type) {
    ResultingType.task => 'Task',
    ResultingType.note => 'Note',
    ResultingType.habit => 'Habit',
    ResultingType.goal => 'Goal',
  };

  static String _habitLabel(HabitLevel level) => switch (level) {
    HabitLevel.mini => 'Mini',
    HabitLevel.normal => 'Normal',
    HabitLevel.mega => 'Mega',
  };
}

class _ChoicePills<T> extends StatelessWidget {
  const _ChoicePills({
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
  });
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Wrap(
      spacing: theme.spacing.sm,
      runSpacing: theme.spacing.sm,
      children: values
          .map((T value) {
            final bool active = value == selected;
            return ChoiceChip(
              selected: active,
              label: Text(label(value)),
              onSelected: (_) => onSelected(value),
              selectedColor: theme.colors.primaryContainer,
              backgroundColor: theme.colors.surfaceContainer,
              side: BorderSide(
                color: active
                    ? theme.colors.primary
                    : theme.colors.outlineVariant,
                width: theme.dimensions.outlineWidth,
              ),
            );
          })
          .toList(growable: false),
    );
  }
}
