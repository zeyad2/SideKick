// Domain enums mirroring the schema's CHECK/enum inventory (SCHEMA.md).
//
// The local drift schema deliberately carries no CHECK constraints; these
// enums are where the allowed value sets are enforced. Each enum maps to the
// exact `wire` string stored in drift and Postgres. `_byWire` tolerates an
// unknown value by falling back (so a newer server value never crashes an
// older client).

T _byWire<T>(List<T> values, String Function(T) wireOf, String wire, T fallback) {
  for (final T value in values) {
    if (wireOf(value) == wire) {
      return value;
    }
  }
  return fallback;
}

enum LlmType {
  task,
  note,
  habit,
  uncategorized;

  String get wire => name;
  static LlmType fromWire(String wire) =>
      _byWire(values, (LlmType v) => v.wire, wire, LlmType.uncategorized);
}

enum CaptureStatus {
  pending,
  processing,
  ready,
  triaged,
  failed,
  discarded;

  String get wire => name;
  static CaptureStatus fromWire(String wire) =>
      _byWire(values, (CaptureStatus v) => v.wire, wire, CaptureStatus.pending);
}

enum ResultingType {
  task,
  note,
  habit;

  String get wire => name;
  static ResultingType? fromWire(String? wire) => wire == null
      ? null
      : _byWire<ResultingType>(
          values,
          (ResultingType v) => v.wire,
          wire,
          ResultingType.task,
        );
}

enum GoalStatus {
  active,
  achieved,
  paused,
  dropped;

  String get wire => name;
  static GoalStatus fromWire(String wire) =>
      _byWire(values, (GoalStatus v) => v.wire, wire, GoalStatus.active);
}

enum TaskStatus {
  todo,
  done,
  archived;

  String get wire => name;
  static TaskStatus fromWire(String wire) =>
      _byWire(values, (TaskStatus v) => v.wire, wire, TaskStatus.todo);
}

enum HabitLevel {
  mini,
  normal,
  mega;

  String get wire => name;
  static HabitLevel fromWire(String wire) =>
      _byWire(values, (HabitLevel v) => v.wire, wire, HabitLevel.mini);
}

enum EnergyMode {
  low,
  normal,
  charged;

  String get wire => name;
  static EnergyMode? fromWire(String? wire) => wire == null
      ? null
      : _byWire<EnergyMode>(
          values,
          (EnergyMode v) => v.wire,
          wire,
          EnergyMode.normal,
        );
}

enum ReminderType {
  time,
  geofence;

  String get wire => name;
  static ReminderType fromWire(String wire) =>
      _byWire(values, (ReminderType v) => v.wire, wire, ReminderType.time);
}

enum GeofenceTransition {
  enter,
  exit;

  String get wire => name;
  static GeofenceTransition? fromWire(String? wire) => wire == null
      ? null
      : _byWire<GeofenceTransition>(
          values,
          (GeofenceTransition v) => v.wire,
          wire,
          GeofenceTransition.enter,
        );
}

enum ReminderStatus {
  scheduled,
  fired,
  done,
  cancelled;

  String get wire => name;
  static ReminderStatus fromWire(String wire) =>
      _byWire(values, (ReminderStatus v) => v.wire, wire, ReminderStatus.scheduled);
}

enum FocusSessionStatus {
  active,
  completed,
  abandoned;

  String get wire => name;
  static FocusSessionStatus fromWire(String wire) => _byWire(
    values,
    (FocusSessionStatus v) => v.wire,
    wire,
    FocusSessionStatus.active,
  );
}

enum BlockingMode {
  soft,
  hard;

  String get wire => name;
  static BlockingMode fromWire(String wire) =>
      _byWire(values, (BlockingMode v) => v.wire, wire, BlockingMode.soft);
}

enum BlockPlatform {
  android,
  ios;

  String get wire => name;
  static BlockPlatform fromWire(String wire) =>
      _byWire(values, (BlockPlatform v) => v.wire, wire, BlockPlatform.android);
}

/// Persona *generated-text* language (D2). Chrome is always English; this only
/// governs persona output. `ar-EG` = Egyptian Arabic.
enum PersonaLanguage {
  english('en'),
  egyptianArabic('ar-EG');

  const PersonaLanguage(this.wire);
  final String wire;

  static PersonaLanguage fromWire(String wire) => _byWire(
    values,
    (PersonaLanguage v) => v.wire,
    wire,
    PersonaLanguage.english,
  );
}
