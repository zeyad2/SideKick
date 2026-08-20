import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/core/db/app_database.dart';

void main() {
  const Set<String> localOnly = <String>{'dirty', 'synced_at'};
  final String sql = File(
    'supabase/migrations/0001_poc_baseline.sql',
  ).readAsStringSync();
  final Map<String, Set<String>> cloudColumns = _parseColumns(sql);

  test('fresh POC migration has only POC cloud tables', () {
    expect(cloudColumns.keys.toSet(), <String>{
      'profiles',
      'places',
      'captures',
      'task_reminders',
      'reminder_events',
      'conversations',
      'messages',
      'events',
    });
  });

  test('drift schema is POC version 1 and mirrors cloud columns', () {
    final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, 1);
    final Map<String, Set<String>> driftColumns = <String, Set<String>>{
      for (final TableInfo<Table, dynamic> t in db.allTables)
        if (t.actualTableName != 'sync_meta')
          t.actualTableName: t.$columns
              .map((GeneratedColumn<Object?> c) => c.name)
              .toSet(),
    };

    cloudColumns.forEach((String table, Set<String> cloud) {
      expect(
        driftColumns[table],
        equals(cloud.union(localOnly)),
        reason: 'drift table `$table` must match the POC baseline',
      );
    });
  });
}

Map<String, Set<String>> _parseColumns(String sql) {
  final RegExp tableStart = RegExp(r'create table public\.(\w+)\s*\(');
  final RegExp columnLine = RegExp(
    r'^\s*([a-z_][a-z0-9_]*)\s+'
    r'(uuid|text|timestamptz|jsonb|boolean|integer|smallint|double)\b',
  );

  final Map<String, Set<String>> result = <String, Set<String>>{};
  for (final RegExpMatch match in tableStart.allMatches(sql)) {
    final String table = match.group(1)!;
    final int bodyStart = match.end;
    final int bodyEnd = sql.indexOf('\n);', bodyStart);
    final String body = sql.substring(bodyStart, bodyEnd);

    result[table] = <String>{
      for (final String line in body.split('\n'))
        if (columnLine.firstMatch(line) case final RegExpMatch col)
          col.group(1)!,
    };
  }
  return result;
}
