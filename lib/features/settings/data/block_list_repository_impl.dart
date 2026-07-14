import 'package:drift/drift.dart';
import 'package:sidekick/core/data/local_first_repository.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/events/domain_event.dart';
import 'package:sidekick/features/settings/domain/block_list_entry.dart';

class BlockListRepositoryImpl extends LocalFirstRepository
    implements BlockListRepository {
  BlockListRepositoryImpl({
    required super.db,
    required super.emitter,
    required super.idGenerator,
    required super.userId,
    super.clock,
  });

  @override
  Stream<List<BlockListEntry>> watchAll() =>
      (db.select(db.blockList)
            ..where(
              (BlockList b) => b.userId.equals(userId) & b.deletedAt.isNull(),
            )
            ..orderBy(<OrderClauseGenerator<BlockList>>[
              (BlockList b) => OrderingTerm.desc(b.createdAt),
            ]))
          .watch()
          .map(
            (List<BlockListRow> rows) =>
                rows.map(_toDomain).toList(growable: false),
          );

  @override
  Future<BlockListEntry> create({
    required BlockPlatform platform,
    required String appIdentifier,
    String? appLabel,
  }) async {
    final DateTime timestamp = now();
    final String id = newId();
    await db
        .into(db.blockList)
        .insert(
          BlockListCompanion.insert(
            id: id,
            userId: userId,
            platform: platform.wire,
            appIdentifier: appIdentifier,
            appLabel: Value<String?>(appLabel),
            createdAt: Value<DateTime>(timestamp),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
    emitter.emitCreated(
      userId: userId,
      entityType: EntityTypes.blockListEntry,
      entityId: id,
    );
    final BlockListRow row = await (db.select(db.blockList)
          ..where((BlockList b) => b.id.equals(id)))
        .getSingle();
    return _toDomain(row);
  }

  @override
  Future<void> delete(String id) async {
    final DateTime timestamp = now();
    await (db.update(db.blockList)
          ..where((BlockList b) => b.id.equals(id) & b.userId.equals(userId)))
        .write(
          BlockListCompanion(
            deletedAt: Value<DateTime>(timestamp),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
  }

  BlockListEntry _toDomain(BlockListRow row) => BlockListEntry(
    id: row.id,
    userId: row.userId,
    platform: BlockPlatform.fromWire(row.platform),
    appIdentifier: row.appIdentifier,
    appLabel: row.appLabel,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}
