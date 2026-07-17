import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/core/capture/capture_permissions.dart';
import 'package:sidekick/core/capture/capture_providers.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/theme/app_theme_scope.dart';
import 'package:sidekick/core/theme/widgets/persona_orb.dart';
import 'package:sidekick/features/inbox/application/capture_processing_providers.dart';
import 'package:sidekick/features/inbox/application/capture_triage_service.dart';
import 'package:sidekick/features/inbox/application/inbox_providers.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';

class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    CaptureStatus.failed => 'Waiting for a connection',
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

class CaptureTriageSheet extends ConsumerStatefulWidget {
  const CaptureTriageSheet({required this.capture, super.key});
  final Capture capture;

  @override
  ConsumerState<CaptureTriageSheet> createState() => _CaptureTriageSheetState();
}

class _CaptureTriageSheetState extends ConsumerState<CaptureTriageSheet> {
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
  HabitLevel _level = HabitLevel.normal;
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
