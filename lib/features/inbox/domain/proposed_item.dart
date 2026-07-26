import 'package:meta/meta.dart';
import 'package:sidekick/core/domain/enums.dart';

/// One draft item extracted from a rant — the flat union defined in
/// docs/CAPTURE_DECOMPOSITION.md §4. Drafts live as an ordered JSON array on
/// `captures.proposed_items` and are NOT real rows until approved (or
/// auto-committed). `kind` + `title` are always present; the rest are populated
/// per kind.
///
/// [id] is a **stable client-assigned** id (§11): Gemini is not trusted to
/// supply one, so the processing service stamps each draft when it writes
/// `proposed_items`. It keys draft → child idempotency across retries and
/// auto-commit replays, so it is the id the materialised child row is created
/// with.
@immutable
class ProposedItem {
  const ProposedItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.confidence,
    this.details,
    this.schedule,
    this.location,
    this.reminder = false,
    this.anchor,
    this.cadence,
    this.level,
    this.why,
    this.targetDate,
  });

  /// Parses a single Gemini array element. The model does NOT supply [id]; a
  /// placeholder is used and the real id is stamped later via [withId]. Throws
  /// [ProposedItemFormatException] on structurally invalid input.
  factory ProposedItem.fromGemini(Object? raw) =>
      _fromMap(raw, id: '', requireId: false);

  /// Reads a draft back from stored `proposed_items` JSON, where [id] is present.
  factory ProposedItem.fromStored(Object? raw) =>
      _fromMap(raw, id: null, requireId: true);

  final String id;
  final ResultingType kind;
  final String title;
  final String? details;
  final DraftConfidence confidence;

  // --- task only ---
  final DraftSchedule? schedule;
  final DraftLocation? location;
  final bool reminder;

  // --- habit only ---
  final String? anchor;

  /// Recurrence rule; heterogeneous shape (`{type, days?, per_week?}`) stored
  /// as-is. v1 authors only daily/weekly-days (§11); custom is stored-not-authored.
  final Map<String, Object?>? cadence;
  final HabitLevel? level;

  // --- goal only ---
  final String? why;
  final DateTime? targetDate;

  bool get isTask => kind == ResultingType.task;
  bool get isHighConfidence => confidence == DraftConfidence.high;

  /// The resolved schedule instant for a task draft (local date + time), or null.
  DateTime? get scheduledAt => schedule?.resolve();

  ProposedItem withId(String newId) => ProposedItem(
    id: newId,
    kind: kind,
    title: title,
    confidence: confidence,
    details: details,
    schedule: schedule,
    location: location,
    reminder: reminder,
    anchor: anchor,
    cadence: cadence,
    level: level,
    why: why,
    targetDate: targetDate,
  );

  ProposedItem copyWith({
    ResultingType? kind,
    String? title,
    String? details,
    DraftConfidence? confidence,
    DateTime? targetDate,
  }) => ProposedItem(
    id: id,
    kind: kind ?? this.kind,
    title: title ?? this.title,
    confidence: confidence ?? this.confidence,
    details: details ?? this.details,
    schedule: schedule,
    location: location,
    reminder: reminder,
    anchor: anchor,
    cadence: cadence,
    level: level,
    why: why,
    targetDate: targetDate ?? this.targetDate,
  );

  static ProposedItem _fromMap(
    Object? raw, {
    required String? id,
    required bool requireId,
  }) {
    if (raw is! Map) {
      throw const ProposedItemFormatException('Draft item must be an object.');
    }
    final Map<String, Object?> json = Map<String, Object?>.from(raw);

    final Object? kindValue = json['kind'];
    final Object? titleValue = json['title'];
    if (kindValue is! String || titleValue is! String) {
      throw const ProposedItemFormatException(
        'Draft item needs string `kind` and `title`.',
      );
    }
    final String title = titleValue.trim();
    if (title.isEmpty) {
      throw const ProposedItemFormatException('Draft `title` is empty.');
    }
    final ResultingType? kind = _resultingType(kindValue);
    if (kind == null) {
      throw const ProposedItemFormatException('Draft `kind` is invalid.');
    }

    String resolvedId;
    if (requireId) {
      final Object? idValue = json['id'];
      if (idValue is! String || idValue.trim().isEmpty) {
        throw const ProposedItemFormatException(
          'Stored draft is missing its `id`.',
        );
      }
      resolvedId = idValue.trim();
    } else {
      resolvedId = id ?? '';
    }

    final String? details = _optionalString(json, 'details');
    final Object? confidenceValue = json['confidence'];
    if (confidenceValue is! String ||
        !DraftConfidence.values.any((v) => v.wire == confidenceValue)) {
      throw const ProposedItemFormatException(
        'Draft `confidence` must be `high` or `low`.',
      );
    }
    final DraftSchedule? schedule = _schedule(json['schedule']);
    final DraftLocation? location = _location(json['location']);
    final bool reminder = _optionalBool(json, 'reminder') ?? false;
    final String? anchor = _optionalString(json, 'anchor');
    final Map<String, Object?>? cadence = _cadence(json['cadence']);
    final HabitLevel? level = _habitLevel(json['level']);
    final String? why = _optionalString(json, 'why');
    final DateTime? targetDate = _strictDate(
      json['target_date'],
      'target_date',
    );

    if (kind != ResultingType.task &&
        (schedule != null || location != null || reminder)) {
      throw const ProposedItemFormatException(
        'Task-only fields were supplied for a non-task draft.',
      );
    }
    if (kind != ResultingType.habit &&
        (anchor != null || cadence != null || level != null)) {
      throw const ProposedItemFormatException(
        'Habit-only fields were supplied for a non-habit draft.',
      );
    }
    if (kind != ResultingType.goal && (why != null || targetDate != null)) {
      throw const ProposedItemFormatException(
        'Goal-only fields were supplied for a non-goal draft.',
      );
    }

    return ProposedItem(
      id: resolvedId,
      kind: kind,
      title: title,
      details: details,
      confidence: DraftConfidence.fromWire(confidenceValue),
      schedule: schedule,
      location: location,
      reminder: reminder,
      anchor: anchor,
      cadence: cadence,
      level: level,
      why: why,
      targetDate: targetDate,
    );
  }

  /// Serialises a draft (WITH its stamped [id]) for storage in `proposed_items`.
  /// Only the fields relevant to [kind] are emitted, keeping the blob tight.
  Map<String, Object?> toJson() {
    final Map<String, Object?> json = <String, Object?>{
      'id': id,
      'kind': kind.wire,
      'title': title,
      'confidence': confidence.wire,
      if (details != null) 'details': details,
    };
    switch (kind) {
      case ResultingType.task:
        if (schedule != null) json['schedule'] = schedule!.toJson();
        if (location != null) json['location'] = location!.toJson();
        if (reminder) json['reminder'] = true;
      case ResultingType.habit:
        if (anchor != null) json['anchor'] = anchor;
        if (cadence != null) json['cadence'] = cadence;
        if (level != null) json['level'] = level!.wire;
      case ResultingType.goal:
        if (why != null) json['why'] = why;
        if (targetDate != null) {
          json['target_date'] = _formatDate(targetDate!);
        }
      case ResultingType.note:
        break;
    }
    return json;
  }

  static ResultingType? _resultingType(String wire) {
    for (final ResultingType value in ResultingType.values) {
      if (value.wire == wire) return value;
    }
    return null;
  }

  static String? _optionalString(Map<String, Object?> json, String key) {
    if (!json.containsKey(key) || json[key] == null) return null;
    final Object? value = json[key];
    if (value is! String) {
      throw ProposedItemFormatException(
        'Draft `$key` must be a string or null.',
      );
    }
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static bool? _optionalBool(Map<String, Object?> json, String key) {
    if (!json.containsKey(key) || json[key] == null) return null;
    final Object? value = json[key];
    if (value is! bool) {
      throw ProposedItemFormatException(
        'Draft `$key` must be a boolean or null.',
      );
    }
    return value;
  }

  static DateTime? _strictDate(Object? raw, String field) {
    if (raw == null) return null;
    if (raw is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
      throw ProposedItemFormatException('Draft `$field` must be an ISO date.');
    }
    final DateTime? parsed = DateTime.tryParse(raw);
    if (parsed == null || _formatDate(parsed) != raw) {
      throw ProposedItemFormatException('Draft `$field` is not a real date.');
    }
    return parsed;
  }

  static DraftSchedule? _schedule(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map) {
      throw const ProposedItemFormatException(
        'Draft `schedule` must be an object or null.',
      );
    }
    final Map<String, Object?> map = Map<String, Object?>.from(raw);
    final DateTime? parsedDate = _strictDate(map['date'], 'schedule.date');
    final Object? timeValue = map['time'];
    String? time;
    if (timeValue != null) {
      if (timeValue is! String ||
          !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(timeValue)) {
        throw const ProposedItemFormatException(
          'Draft `schedule.time` must be HH:mm.',
        );
      }
      time = timeValue;
    }
    final String? date = parsedDate == null ? null : _formatDate(parsedDate);
    if (date == null && time == null) return null;
    return DraftSchedule(date: date, time: time);
  }

  static DraftLocation? _location(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map) {
      throw const ProposedItemFormatException(
        'Draft `location` must be an object or null.',
      );
    }
    final Map<String, Object?> map = Map<String, Object?>.from(raw);
    final String? name = _optionalString(map, 'name');
    if (name == null) {
      throw const ProposedItemFormatException(
        'Draft `location.name` is required.',
      );
    }
    final Object? transitionValue = map['transition'];
    GeofenceTransition? transition;
    if (transitionValue != null) {
      if (transitionValue is! String ||
          !GeofenceTransition.values.any((v) => v.wire == transitionValue)) {
        throw const ProposedItemFormatException(
          'Draft `location.transition` is invalid.',
        );
      }
      transition = GeofenceTransition.fromWire(transitionValue);
    }
    return DraftLocation(name: name, transition: transition);
  }

  static Map<String, Object?>? _cadence(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map) {
      throw const ProposedItemFormatException(
        'Draft `cadence` must be an object or null.',
      );
    }
    final Map<String, Object?> map = Map<String, Object?>.from(raw);
    final Object? type = map['type'];
    if (type is! String ||
        !const <String>{'daily', 'weekly', 'custom'}.contains(type)) {
      throw const ProposedItemFormatException(
        'Draft `cadence.type` is invalid.',
      );
    }
    final Object? days = map['days'];
    if (days != null) {
      const Set<String> allowed = <String>{
        'mon',
        'tue',
        'wed',
        'thu',
        'fri',
        'sat',
        'sun',
      };
      if (days is! List ||
          days.any((d) => d is! String || !allowed.contains(d))) {
        throw const ProposedItemFormatException(
          'Draft `cadence.days` is invalid.',
        );
      }
    }
    final Object? perWeek = map['per_week'];
    if (perWeek != null && (perWeek is! int || perWeek < 1 || perWeek > 7)) {
      throw const ProposedItemFormatException(
        'Draft `cadence.per_week` must be 1..7.',
      );
    }
    return map;
  }

  static HabitLevel? _habitLevel(Object? raw) {
    if (raw == null) return null;
    if (raw is! String || !HabitLevel.values.any((v) => v.wire == raw)) {
      throw const ProposedItemFormatException('Draft `level` is invalid.');
    }
    return HabitLevel.fromWire(raw);
  }

  static String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

