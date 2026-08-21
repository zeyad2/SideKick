import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/core/data/id_generator.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/events/event_emitter.dart';
import 'package:sidekick/core/events/events_repository.dart';
import 'package:sidekick/features/inbox/data/captures_repository_impl.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';
import 'package:sidekick/features/reminders/application/reminder_creation_service.dart';
import 'package:sidekick/features/reminders/application/reminder_draft_service.dart';
import 'package:sidekick/features/reminders/data/task_reminders_repository_impl.dart';
import 'package:sidekick/features/reminders/domain/task_reminder.dart';

void main() {
  late AppDatabase db;
  late CapturesRepositoryImpl captures;
  late TaskRemindersRepositoryImpl reminders;
  late ReminderCreationService service;
  late DateTime now;

  setUp(() {
    now = DateTime.utc(2026, 8, 20, 10);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final EventEmitter emitter = EventEmitter(
      DriftEventsRepository(db),
      IdGenerator(),
    );
    captures = CapturesRepositoryImpl(
      db: db,
      emitter: emitter,
      idGenerator: IdGenerator(),
      userId: 'u1',
      clock: () => now,
    );
    reminders = TaskRemindersRepositoryImpl(
      db: db,
      emitter: emitter,
      idGenerator: IdGenerator(),
      userId: 'u1',
      clock: () => now,
    );
    service = ReminderCreationService(
      captures: captures,
      reminders: reminders,
      drafts: const HeuristicReminderDraftService(),
      clock: () => now,
    );
  });

  tearDown(() => db.close());

  Future<List<TaskReminder>> pending() =>
      reminders.watchByStatus(TaskReminderStatus.pendingAutoCommit).first;

  test('typed high-confidence reminder enters countdown', () async {
    final ReminderCreationResult result = await service.submitText(
      'Remind me to call the dentist tomorrow',
    );

    expect(result.autoCommitted, hasLength(1));
    expect(result.needsReview, isEmpty);
    final TaskReminder reminder = (await pending()).single;
    expect(reminder.status, TaskReminderStatus.pendingAutoCommit);
    expect(reminder.autoCommitDeadlineAt, now.add(const Duration(seconds: 10)));
    expect(reminder.scheduledAt, DateTime.utc(2026, 8, 21, 9));
  });

  test('countdown expiry activates reminder', () async {
    await service.submitText('Remind me to call the dentist tomorrow');
    now = now.add(const Duration(seconds: 11));

    expect(await service.activateDueAutoCommits(), 1);

    final List<TaskReminder> active = await reminders
        .watchByStatus(TaskReminderStatus.active)
        .first;
    expect(active.single.status, TaskReminderStatus.active);
    expect(active.single.autoCommitDeadlineAt, isNull);
  });

  test('cancel during countdown prevents activation', () async {
    await service.submitText('Remind me to call the dentist tomorrow');
    final TaskReminder reminder = (await pending()).single;

    await service.cancelAutoCommit(reminder.id);
    now = now.add(const Duration(seconds: 11));

    expect(await service.activateDueAutoCommits(), 0);
    final List<TaskReminder> cancelled = await reminders
        .watchByStatus(TaskReminderStatus.cancelled)
        .first;
    expect(cancelled.single.id, reminder.id);
  });

  test('edit during countdown saves edited reminder', () async {
    await service.submitText('Remind me to call the dentist tomorrow');
    final TaskReminder reminder = (await pending()).single;

    await service.editAutoCommit(
      reminder.id,
      title: 'Call Dr. Mina',
      details: 'Bring insurance card.',
    );

    final TaskReminder edited = (await pending()).single;
    expect(edited.title, 'Call Dr. Mina');
    expect(edited.details, 'Bring insurance card.');
    expect(edited.confidence, 1);
  });

  test('typed multi-task input creates multiple pending reminders', () async {
    await service.submitText(
      'Remind me to call Sam tomorrow; remind me to pay rent at 7pm',
    );

    expect(await pending(), hasLength(2));
  });

  test(
    'audio capture with multiple reminders creates multiple pending rows',
    () async {
      final File file = await _audioFile(
        'remind me to call Sam tomorrow; remind me to pay rent at 7pm',
      );
      final Capture capture = await captures.create(
        audioPath: file.path,
        source: CaptureSource.audio.wire,
      );

      final ReminderCreationResult result = await service.processAudioCapture(
        capture,
      );

      expect(result.autoCommitted, hasLength(2));
      expect(await pending(), hasLength(2));
      final Capture updated = (await captures.getByIds(<String>[
        capture.id,
      ])).single;
      expect(updated.rawTranscript, contains('call Sam'));
      expect(await file.exists(), isTrue);
    },
  );

  test('low-confidence draft opens review instead of auto-commit', () async {
    final ReminderCreationResult result = await service.submitText(
      'Maybe call Sam tomorrow',
    );

    expect(result.autoCommitted, isEmpty);
    expect(result.needsReview, hasLength(1));
    expect(await pending(), isEmpty);
  });

  test('missing-trigger draft opens review instead of auto-commit', () async {
    final ReminderCreationResult result = await service.submitText('Buy milk');

    expect(result.autoCommitted, isEmpty);
    expect(result.needsReview, hasLength(1));
    expect(result.needsReview.single.hasConcreteTrigger, isFalse);
  });

  test('reviewed draft can be approved into an active reminder', () async {
    final ReminderCreationResult result = await service.submitText('Buy milk');

    await service.approveReviewedDraft(
      result.needsReview.single,
      source: TaskReminderSource.typed,
      captureId: result.captureId!,
      title: 'Buy milk',
      scheduledAt: DateTime.utc(2026, 8, 21, 9),
    );

    final List<TaskReminder> active = await reminders
        .watchByStatus(TaskReminderStatus.active)
        .first;
    expect(active.single.title, 'Buy milk');
    expect(active.single.scheduledAt, DateTime.utc(2026, 8, 21, 9));
  });

  test('reviewed time draft requires schedule before activation', () async {
    final ReminderCreationResult result = await service.submitText('Buy milk');

    await expectLater(
      () => service.approveReviewedDraft(
        result.needsReview.single,
        source: TaskReminderSource.typed,
        captureId: result.captureId!,
        title: 'Buy milk',
      ),
      throwsA(isA<ReminderDraftFormatException>()),
    );
  });

  test('draft parser rejects habit, goal, and note output', () async {
    for (final String input in <String>[
      'make this a habit tomorrow',
      'add a goal tomorrow',
      'save a note tomorrow',
    ]) {
      expect(
        () => service.submitText(input),
        throwsA(isA<ReminderDraftFormatException>()),
      );
    }
  });

  test('unclear audio permits 2 retries then falls back to typing', () async {
    final File file = await _audioFile('unclear');
    final Capture capture = await captures.create(
      audioPath: file.path,
      source: CaptureSource.audio.wire,
    );

    final ReminderCreationResult first = await service.processAudioCapture(
      capture,
    );
    final Capture afterFirst = (await captures.getByIds(<String>[
      capture.id,
    ])).single;
    final ReminderCreationResult second = await service.processAudioCapture(
      afterFirst,
    );

    expect(first.unclearAudio, isTrue);
    expect(first.retryLimitReached, isFalse);
    expect(second.unclearAudio, isTrue);
    expect(second.retryLimitReached, isTrue);
    final Capture updated = (await captures.getByIds(<String>[
      capture.id,
    ])).single;
    expect(updated.error, contains('Type the reminder instead'));
  });

  test('audio remains on disk after parser failure', () async {
    service = ReminderCreationService(
      captures: captures,
      reminders: reminders,
      drafts: const _FailingDraftService(),
      clock: () => now,
    );
    final File file = await _audioFile('remind me tomorrow');
    final Capture capture = await captures.create(
      audioPath: file.path,
      source: CaptureSource.audio.wire,
    );

    await expectLater(
      () => service.processAudioCapture(capture),
      throwsA(isA<StateError>()),
    );

    final Capture updated = (await captures.getByIds(<String>[
      capture.id,
    ])).single;
    expect(updated.status, CaptureStatus.failed);
    expect(updated.audioPath, file.path);
    expect(await file.exists(), isTrue);
  });
}

Future<File> _audioFile(String transcript) async {
  final Directory directory = await Directory.systemTemp.createTemp(
    'sidekick_phase2_',
  );
  final File file = File('${directory.path}/capture.txt');
  return file.writeAsString(transcript);
}

class _FailingDraftService implements ReminderDraftService {
  const _FailingDraftService();

  @override
  Future<ReminderDraftParseResult> parseAudio(
    File file,
    ReminderDraftContext context,
  ) async {
    throw StateError('network unavailable');
  }

  @override
  Future<ReminderDraftParseResult> parseText(
    String input,
    ReminderDraftContext context,
  ) async {
    throw StateError('network unavailable');
  }
}
