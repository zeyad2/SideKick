import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';
import 'package:sidekick/features/places/domain/place.dart';
import 'package:sidekick/features/profile/domain/profile.dart';
import 'package:sidekick/features/reminders/domain/reminder_event.dart';
import 'package:sidekick/features/reminders/domain/task_reminder.dart';

const int defaultAssistantContextMaxBytes = 12 * 1024;
const int defaultAssistantContextPlacesLimit = 20;
const int defaultAssistantContextActiveRemindersLimit = 20;
const int defaultAssistantContextRecentEventsLimit = 30;
const int defaultAssistantContextUnclearCapturesLimit = 10;
const int minimumAssistantContextMaxBytes = 512;
const Set<String> allowedExternalProfilePrefs = <String>{
  'timezone',
  'default_reminder_time',
  'default_dwell_seconds',
  'reminder_locale',
};
const Set<String> allowedExternalReminderEventMetadata = <String>{
  'source',
  'action_id',
  'correction',
  'snooze_seconds',
  'place_id',
  'trigger_type',
  'open_edit',
};

@immutable
class AssistantContext {
  const AssistantContext({
    required this.profile,
    required this.places,
    required this.activeReminders,
    required this.recentReminderActions,
    required this.recentUnclearCaptures,
    required this.truncated,
    required this.maxBytes,
  });

  final Map<String, Object?>? profile;
  final List<Map<String, Object?>> places;
  final List<Map<String, Object?>> activeReminders;
  final List<Map<String, Object?>> recentReminderActions;
  final List<Map<String, Object?>> recentUnclearCaptures;
  final bool truncated;
  final int maxBytes;

  bool get isEmpty =>
      profile == null &&
      places.isEmpty &&
      activeReminders.isEmpty &&
      recentReminderActions.isEmpty &&
      recentUnclearCaptures.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'profile': profile,
    'places': places,
    'active_reminders': activeReminders,
    'recent_reminder_actions': recentReminderActions,
    'recent_unclear_captures': recentUnclearCaptures,
    'truncated': truncated,
    'max_bytes': maxBytes,
  };

  int get encodedBytes => utf8.encode(jsonEncode(toJson())).length;
}

abstract interface class AssistantContextBuilder {
  Future<AssistantContext> build();
}

class RepositoryAssistantContextBuilder implements AssistantContextBuilder {
  RepositoryAssistantContextBuilder({
    required this.profile,
    required this.places,
    required this.reminders,
    required this.events,
    required this.captures,
    this.maxBytes = defaultAssistantContextMaxBytes,
    this.placesLimit = defaultAssistantContextPlacesLimit,
    this.activeRemindersLimit = defaultAssistantContextActiveRemindersLimit,
    this.recentEventsLimit = defaultAssistantContextRecentEventsLimit,
    this.unclearCapturesLimit = defaultAssistantContextUnclearCapturesLimit,
  }) {
    if (maxBytes < minimumAssistantContextMaxBytes) {
      throw ArgumentError.value(
        maxBytes,
        'maxBytes',
        'Assistant context maxBytes must be at least $minimumAssistantContextMaxBytes.',
      );
    }
  }

  final ProfileRepository profile;
  final PlacesRepository places;
  final TaskRemindersRepository reminders;
  final ReminderEventsRepository events;
  final CapturesRepository captures;
  final int maxBytes;
  final int placesLimit;
  final int activeRemindersLimit;
  final int recentEventsLimit;
  final int unclearCapturesLimit;

  @override
  Future<AssistantContext> build() async {
    final Profile? currentProfile = await profile.get();
    final List<Place> savedPlaces = await places.watchAll().first;
    final List<TaskReminder> active = await reminders
        .watchByStatus(TaskReminderStatus.active)
        .first;
    final List<ReminderEvent> recentActions = await events.recentActions(
      limit: recentEventsLimit,
    );
    final List<Capture> unclearCaptures =
        (await captures.watchByStatuses(<CaptureStatus>{
              CaptureStatus.failed,
            }).first)
            .where(_isUnclearCapture)
            .take(unclearCapturesLimit)
            .toList(growable: false);

    return _bounded(
      profile: currentProfile == null ? null : _profile(currentProfile),
      places: savedPlaces.take(placesLimit).map(_place).toList(growable: false),
      activeReminders: active
          .take(activeRemindersLimit)
          .map(_reminder)
          .toList(growable: false),
      recentReminderActions: recentActions.map(_event).toList(growable: false),
      recentUnclearCaptures: unclearCaptures
          .map(_capture)
          .toList(growable: false),
    );
  }

