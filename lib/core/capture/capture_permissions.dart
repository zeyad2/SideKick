import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sidekick/core/capture/native_capture_api.dart';

@immutable
class CapturePermissionSnapshot {
  const CapturePermissionSnapshot({
    required this.microphone,
    required this.notifications,
    required this.location,
    required this.backgroundLocation,
    required this.accessibility,
    required this.ignoringBatteryOptimizations,
  });

  final bool microphone;
  final bool notifications;
  final bool location;
  final bool backgroundLocation;
  final bool accessibility;
  final bool ignoringBatteryOptimizations;

  bool get ready => microphone && notifications && accessibility;
}

class CapturePermissions {
  CapturePermissions(this.nativeApi);
  final NativeCaptureApi nativeApi;

  bool get _android => !kIsWeb && Platform.isAndroid;

  Future<CapturePermissionSnapshot> status() async {
    if (!_android) {
      return const CapturePermissionSnapshot(
        microphone: false,
        notifications: false,
        location: false,
        backgroundLocation: false,
        accessibility: false,
        ignoringBatteryOptimizations: false,
      );
    }
    return CapturePermissionSnapshot(
      microphone: await Permission.microphone.isGranted,
      notifications:
          await FlutterForegroundTask.checkNotificationPermission() ==
          NotificationPermission.granted,
      location: await Permission.locationWhenInUse.isGranted,
      backgroundLocation: await Permission.locationAlways.isGranted,
      accessibility: await nativeApi.isAccessibilityEnabled(),
      ignoringBatteryOptimizations:
          await FlutterForegroundTask.isIgnoringBatteryOptimizations,
    );
  }

  Future<bool> requestMicrophone() async =>
      _android && await Permission.microphone.request().isGranted;

  Future<bool> requestNotifications() async =>
      _android &&
      await FlutterForegroundTask.requestNotificationPermission() ==
          NotificationPermission.granted;

  Future<bool> requestLocation() async =>
      _android && await Permission.locationWhenInUse.request().isGranted;

  Future<bool> requestBackgroundLocation() async =>
      _android && await Permission.locationAlways.request().isGranted;

  Future<void> openAccessibilitySettings() =>
      nativeApi.openAccessibilitySettings();

  Future<void> requestBatteryOptimizationExemption() async {
    if (_android &&
        !await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }
}

void initializeCaptureForegroundRuntime() {
  if (kIsWeb || !Platform.isAndroid) {
    return;
  }

  FlutterForegroundTask.initCommunicationPort();
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'sidekick_capture_runtime',
      channelName: 'Voice capture runtime',
      channelDescription: 'Keeps an active Sidekick voice capture alive.',
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      autoRunOnBoot: false,
      autoRunOnMyPackageReplaced: false,
      allowWakeLock: true,
    ),
  );
}
