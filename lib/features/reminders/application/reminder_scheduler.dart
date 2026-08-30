import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/features/places/domain/place.dart';
import 'package:sidekick/features/reminders/domain/reminder_event.dart';
import 'package:sidekick/features/reminders/domain/task_reminder.dart';

const int defaultGeofenceRadiusM = 150;
const int defaultDwellSeconds = 60;
const Duration defaultLaterSnooze = Duration(hours: 2);

enum ReminderNotificationAction {
  done('done'),
  later('later'),
  reschedule('reschedule'),
  dismiss('dismiss'),
  wrongPlace('wrong_place'),
  open('open');

  const ReminderNotificationAction(this.wire);
  final String wire;

  static ReminderNotificationAction fromWire(String? wire) {
    for (final ReminderNotificationAction value in values) {
      if (value.wire == wire) return value;
    }
    return ReminderNotificationAction.open;
  }
}

@immutable
class ReminderAction {
  const ReminderAction({
    required this.reminderId,
    required this.action,
    this.metadata = const <String, Object?>{},
  });

  final String reminderId;
  final ReminderNotificationAction action;
  final Map<String, Object?> metadata;
}

class ReminderNotificationPayload {
  const ReminderNotificationPayload({
    required this.reminderId,
    required this.action,
  });

  final String reminderId;
  final ReminderNotificationAction action;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': reminderId,
    'action': action.wire,
  };

  static ReminderNotificationPayload? parse({
    required String? payload,
    String? actionId,
  }) {
    if (payload == null || payload.isEmpty) return null;
    final Object? decoded = jsonDecode(payload);
    if (decoded is! Map) return null;
    final Object? id = decoded['id'];
    if (id is! String || id.isEmpty) return null;
    final Object? payloadAction = decoded['action'];
    return ReminderNotificationPayload(
      reminderId: id,
      action: ReminderNotificationAction.fromWire(
        actionId ?? (payloadAction as String?),
      ),
    );
  }
}

class ReminderNotificationDispatcher {
  ReminderNotificationDispatcher._();

  static ReminderScheduler? _scheduler;
  static final List<ReminderAction> _pending = <ReminderAction>[];

  static void attach(ReminderScheduler scheduler) {
    _scheduler = scheduler;
    if (_pending.isEmpty) return;
    final List<ReminderAction> pending = List<ReminderAction>.of(_pending);
    _pending.clear();
    for (final ReminderAction action in pending) {
      unawaited(scheduler.handleAction(action));
    }
  }

  static void detach(ReminderScheduler scheduler) {
    if (identical(_scheduler, scheduler)) {
      _scheduler = null;
    }
  }

  static void dispatch(ReminderAction action) {
    final ReminderScheduler? scheduler = _scheduler;
    if (scheduler == null) {
      _pending.add(action);
      return;
    }
    unawaited(scheduler.handleAction(action));
  }

  static void dispatchPayload({required String? payload, String? actionId}) {
    final ReminderNotificationPayload? parsed =
        ReminderNotificationPayload.parse(payload: payload, actionId: actionId);
    if (parsed == null) return;
    final Map<String, Object?> metadata = <String, Object?>{
      'source': 'notification',
    };
    if (actionId != null) {
      metadata['action_id'] = actionId;
    }
    dispatch(
      ReminderAction(
        reminderId: parsed.reminderId,
        action: parsed.action,
        metadata: metadata,
      ),
    );
  }
}

class ReminderEditDispatcher {
  ReminderEditDispatcher._();

  static String? _pendingReminderId;
  static void Function(String reminderId)? _listener;

  static void attach(void Function(String reminderId) listener) {
    _listener = listener;
    final String? pending = _pendingReminderId;
    if (pending == null) return;
    _pendingReminderId = null;
    listener(pending);
  }

  static void detach(void Function(String reminderId) listener) {
    if (identical(_listener, listener)) {
      _listener = null;
    }
  }

