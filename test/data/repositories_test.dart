import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/core/data/id_generator.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/events/event_emitter.dart';
import 'package:sidekick/core/events/events_repository.dart';
import 'package:sidekick/features/conversations/data/conversation_repository_impl.dart';
import 'package:sidekick/features/conversations/domain/conversation.dart';
import 'package:sidekick/features/inbox/data/captures_repository_impl.dart';
import 'package:sidekick/features/places/data/places_repository_impl.dart';
import 'package:sidekick/features/reminders/data/reminder_events_repository_impl.dart';
import 'package:sidekick/features/reminders/data/task_reminders_repository_impl.dart';
import 'package:sidekick/features/reminders/domain/reminder_event.dart';
import 'package:sidekick/features/reminders/domain/task_reminder.dart';

void main() {
  late AppDatabase db;
  late EventEmitter emitter;
  late TaskRemindersRepositoryImpl reminders;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    emitter = EventEmitter(DriftEventsRepository(db), IdGenerator());
    reminders = TaskRemindersRepositoryImpl(
      db: db,
      emitter: emitter,
      idGenerator: IdGenerator(),
      userId: 'u1',
      clock: () => DateTime.utc(2026, 8, 18, 10),
    );
  });

  tearDown(() => db.close());

  Future<TaskReminderRow> rowFor(String id) =>
      (db.select(db.taskReminders)..where((t) => t.id.equals(id))).getSingle();

  test('task reminder create is local-first, dirty, and streamed', () async {
    final Future<List<TaskReminder>> firstNonEmpty = reminders
        .watchAll()
        .firstWhere((List<TaskReminder> rows) => rows.isNotEmpty);

    final TaskReminder created = await reminders.create(
      TaskReminderDraft(
        title: 'Buy milk',
        source: TaskReminderSource.typed,
        confidence: 0.92,
        triggerType: TaskReminderTriggerType.time,
        scheduledAt: DateTime.utc(2026, 8, 18, 12),
      ),
    );

    final TaskReminderRow row = await rowFor(created.id);
    expect(row.userId, 'u1');
    expect(row.dirty, isTrue);
    expect(row.syncedAt, isNull);
    expect((await firstNonEmpty).single.id, created.id);
  });

  test('update marks dirty and advances updated_at', () async {
    final TaskReminder created = await reminders.create(
      TaskReminderDraft(
        title: 'Original',
        source: TaskReminderSource.typed,
        confidence: 0.8,
        triggerType: TaskReminderTriggerType.time,
        scheduledAt: DateTime.utc(2026, 8, 18, 12),
      ),
    );
    final DateTime before = (await rowFor(created.id)).updatedAt;

    final laterRepo = TaskRemindersRepositoryImpl(
      db: db,
      emitter: emitter,
      idGenerator: IdGenerator(),
      userId: 'u1',
      clock: () => DateTime.utc(2026, 8, 18, 11),
    );
    await laterRepo.update(created.copyWith(title: 'Changed'));

    final TaskReminderRow row = await rowFor(created.id);
    expect(row.title, 'Changed');
    expect(row.dirty, isTrue);
    expect(row.updatedAt.isAfter(before), isTrue);
  });

  test('soft delete hides rows but leaves tombstone syncable', () async {
    final TaskReminder created = await reminders.create(
      TaskReminderDraft(
        title: 'Temp',
        source: TaskReminderSource.manual,
        confidence: 1,
        triggerType: TaskReminderTriggerType.time,
        scheduledAt: DateTime.utc(2026, 8, 18, 12),
      ),
    );

    await reminders.delete(created.id);

    final TaskReminderRow row = await rowFor(created.id);
    expect(row.deletedAt, isNotNull);
    expect(row.dirty, isTrue);
    expect(await reminders.watchAll().first, isEmpty);
  });

  test('repository streams are owner-scoped', () async {
    await reminders.create(
      TaskReminderDraft(
        title: 'u1 reminder',
        source: TaskReminderSource.manual,
        confidence: 1,
        triggerType: TaskReminderTriggerType.time,
        scheduledAt: DateTime.utc(2026, 8, 18, 12),
      ),
    );
    final other = TaskRemindersRepositoryImpl(
      db: db,
      emitter: emitter,
      idGenerator: IdGenerator(),
      userId: 'u2',
    );

    expect((await reminders.watchAll().first), hasLength(1));
    expect(await other.watchAll().first, isEmpty);
  });

  test('all Phase 1 repositories can store rows', () async {
    final captures = CapturesRepositoryImpl(
      db: db,
      emitter: emitter,
      idGenerator: IdGenerator(),
      userId: 'u1',
    );
    final places = PlacesRepositoryImpl(
      db: db,
      emitter: emitter,
      idGenerator: IdGenerator(),
      userId: 'u1',
    );
    final reminderEvents = ReminderEventsRepositoryImpl(
      db: db,
      emitter: emitter,
      idGenerator: IdGenerator(),
      userId: 'u1',
    );
    final conversations = ConversationRepositoryImpl(
      db: db,
      emitter: emitter,
      idGenerator: IdGenerator(),
      userId: 'u1',
    );

    final capture = await captures.create(
      inputText: 'Remind me',
      source: 'typed',
    );
    final place = await places.create(name: 'Gym', lat: 30, lng: 31);
    final reminder = await reminders.create(
      TaskReminderDraft(
        title: 'Stretch',
        source: TaskReminderSource.typed,
        confidence: 0.9,
        triggerType: TaskReminderTriggerType.place,
        placeId: place.id,
        geofenceTransition: GeofenceTransition.enter,
        captureId: capture.id,
        aiContext: const <String, Object?>{'place': 'Gym'},
      ),
    );
    final ReminderEvent event = await reminderEvents.append(
      reminderId: reminder.id,
      eventType: ReminderEventType.created,
    );
    final Conversation conversation = await conversations.create(
      title: 'Future',
    );
    final Message message = await conversations.addMessage(
      conversationId: conversation.id,
      role: 'user',
      content: 'stored for later',
    );

    expect(event.reminderId, reminder.id);
    expect(message.conversationId, conversation.id);
    expect(
      await conversations.watchMessages(conversation.id).first,
      hasLength(1),
    );
  });
}