  AssistantContext _bounded({
    required Map<String, Object?>? profile,
    required List<Map<String, Object?>> places,
    required List<Map<String, Object?>> activeReminders,
    required List<Map<String, Object?>> recentReminderActions,
    required List<Map<String, Object?>> recentUnclearCaptures,
  }) {
    places = List<Map<String, Object?>>.of(places);
    activeReminders = List<Map<String, Object?>>.of(activeReminders);
    recentReminderActions = List<Map<String, Object?>>.of(
      recentReminderActions,
    );
    recentUnclearCaptures = List<Map<String, Object?>>.of(
      recentUnclearCaptures,
    );
    bool truncated = false;
    AssistantContext context() => AssistantContext(
      profile: profile,
      places: places,
      activeReminders: activeReminders,
      recentReminderActions: recentReminderActions,
      recentUnclearCaptures: recentUnclearCaptures,
      truncated: truncated,
      maxBytes: maxBytes,
    );

    while (context().encodedBytes > maxBytes &&
        (recentUnclearCaptures.isNotEmpty ||
            recentReminderActions.isNotEmpty ||
            activeReminders.isNotEmpty ||
            places.isNotEmpty ||
            profile != null)) {
      truncated = true;
      if (recentUnclearCaptures.isNotEmpty) {
        recentUnclearCaptures.removeLast();
      } else if (recentReminderActions.isNotEmpty) {
        recentReminderActions.removeLast();
      } else if (activeReminders.isNotEmpty) {
        activeReminders.removeLast();
      } else if (places.isNotEmpty) {
        places.removeLast();
      } else {
        profile = null;
      }
    }
    return context();
  }

  static bool _isUnclearCapture(Capture capture) {
    final String error = capture.error?.toLowerCase() ?? '';
    return error.contains('unclear') || error.contains('inaudible');
  }

  static Map<String, Object?> _profile(Profile profile) => <String, Object?>{
    'id': profile.id,
    'persona_response_language': profile.personaResponseLanguage.wire,
    'theme': profile.theme,
    'prefs': <String, Object?>{
      for (final MapEntry<String, Object?> entry in profile.prefs.entries)
        if (allowedExternalProfilePrefs.contains(entry.key) &&
            _isJsonScalar(entry.value))
          entry.key: entry.value,
    },
  };

  static Map<String, Object?> _place(Place place) => <String, Object?>{
    'id': place.id,
    'name': place.name,
    'radius_m': place.radiusM,
  };

  static Map<String, Object?> _reminder(TaskReminder reminder) =>
      <String, Object?>{
        'id': reminder.id,
        'title': reminder.title,
        'trigger_type': reminder.triggerType.wire,
        'scheduled_at': reminder.scheduledAt?.toIso8601String(),
        'place_id': reminder.placeId,
        'geofence_transition': reminder.geofenceTransition?.wire,
        'dwell_seconds': reminder.dwellSeconds,
      };

  static Map<String, Object?> _event(ReminderEvent event) => <String, Object?>{
    'id': event.id,
    'reminder_id': event.reminderId,
    'event_type': event.eventType.wire,
    'metadata': <String, Object?>{
      for (final MapEntry<String, Object?> entry in event.metadata.entries)
        if (allowedExternalReminderEventMetadata.contains(entry.key) &&
            _isJsonScalar(entry.value))
          entry.key: entry.value,
    },
    'occurred_at': event.occurredAt.toIso8601String(),
  };

  static Map<String, Object?> _capture(Capture capture) => <String, Object?>{
    'id': capture.id,
    'source': capture.source.wire,
    'error': capture.error,
    'captured_at': capture.capturedAt.toIso8601String(),
  };

  static bool _isJsonScalar(Object? value) =>
      value == null || value is String || value is num || value is bool;
}
