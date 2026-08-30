import 'package:meta/meta.dart';

@immutable
class ReminderSoundOption {
  const ReminderSoundOption({
    required this.id,
    required this.name,
    required this.downloaded,
    required this.selected,
  });

  factory ReminderSoundOption.fromMap(Map<Object?, Object?> map) =>
      ReminderSoundOption(
        id: map['id'] as String? ?? '',
        name: map['name'] as String? ?? '',
        downloaded: map['downloaded'] == true,
        selected: map['selected'] == true,
      );

  final String id;
  final String name;
  final bool downloaded;
  final bool selected;
}

@immutable
class ReminderSoundState {
  const ReminderSoundState({
    required this.selectedId,
    required this.catalog,
    this.localName,
    this.localAvailable = false,
  });

  const ReminderSoundState.systemDefault()
    : selectedId = 'system',
      catalog = const <ReminderSoundOption>[],
      localName = null,
      localAvailable = false;

  factory ReminderSoundState.fromMap(Map<Object?, Object?> map) {
    final List<Object?> rawCatalog = List<Object?>.from(
      map['catalog'] as List? ?? const <Object?>[],
    );
    return ReminderSoundState(
      selectedId: map['selectedId'] as String? ?? 'system',
      catalog: rawCatalog
          .whereType<Map>()
          .map(
            (Map<Object?, Object?> value) => ReminderSoundOption.fromMap(value),
          )
          .where((ReminderSoundOption value) => value.id.isNotEmpty)
          .toList(growable: false),
      localName: map['localName'] as String?,
      localAvailable: map['localAvailable'] == true,
    );
  }

  final String selectedId;
  final List<ReminderSoundOption> catalog;
  final String? localName;
  final bool localAvailable;

  bool get systemSelected => selectedId == 'system';
  bool get localSelected => selectedId == 'local';
}

abstract interface class ReminderSoundPlatform {
  Future<ReminderSoundState> state();
  Future<void> download(String id);
  Future<void> select(String id);
  Future<void> chooseLocalFile();
  Future<void> preview(String id);
  Future<void> delete(String id);
}
