import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/features/inbox/domain/proposed_item.dart';

enum AutoCommitNotificationAction { undo, edit }

class AutoCommitNotificationRequest {
  const AutoCommitNotificationRequest(this.captureId, this.action);
  final String captureId;
  final AutoCommitNotificationAction action;
}

class AutoCommitNotifications {
  AutoCommitNotifications({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const String undoAction = 'capture_auto_undo';
  static const String editAction = 'capture_auto_edit';
  static const String category = 'capture_auto_commit';
  final FlutterLocalNotificationsPlugin _plugin;
  final StreamController<AutoCommitNotificationRequest> _actions =
      StreamController<AutoCommitNotificationRequest>.broadcast();
  Future<void>? _initialization;
  bool _available = false;

  Stream<AutoCommitNotificationRequest> get actions => _actions.stream;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    try {
      await _plugin.initialize(
        settings: InitializationSettings(
          android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            notificationCategories: <DarwinNotificationCategory>[
              DarwinNotificationCategory(
                category,
                actions: <DarwinNotificationAction>[
                  DarwinNotificationAction.plain(
                    undoAction,
                    'Undo',
                    options: <DarwinNotificationActionOption>{
                      DarwinNotificationActionOption.foreground,
                    },
                  ),
                  DarwinNotificationAction.plain(
                    editAction,
                    'Edit',
                    options: <DarwinNotificationActionOption>{
                      DarwinNotificationActionOption.foreground,
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        onDidReceiveNotificationResponse: _handleResponse,
      );
      _available = true;
      final NotificationAppLaunchDetails? launch = await _plugin
          .getNotificationAppLaunchDetails();
      final NotificationResponse? response = launch?.notificationResponse;
      if (launch?.didNotificationLaunchApp == true && response != null) {
        _handleResponse(response);
      }
    } catch (error) {
      debugPrint('Auto-commit notifications unavailable: $error');
    }
  }

  Future<void> show(String captureId, List<ProposedItem> items) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    await initialize();
    if (!_available) return;
    final int count = items.length;
    await _plugin.show(
      id: captureId.hashCode & 0x7fffffff,
      title: '✓ Added $count ${count == 1 ? 'task' : 'tasks'}',
      body: items.map((item) => item.title).join(' · '),
      notificationDetails: NotificationDetails(
        android: const AndroidNotificationDetails(
          'capture_auto_commit',
          'Auto-added captures',
          channelDescription:
              'Grouped Undo and Edit actions for auto-added tasks.',
          importance: Importance.high,
          priority: Priority.high,
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction(
              undoAction,
              'Undo',
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              editAction,
              'Edit',
              showsUserInterface: true,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(categoryIdentifier: category),
      ),
      payload: captureId,
    );
  }

  void _handleResponse(NotificationResponse response) {
    final String? captureId = response.payload;
    if (captureId == null || captureId.isEmpty) return;
    final AutoCommitNotificationAction? action = switch (response.actionId) {
      undoAction => AutoCommitNotificationAction.undo,
      editAction || '' => AutoCommitNotificationAction.edit,
      _ => null,
    };
    if (action != null) {
      _actions.add(AutoCommitNotificationRequest(captureId, action));
    }
  }

  Future<void> dispose() => _actions.close();
}

class AutoCommitEditRequestController extends Notifier<String?> {
  @override
  String? build() => null;
  void request(String captureId) => state = captureId;
  void clear() => state = null;
}

final NotifierProvider<AutoCommitEditRequestController, String?>
autoCommitEditRequestProvider =
    NotifierProvider<AutoCommitEditRequestController, String?>(
      AutoCommitEditRequestController.new,
    );
