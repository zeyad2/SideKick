import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/features/settings/domain/reminder_sound.dart';

final Provider<ReminderSoundPlatform> reminderSoundPlatformProvider =
    Provider<ReminderSoundPlatform>(
      (Ref ref) => const AndroidReminderSoundPlatform(),
    );

class AndroidReminderSoundPlatform implements ReminderSoundPlatform {
  const AndroidReminderSoundPlatform({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.sidekick/reminders',
  );

  final MethodChannel _channel;

  @override
  Future<ReminderSoundState> state() async {
    try {
      final Map<Object?, Object?>? value = await _channel
          .invokeMethod<Map<Object?, Object?>>('getReminderSoundState');
      return value == null
          ? const ReminderSoundState.systemDefault()
          : ReminderSoundState.fromMap(value);
    } on MissingPluginException {
      return const ReminderSoundState.systemDefault();
    }
  }

  @override
  Future<void> download(String id) =>
      _invoke('downloadReminderSound', <String, Object?>{'id': id});

  @override
  Future<void> select(String id) =>
      _invoke('selectReminderSound', <String, Object?>{'id': id});

  @override
  Future<void> chooseLocalFile() => _invoke('pickLocalReminderSound');

  @override
  Future<void> preview(String id) =>
      _invoke('previewReminderSound', <String, Object?>{'id': id});

  @override
  Future<void> delete(String id) =>
      _invoke('deleteReminderSound', <String, Object?>{'id': id});

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException catch (error) {
      throw StateError(error.message ?? 'Reminder sound action failed.');
    }
  }
}