  static void request(String reminderId) {
    final void Function(String reminderId)? listener = _listener;
    if (listener == null) {
      _pendingReminderId = reminderId;
      return;
    }
    listener(reminderId);
  }
}

@immutable
class ReminderGeofenceTrigger {
  const ReminderGeofenceTrigger({
    required this.reminderId,
    required this.transition,
    required this.arrivedAt,
  });

  final String reminderId;
  final GeofenceTransition transition;
  final DateTime arrivedAt;
}

@immutable
class ScheduledReminderRequest {
  const ScheduledReminderRequest({
    required this.reminder,
    this.place,
    this.radiusM = defaultGeofenceRadiusM,
    this.dwellSeconds = defaultDwellSeconds,
  });

  final TaskReminder reminder;
  final Place? place;
  final int radiusM;
  final int dwellSeconds;
}

abstract interface class ReminderScheduler {
  Future<void> schedule(TaskReminder reminder);
  Future<void> cancel(String id);
  Future<int> activateDueAutoCommits();
  Future<void> resyncAll();
  Future<void> handleAction(ReminderAction action);
}

abstract interface class ReminderSchedulePlatform {
  Future<void> scheduleTime(ScheduledReminderRequest request);
  Future<void> registerGeofence(ScheduledReminderRequest request);
  Future<void> cancel(String id);
}

abstract interface class NativeReminderActionJournal {
  Future<List<ReminderAction>> pendingNativeActions();
  Future<void> ackNativeAction(String actionId);
}

abstract interface class DeviceTimeZoneSource {
  Future<String> currentTimeZoneName();
}

class ReminderSchedulerService implements ReminderScheduler {
  ReminderSchedulerService({
    required this.reminders,
    required this.events,
    required this.places,
    required this.platform,
    required this.clock,
    this.atomically,
    this.laterSnooze = defaultLaterSnooze,
  });

  final TaskRemindersRepository reminders;
  final ReminderEventsRepository events;
  final PlacesRepository places;
  final ReminderSchedulePlatform platform;
  final DateTime Function() clock;
  final Future<T> Function<T>(Future<T> Function() action)? atomically;
  final Duration laterSnooze;

  final Map<String, DateTime> _pendingDwellStarts = <String, DateTime>{};

  @override
  Future<void> schedule(TaskReminder reminder) async {
    if (reminder.status != TaskReminderStatus.active &&
        reminder.status != TaskReminderStatus.pendingAutoCommit) {
      await cancel(reminder.id);
      return;
    }
    switch (reminder.triggerType) {
      case TaskReminderTriggerType.time:
        if (reminder.scheduledAt == null) return;
        await platform.scheduleTime(
          ScheduledReminderRequest(reminder: reminder),
        );
      case TaskReminderTriggerType.place:
        final Place? place = await _placeFor(reminder.placeId);
        if (place == null || reminder.geofenceTransition == null) return;
        await platform.registerGeofence(
          ScheduledReminderRequest(
            reminder: reminder,
            place: place,
            radiusM: place.radiusM <= 0
                ? defaultGeofenceRadiusM
                : place.radiusM,
            dwellSeconds: reminder.dwellSeconds ?? defaultDwellSeconds,
          ),
        );
    }
  }

  @override
  Future<void> cancel(String id) => platform.cancel(id);

