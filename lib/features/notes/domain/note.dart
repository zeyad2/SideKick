import 'package:meta/meta.dart';

@immutable
class Note {
  const Note({
    required this.id,
    required this.userId,
    required this.createdAt,
    required this.updatedAt,
    this.captureId,
    this.title,
    this.body,
  });

  final String id;
  final String userId;
  final String? captureId;
  final String? title;
  final String? body;
  final DateTime createdAt;
  final DateTime updatedAt;

  Note copyWith({String? title, String? body}) => Note(
    id: id,
    userId: userId,
    captureId: captureId,
    title: title ?? this.title,
    body: body ?? this.body,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

abstract interface class NotesRepository {
  Stream<List<Note>> watchAll();
  Future<Note> create({String? title, String? body, String? captureId});
  Future<void> update(Note note);
  Future<void> delete(String id);
}
