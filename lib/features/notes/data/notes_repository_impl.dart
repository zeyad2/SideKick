import 'package:drift/drift.dart';
import 'package:sidekick/core/data/local_first_repository.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/events/domain_event.dart';
import 'package:sidekick/features/notes/domain/note.dart';

class NotesRepositoryImpl extends LocalFirstRepository
    implements NotesRepository, CaptureLinkedNotesRepository {
  NotesRepositoryImpl({
    required super.db,
    required super.emitter,
    required super.idGenerator,
    required super.userId,
    super.clock,
  });

  @override
  Stream<List<Note>> watchAll() =>
      (db.select(db.notes)
            ..where((Notes n) => n.userId.equals(userId) & n.deletedAt.isNull())
            ..orderBy(<OrderClauseGenerator<Notes>>[
              (Notes n) => OrderingTerm.desc(n.createdAt),
            ]))
          .watch()
          .map(
            (List<NoteRow> rows) => rows.map(_toDomain).toList(growable: false),
          );

  @override
  Future<Note> create({String? title, String? body, String? captureId}) async {
    return _createWithId(
      id: newId(),
      title: title,
      body: body,
      captureId: captureId,
    );
  }

  @override
  Future<Note> createForCapture({
    required String captureId,
    String? id,
    String? title,
    String? body,
  }) => _createWithId(
    id: id ?? captureId,
    title: title,
    body: body,
    captureId: captureId,
  );

  Future<Note> _createWithId({
    required String id,
    String? title,
    String? body,
    String? captureId,
  }) async {
    final DateTime timestamp = now();
    final NoteRow? inserted = await db
        .into(db.notes)
        .insertReturningOrNull(
          NotesCompanion.insert(
            id: id,
            userId: userId,
            title: Value<String?>(title),
            body: Value<String?>(body),
            captureId: Value<String?>(captureId),
            createdAt: Value<DateTime>(timestamp),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    if (inserted != null) {
      emitter.emitCreated(
        userId: userId,
        entityType: EntityTypes.note,
        entityId: id,
      );
    }
    final NoteRow row =
        await (db.select(db.notes)
              ..where((Notes n) => n.id.equals(id) & n.userId.equals(userId)))
            .getSingle();
    return _toDomain(row);
  }

  @override
  Future<void> update(Note note) async {
    final DateTime timestamp = now();
    await (db.update(db.notes)
          ..where((Notes n) => n.id.equals(note.id) & n.userId.equals(userId)))
        .write(
          NotesCompanion(
            title: Value<String?>(note.title),
            body: Value<String?>(note.body),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
  }

  @override
  Future<void> delete(String id) async {
    final DateTime timestamp = now();
    await (db.update(
      db.notes,
    )..where((Notes n) => n.id.equals(id) & n.userId.equals(userId))).write(
      NotesCompanion(
        deletedAt: Value<DateTime>(timestamp),
        updatedAt: Value<DateTime>(timestamp),
        dirty: const Value<bool>(true),
      ),
    );
  }

  Note _toDomain(NoteRow row) => Note(
    id: row.id,
    userId: row.userId,
    captureId: row.captureId,
    title: row.title,
    body: row.body,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}
