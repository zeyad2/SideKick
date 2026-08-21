import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/core/auth/auth_providers.dart';
import 'package:sidekick/core/data/id_generator.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/events/event_emitter.dart';
import 'package:sidekick/core/providers/core_providers.dart';
import 'package:sidekick/features/conversations/data/conversation_repository_impl.dart';
import 'package:sidekick/features/conversations/domain/conversation.dart';
import 'package:sidekick/features/inbox/data/captures_repository_impl.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';
import 'package:sidekick/features/places/data/places_repository_impl.dart';
import 'package:sidekick/features/places/domain/place.dart';
import 'package:sidekick/features/profile/data/profile_repository_impl.dart';
import 'package:sidekick/features/profile/domain/profile.dart';
import 'package:sidekick/features/reminders/data/reminder_events_repository_impl.dart';
import 'package:sidekick/features/reminders/data/task_reminders_repository_impl.dart';
import 'package:sidekick/features/reminders/domain/reminder_event.dart';
import 'package:sidekick/features/reminders/domain/task_reminder.dart';

/// Shared constructor args for the user-scoped POC repositories.
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
        clock: ref.watch(clockProvider),
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
        clock: ref.watch(clockProvider),
      );
    });

final Provider<TaskRemindersRepository> taskRemindersRepositoryProvider =
    Provider<TaskRemindersRepository>((Ref ref) {
      final d = _deps(ref);
      return TaskRemindersRepositoryImpl(
        db: d.db,
        emitter: d.emitter,
        idGenerator: d.idGenerator,
        userId: d.userId,
        clock: ref.watch(clockProvider),
      );
    });

final Provider<ReminderEventsRepository> reminderEventsRepositoryProvider =
    Provider<ReminderEventsRepository>((Ref ref) {
      final d = _deps(ref);
      return ReminderEventsRepositoryImpl(
        db: d.db,
        emitter: d.emitter,
        idGenerator: d.idGenerator,
        userId: d.userId,
        clock: ref.watch(clockProvider),
      );
    });

final Provider<ConversationRepository> conversationRepositoryProvider =
    Provider<ConversationRepository>((Ref ref) {
      final d = _deps(ref);
      return ConversationRepositoryImpl(
        db: d.db,
        emitter: d.emitter,
        idGenerator: d.idGenerator,
        userId: d.userId,
        clock: ref.watch(clockProvider),
      );
    });

/// Profile/preferences repository (no [EventEmitter] because preference edits
/// are not behavioural events).
final Provider<ProfileRepository> profileRepositoryProvider =
    Provider<ProfileRepository>(
      (Ref ref) => ProfileRepositoryImpl(
        db: ref.watch(appDatabaseProvider),
        userId: ref.watch(requireUserIdProvider),
      ),
    );
