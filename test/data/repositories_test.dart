import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/core/data/id_generator.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/events/event_emitter.dart';
import 'package:sidekick/core/events/events_repository.dart';
import 'package:sidekick/features/tasks/data/tasks_repository_impl.dart';
import 'package:sidekick/features/tasks/domain/task.dart';

void main() {
  late AppDatabase db;
  late DriftEventsRepository events;
  late EventEmitter emitter;
  late TasksRepositoryImpl tasks;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    events = DriftEventsRepository(db);
    emitter = EventEmitter(events, IdGenerator());
    tasks = TasksRepositoryImpl(
      db: db,
      emitter: emitter,
      idGenerator: IdGenerator(),
      userId: 'u1',
    );
  });

  tearDown(() => db.close());

  Future<TaskRow> rowFor(String id) =>
      (db.select(db.tasks)..where((Tasks t) => t.id.equals(id))).getSingle();

  test('create writes local-first, marks dirty, and streams instantly', () async {
    final Future<List<Task>> firstNonEmpty =
        tasks.watchAll().firstWhere((List<Task> list) => list.isNotEmpty);

    final Task created = await tasks.create(title: 'Buy milk');

    expect(created.title, 'Buy milk');
    expect(created.status, TaskStatus.todo);

    final TaskRow row = await rowFor(created.id);
    expect(row.dirty, isTrue, reason: 'a fresh local row is unsynced');
    expect(row.syncedAt, isNull);
    expect(row.userId, 'u1');

    final List<Task> streamed = await firstNonEmpty;
    expect(streamed.single.id, created.id);
  });

  test('create emits a structural <entity>_created event (D9)', () async {
    final Task created = await tasks.create(title: 'Ship it');
    await emitter.settle();

    final events0 = await events.getSince(DateTime.utc(2000));
    final created0 = events0.where((e) => e.eventType == 'task_created');
    expect(created0.length, 1);
    expect(created0.single.entityId, created.id);

    // The event row is itself dirty for sync.
    final eventRow = await (db.select(db.events)).getSingle();
    expect(eventRow.dirty, isTrue);
  });

  test('status change emits task_status_changed with {from,to}', () async {
    final Task created = await tasks.create(title: 'Do thing');
    await emitter.settle();

    await tasks.update(created.copyWith(status: TaskStatus.done));
    await emitter.settle();

    final all = await events.getSince(DateTime.utc(2000));
    final changed = all.where((e) => e.eventType == 'task_status_changed');
    expect(changed.length, 1);
    expect(changed.single.metadata['from'], 'todo');
    expect(changed.single.metadata['to'], 'done');
  });

  test('soft delete tombstones the row and hides it from watchAll', () async {
    final Task created = await tasks.create(title: 'Temp');
    await tasks.delete(created.id);

    final TaskRow row = await rowFor(created.id);
    expect(row.deletedAt, isNotNull);
    expect(row.dirty, isTrue);

    final List<Task> visible = await tasks.watchAll().first;
    expect(visible, isEmpty);
  });

  test('watchAll is scoped to the owning user (local isolation)', () async {
    await tasks.create(title: 'u1 task');
    final TasksRepositoryImpl otherUser = TasksRepositoryImpl(
      db: db,
      emitter: emitter,
      idGenerator: IdGenerator(),
      userId: 'u2',
    );

    expect((await tasks.watchAll().first).length, 1);
    expect(await otherUser.watchAll().first, isEmpty);
  });
}
