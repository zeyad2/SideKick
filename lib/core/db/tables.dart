import 'package:drift/drift.dart';

/// Columns mirrored by every cloud-syncable POC table plus local sync
/// bookkeeping. `dirty` and `synced_at` are local-only and never pushed.
mixin SyncColumns on Table {
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();
  DateTimeColumn get syncedAt => dateTime().nullable()();
}

@DataClassName('ProfileRow')
class Profiles extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get personaResponseLanguage =>
      text().withDefault(const Constant('en'))();
  TextColumn get theme =>
      text().withDefault(const Constant('analog_companion'))();
  TextColumn get prefs => text().withDefault(const Constant('{}'))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('PlaceRow')
class Places extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  RealColumn get lat => real()();
  RealColumn get lng => real()();
  IntColumn get radiusM => integer().withDefault(const Constant(150))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('CaptureRow')
class Captures extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get source => text()();
  TextColumn get inputText => text().nullable()();
  TextColumn get audioPath => text().nullable()();
  TextColumn get rawTranscript => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get error => text().nullable()();
  TextColumn get metadata => text().withDefault(const Constant('{}'))();
  DateTimeColumn get capturedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('TaskReminderRow')
@TableIndex(
  name: 'task_reminders_capture_draft_uidx',
  columns: <Symbol>{#userId, #captureId, #draftId},
  unique: true,
)
class TaskReminders extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get title => text()();
  TextColumn get details => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  TextColumn get source => text()();
  RealColumn get confidence => real().withDefault(const Constant(0))();
  TextColumn get triggerType => text()();
  DateTimeColumn get scheduledAt => dateTime().nullable()();
  TextColumn get placeId => text().nullable()();
  TextColumn get geofenceTransition => text().nullable()();
  IntColumn get dwellSeconds => integer().nullable()();
  DateTimeColumn get autoCommitDeadlineAt => dateTime().nullable()();
  TextColumn get captureId => text().nullable()();
  TextColumn get draftId => text().nullable()();
  TextColumn get aiExplanation => text().nullable()();
  TextColumn get aiContext => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('ReminderEventRow')
class ReminderEvents extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get reminderId => text()();
  TextColumn get eventType => text()();
  TextColumn get metadata => text().withDefault(const Constant('{}'))();
  DateTimeColumn get occurredAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('ConversationRow')
class Conversations extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get title => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('open'))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('MessageRow')
class Messages extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get conversationId => text()();
  TextColumn get role => text()();
  TextColumn get content => text()();
  TextColumn get metadata => text().withDefault(const Constant('{}'))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('EventRow')
class Events extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get eventType => text()();
  TextColumn get entityType => text().nullable()();
  TextColumn get entityId => text().nullable()();
  TextColumn get metadata => text().withDefault(const Constant('{}'))();
  DateTimeColumn get occurredAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

class SyncMeta extends Table {
  TextColumn get syncTable => text()();
  DateTimeColumn get lastPull => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{syncTable};
}