/// A task draft's suggested schedule: an ISO date and/or an HH:mm time.
@immutable
class DraftSchedule {
  const DraftSchedule({this.date, this.time});

  final String? date; // ISO yyyy-MM-dd
  final String? time; // HH:mm, 24h

  static DraftSchedule? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Object? date = raw['date'];
    final Object? time = raw['time'];
    final String? d = date is String && date.trim().isNotEmpty
        ? date.trim()
        : null;
    final String? t = time is String && time.trim().isNotEmpty
        ? time.trim()
        : null;
    if (d == null && t == null) return null;
    return DraftSchedule(date: d, time: t);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    if (date != null) 'date': date,
    if (time != null) 'time': time,
  };

  /// Resolves to a local [DateTime]. A time without a date resolves against
  /// today; a date without a time resolves to local midnight. Returns null if
  /// the stored strings do not parse.
  DateTime? resolve() {
    if (date == null && time == null) return null;
    final DateTime base = date != null
        ? (DateTime.tryParse(date!) ?? DateTime.now())
        : DateTime.now();
    if (time == null) {
      return DateTime(base.year, base.month, base.day);
    }
    final List<String> parts = time!.split(':');
    final int hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final int minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return DateTime(base.year, base.month, base.day, hour, minute);
  }
}

/// A task draft's location context — DESIGNED-FOR-FUTURE (geofence), stored but
/// inert this phase (§9). Kept so the field survives a round-trip.
@immutable
class DraftLocation {
  const DraftLocation({required this.name, this.transition});

  final String name;
  final GeofenceTransition? transition;

  static DraftLocation? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Object? name = raw['name'];
    if (name is! String || name.trim().isEmpty) return null;
    return DraftLocation(
      name: name.trim(),
      transition: raw['transition'] is String
          ? GeofenceTransition.fromWire(raw['transition']! as String)
          : null,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    if (transition != null) 'transition': transition!.wire,
  };
}

class ProposedItemFormatException implements Exception {
  const ProposedItemFormatException(this.message);
  final String message;

  @override
  String toString() => 'ProposedItemFormatException: $message';
}
