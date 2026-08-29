import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';
import 'package:sidekick/features/places/domain/place.dart';
import 'package:sidekick/features/reminders/application/reminder_creation_service.dart';
import 'package:sidekick/features/reminders/application/reminder_draft_service.dart';
import 'package:sidekick/features/reminders/application/reminder_scheduler.dart';
import 'package:sidekick/features/reminders/domain/reminder_event.dart';
import 'package:sidekick/features/reminders/domain/task_reminder.dart';

void main() {
  late DateTime now;
  late _FakeTaskRemindersRepository reminders;
  late _FakeReminderEventsRepository events;
  late _FakePlacesRepository places;
  late _FakeSchedulePlatform platform;
  late ReminderSchedulerService scheduler;

  setUp(() {
    now = DateTime.utc(2026, 8, 21, 10);
    reminders = _FakeTaskRemindersRepository(now);
    events = _FakeReminderEventsRepository(now);
    places = _FakePlacesRepository(now);
    platform = _FakeSchedulePlatform();
    scheduler = ReminderSchedulerService(
      reminders: reminders,
      events: events,
      places: places,
      platform: platform,
      clock: () => now,
    );
  });

  test(
    'time reminder schedules a notification through scheduler interface',
    () async {
      final TaskReminder reminder = _reminder(
        scheduledAt: DateTime.utc(2026, 8, 21, 12),
      );
      reminders.rows[reminder.id] = reminder;

      await scheduler.schedule(reminder);

      expect(platform.time.single.reminder.id, reminder.id);
    },
  );

  test('Done marks reminder done and logs reminder_actioned event', () async {
    final TaskReminder reminder = _reminder();
    reminders.rows[reminder.id] = reminder;

    await scheduler.handleAction(
      ReminderAction(
        reminderId: reminder.id,
        action: ReminderNotificationAction.done,
      ),
    );

    expect(reminders.rows[reminder.id]!.status, TaskReminderStatus.done);
    expect(platform.cancelled, contains(reminder.id));
    expect(events.rows.single.eventType, ReminderEventType.done);
  });

  test(
    'notification action payload dispatches through attached scheduler',
    () async {
      final TaskReminder reminder = _reminder();
      reminders.rows[reminder.id] = reminder;
      ReminderNotificationDispatcher.attach(scheduler);
      addTearDown(() => ReminderNotificationDispatcher.detach(scheduler));

      ReminderNotificationDispatcher.dispatchPayload(
        payload: jsonEncode(
          ReminderNotificationPayload(
            reminderId: reminder.id,
            action: ReminderNotificationAction.open,
          ).toJson(),
        ),
        actionId: ReminderNotificationAction.done.wire,
      );
      await Future<void>.delayed(Duration.zero);

      expect(reminders.rows[reminder.id]!.status, TaskReminderStatus.done);
      expect(events.rows.single.eventType, ReminderEventType.done);
    },
  );

  test('Later snoozes 2 hours and reschedules', () async {
    final TaskReminder reminder = _reminder();
    reminders.rows[reminder.id] = reminder;

    await scheduler.handleAction(
      ReminderAction(
        reminderId: reminder.id,
        action: ReminderNotificationAction.later,
      ),
    );

    final TaskReminder updated = reminders.rows[reminder.id]!;
    expect(updated.scheduledAt, DateTime.utc(2026, 8, 21, 12));
    expect(updated.triggerType, TaskReminderTriggerType.time);
    expect(platform.time.single.reminder.id, reminder.id);
    expect(events.rows.single.eventType, ReminderEventType.later);
  });

  test('Dismiss logs event without deleting reminder', () async {
    final TaskReminder reminder = _reminder();
    reminders.rows[reminder.id] = reminder;

    await scheduler.handleAction(
      ReminderAction(
        reminderId: reminder.id,
        action: ReminderNotificationAction.dismiss,
      ),
    );

    expect(reminders.rows[reminder.id]!.status, TaskReminderStatus.active);
    expect(events.rows.single.eventType, ReminderEventType.dismissed);
  });

  test('Wrong place logs event and stores correction signal', () async {
    final TaskReminder reminder = _reminder();
    reminders.rows[reminder.id] = reminder;
    String? editReminderId;
    void listener(String reminderId) {
      editReminderId = reminderId;
    }

    ReminderEditDispatcher.attach(listener);
    addTearDown(() => ReminderEditDispatcher.detach(listener));

    await scheduler.handleAction(
      ReminderAction(
        reminderId: reminder.id,
        action: ReminderNotificationAction.wrongPlace,
      ),
    );

    expect(events.rows.single.eventType, ReminderEventType.wrongPlace);
    expect(events.rows.single.metadata['correction'], 'wrong_place');
    expect(events.rows.single.metadata['edit_route'], contains(reminder.id));
    expect(editReminderId, reminder.id);
  });

  test(
    'geofence reminder registers expected place/radius/transition',
    () async {
      final Place place = places.add(radiusM: 200);
      final TaskReminder reminder = _reminder(
        triggerType: TaskReminderTriggerType.place,
        scheduledAt: null,
        placeId: place.id,
        transition: GeofenceTransition.exit,
        dwellSeconds: 90,
      );
      reminders.rows[reminder.id] = reminder;

      await scheduler.schedule(reminder);

      final ScheduledReminderRequest request = platform.geofences.single;
      expect(request.place!.id, place.id);
      expect(request.radiusM, 200);
      expect(request.dwellSeconds, 90);
      expect(request.reminder.geofenceTransition, GeofenceTransition.exit);
    },
  );

  test('dwell filter prevents immediate noisy firing', () async {
    final TaskReminder reminder = _reminder(
      triggerType: TaskReminderTriggerType.place,
      scheduledAt: null,
      placeId: places.add().id,
      transition: GeofenceTransition.enter,
      dwellSeconds: 60,
    );
    reminders.rows[reminder.id] = reminder;

    final bool first = await scheduler.handleGeofenceTrigger(
      ReminderGeofenceTrigger(
        reminderId: reminder.id,
        transition: GeofenceTransition.enter,
        arrivedAt: now,
      ),
    );
    final bool second = await scheduler.handleGeofenceTrigger(
      ReminderGeofenceTrigger(
        reminderId: reminder.id,
        transition: GeofenceTransition.enter,
        arrivedAt: now.add(const Duration(seconds: 61)),
      ),
    );

    expect(first, isFalse);
    expect(second, isTrue);
    expect(events.rows.single.eventType, ReminderEventType.fired);
  });

  test('resyncAll restores active reminders after restart', () async {
    reminders.rows['active'] = _reminder(id: 'active');
    reminders.rows['done'] = _reminder(
      id: 'done',
      status: TaskReminderStatus.done,
    );

    await scheduler.resyncAll();

    expect(platform.time.map((request) => request.reminder.id), <String>[
      'active',
    ]);
  });

  test('resync scheduling failure is not recorded as user feedback', () async {
    reminders.rows['active'] = _reminder(id: 'active');
    platform.failScheduling = true;

    await scheduler.resyncAll();

    expect(events.rows, isEmpty);
  });

  test('resyncAll drains native actions and ACKs after persistence', () async {
    final TaskReminder reminder = _reminder();
    reminders.rows[reminder.id] = reminder;
    platform.nativeActions.add(
      ReminderAction(
        reminderId: reminder.id,
        action: ReminderNotificationAction.done,
        metadata: const <String, Object?>{
          'native_action_id': 'native-1',
          'source': 'native_notification',
        },
      ),
    );

    await scheduler.resyncAll();

    expect(reminders.rows[reminder.id]!.status, TaskReminderStatus.done);
    expect(events.rows.single.eventType, ReminderEventType.done);
    expect(platform.ackedNativeActions, <String>['native-1']);
  });

  test('native action replay is idempotent by native_action_id', () async {
    final TaskReminder reminder = _reminder();
    reminders.rows[reminder.id] = reminder;
    platform.nativeActions.add(
      ReminderAction(
        reminderId: reminder.id,
        action: ReminderNotificationAction.later,
        metadata: const <String, Object?>{
          'native_action_id': 'native-later-1',
          'source': 'native_notification',
        },
      ),
    );

    await scheduler.resyncAll();
    final DateTime firstSnooze = reminders.rows[reminder.id]!.scheduledAt!;
    now = now.add(const Duration(hours: 1));
    await scheduler.resyncAll();

    expect(events.rows, hasLength(1));
    expect(events.rows.single.id, 'native-later-1');
    expect(reminders.rows[reminder.id]!.scheduledAt, firstSnooze);
    expect(platform.ackedNativeActions, <String>[
      'native-later-1',
      'native-later-1',
    ]);
  });

  test('auto-commit activation calls scheduler exactly once', () async {
    final _FakeCaptureRepository captures = _FakeCaptureRepository(now);
    final ReminderCreationService creation = ReminderCreationService(
      captures: captures,
      reminders: reminders,
      drafts: const HeuristicReminderDraftService(),
      clock: () => now,
      scheduler: scheduler,
    );
    await creation.submitText('Remind me to call Sam tomorrow');
    now = now.add(const Duration(seconds: 11));

    expect(await creation.activateDueAutoCommits(), 1);

    expect(platform.time, hasLength(1));
    expect(reminders.rows.values.single.status, TaskReminderStatus.active);
  });

  test('approved review draft schedules immediately', () async {
    final _FakeCaptureRepository captures = _FakeCaptureRepository(now);
    final ReminderCreationService creation = ReminderCreationService(
      captures: captures,
      reminders: reminders,
      drafts: const HeuristicReminderDraftService(),
      clock: () => now,
      scheduler: scheduler,
    );
    const ParsedReminderDraft draft = ParsedReminderDraft(
      title: 'Call Sam',
      confidence: 0.5,
      triggerType: TaskReminderTriggerType.time,
      scheduledAt: null,
      explanation: 'Needs review.',
    );

    await creation.approveReviewedDraft(
      draft,
      source: TaskReminderSource.typed,
      captureId: 'c1',
      title: 'Call Sam',
      scheduledAt: DateTime.utc(2026, 8, 21, 13),
    );

    expect(platform.time.single.reminder.title, 'Call Sam');
    expect(reminders.rows.values.single.status, TaskReminderStatus.active);
  });
}

