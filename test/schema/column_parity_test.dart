import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/core/db/app_database.dart';

/// Integration: the drift mirror's column names must match the cloud
/// migrations EXACTLY (the LOCKED `0001` + `0002`, plus additive `0004`
/// column adds), plus only the two client-local sync columns (`dirty`,
/// `synced_at`) the cloud schema omits (R0).
///
/// Column names are parsed straight out of the migration SQL so the test tracks
/// the source of truth, not a hand-copied list.
void main() {
  /// Local-only columns the drift mirror adds on top of every cloud table.
  const Set<String> localOnly = <String>{'dirty', 'synced_at'};

  final String sql = <String>[
    File('supabase/migrations/0001_initial_schema.sql').readAsStringSync(),
    File('supabase/migrations/0002_events_log.sql').readAsStringSync(),
    // 0004 is additive `alter table ... add column` (capture decomposition).
    File(
      'supabase/migrations/0004_capture_decomposition.sql',
    ).readAsStringSync(),
  ].join('\n');

  final Map<String, Set<String>> cloudColumns = _parseColumns(sql);

  test('migration parsing found all 13 cloud tables', () {
    expect(cloudColumns.keys.toSet(), <String>{
      'profiles',
      'captures',
      'goals',
      'tasks',
      'notes',
      'habits',
      'habit_completions',
      'places',
      'focus_sessions',
      'vibe_checks',
      'reminders',
      'block_list',
      'events',
    });
  });

  test('every drift table mirrors its migration columns + dirty/synced_at', () {
    final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final Map<String, Set<String>> driftColumns = <String, Set<String>>{
      for (final TableInfo<Table, dynamic> t in db.allTables)
        t.actualTableName: t.$columns
            .map((GeneratedColumn<Object?> c) => c.name)
            .toSet(),
    };

    cloudColumns.forEach((String table, Set<String> cloud) {
      expect(
        driftColumns[table],
        equals(cloud.union(localOnly)),
        reason: 'drift table `$table` must match the migration exactly',
      );
    });
  });
}

/// Extracts `{table: {column, ...}}` from the migration SQL. A column line
/// starts with an identifier immediately followed by a SQL type keyword;
/// constraint/check lines never do, so they are naturally excluded.
Map<String, Set<String>> _parseColumns(String sql) {
  final RegExp tableStart = RegExp(r'create table public\.(\w+)\s*\(');
  final RegExp columnLine = RegExp(
    r'^\s*([a-z_][a-z0-9_]*)\s+'
    r'(uuid|text|timestamptz|jsonb|boolean|integer|smallint|double|date)\b',
  );

  final Map<String, Set<String>> result = <String, Set<String>>{};
  for (final RegExpMatch match in tableStart.allMatches(sql)) {
    final String table = match.group(1)!;
    final int bodyStart = match.end;
    final int bodyEnd = sql.indexOf('\n);', bodyStart);
    final String body = sql.substring(bodyStart, bodyEnd);

    final Set<String> columns = <String>{};
    for (final String line in body.split('\n')) {
      final RegExpMatch? col = columnLine.firstMatch(line);
      if (col != null) {
        columns.add(col.group(1)!);
      }
    }
    result[table] = columns;
  }

  // Additive column adds from later migrations (`alter table ... add column`),
  // which may span the table name and the column onto separate lines.
  final RegExp alterAdd = RegExp(
    r'alter table public\.(\w+)\s+add column\s+(?:if not exists\s+)?'
    r'([a-z_][a-z0-9_]*)\s+'
    r'(uuid|text|timestamptz|jsonb|boolean|integer|smallint|double|date)\b',
    caseSensitive: false,
  );
  for (final RegExpMatch match in alterAdd.allMatches(sql)) {
    (result[match.group(1)!] ??= <String>{}).add(match.group(2)!);
  }
  return result;
}
