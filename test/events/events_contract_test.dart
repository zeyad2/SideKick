import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/core/data/id_generator.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/events/domain_event.dart';
import 'package:sidekick/core/events/events_repository.dart';

void main() {
  test('append writes an immutable, dirty event row (D9)', () async {
    final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
    final DriftEventsRepository events = DriftEventsRepository(db);

    final DateTime when = DateTime.utc(2026, 7, 12, 8);
    await events.append(
      DomainEvent(
        id: IdGenerator().v4(),
        userId: 'u1',
        eventType: 'energy_mode_changed',
        metadata: <String, Object?>{'from': 'normal', 'to': 'low'},
        occurredAt: when,
      ),
    );

    final EventRow row = await db.select(db.events).getSingle();
    expect(row.eventType, 'energy_mode_changed');
    expect(row.dirty, isTrue);
    // Immutable rows: updated_at == occurred_at (0002 contract).
    expect(row.updatedAt, when);

    final restored = await events.getSince(DateTime.utc(2000));
    expect(restored.single.metadata['to'], 'low');

    await db.close();
  });

  test('no events READ surface exists in lib (write-only groundwork)', () {
    // `getSince` is the only read, and it is TEST-ONLY: it must not be
    // referenced by any production code outside the events repository itself.
    final Directory lib = Directory('lib');
    final Iterable<File> dartFiles = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'));

    final List<String> offenders = <String>[];
    for (final File file in dartFiles) {
      final String path = file.path.replaceAll(r'\', '/');
      if (path.endsWith('core/events/events_repository.dart')) {
        continue;
      }
      if (file.readAsStringSync().contains('.getSince(')) {
        offenders.add(path);
      }
    }
    expect(offenders, isEmpty, reason: 'events must stay write-only in lib/');
  });
}
