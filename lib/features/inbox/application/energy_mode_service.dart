import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/events/event_emitter.dart';
import 'package:sidekick/features/profile/domain/profile.dart';

class EnergyModeService {
  EnergyModeService({
    required this.userId,
    required this.profiles,
    required this.emitter,
  });

  static const String preferenceKey = 'energy_mode';
  final String userId;
  final ProfileRepository profiles;
  final EventEmitter emitter;

  Future<void> setMode(EnergyMode mode) async {
    final Profile current = await profiles.ensureExists();
    final EnergyMode from =
        EnergyMode.fromWire(current.prefs[preferenceKey] as String?) ??
        EnergyMode.normal;
    if (from == mode) return;
    await profiles.mergePrefs(<String, Object?>{preferenceKey: mode.wire});
    emitter.emit(
      userId: userId,
      eventType: 'energy_mode_changed',
      metadata: <String, Object?>{
        'from': from.wire,
        'to': mode.wire,
        'auto': false,
      },
    );
  }
}
