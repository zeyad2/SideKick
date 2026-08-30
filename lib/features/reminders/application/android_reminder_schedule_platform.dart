import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sidekick/features/reminders/application/reminder_scheduler.dart';

@pragma('vm:entry-point')
void sidekickReminderBackgroundNotificationTap(NotificationResponse response) {
  final ReminderNotificationPayload? parsed = ReminderNotificationPayload.parse(
    payload: response.payload,
    actionId: response.actionId,
  );
  if (parsed != null) {
    unawaited(
      AndroidReminderSchedulePlatform.enqueueNativeAction(
        reminderId: parsed.reminderId,
        action: parsed.action,
      ),
    );
  }
}

class AndroidReminderSchedulePlatform
    implements
        ReminderSchedulePlatform,
        NativeReminderActionJournal,
        DeviceTimeZoneSource {
  AndroidReminderSchedulePlatform({
    FlutterLocalNotificationsPlugin? notifications,
    MethodChannel? channel,
  }) : _notifications = notifications ?? FlutterLocalNotificationsPlugin(),
       _channel = channel ?? _defaultChannel;

  static const String channelId = 'sidekick_reminders';
  static const String channelName = 'Task reminders';
  static const String category = 'sidekick_reminder_actions';
  static const MethodChannel _defaultChannel = MethodChannel(
    'com.sidekick/reminders',
  );

  final FlutterLocalNotificationsPlugin _notifications;
  final MethodChannel _channel;
  bool _initialized = false;
  bool _requestedFullScreenIntentPermission = false;

  @override
  Future<void> scheduleTime(ScheduledReminderRequest request) async {
    await _ensureInitialized();
    _requestFullScreenIntentPermissionOnce();
    final DateTime? scheduledAt = request.reminder.scheduledAt;
    if (scheduledAt == null) return;
    final int notificationId = await _nativeNotificationId(request.reminder.id);
    await _channel.invokeMethod<void>('scheduleTimeReminder', <String, Object?>{
      'id': request.reminder.id,
      'title': request.reminder.title,
      'details': request.reminder.details,
      'triggerAtMs': scheduledAt.toUtc().millisecondsSinceEpoch,
      'notificationId': notificationId,
    });
  }

  void _requestFullScreenIntentPermissionOnce() {
    if (_requestedFullScreenIntentPermission) return;
    _requestedFullScreenIntentPermission = true;
    final AndroidFlutterLocalNotificationsPlugin? android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    unawaited(() async {
      try {
        await android.requestFullScreenIntentPermission();
      } on PlatformException {
        // Scheduling still succeeds. Android will fall back to a heads-up
        // notification if the permission is unavailable or declined.
      }
    }());
  }

  @override
  Future<void> registerGeofence(ScheduledReminderRequest request) async {
    await _ensureInitialized();
    final place = request.place;
    if (place == null || request.reminder.geofenceTransition == null) return;
    try {
      await _channel.invokeMethod<void>('registerGeofence', <String, Object?>{
        'id': request.reminder.id,
        'title': request.reminder.title,
        'details': request.reminder.details,
        'lat': place.lat,
        'lng': place.lng,
        'radiusM': request.radiusM,
        'transition': request.reminder.geofenceTransition!.wire,
        'dwellSeconds': request.dwellSeconds,
      });
    } on PlatformException catch (error) {
      throw StateError('Geofence registration failed: ${error.message}');
    }
  }

  @override
  Future<void> cancel(String id) async {
    await _ensureInitialized();
    final int notificationId = await _nativeNotificationId(id);
    try {
      await _channel.invokeMethod<void>('cancelTimeReminder', <String, Object?>{
        'id': id,
        'notificationId': notificationId,
      });
      await _channel.invokeMethod<void>('cancelGeofence', <String, Object?>{
        'id': id,
      });
    } on PlatformException {
      return;
    }
  }

  @override
  Future<List<ReminderAction>> pendingNativeActions() async {
    await _ensureInitialized();
    try {
      final List<Object?> actions =
          await _channel.invokeMethod<List<Object?>>('drainNativeActions') ??
          const <Object?>[];
      return actions
          .whereType<Map>()
          .map((Map action) {
            final String id = action['id'] as String? ?? '';
            final String wire = action['action'] as String? ?? '';
            return ReminderAction(
              reminderId: id,
              action: ReminderNotificationAction.fromWire(wire),
              metadata: <String, Object?>{
                'source': action['source'] as String? ?? 'native_notification',
                if (action['recordedAtMs'] != null)
                  'recorded_at_ms': action['recordedAtMs'],
                if (action['rescheduleAtMs'] != null)
                  'reschedule_at_ms': action['rescheduleAtMs'],
                if (action['actionId'] != null)
                  'native_action_id': action['actionId'],
              },
            );
          })
          .where((ReminderAction action) => action.reminderId.isNotEmpty)
          .toList();
    } on PlatformException {
      return const <ReminderAction>[];
    }
  }

  @override
  Future<void> ackNativeAction(String actionId) async {
    await _ensureInitialized();
    try {
      await _channel.invokeMethod<void>('ackNativeAction', <String, Object?>{
        'actionId': actionId,
      });
    } on PlatformException {
      return;
    }
  }

  @override
  Future<String> currentTimeZoneName() async {
    try {
      final String? zone = await _channel.invokeMethod<String>(
        'currentTimeZoneName',
      );
      if (zone != null && zone.trim().isNotEmpty) return zone.trim();
    } on PlatformException {
      // Fall through to the only deterministic cross-platform fallback.
    }
    return 'UTC';
  }

  static Future<void> enqueueNativeAction({
    required String reminderId,
    required ReminderNotificationAction action,
  }) async {
    try {
      await _defaultChannel.invokeMethod<void>(
        'enqueueNativeAction',
        <String, Object?>{'id': reminderId, 'action': action.wire},
      );
    } on PlatformException {
      return;
    }
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _notifications.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: <DarwinNotificationCategory>[
            _darwinCategory(),
          ],
        ),
      ),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final ReminderNotificationPayload? parsed =
            ReminderNotificationPayload.parse(
              payload: response.payload,
              actionId: response.actionId,
            );
        if (parsed != null) {
          unawaited(
            AndroidReminderSchedulePlatform.enqueueNativeAction(
              reminderId: parsed.reminderId,
              action: parsed.action,
            ),
          );
        }
      },
      onDidReceiveBackgroundNotificationResponse:
          sidekickReminderBackgroundNotificationTap,
    );
    _initialized = true;
  }

  DarwinNotificationCategory _darwinCategory() => DarwinNotificationCategory(
    category,
    actions: <DarwinNotificationAction>[
      DarwinNotificationAction.plain('done', 'Done'),
      DarwinNotificationAction.plain('later', 'Later'),
      DarwinNotificationAction.plain('dismiss', 'Dismiss'),
      DarwinNotificationAction.plain('wrong_place', 'Wrong place'),
    ],
  );

  Future<int> _nativeNotificationId(String id) async {
    try {
      return await _channel.invokeMethod<int>(
            'managedNotificationId',
            <String, Object?>{'id': id},
          ) ??
          0;
    } on PlatformException {
      throw StateError('Native notification ID allocation failed.');
    }
  }
}
