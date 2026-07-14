import 'package:meta/meta.dart';
import 'package:sidekick/core/domain/enums.dart';

/// One app blocked during focus sessions. `appIdentifier` holds an Android
/// package name OR an iOS opaque token, disambiguated by [platform].
@immutable
class BlockListEntry {
  const BlockListEntry({
    required this.id,
    required this.userId,
    required this.platform,
    required this.appIdentifier,
    required this.createdAt,
    required this.updatedAt,
    this.appLabel,
  });

  final String id;
  final String userId;
  final BlockPlatform platform;
  final String appIdentifier;
  final String? appLabel;
  final DateTime createdAt;
  final DateTime updatedAt;
}

abstract interface class BlockListRepository {
  Stream<List<BlockListEntry>> watchAll();
  Future<BlockListEntry> create({
    required BlockPlatform platform,
    required String appIdentifier,
    String? appLabel,
  });
  Future<void> delete(String id);
}