TaskReminder _reminder({
  String id = 'r1',
  TaskReminderStatus status = TaskReminderStatus.active,
  TaskReminderTriggerType triggerType = TaskReminderTriggerType.time,
  DateTime? scheduledAt,
  String? placeId,
  GeofenceTransition? transition,
  int? dwellSeconds,
}) {
  final DateTime now = DateTime.utc(2026, 8, 21, 10);
  return TaskReminder(
    id: id,
    userId: 'u1',
    title: 'Call Sam',
    status: status,
    source: TaskReminderSource.typed,
    confidence: 0.9,
    triggerType: triggerType,
    scheduledAt: scheduledAt ?? DateTime.utc(2026, 8, 21, 11),
    placeId: placeId,
    geofenceTransition: transition,
    dwellSeconds: dwellSeconds,
    createdAt: now,
    updatedAt: now,
  );
}

class _FakeTaskRemindersRepository implements TaskRemindersRepository {
  _FakeTaskRemindersRepository(this.now);

  DateTime now;
  final Map<String, TaskReminder> rows = <String, TaskReminder>{};
  int _nextId = 0;

  @override
  Future<TaskReminder> create(TaskReminderDraft draft) async {
    final String id = 'r${++_nextId}';
    final TaskReminder reminder = TaskReminder(
      id: id,
      userId: 'u1',
      title: draft.title,
      details: draft.details,
      status: draft.status,
      source: draft.source,
      confidence: draft.confidence,
      triggerType: draft.triggerType,
      scheduledAt: draft.scheduledAt,
      placeId: draft.placeId,
      geofenceTransition: draft.geofenceTransition,
      dwellSeconds: draft.dwellSeconds,
      autoCommitDeadlineAt: draft.autoCommitDeadlineAt,
      captureId: draft.captureId,
      draftId: draft.draftId,
      aiExplanation: draft.aiExplanation,
      aiContext: draft.aiContext,
      createdAt: now,
      updatedAt: now,
    );
    rows[id] = reminder;
    return reminder;
  }

