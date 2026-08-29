import 'dart:convert';
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
import 'package:sidekick/features/places/data/places_repository_impl.dart';
import 'package:sidekick/features/profile/data/profile_repository_impl.dart';
import 'package:sidekick/features/reminders/application/assistant_context_builder.dart';
import 'package:sidekick/features/reminders/application/reminder_creation_service.dart';
import 'package:sidekick/features/reminders/application/reminder_draft_service.dart';
import 'package:sidekick/features/reminders/data/reminder_events_repository_impl.dart';
import 'package:sidekick/features/reminders/data/task_reminders_repository_impl.dart';
import 'package:sidekick/features/reminders/domain/reminder_event.dart';
import 'package:sidekick/features/reminders/domain/task_reminder.dart';

void main() {
  late AppDatabase db;
  late EventEmitter emitter;
  late CapturesRepositoryImpl captures;
  late TaskRemindersRepositoryImpl reminders;
  late ReminderEventsRepositoryImpl reminderEvents;
  late ReminderCreationService service;
  late DateTime now;

  setUp(() {
    now = DateTime.utc(2026, 8, 20, 10);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    emitter = EventEmitter(DriftEventsRepository(db), IdGenerator());
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
    reminderEvents = ReminderEventsRepositoryImpl(
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
      events: reminderEvents,
      atomically: db.transaction,
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
    final List<ReminderEvent> events = await reminderEvents
        .watchForReminder(reminder.id)
        .first;
    expect(events.single.eventType, ReminderEventType.edited);
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

  test('audio capture processing is idempotent after success', () async {
    final File file = await _audioFile(
      'remind me to call Sam tomorrow; remind me to pay rent at 7pm',
    );
    final Capture capture = await captures.create(
      audioPath: file.path,
      source: CaptureSource.audio.wire,
    );

    final ReminderCreationResult first = await service.processAudioCapture(
      capture,
    );
    final Capture updated = (await captures.getByIds(<String>[
      capture.id,
    ])).single;
    final ReminderCreationResult second = await service.processAudioCapture(
      updated,
    );

    expect(first.autoCommitted, hasLength(2));
    expect(second.autoCommitted, hasLength(2));
    expect(await pending(), hasLength(2));
  });

  test('low-confidence draft opens review instead of auto-commit', () async {
    final ReminderCreationResult result = await service.submitText(
      'Maybe call Sam tomorrow',
    );

    expect(result.autoCommitted, isEmpty);
    expect(result.needsReview, hasLength(1));
    expect(await pending(), isEmpty);
  });

  test(
    'review drafts persist and reconstruct across service recreation',
    () async {
      final ReminderCreationResult result = await service.submitText(
        'Maybe call Sam tomorrow',
      );

      final ReminderCreationService recreated = ReminderCreationService(
        captures: captures,
        reminders: reminders,
        drafts: const HeuristicReminderDraftService(),
        clock: () => now,
        events: reminderEvents,
      );

      final List<PendingReviewDraft> restored = await recreated
          .pendingReviewDrafts();
      expect(result.needsReview, hasLength(1));
      expect(restored, hasLength(1));
      expect(restored.single.captureId, result.captureId);
      expect(restored.single.draft.title, contains('call Sam'));
    },
  );

  test('missing-trigger draft opens review instead of auto-commit', () async {
    final ReminderCreationResult result = await service.submitText('Buy milk');

    expect(result.autoCommitted, isEmpty);
    expect(result.needsReview, hasLength(1));
    expect(result.needsReview.single.hasConcreteTrigger, isFalse);
  });

  test(
    'saved place context can select a place trigger and stores metadata',
    () async {
      final places = PlacesRepositoryImpl(
        db: db,
        emitter: emitter,
        idGenerator: IdGenerator(),
        userId: 'u1',
        clock: () => now,
      );
      final place = await places.create(name: 'Workshop', lat: 30, lng: 31);
      service = ReminderCreationService(
        captures: captures,
        reminders: reminders,
        drafts: const HeuristicReminderDraftService(),
        clock: () => now,
        events: reminderEvents,
        contextBuilder: RepositoryAssistantContextBuilder(
          profile: ProfileRepositoryImpl(
            db: db,
            userId: 'u1',
            clock: () => now,
          ),
          places: places,
          reminders: reminders,
          events: reminderEvents,
          captures: captures,
        ),
      );

      final ReminderCreationResult result = await service.submitText(
        'Remind me to grab the charger at Workshop',
      );

      expect(result.autoCommitted, hasLength(1));
      final TaskReminder reminder = (await pending()).single;
      expect(reminder.triggerType, TaskReminderTriggerType.place);
      expect(reminder.placeId, place.id);
      expect(reminder.aiExplanation, contains('life context'));
      expect(
        reminder.aiContext,
        containsPair('context_items_used', <String>['place:${place.id}']),
      );
    },
  );

  test(
    'recent Wrong Place context forces similar place draft into review',
    () async {
      final places = PlacesRepositoryImpl(
        db: db,
        emitter: emitter,
        idGenerator: IdGenerator(),
        userId: 'u1',
        clock: () => now,
      );
      final place = await places.create(name: 'Workshop', lat: 30, lng: 31);
      final existing = await reminders.create(
        TaskReminderDraft(
          title: 'Grab charger',
          source: TaskReminderSource.typed,
          confidence: 0.9,
          triggerType: TaskReminderTriggerType.place,
          placeId: place.id,
          geofenceTransition: GeofenceTransition.enter,
        ),
      );
      await reminderEvents.append(
        reminderId: existing.id,
        eventType: ReminderEventType.wrongPlace,
        metadata: <String, Object?>{
          'correction': 'wrong_place',
          'place_id': place.id,
        },
      );
      service = ReminderCreationService(
        captures: captures,
        reminders: reminders,
        drafts: const HeuristicReminderDraftService(),
        clock: () => now,
        events: reminderEvents,
        contextBuilder: RepositoryAssistantContextBuilder(
          profile: ProfileRepositoryImpl(
            db: db,
            userId: 'u1',
            clock: () => now,
          ),
          places: places,
          reminders: reminders,
          events: reminderEvents,
          captures: captures,
        ),
      );

      final ReminderCreationResult result = await service.submitText(
        'Remind me to grab the charger at Workshop',
      );

      expect(result.autoCommitted, isEmpty);
      expect(result.needsReview.single.explanation, contains('Wrong place'));
    },
  );

  test('AI does not create reminders without user input', () async {
    final ReminderCreationResult result = await service.submitText('');

    expect(result.autoCommitted, isEmpty);
    expect(result.needsReview, isEmpty);
    expect(await reminders.watchAll().first, isEmpty);
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

  test('review draft approval is idempotent by capture and draft id', () async {
    final ReminderCreationResult result = await service.submitText('Buy milk');

    final TaskReminder first = await service.approveReviewedDraft(
      result.needsReview.single,
      source: TaskReminderSource.typed,
      captureId: result.captureId!,
      title: 'Buy milk',
      scheduledAt: DateTime.utc(2026, 8, 21, 9),
    );
    final TaskReminder second = await service.approveReviewedDraft(
      result.needsReview.single,
      source: TaskReminderSource.typed,
      captureId: result.captureId!,
      title: 'Buy milk',
      scheduledAt: DateTime.utc(2026, 8, 21, 9),
    );

    expect(second.id, first.id);
    expect(second.draftId, result.needsReview.single.draftId);
    expect(
      await reminders.watchByStatus(TaskReminderStatus.active).first,
      hasLength(1),
    );
  });

  test(
    'concurrent same-title review approvals re-fetch the capture draft winner',
    () async {
      service = ReminderCreationService(
        captures: captures,
        reminders: reminders,
        drafts: const _SameTitleReviewDraftService(),
        clock: () => now,
        atomically: db.transaction,
      );
      final ReminderCreationResult result = await service.submitText(
        'two drafts',
      );
      final ParsedReminderDraft draft = result.needsReview.first;

      final List<TaskReminder> approved =
          await Future.wait(<Future<TaskReminder>>[
            service.approveReviewedDraft(
              draft,
              source: TaskReminderSource.typed,
              captureId: result.captureId!,
              title: draft.title,
              scheduledAt: DateTime.utc(2026, 8, 21, 9),
            ),
            service.approveReviewedDraft(
              draft,
              source: TaskReminderSource.typed,
              captureId: result.captureId!,
              title: draft.title,
              scheduledAt: DateTime.utc(2026, 8, 21, 9),
            ),
          ]);

      expect(approved.first.id, approved.last.id);
      expect(approved.first.draftId, draft.draftId);
      expect(
        await reminders.watchByStatus(TaskReminderStatus.active).first,
        hasLength(1),
      );
    },
  );

  test(
    'approval rolls back reminder and review state when transaction fails',
    () async {
      final ReminderCreationResult result = await service.submitText(
        'Buy milk',
      );
      service = ReminderCreationService(
        captures: captures,
        reminders: reminders,
        drafts: const HeuristicReminderDraftService(),
        clock: () => now,
        atomically: <T>(Future<T> Function() action) {
          return db.transaction<T>(() async {
            await action();
            throw StateError('rollback approval');
          });
        },
      );

      await expectLater(
        () => service.approveReviewedDraft(
          result.needsReview.single,
          source: TaskReminderSource.typed,
          captureId: result.captureId!,
          title: 'Buy milk',
          scheduledAt: DateTime.utc(2026, 8, 21, 9),
        ),
        throwsA(isA<StateError>()),
      );

      expect(
        await reminders.watchByStatus(TaskReminderStatus.active).first,
        isEmpty,
      );
      expect(await service.pendingReviewDrafts(), hasLength(1));
    },
  );

  test(
    'same-title review drafts dismiss independently by stable draft id',
    () async {
      service = ReminderCreationService(
        captures: captures,
        reminders: reminders,
        drafts: const _SameTitleReviewDraftService(),
        clock: () => now,
      );

      final ReminderCreationResult result = await service.submitText(
        'two drafts',
      );
      final List<PendingReviewDraft> restored = await service
          .pendingReviewDrafts();
      await service.dismissReviewedDraft(restored.first);

      final List<PendingReviewDraft> remaining = await service
          .pendingReviewDrafts();
      expect(result.needsReview, hasLength(2));
      expect(remaining, hasLength(1));
      expect(remaining.single.draft.title, 'Buy milk');
      expect(
        remaining.single.draft.draftId,
        isNot(restored.first.draft.draftId),
      );
    },
  );

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

  test(
    'multi-item persistence validates all drafts before creating rows',
    () async {
      service = ReminderCreationService(
        captures: captures,
        reminders: reminders,
        drafts: const _InvalidMultiDraftService(),
        clock: () => now,
      );

      await expectLater(
        () => service.submitText('two drafts'),
        throwsA(isA<ReminderDraftFormatException>()),
      );

      expect(await reminders.watchAll().first, isEmpty);
    },
  );

  test('Gemini prompt includes bounded context and context item rules', () {
    const AssistantContext context = AssistantContext(
      profile: <String, Object?>{
        'id': 'u1',
        'persona_response_language': 'en',
        'theme': 'analog_companion',
        'prefs': <String, Object?>{},
      },
      places: <Map<String, Object?>>[
        <String, Object?>{'id': 'p1', 'name': 'Workshop', 'radius_m': 150},
      ],
      activeReminders: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'r1',
          'title': 'Pick up meds',
          'trigger_type': 'time',
        },
      ],
      recentReminderActions: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'e1',
          'reminder_id': 'r1',
          'event_type': 'wrong_place',
        },
      ],
      recentUnclearCaptures: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'c1',
          'source': 'audio',
          'error': 'Audio was unclear.',
        },
      ],
      truncated: false,
      maxBytes: 12288,
    );

    final String prompt = GeminiReminderDraftService.promptForTesting(
      ReminderDraftContext(now: now, assistantContext: context),
    );

    expect(prompt, contains('"places":[{"id":"p1","name":"Workshop"'));
    expect(prompt, contains('"recent_reminder_actions"'));
    expect(prompt, contains('Do not create reminders from background context'));
    expect(prompt, contains('place:<id>'));
    expect(prompt, contains('Assistant context JSON, bounded and redacted'));
  });

  test('Gemini parser rejects non task reminder output', () {
    const GeminiReminderDraftService gemini = GeminiReminderDraftService(
      apiKey: 'test-key',
      model: 'test-model',
    );
    final String body = jsonEncode(<String, Object?>{
      'candidates': <Object?>[
        <String, Object?>{
          'content': <String, Object?>{
            'parts': <Object?>[
              <String, Object?>{
                'text': jsonEncode(<String, Object?>{
                  'is_unclear': false,
                  'drafts': <Object?>[
                    <String, Object?>{
                      'kind': 'note',
                      'title': 'Journal',
                      'confidence': 0.9,
                      'trigger_type': 'time',
                    },
                  ],
                }),
              },
            ],
          },
        },
      ],
    });

    expect(
      () => gemini.parseGeminiResponseForTesting(
        body,
        ReminderDraftContext(now: now),
      ),
      throwsA(isA<ReminderDraftFormatException>()),
    );
  });

  test('Gemini parser rejects invalid confidence and unknown context IDs', () {
    const GeminiReminderDraftService gemini = GeminiReminderDraftService(
      apiKey: 'test-key',
      model: 'test-model',
    );
    String body(Map<String, Object?> draft) => jsonEncode(<String, Object?>{
      'candidates': <Object?>[
        <String, Object?>{
          'content': <String, Object?>{
            'parts': <Object?>[
              <String, Object?>{
                'text': jsonEncode(<String, Object?>{
                  'is_unclear': false,
                  'drafts': <Object?>[draft],
                }),
              },
            ],
          },
        },
      ],
    });
    const AssistantContext assistantContext = AssistantContext(
      profile: null,
      places: <Map<String, Object?>>[
        <String, Object?>{'id': 'p1', 'name': 'Home', 'radius_m': 150},
      ],
      activeReminders: <Map<String, Object?>>[],
      recentReminderActions: <Map<String, Object?>>[],
      recentUnclearCaptures: <Map<String, Object?>>[],
      truncated: false,
      maxBytes: 12288,
    );
    final ReminderDraftContext context = ReminderDraftContext(
      now: now,
      assistantContext: assistantContext,
    );

    expect(
      () => gemini.parseGeminiResponseForTesting(
        body(<String, Object?>{
          'kind': 'task_reminder',
          'title': 'Bad confidence',
          'confidence': 1.2,
          'trigger_type': 'time',
          'scheduled_at': '2026-08-21T09:00:00Z',
          'explanation': 'Invalid confidence.',
        }),
        context,
      ),
      throwsA(isA<ReminderDraftFormatException>()),
    );
    expect(
      () => gemini.parseGeminiResponseForTesting(
        body(<String, Object?>{
          'kind': 'task_reminder',
          'title': 'Bad place',
          'confidence': 0.9,
          'trigger_type': 'place',
          'place_id': 'p2',
          'geofence_transition': 'enter',
          'explanation': 'Invalid place.',
          'context_items_used': <String>['place:p2'],
        }),
        context,
      ),
      throwsA(isA<ReminderDraftFormatException>()),
    );
  });

  test(
    'Gemini parser rejects malformed context, timestamps, and explanations',
    () {
      const GeminiReminderDraftService gemini = GeminiReminderDraftService(
        apiKey: 'test-key',
        model: 'test-model',
      );
      String body(Map<String, Object?> draft) => jsonEncode(<String, Object?>{
        'candidates': <Object?>[
          <String, Object?>{
            'content': <String, Object?>{
              'parts': <Object?>[
                <String, Object?>{
                  'text': jsonEncode(<String, Object?>{
                    'is_unclear': false,
                    'drafts': <Object?>[draft],
                  }),
                },
              ],
            },
          },
        ],
      });
      final Map<String, Object?> valid = <String, Object?>{
        'kind': 'task_reminder',
        'title': 'Call Sam',
        'confidence': 0.9,
        'trigger_type': 'time',
        'scheduled_at': '2026-08-21T09:00:00Z',
        'explanation': 'User gave a concrete time.',
      };

      for (final Map<String, Object?> invalid in <Map<String, Object?>>[
        <String, Object?>{...valid, 'context_items_used': 'place:p1'},
        <String, Object?>{
          ...valid,
          'context_items_used': <Object?>[42],
        },
        <String, Object?>{...valid, 'scheduled_at': '2026-08-21T09:00:00'},
        <String, Object?>{...valid, 'explanation': ''},
      ]) {
        expect(
          () => gemini.parseGeminiResponseForTesting(
            body(invalid),
            ReminderDraftContext(now: now),
          ),
          throwsA(isA<ReminderDraftFormatException>()),
        );
      }
    },
  );

  test('heuristic wall-clock parsing uses supplied IANA timezone', () async {
    final ReminderDraftParseResult cairo =
        await const HeuristicReminderDraftService().parseText(
          'remind me to call Sam at 9pm',
          ReminderDraftContext(
            now: DateTime.utc(2026, 8, 20, 10),
            timeZoneName: 'Africa/Cairo',
          ),
        );
    final ReminderDraftParseResult newYorkSummer =
        await const HeuristicReminderDraftService().parseText(
          'remind me to call Sam at 9pm',
          ReminderDraftContext(
            now: DateTime.utc(2026, 7, 1, 12),
            timeZoneName: 'America/New_York',
          ),
        );
    final ReminderDraftParseResult newYorkWinter =
        await const HeuristicReminderDraftService().parseText(
          'remind me to call Sam at 9pm',
          ReminderDraftContext(
            now: DateTime.utc(2026, 1, 1, 12),
            timeZoneName: 'America/New_York',
          ),
        );
    final ReminderDraftParseResult cairoWinter =
        await const HeuristicReminderDraftService().parseText(
          'remind me to call Sam at 9pm',
          ReminderDraftContext(
            now: DateTime.utc(2026, 1, 1, 12),
            timeZoneName: 'Africa/Cairo',
          ),
        );
    final ReminderDraftParseResult newYorkSpringForward =
        await const HeuristicReminderDraftService().parseText(
          'remind me to call Sam at 3:30am',
          ReminderDraftContext(
            now: DateTime.utc(2026, 3, 8, 6),
            timeZoneName: 'America/New_York',
          ),
        );
    final ReminderDraftParseResult newYorkFallBack =
        await const HeuristicReminderDraftService().parseText(
          'remind me to call Sam at 2:30am',
          ReminderDraftContext(
            now: DateTime.utc(2026, 11, 1, 4),
            timeZoneName: 'America/New_York',
          ),
        );
    final ReminderDraftParseResult springForwardEvePastRollover =
        await const HeuristicReminderDraftService().parseText(
          'remind me to call Sam at 11pm',
          ReminderDraftContext(
            now: DateTime.utc(2026, 3, 8, 4, 30),
            timeZoneName: 'America/New_York',
          ),
        );
    final ReminderDraftParseResult fallBackEvePastRollover =
        await const HeuristicReminderDraftService().parseText(
          'remind me to call Sam at 11pm',
          ReminderDraftContext(
            now: DateTime.utc(2026, 11, 1, 3, 30),
            timeZoneName: 'America/New_York',
          ),
        );

    expect(cairo.drafts.single.scheduledAt, DateTime.utc(2026, 8, 20, 18));
    expect(cairoWinter.drafts.single.scheduledAt, DateTime.utc(2026, 1, 1, 19));
    expect(
      newYorkSummer.drafts.single.scheduledAt,
      DateTime.utc(2026, 7, 2, 1),
    );
    expect(
      newYorkWinter.drafts.single.scheduledAt,
      DateTime.utc(2026, 1, 2, 2),
    );
    expect(
      newYorkSpringForward.drafts.single.scheduledAt,
      DateTime.utc(2026, 3, 8, 7, 30),
    );
    expect(
      newYorkFallBack.drafts.single.scheduledAt,
      DateTime.utc(2026, 11, 1, 7, 30),
    );
    expect(
      springForwardEvePastRollover.drafts.single.scheduledAt,
      DateTime.utc(2026, 3, 9, 3),
    );
    expect(
      fallBackEvePastRollover.drafts.single.scheduledAt,
      DateTime.utc(2026, 11, 2, 4),
    );
  });

  test(
    'unclear audio permits initial attempt plus 2 retries then falls back to typing',
    () async {
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
      final Capture afterSecond = (await captures.getByIds(<String>[
        capture.id,
      ])).single;
      final ReminderCreationResult third = await service.processAudioCapture(
        afterSecond,
      );

      expect(first.unclearAudio, isTrue);
      expect(first.retryLimitReached, isFalse);
      expect(second.unclearAudio, isTrue);
      expect(second.retryLimitReached, isFalse);
      expect(third.unclearAudio, isTrue);
      expect(third.retryLimitReached, isTrue);
      final Capture updated = (await captures.getByIds(<String>[
        capture.id,
      ])).single;
      expect(updated.error, contains('Type the reminder instead'));
    },
  );

  test('audio retry can be associated with a replacement recording', () async {
    final File firstFile = await _audioFile('unclear');
    final Capture capture = await captures.create(
      audioPath: firstFile.path,
      source: CaptureSource.audio.wire,
    );
    await service.processAudioCapture(capture);
    final Capture afterFirst = (await captures.getByIds(<String>[
      capture.id,
    ])).single;
    final File replacement = await _audioFile('remind me to call Sam tomorrow');

    await service.associateReplacementRecording(
      afterFirst,
      audioPath: replacement.path,
    );
    final Capture retriable = (await captures.getByIds(<String>[
      capture.id,
    ])).single;
    final ReminderCreationResult result = await service.processAudioCapture(
      retriable,
    );

    expect(retriable.audioPath, replacement.path);
    expect(result.autoCommitted, hasLength(1));
  });

  test(
    'stale concurrent audio retries atomically increment stored attempts',
    () async {
      final File file = await _audioFile('unclear');
      final Capture capture = await captures.create(
        audioPath: file.path,
        source: CaptureSource.audio.wire,
      );

      await Future.wait(<Future<ReminderCreationResult>>[
        service.processAudioCapture(capture),
        service.processAudioCapture(capture),
      ]);
      final Capture afterConcurrent = (await captures.getByIds(<String>[
        capture.id,
      ])).single;
      final ReminderCreationResult third = await service.processAudioCapture(
        afterConcurrent,
      );

      expect(third.retryLimitReached, isTrue);
      final Capture updated = (await captures.getByIds(<String>[
        capture.id,
      ])).single;
      expect(updated.error, contains('Type the reminder instead'));
    },
  );

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

  test(
    'audio parser exception preserves existing structured attempt state',
    () async {
      final File file = await _audioFile('unclear');
      final Capture capture = await captures.create(
        audioPath: file.path,
        source: CaptureSource.audio.wire,
      );
      await service.processAudioCapture(capture);
      service = ReminderCreationService(
        captures: captures,
        reminders: reminders,
        drafts: const _FailingDraftService(),
        clock: () => now,
        atomically: db.transaction,
      );

      await expectLater(
        () => service.processAudioCapture(capture),
        throwsA(isA<StateError>()),
      );
      service = ReminderCreationService(
        captures: captures,
        reminders: reminders,
        drafts: const HeuristicReminderDraftService(),
        clock: () => now,
        atomically: db.transaction,
      );
      final Capture afterFailure = (await captures.getByIds(<String>[
        capture.id,
      ])).single;
      final ReminderCreationResult secondUnclear = await service
          .processAudioCapture(afterFailure);

      expect(secondUnclear.retryLimitReached, isFalse);
      expect(
        ReminderCreationService.captureStateMessageFor(afterFailure),
        contains('network unavailable'),
      );
    },
  );
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