  @override
  Future<int> activateDueAutoCommits() async {
    final DateTime now = clock();
    final List<TaskReminder> pending = await reminders
        .watchByStatus(TaskReminderStatus.pendingAutoCommit)
        .first;
    int activated = 0;
    for (final TaskReminder reminder in pending) {
      final DateTime? deadline = reminder.autoCommitDeadlineAt;
      if (deadline == null || deadline.isAfter(now)) continue;
      final TaskReminder active = TaskReminder(
        id: reminder.id,
        userId: reminder.userId,
        title: reminder.title,
        details: reminder.details,
        status: TaskReminderStatus.active,
        source: reminder.source,
        confidence: reminder.confidence,
        triggerType: reminder.triggerType,
        scheduledAt: reminder.scheduledAt,
        placeId: reminder.placeId,
        geofenceTransition: reminder.geofenceTransition,
        dwellSeconds: reminder.dwellSeconds,
        captureId: reminder.captureId,
        draftId: reminder.draftId,
        aiExplanation: reminder.aiExplanation,
        aiContext: reminder.aiContext,
        createdAt: reminder.createdAt,
        updatedAt: reminder.updatedAt,
      );
      await _runAtomic(() async {
        await reminders.update(active);
        await _append(
          active.id,
          ReminderEventType.activated,
          const <String, Object?>{'source': 'auto_commit_deadline'},
        );
      });
      try {
        await schedule(active);
      } catch (_) {
        // The row is active and remains eligible for the next resync even if
        // the current platform registration is temporarily unavailable.
      }
      activated++;
    }
    return activated;
  }

  @override
  Future<void> resyncAll() async {
    await activateDueAutoCommits();
    final List<TaskReminder> active = await reminders
        .watchByStatus(TaskReminderStatus.active)
        .first;
    for (final TaskReminder reminder in active) {
      try {
        await schedule(reminder);
      } catch (_) {
        // Permission/runtime failures are operational state, not user
        // feedback. Settings exposes permission state; never poison the
        // correction loop with a fake Dismiss action.
      }
    }
    if (platform is NativeReminderActionJournal) {
      final NativeReminderActionJournal journal =
          platform as NativeReminderActionJournal;
      final List<ReminderAction> actions = await journal.pendingNativeActions();
      for (final ReminderAction action in actions) {
        await handleAction(action);
      }
    }
  }

  @override
  Future<void> handleAction(ReminderAction action) async {
    final TaskReminder? reminder = await _findReminder(action.reminderId);
    if (reminder == null) return;
    final String? nativeActionId =
        action.metadata['native_action_id'] as String?;
    final NativeReminderActionJournal? journal =
        platform is NativeReminderActionJournal
        ? platform as NativeReminderActionJournal
        : null;
    if (nativeActionId != null &&
        await events.findByNativeActionId(nativeActionId) != null) {
      await journal?.ackNativeAction(nativeActionId);
      return;
    }
    switch (action.action) {
      case ReminderNotificationAction.done:
        await _runAtomic(() async {
          await reminders.update(
            reminder.copyWith(status: TaskReminderStatus.done),
          );
          await _append(reminder.id, ReminderEventType.done, action.metadata);
        });
        await cancel(reminder.id);
      case ReminderNotificationAction.later:
        final TaskReminder snoozed = TaskReminder(
          id: reminder.id,
          userId: reminder.userId,
          title: reminder.title,
          details: reminder.details,
          status: TaskReminderStatus.active,
          source: reminder.source,
          confidence: reminder.confidence,
          triggerType: TaskReminderTriggerType.time,
          scheduledAt: clock().add(laterSnooze),
          captureId: reminder.captureId,
          draftId: reminder.draftId,
          aiExplanation: reminder.aiExplanation,
          aiContext: reminder.aiContext,
          createdAt: reminder.createdAt,
          updatedAt: reminder.updatedAt,
        );
        await _runAtomic(() async {
          await reminders.update(snoozed);
          await _append(reminder.id, ReminderEventType.later, <String, Object?>{
            ...action.metadata,
            'snooze_seconds': laterSnooze.inSeconds,
          });
        });
        await schedule(snoozed);
      case ReminderNotificationAction.reschedule:
        final Object? rawTimestamp = action.metadata['reschedule_at_ms'];
        if (rawTimestamp is! int) return;
        final TaskReminder rescheduled = TaskReminder(
          id: reminder.id,
          userId: reminder.userId,
          title: reminder.title,
          details: reminder.details,
          status: TaskReminderStatus.active,
          source: reminder.source,
          confidence: reminder.confidence,
          triggerType: TaskReminderTriggerType.time,
          scheduledAt: DateTime.fromMillisecondsSinceEpoch(
            rawTimestamp,
            isUtc: true,
          ),
          captureId: reminder.captureId,
          draftId: reminder.draftId,
          aiExplanation: reminder.aiExplanation,
          aiContext: reminder.aiContext,
          createdAt: reminder.createdAt,
          updatedAt: reminder.updatedAt,
        );
        await _runAtomic(() async {
          await reminders.update(rescheduled);
          await _append(reminder.id, ReminderEventType.later, <String, Object?>{
            ...action.metadata,
            'rescheduled_at': rescheduled.scheduledAt!.toIso8601String(),
          });
        });
        await schedule(rescheduled);
      case ReminderNotificationAction.dismiss:
        await _runAtomic(() async {
          await reminders.update(
            reminder.copyWith(status: TaskReminderStatus.dismissed),
          );
          await _append(
            reminder.id,
            ReminderEventType.dismissed,
            action.metadata,
          );
        });
        await cancel(reminder.id);
      case ReminderNotificationAction.wrongPlace:
        await _runAtomic(() async {
          await _append(
            reminder.id,
            ReminderEventType.wrongPlace,
            <String, Object?>{
              ...action.metadata,
              'correction': 'wrong_place',
              if (reminder.placeId != null) 'place_id': reminder.placeId,
              'trigger_type': reminder.triggerType.wire,
              'open_edit': true,
              'edit_route': '/capture?editReminderId=${reminder.id}',
            },
          );
        });
        ReminderEditDispatcher.request(reminder.id);
      case ReminderNotificationAction.open:
        await _runAtomic(() async {
          await _append(reminder.id, ReminderEventType.fired, action.metadata);
        });
    }
    if (nativeActionId != null && journal != null) {
      await journal.ackNativeAction(nativeActionId);
    }
  }