  @override
  Future<void> delete(String id) async {
    rows.remove(id);
  }

  @override
  Future<void> update(TaskReminder reminder) async {
    rows[reminder.id] = reminder;
  }

  @override
  Stream<List<TaskReminder>> watchAll() =>
      Stream<List<TaskReminder>>.value(rows.values.toList(growable: false));

  @override
  Stream<List<TaskReminder>> watchByStatus(TaskReminderStatus status) =>
      Stream<List<TaskReminder>>.value(
        rows.values
            .where((TaskReminder reminder) => reminder.status == status)
            .toList(growable: false),
      );
}

class _FakeReminderEventsRepository implements ReminderEventsRepository {
  _FakeReminderEventsRepository(this.now);

  DateTime now;
  final List<ReminderEvent> rows = <ReminderEvent>[];

  @override
  Future<ReminderEvent> append({
    required String reminderId,
    required ReminderEventType eventType,
    Map<String, Object?> metadata = const <String, Object?>{},
    String? id,
  }) async {
    final String eventId = id ?? 'e${rows.length + 1}';
    final ReminderEvent? existing = await findById(eventId);
    if (existing != null) return existing;
    final ReminderEvent event = ReminderEvent(
      id: eventId,
      userId: 'u1',
      reminderId: reminderId,
      eventType: eventType,
      metadata: metadata,
      occurredAt: now,
      createdAt: now,
      updatedAt: now,
    );
    rows.add(event);
    return event;
  }

