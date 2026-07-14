import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/core/auth/auth_providers.dart';
import 'package:sidekick/core/data/id_generator.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/events/event_emitter.dart';
import 'package:sidekick/core/providers/core_providers.dart';
import 'package:sidekick/features/focus/data/focus_sessions_repository_impl.dart';
import 'package:sidekick/features/focus/data/vibe_checks_repository_impl.dart';
import 'package:sidekick/features/focus/domain/focus_session.dart';
import 'package:sidekick/features/focus/domain/vibe_check.dart';
import 'package:sidekick/features/goals/data/goals_repository_impl.dart';
import 'package:sidekick/features/goals/domain/goal.dart';
import 'package:sidekick/features/habits/data/habit_completions_repository_impl.dart';
import 'package:sidekick/features/habits/data/habits_repository_impl.dart';
import 'package:sidekick/features/habits/domain/habit.dart';
import 'package:sidekick/features/habits/domain/habit_completion.dart';
import 'package:sidekick/features/inbox/data/captures_repository_impl.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';
import 'package:sidekick/features/notes/data/notes_repository_impl.dart';
import 'package:sidekick/features/notes/domain/note.dart';
import 'package:sidekick/features/places/data/places_repository_impl.dart';
import 'package:sidekick/features/places/domain/place.dart';
import 'package:sidekick/features/profile/data/profile_repository_impl.dart';
import 'package:sidekick/features/profile/domain/profile.dart';
import 'package:sidekick/features/reminders/data/reminders_repository_impl.dart';
import 'package:sidekick/features/reminders/domain/reminder.dart';
import 'package:sidekick/features/settings/data/block_list_repository_impl.dart';
import 'package:sidekick/features/settings/domain/block_list_entry.dart';
import 'package:sidekick/features/tasks/data/tasks_repository_impl.dart';
import 'package:sidekick/features/tasks/domain/task.dart';

/// Shared constructor args for the user-scoped repositories.
({AppDatabase db, EventEmitter emitter, IdGenerator idGenerator, String userId})
_deps(Ref ref) => (
  db: ref.watch(appDatabaseProvider),
  emitter: ref.watch(eventEmitterProvider),
  idGenerator: ref.watch(idGeneratorProvider),
  userId: ref.watch(requireUserIdProvider),
);

final Provider<CapturesRepository> capturesRepositoryProvider =
    Provider<CapturesRepository>((Ref ref) {
      final d = _deps(ref);
      return CapturesRepositoryImpl(
        db: d.db,
        emitter: d.emitter,
        idGenerator: d.idGenerator,
        userId: d.userId,
      );
    });

final Provider<TasksRepository> tasksRepositoryProvider =
    Provider<TasksRepository>((Ref ref) {
      final d = _deps(ref);
      return TasksRepositoryImpl(
        db: d.db,
        emitter: d.emitter,
        idGenerator: d.idGenerator,
        userId: d.userId,
      );
    });

final Provider<NotesRepository> notesRepositoryProvider =
    Provider<NotesRepository>((Ref ref) {
      final d = _deps(ref);
      return NotesRepositoryImpl(
        db: d.db,
        emitter: d.emitter,
        idGenerator: d.idGenerator,
        userId: d.userId,
      );
    });

final Provider<GoalsRepository> goalsRepositoryProvider =
    Provider<GoalsRepository>((Ref ref) {
      final d = _deps(ref);
      return GoalsRepositoryImpl(
        db: d.db,
        emitter: d.emitter,
        idGenerator: d.idGenerator,
        userId: d.userId,
      );
    });

final Provider<HabitsRepository> habitsRepositoryProvider =
    Provider<HabitsRepository>((Ref ref) {
      final d = _deps(ref);
      return HabitsRepositoryImpl(
        db: d.db,
        emitter: d.emitter,
        idGenerator: d.idGenerator,
        userId: d.userId,
      );
    });

final Provider<HabitCompletionsRepository> habitCompletionsRepositoryProvider =
    Provider<HabitCompletionsRepository>((Ref ref) {
      final d = _deps(ref);
      return HabitCompletionsRepositoryImpl(
        db: d.db,
        emitter: d.emitter,
        idGenerator: d.idGenerator,
        userId: d.userId,
      );
    });

final Provider<PlacesRepository> placesRepositoryProvider =
    Provider<PlacesRepository>((Ref ref) {
      final d = _deps(ref);
      return PlacesRepositoryImpl(
        db: d.db,
        emitter: d.emitter,
        idGenerator: d.idGenerator,
        userId: d.userId,
      );
    });

final Provider<FocusSessionsRepository> focusSessionsRepositoryProvider =
    Provider<FocusSessionsRepository>((Ref ref) {
      final d = _deps(ref);
      return FocusSessionsRepositoryImpl(
        db: d.db,
        emitter: d.emitter,
        idGenerator: d.idGenerator,
        userId: d.userId,
      );
    });

final Provider<VibeChecksRepository> vibeChecksRepositoryProvider =
    Provider<VibeChecksRepository>((Ref ref) {
      final d = _deps(ref);
      return VibeChecksRepositoryImpl(
        db: d.db,
        emitter: d.emitter,
        idGenerator: d.idGenerator,
        userId: d.userId,
      );
    });

final Provider<RemindersRepository> remindersRepositoryProvider =
    Provider<RemindersRepository>((Ref ref) {
      final d = _deps(ref);
      return RemindersRepositoryImpl(
        db: d.db,
        emitter: d.emitter,
        idGenerator: d.idGenerator,
        userId: d.userId,
      );
    });

final Provider<BlockListRepository> blockListRepositoryProvider =
    Provider<BlockListRepository>((Ref ref) {
      final d = _deps(ref);
      return BlockListRepositoryImpl(
        db: d.db,
        emitter: d.emitter,
        idGenerator: d.idGenerator,
        userId: d.userId,
      );
    });

/// Profile/preferences repository (no [EventEmitter] — preference edits are not
/// behavioural events).
final Provider<ProfileRepository> profileRepositoryProvider =
    Provider<ProfileRepository>(
      (Ref ref) => ProfileRepositoryImpl(
        db: ref.watch(appDatabaseProvider),
        userId: ref.watch(requireUserIdProvider),
      ),
    );