  Future<bool> handleGeofenceTrigger(ReminderGeofenceTrigger trigger) async {
    final TaskReminder? reminder = await _findReminder(trigger.reminderId);
    if (reminder == null ||
        reminder.status != TaskReminderStatus.active ||
        reminder.geofenceTransition != trigger.transition) {
      return false;
    }
    final int dwellSeconds = reminder.dwellSeconds ?? defaultDwellSeconds;
    final DateTime? startedAt = _pendingDwellStarts[reminder.id];
    if (startedAt == null) {
      _pendingDwellStarts[reminder.id] = trigger.arrivedAt;
      return dwellSeconds <= 0;
    }
    final bool ready =
        trigger.arrivedAt.difference(startedAt).inSeconds >= dwellSeconds;
    if (ready) {
      _pendingDwellStarts.remove(reminder.id);
      await _append(reminder.id, ReminderEventType.fired, <String, Object?>{
        'transition': trigger.transition.wire,
        'dwell_seconds': dwellSeconds,
      });
    }
    return ready;
  }

  Future<Place?> _placeFor(String? id) async {
    if (id == null) return null;
    final List<Place> rows = await places.watchAll().first;
    for (final Place place in rows) {
      if (place.id == id) return place;
    }
    return null;
  }

  Future<TaskReminder?> _findReminder(String id) async {
    final List<TaskReminder> rows = await reminders.watchAll().first;
    for (final TaskReminder reminder in rows) {
      if (reminder.id == id) return reminder;
    }
    return null;
  }

  Future<void> _append(
    String reminderId,
    ReminderEventType eventType,
    Map<String, Object?> metadata, {
    String? id,
  }) async {
    await events.append(
      reminderId: reminderId,
      eventType: eventType,
      metadata: metadata,
      id: id,
    );
  }

  Future<T> _runAtomic<T>(Future<T> Function() action) {
    final tx = atomically;
    if (tx == null) return action();
    return tx<T>(action);
  }
}
