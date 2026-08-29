import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final String migration = File(
    'supabase/migrations/0001_poc_baseline.sql',
  ).readAsStringSync();

  test('all POC tables enable RLS and have owner policies', () {
    const List<String> tables = <String>[
      'profiles',
      'places',
      'captures',
      'task_reminders',
      'reminder_events',
      'conversations',
      'messages',
      'events',
    ];

    for (final String table in tables) {
      expect(
        migration,
        contains('alter table public.$table'),
        reason: '$table must enable RLS',
      );
      if (table == 'events' || table == 'reminder_events') {
        expect(
          migration,
          contains('create policy ${table}_owner_read on public.$table'),
          reason: '$table must have an owner read policy',
        );
        expect(
          migration,
          contains('create policy ${table}_owner_insert on public.$table'),
          reason: '$table must have an owner insert policy',
        );
      } else {
        expect(
          migration,
          contains('create policy ${table}_owner on public.$table'),
          reason: '$table must have an owner policy',
        );
      }
    }
  });

  test('cloud schema omits local-only sync columns', () {
    expect(migration, isNot(contains('dirty')));
    expect(migration, isNot(contains('synced_at')));
  });

  test('server RLS tests target POC tables', () {
    final String rls = File(
      'supabase/tests/10_rls_isolation.sql',
    ).readAsStringSync();
    expect(rls, contains('public.task_reminders'));
    expect(rls, contains('reminder_events'));
    expect(rls, contains('conversations'));
    expect(rls, contains('messages'));
    expect(rls, isNot(contains('public.tasks')));
    expect(rls, isNot(contains('public.habits')));
  });

  test('POC baseline includes server LWW guard for normal sync tables', () {
    expect(
      migration,
      contains('create or replace function public.sync_lww_guard()'),
    );
    for (final String table in <String>[
      'profiles',
      'places',
      'captures',
      'task_reminders',
      'conversations',
      'messages',
    ]) {
      expect(migration, contains('on public.$table'));
    }
    expect(migration, contains('old.updated_at > new.updated_at'));
  });
}
