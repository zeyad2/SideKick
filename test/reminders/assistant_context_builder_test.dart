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
import 'package:sidekick/features/reminders/data/reminder_events_repository_impl.dart';
import 'package:sidekick/features/reminders/data/task_reminders_repository_impl.dart';
import 'package:sidekick/features/reminders/domain/task_reminder.dart';

void main() {
  late AppDatabase db;
  late EventEmitter emitter;
  late DateTime now;
  late ProfileRepositoryImpl profile;
  late PlacesRepositoryImpl places;
  late TaskRemindersRepositoryImpl reminders;
  late ReminderEventsRepositoryImpl reminderEvents;
  late CapturesRepositoryImpl captures;

  setUp(() {
    now = DateTime.utc(2026, 8, 22, 9);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    emitter = EventEmitter(DriftEventsRepository(db), IdGenerator());
    profile = ProfileRepositoryImpl(db: db, userId: 'u1', clock: () => now);
    places = PlacesRepositoryImpl(
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
    captures = CapturesRepositoryImpl(
      db: db,
      emitter: emitter,
      idGenerator: IdGenerator(),
      userId: 'u1',
      clock: () => now,
    );
  });

  tearDown(() => db.close());

  RepositoryAssistantContextBuilder builder({int maxBytes = 12000}) =>
      RepositoryAssistantContextBuilder(
        profile: profile,
        places: places,
        reminders: reminders,
        events: reminderEvents,
        captures: captures,
        maxBytes: maxBytes,
      );

  test('saved places appear in AI context without coordinates', () async {
    await places.create(name: 'Workshop', lat: 30.1, lng: 31.2);

    final AssistantContext context = await builder().build();

    expect(context.places.single['name'], 'Workshop');
    expect(context.places.single.containsKey('lat'), isFalse);
    expect(context.places.single.containsKey('lng'), isFalse);
  });

  test('active reminders appear in AI context', () async {
    await reminders.create(
      TaskReminderDraft(
        title: 'Pick up meds',
        source: TaskReminderSource.typed,
        confidence: 0.9,
        triggerType: TaskReminderTriggerType.time,
        scheduledAt: DateTime.utc(2026, 8, 22, 17),
      ),
    );

    final AssistantContext context = await builder().build();

    expect(context.activeReminders.single['title'], 'Pick up meds');
    expect(context.activeReminders.single['trigger_type'], 'time');
  });

  test('recent Wrong place feedback appears in later context', () async {
    final TaskReminder reminder = await reminders.create(
      TaskReminderDraft(
        title: 'Take keys',
        source: TaskReminderSource.typed,
        confidence: 0.9,
        triggerType: TaskReminderTriggerType.time,
        scheduledAt: DateTime.utc(2026, 8, 22, 17),
      ),
    );
    await reminderEvents.append(
      reminderId: reminder.id,
      eventType: ReminderEventType.wrongPlace,
      metadata: const <String, Object?>{'correction': 'wrong_place'},
    );

    final AssistantContext context = await builder().build();

    expect(context.recentReminderActions.single['event_type'], 'wrong_place');
    expect(
      context.recentReminderActions.single['metadata'],
      containsPair('correction', 'wrong_place'),
    );
  });

  test(
    'recent unclear captures appear in context without transcript',
    () async {
      final Capture capture = await captures.create(
        audioPath: 'capture.m4a',
        source: CaptureSource.audio.wire,
      );
      await captures.update(
        capture.copyWith(
          status: CaptureStatus.failed,
          rawTranscript: 'private transcript',
          error: 'Audio was unclear.',
        ),
      );

      final AssistantContext context = await builder().build();

      expect(context.recentUnclearCaptures.single['id'], capture.id);
      expect(context.recentUnclearCaptures.single['reason'], 'unclear_audio');
      expect(
        context.recentUnclearCaptures.single.containsKey('error'),
        isFalse,
      );
      expect(
        context.recentUnclearCaptures.single.containsKey('raw_transcript'),
        isFalse,
      );
    },
  );

  test('capture workflow state never enters assistant context', () async {
    final Capture capture = await captures.create(
      audioPath: 'capture.m4a',
      source: CaptureSource.audio.wire,
    );
    await captures.update(
      capture.copyWith(
        status: CaptureStatus.failed,
        error: 'Audio was unclear.',
        metadata: const <String, Object?>{
          'draft_state':
              'sidekick_state:{"review_drafts":[{"details":"private speech"}]}',
        },
      ),
    );

    final String encoded = contextJson(await builder().build());

    expect(encoded, isNot(contains('sidekick_state:')));
    expect(encoded, isNot(contains('private speech')));
  });

  test('context builder enforces bounded payload size', () async {
    for (int i = 0; i < 20; i++) {
      await places.create(
        name: 'Place number $i with a long label',
        lat: i.toDouble(),
        lng: i.toDouble(),
      );
    }

    final AssistantContext context = await builder(maxBytes: 700).build();

    expect(context.encodedBytes, lessThanOrEqualTo(700));
    expect(context.truncated, isTrue);
  });

  test('context builder filters profile prefs before enforcing size', () async {
    await profile.mergePrefs(<String, Object?>{
      'long': List<String>.filled(20, 'preference with many words').join(' '),
      'timezone': 'Africa/Cairo',
    });

    final AssistantContext context = await builder(maxBytes: 512).build();

    expect(context.encodedBytes, lessThanOrEqualTo(512));
    expect(context.truncated, isFalse);
    expect(context.profile?['prefs'], isNot(contains('long')));
    expect(context.profile?['prefs'], containsPair('timezone', 'Africa/Cairo'));
  });

  test('context builder rejects byte limits below the contract floor', () {
    expect(
      () => builder(maxBytes: minimumAssistantContextMaxBytes - 1),
      throwsArgumentError,
    );
  });

  test('reminder event metadata is allowlisted for external context', () async {
    final TaskReminder reminder = await reminders.create(
      TaskReminderDraft(
        title: 'Take keys',
        source: TaskReminderSource.typed,
        confidence: 0.9,
        triggerType: TaskReminderTriggerType.time,
        scheduledAt: DateTime.utc(2026, 8, 22, 17),
      ),
    );
    await reminderEvents.append(
      reminderId: reminder.id,
      eventType: ReminderEventType.wrongPlace,
      metadata: const <String, Object?>{
        'correction': 'wrong_place',
        'place_id': 'p1',
        'raw_coordinates': <double>[30, 31],
        'private_note': 'do not send',
      },
    );

    final AssistantContext context = await builder().build();
    final Object? metadata = context.recentReminderActions.single['metadata'];

    expect(metadata, containsPair('correction', 'wrong_place'));
    expect(metadata, containsPair('place_id', 'p1'));
    expect(metadata, isNot(contains('raw_coordinates')));
    expect(metadata, isNot(contains('private_note')));
  });
}

String contextJson(AssistantContext context) => context.toJson().toString();
