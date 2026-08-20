// Domain enums mirroring the POC schema's CHECK/enum inventory.
//
// The local drift schema deliberately carries no CHECK constraints; these
// enums are where the allowed value sets are enforced. Each enum maps to the
// exact `wire` string stored in drift and Postgres. `_byWire` tolerates an
// unknown value by falling back (so a newer server value never crashes an
// older client).

T _byWire<T>(
  List<T> values,
  String Function(T) wireOf,
  String wire,
  T fallback,
) {
  for (final T value in values) {
    if (wireOf(value) == wire) {
      return value;
    }
  }
  return fallback;
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

enum CaptureSource {
  typed,
  audio,
  shortcut;

  String get wire => name;
  static CaptureSource fromWire(String wire) =>
      _byWire(values, (CaptureSource v) => v.wire, wire, CaptureSource.audio);
}

enum TaskReminderStatus {
  pendingAutoCommit('pending_auto_commit'),
  active('active'),
  done('done'),
  dismissed('dismissed'),
  cancelled('cancelled');

  const TaskReminderStatus(this.wire);
  final String wire;

  static TaskReminderStatus fromWire(String wire) => _byWire(
    values,
    (TaskReminderStatus v) => v.wire,
    wire,
    TaskReminderStatus.active,
  );
}

enum TaskReminderSource {
  typed,
  audio,
  manual;

  String get wire => name;
  static TaskReminderSource fromWire(String wire) => _byWire(
    values,
    (TaskReminderSource v) => v.wire,
    wire,
    TaskReminderSource.manual,
  );
}

enum TaskReminderTriggerType {
  time,
  place;

  String get wire => name;
  static TaskReminderTriggerType fromWire(String wire) => _byWire(
    values,
    (TaskReminderTriggerType v) => v.wire,
    wire,
    TaskReminderTriggerType.time,
  );
}

enum ReminderEventType {
  created,
  activated,
  done,
  later,
  dismissed,
  wrongPlace,
  edited,
  fired;

  String get wire => switch (this) {
    ReminderEventType.wrongPlace => 'wrong_place',
    _ => name,
  };

  static ReminderEventType fromWire(String wire) => _byWire(
    values,
    (ReminderEventType v) => v.wire,
    wire,
    ReminderEventType.created,
  );
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
