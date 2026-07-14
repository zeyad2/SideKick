import 'package:drift/drift.dart';
import 'package:sidekick/core/data/id_generator.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/db/json_codec.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/features/profile/domain/profile.dart';

/// LOCAL-FIRST profile/preferences store. The profile row's primary key IS the
/// auth user id (profiles has no separate `user_id`). Unlike the other
/// repositories this one emits no structural events (preference edits are not
/// behavioural signals) and needs no [EventEmitter].
class ProfileRepositoryImpl implements ProfileRepository {
  ProfileRepositoryImpl({
    required this.db,
    required this.userId,
    IdGenerator? idGenerator,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  final AppDatabase db;
  final String userId;
  final DateTime Function() _clock;

  @override
  Stream<Profile?> watch() =>
      (db.select(db.profiles)..where((Profiles p) => p.id.equals(userId)))
          .watchSingleOrNull()
          .map((ProfileRow? row) => row == null ? null : _toDomain(row));

  @override
  Future<Profile?> get() async {
    final ProfileRow? row = await (db.select(db.profiles)
          ..where((Profiles p) => p.id.equals(userId)))
        .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  @override
  Future<Profile> ensureExists() async {
    final DateTime timestamp = _clock();
    // Local-first: create the mirror row if the pull hasn't delivered it yet.
    // A concurrent pull upserts the server copy over this via LWW.
    await db
        .into(db.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: userId,
            personaResponseLanguage: Value<String>(PersonaLanguage.english.wire),
            theme: const Value<String>('analog_companion'),
            createdAt: Value<DateTime>(timestamp),
            updatedAt: Value<DateTime>(timestamp),
            // A locally-provisioned profile is not yet pushed.
            dirty: const Value<bool>(true),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    return (await get())!;
  }

  @override
  Future<void> setPersonaLanguage(PersonaLanguage language) async {
    await ensureExists();
    final DateTime timestamp = _clock();
    await (db.update(db.profiles)..where((Profiles p) => p.id.equals(userId)))
        .write(
          ProfilesCompanion(
            personaResponseLanguage: Value<String>(language.wire),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
  }

  @override
  Future<void> setTheme(String theme) async {
    await ensureExists();
    final DateTime timestamp = _clock();
    await (db.update(db.profiles)..where((Profiles p) => p.id.equals(userId)))
        .write(
          ProfilesCompanion(
            theme: Value<String>(theme),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
  }

  @override
  Future<void> mergePrefs(Map<String, Object?> values) async {
    final Profile current = await ensureExists();
    final Map<String, Object?> merged = <String, Object?>{
      ...current.prefs,
      ...values,
    };
    final DateTime timestamp = _clock();
    await (db.update(db.profiles)..where((Profiles p) => p.id.equals(userId)))
        .write(
          ProfilesCompanion(
            prefs: Value<String>(JsonCodecs.encode(merged)),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
  }

  Profile _toDomain(ProfileRow row) => Profile(
    id: row.id,
    personaResponseLanguage: PersonaLanguage.fromWire(
      row.personaResponseLanguage,
    ),
    theme: row.theme,
    prefs: JsonCodecs.decodeMap(row.prefs),
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}