class _InvalidMultiDraftService implements ReminderDraftService {
  const _InvalidMultiDraftService();

  @override
  Future<ReminderDraftParseResult> parseAudio(
    File file,
    ReminderDraftContext context,
  ) => parseText('', context);

  @override
  Future<ReminderDraftParseResult> parseText(
    String input,
    ReminderDraftContext context,
  ) async => ReminderDraftParseResult(
    drafts: <ParsedReminderDraft>[
      ParsedReminderDraft(
        title: 'Valid',
        confidence: 0.9,
        triggerType: TaskReminderTriggerType.time,
        scheduledAt: DateTime.utc(2026, 8, 21, 9),
        explanation: 'Valid.',
      ),
      const ParsedReminderDraft(
        title: '',
        confidence: 0.9,
        triggerType: TaskReminderTriggerType.time,
        scheduledAt: null,
        explanation: 'Invalid.',
      ),
    ],
  );
}

class _SameTitleReviewDraftService implements ReminderDraftService {
  const _SameTitleReviewDraftService();

  @override
  Future<ReminderDraftParseResult> parseAudio(
    File file,
    ReminderDraftContext context,
  ) => parseText('', context);

  @override
  Future<ReminderDraftParseResult> parseText(
    String input,
    ReminderDraftContext context,
  ) async => const ReminderDraftParseResult(
    drafts: <ParsedReminderDraft>[
      ParsedReminderDraft(
        title: 'Buy milk',
        confidence: 0.4,
        triggerType: TaskReminderTriggerType.time,
        explanation: 'Missing schedule.',
      ),
      ParsedReminderDraft(
        title: 'Buy milk',
        confidence: 0.4,
        triggerType: TaskReminderTriggerType.time,
        explanation: 'Also missing schedule.',
      ),
    ],
  );
}
