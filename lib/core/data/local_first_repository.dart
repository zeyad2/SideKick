import 'package:sidekick/core/data/id_generator.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/events/event_emitter.dart';

/// Shared plumbing for the local-first repositories (D5). Every concrete
/// repository is bound to exactly one signed-in [userId] and writes to the
/// local [AppDatabase] first, marking rows dirty for background sync.
///
/// Typed companions differ per table, so the actual create/update/delete SQL
/// lives in each impl — this base only centralises the id generator, the
/// wall-clock, and the (non-blocking) [EventEmitter] the mutations ride on.
abstract class LocalFirstRepository {
  LocalFirstRepository({
    required this.db,
    required this.emitter,
    required this.idGenerator,
    required this.userId,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  final AppDatabase db;
  final EventEmitter emitter;
  final IdGenerator idGenerator;

  /// The owner of every row this repository reads or writes.
  final String userId;

  final DateTime Function() _clock;

  /// Device wall-clock, UTC. This is the client-owned LWW `updated_at` clock.
  DateTime now() => _clock();

  String newId() => idGenerator.v4();
}
