import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/core/capture/capture_permissions.dart';
import 'package:sidekick/core/capture/capture_providers.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/theme/app_theme_scope.dart';
import 'package:sidekick/core/theme/widgets/persona_orb.dart';
import 'package:sidekick/features/inbox/application/inbox_providers.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';

class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final AsyncValue<List<Capture>> captures = ref.watch(inboxCapturesProvider);

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
                          'Type or record one reminder. Sidekick will infer the task, time, and place trigger in the POC flow.',
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
                        Text(
                          'AUDIO CAPTURES',
                          style: theme.textTheme.labelMedium,
                        ),
                      ],
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
                    child: Center(child: Text('Captures will be back shortly.')),
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
                                _CaptureCard(capture: items[index]),
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Typed reminder drafting lands in Phase 2.')),
    );
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
}

class _CaptureCard extends StatelessWidget {
  const _CaptureCard({required this.capture});

  final Capture capture;

  @override
  Widget build(BuildContext context) {
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
}
