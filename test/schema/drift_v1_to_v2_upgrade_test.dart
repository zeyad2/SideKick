import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/core/db/app_database.dart';

void main() {
  test('on-disk Drift v1 upgrades to decomposition v2 without data loss', () async {
    final Directory temp = await Directory.systemTemp.createTemp(
      'sidekick-drift-upgrade-',
    );
    addTearDown(() => temp.delete(recursive: true));
    final File file = File('${temp.path}/sidekick.sqlite');

    final AppDatabase seed = AppDatabase.forTesting(NativeDatabase(file));
    await seed.customStatement(
      "INSERT INTO captures (id, user_id, status) VALUES ('capture-1', 'u1', 'ready')",
    );
    await seed.customStatement(
      "INSERT INTO goals (id, user_id, title) VALUES ('goal-1', 'u1', 'Keep me')",
    );
    await seed.customStatement(
      'ALTER TABLE captures DROP COLUMN proposed_items',
    );
    await seed.customStatement(
      'ALTER TABLE captures DROP COLUMN dispositioned_item_ids',
    );
    await seed.customStatement(
      'ALTER TABLE captures DROP COLUMN auto_committed_at',
    );
    await seed.customStatement('ALTER TABLE goals DROP COLUMN capture_id');
    await seed.customStatement('PRAGMA user_version = 1');
    await seed.close();

    final AppDatabase upgraded = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(upgraded.close);
    final CaptureRow capture = await upgraded
        .select(upgraded.captures)
        .getSingle();
    final GoalRow goal = await upgraded.select(upgraded.goals).getSingle();

    expect(capture.id, 'capture-1');
    expect(capture.proposedItems, isNull);
    expect(capture.dispositionedItemIds, '[]');
    expect(capture.autoCommittedAt, isNull);
    expect(goal.title, 'Keep me');
    expect(goal.captureId, isNull);
  });
}