  @override
  Stream<List<ReminderEvent>> watchForReminder(String reminderId) =>
      Stream<List<ReminderEvent>>.value(
        rows
            .where((ReminderEvent event) => event.reminderId == reminderId)
            .toList(growable: false),
      );

  @override
  Future<List<ReminderEvent>> recentActions({required int limit}) async => rows
      .where(
        (ReminderEvent event) => <ReminderEventType>{
          ReminderEventType.done,
          ReminderEventType.later,
          ReminderEventType.dismissed,
          ReminderEventType.wrongPlace,
          ReminderEventType.edited,
        }.contains(event.eventType),
      )
      .take(limit)
      .toList(growable: false);

  @override
  Future<ReminderEvent?> findById(String id) async {
    for (final ReminderEvent event in rows) {
      if (event.id == id) return event;
    }
    return null;
  }
}

class _FakePlacesRepository implements PlacesRepository {
  _FakePlacesRepository(this.now);

  DateTime now;
  final List<Place> rows = <Place>[];

  Place add({int radiusM = 150}) {
    final Place place = Place(
      id: 'p${rows.length + 1}',
      userId: 'u1',
      name: 'Home',
      lat: 30,
      lng: 31,
      radiusM: radiusM,
      createdAt: now,
      updatedAt: now,
    );
    rows.add(place);
    return place;
  }

  @override
  Future<Place> create({
    required String name,
    required double lat,
    required double lng,
    int radiusM = 150,
  }) async {
    final Place place = Place(
      id: 'p${rows.length + 1}',
      userId: 'u1',
      name: name,
      lat: lat,
      lng: lng,
      radiusM: radiusM,
      createdAt: now,
      updatedAt: now,
    );
    rows.add(place);
    return place;
  }

  @override
  Future<void> delete(String id) async {
    rows.removeWhere((Place place) => place.id == id);
  }

  @override
  Future<void> update(Place place) async {}

  @override
  Stream<List<Place>> watchAll() =>
      Stream<List<Place>>.value(rows.toList(growable: false));
}

class _FakeSchedulePlatform
    implements ReminderSchedulePlatform, NativeReminderActionJournal {
  final List<ScheduledReminderRequest> time = <ScheduledReminderRequest>[];
  final List<ScheduledReminderRequest> geofences = <ScheduledReminderRequest>[];
  final List<String> cancelled = <String>[];
  final List<ReminderAction> nativeActions = <ReminderAction>[];
  final List<String> ackedNativeActions = <String>[];
  bool failScheduling = false;

  @override
  Future<void> cancel(String id) async {
    cancelled.add(id);
  }

  @override
  Future<void> registerGeofence(ScheduledReminderRequest request) async {
    if (failScheduling) throw StateError('permission denied');
    geofences.add(request);
  }

  @override
  Future<void> scheduleTime(ScheduledReminderRequest request) async {
    if (failScheduling) throw StateError('permission denied');
    time.add(request);
  }

  @override
  Future<List<ReminderAction>> pendingNativeActions() async =>
      nativeActions.toList(growable: false);

  @override
  Future<void> ackNativeAction(String actionId) async {
    ackedNativeActions.add(actionId);
  }
}

class _FakeCaptureRepository implements CapturesRepository {
  _FakeCaptureRepository(this.now);

  DateTime now;
  final Map<String, Capture> rows = <String, Capture>{};

  @override
  Future<Capture> create({
    String? inputText,
    String? audioPath,
    DateTime? capturedAt,
    String source = 'typed',
  }) async {
    final Capture capture = Capture(
      id: 'c${rows.length + 1}',
      userId: 'u1',
      source: CaptureSource.fromWire(source),
      inputText: inputText,
      audioPath: audioPath,
      status: CaptureStatus.pending,
      capturedAt: capturedAt ?? now,
      createdAt: now,
      updatedAt: now,
    );
    rows[capture.id] = capture;
    return capture;
  }

  @override
  Future<void> delete(String id) async {
    rows.remove(id);
  }

  @override
  Future<List<Capture>> getByIds(List<String> ids) async =>
      ids.map((String id) => rows[id]).whereType<Capture>().toList();

  @override
  Future<void> update(Capture capture) async {
    rows[capture.id] = capture;
  }

  @override
  Stream<List<Capture>> watchAll() =>
      Stream<List<Capture>>.value(rows.values.toList(growable: false));

  @override
  Stream<List<Capture>> watchByStatuses(Set<CaptureStatus> statuses) =>
      Stream<List<Capture>>.value(
        rows.values
            .where((Capture capture) => statuses.contains(capture.status))
            .toList(growable: false),
      );
}
