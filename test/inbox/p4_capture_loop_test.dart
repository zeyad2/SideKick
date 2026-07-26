import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/core/audio/pending_audio_queue.dart';
import 'package:sidekick/core/capture/capture_contract.dart';
import 'package:sidekick/core/capture/capture_ingestion_barrier.dart';
import 'package:sidekick/core/capture/native_capture_api.dart';
import 'package:sidekick/core/data/id_generator.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/events/domain_event.dart';
import 'package:sidekick/core/events/event_emitter.dart';
import 'package:sidekick/core/events/events_repository.dart';
import 'package:sidekick/core/sync/connectivity_service.dart';
import 'package:sidekick/features/goals/data/goals_repository_impl.dart';
import 'package:sidekick/features/habits/data/habits_repository_impl.dart';
import 'package:sidekick/features/inbox/application/capture_processing_service.dart';
import 'package:sidekick/features/inbox/application/capture_triage_service.dart';
import 'package:sidekick/features/inbox/application/energy_mode_service.dart';
import 'package:sidekick/features/inbox/data/captures_repository_impl.dart';
import 'package:sidekick/features/inbox/data/gemini_client.dart';
import 'package:sidekick/features/inbox/domain/auto_commit.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';
import 'package:sidekick/features/inbox/domain/capture_analysis.dart';
import 'package:sidekick/features/inbox/domain/proposed_item.dart';
import 'package:sidekick/features/notes/data/notes_repository_impl.dart';
import 'package:sidekick/features/notes/domain/note.dart';
import 'package:sidekick/features/profile/data/profile_repository_impl.dart';
import 'package:sidekick/features/tasks/data/tasks_repository_impl.dart';
import 'package:sidekick/features/tasks/domain/task.dart';

void main() {
  group('Gemini client fixtures', () {
    test(
      'fixture audio returns strict parsed JSON and strips fences',
      () async {
        final Directory temp = await Directory.systemTemp.createTemp(
          'sidekick-p4-gemini-',
        );
        addTearDown(() => temp.delete(recursive: true));
        final File audio = File('${temp.path}/fixture.aac')
          ..writeAsBytesSync(<int>[1, 2, 3, 4], flush: true);
        final _FixtureTransport transport = _FixtureTransport(_validEnvelope());
        final GeminiFlashClient client = GeminiFlashClient(
          apiKey: 'fixture-key',
          model: 'fixture-model',
          transport: transport,
          delay: (_) async {},
        );

        final analysis = await client.analyzeCaptureAudio(audio);

        expect(analysis.items, hasLength(1));
        expect(analysis.items.single.kind, ResultingType.task);
        expect(analysis.items.single.title, 'Call the dentist');
        expect(analysis.items.single.confidence, DraftConfidence.high);
        expect(analysis.rawTranscript, contains('el dentist'));
        final body = transport.lastBody!;
        final contents = body['contents']! as List<Object?>;
        final parts =
            (contents.single! as Map<String, Object?>)['parts']!
                as List<Object?>;
        final inline =
            (parts.last! as Map<String, Object?>)['inlineData']!
                as Map<String, Object?>;
        expect(inline['mimeType'], 'audio/aac');
        expect(inline['data'], 'AQIDBA==');
      },
    );

    test('malformed Gemini fixture becomes a failed, retryable row', () async {
      final _P4Harness harness = await _P4Harness.openMemory();
      addTearDown(harness.close);
      final PendingAudio queued = await harness.queue.enqueueBytes(<int>[
        7,
        8,
        9,
      ]);
      final Capture capture = await harness.captures.create(
        audioPath: queued.file.path,
        source: 'trigger',
      );
      final GeminiFlashClient client = GeminiFlashClient(
        apiKey: 'fixture-key',
        model: 'fixture-model',
        maxAttempts: 1,
        transport: _FixtureTransport(_malformedEnvelope()),
      );
      final CaptureIngestionBarrier barrier = CaptureIngestionBarrier();
      final CaptureProcessingService processing = CaptureProcessingService(
        captures: harness.captures,
        gemini: client,
        connectivity: _OfflineConnectivity(),
        barrier: barrier,
        triage: _triageFor(harness, barrier),
        idGenerator: IdGenerator(),
        baseRetryDelay: const Duration(days: 1),
      );
      addTearDown(processing.dispose);

      await processing.processById(capture.id);

      final Capture after = (await harness.captures.getByIds(<String>[
        capture.id,
      ])).single;
      expect(after.status, CaptureStatus.failed);
      expect(
        queued.file.existsSync(),
        isTrue,
        reason: 'malformed response never drains audio',
      );
    });

    test('nested draft format errors use the Gemini format retry', () async {
      final Directory temp = await Directory.systemTemp.createTemp(
        'sidekick-p4-nested-retry-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final File audio = File('${temp.path}/fixture.aac')
        ..writeAsBytesSync(<int>[1], flush: true);
      final _SequenceTransport transport =
          _SequenceTransport(<Map<String, Object?>>[
            _envelopeWithText(
              '{"raw_transcript":"x","items":[{"kind":"task","title":"x",'
              '"confidence":"high","schedule":{"time":"99:00"}}]}',
            ),
            _validEnvelope(),
          ]);
      final GeminiFlashClient client = GeminiFlashClient(
        apiKey: 'fixture-key',
        model: 'fixture-model',
        maxAttempts: 2,
        transport: transport,
        delay: (_) async {},
      );

      final CaptureAnalysis analysis = await client.analyzeCaptureAudio(audio);

      expect(transport.calls, 2);
      expect(analysis.items.single.title, 'Call the dentist');
    });

    test('unknown high-confidence kind is rejected, never coerced to task', () {
      expect(
        () => CaptureAnalysis.parse(
          '{"raw_transcript":"x","items":[{"kind":"unknown",'
          '"title":"wrong","confidence":"high"}]}',
        ),
        throwsA(isA<CaptureAnalysisFormatException>()),
      );
    });

    test('malformed envelope uses the configured immediate retry', () async {
      final Directory temp = await Directory.systemTemp.createTemp(
        'sidekick-p4-envelope-retry-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final File audio = File('${temp.path}/fixture.aac')
        ..writeAsBytesSync(<int>[1], flush: true);
      final _SequenceTransport transport = _SequenceTransport(
        <Map<String, Object?>>[
          <String, Object?>{'candidates': <Object?>[]},
          _validEnvelope(),
        ],
      );
      final GeminiFlashClient client = GeminiFlashClient(
        apiKey: 'fixture-key',
        model: 'fixture-model',
        maxAttempts: 2,
        transport: transport,
        delay: (_) async {},
      );

      await client.analyzeCaptureAudio(audio);

      expect(transport.calls, 2);
    });

    test('raw transcript survives parsing verbatim', () {
      final CaptureAnalysis analysis = CaptureAnalysis.parse(
        '{"raw_transcript":"  exact words  ","items":[]}',
      );
      expect(analysis.rawTranscript, '  exact words  ');
    });
  });

  test('API failure leaves the capture and audio queued for retry', () async {
    final _P4Harness harness = await _P4Harness.openMemory();
    addTearDown(harness.close);
    final PendingAudio queued = await harness.queue.enqueueBytes(<int>[
      9,
      8,
      7,
    ]);
    final Capture capture = await harness.captures.create(
      audioPath: queued.file.path,
      source: 'fab',
    );
    final CaptureIngestionBarrier barrier = CaptureIngestionBarrier();
    final CaptureProcessingService processing = CaptureProcessingService(
      captures: harness.captures,
      gemini: _FailingGemini(),
      connectivity: _OfflineConnectivity(),
      barrier: barrier,
      triage: _triageFor(harness, barrier),
      idGenerator: IdGenerator(),
      baseRetryDelay: const Duration(days: 1),
    );
    addTearDown(processing.dispose);

    await processing.processById(capture.id);

    final Capture after = (await harness.captures.getByIds(<String>[
      capture.id,
    ])).single;
    expect(after.status, CaptureStatus.failed);
    expect((await harness.queue.pending()).single.file.path, queued.file.path);
  });

  test('triage writes the typed P2 repository and survives restart', () async {
    final Directory temp = await Directory.systemTemp.createTemp(
      'sidekick-p4-restart-',
    );
    addTearDown(() => temp.delete(recursive: true));
    final File dbFile = File('${temp.path}/sidekick.sqlite');
    final DirectoryPendingAudioQueue queue = DirectoryPendingAudioQueue(
      baseDir: temp,
    );
    final PendingAudio audio = await queue.enqueueBytes(<int>[1, 3, 3, 7]);
    final AppDatabase db1 = AppDatabase.forTesting(NativeDatabase(dbFile));
    final _Repositories repos1 = _Repositories(db1);
    final Capture created = await repos1.captures.create(
      audioPath: audio.file.path,
      source: 'trigger',
    );
    await repos1.captures.update(
      created.copyWith(
        rawTranscript: 'Book el dentist bokra.',
        llmType: LlmType.task,
        title: 'Call the dentist',
        details: 'Book an appointment tomorrow.',
        status: CaptureStatus.ready,
      ),
    );
    final _FakeNativeApi native = _FakeNativeApi(<NativeCapturedAudio>[
      NativeCapturedAudio(
        eventId: 'native-fixture',
        audioPath: audio.file.path,
        capturedAt: created.capturedAt,
        ownerId: 'u1',
      ),
    ]);
    final CaptureTriageService triage = CaptureTriageService(
      userId: 'u1',
      captures: repos1.captures,
      tasks: repos1.tasks,
      notes: repos1.notes,
      habits: repos1.habits,
      goals: repos1.goals,
      emitter: repos1.emitter,
      nativeApi: native,
      pendingQueue: Future<PendingAudioQueue>.value(queue),
      barrier: CaptureIngestionBarrier(),
      db: db1,
      clock: () => created.capturedAt.add(const Duration(seconds: 9)),
    );

    final CaptureTriageResult result = await triage.save(
      created.id,
      const CaptureTriageDraft(
        type: ResultingType.task,
        title: 'Call dentist tomorrow',
        details: 'Ask for a morning slot.',
      ),
    );
    await repos1.emitter.settle();
    expect(result.type, ResultingType.task);
    expect(native.acknowledged, <String>['native-fixture']);
    expect(audio.file.existsSync(), isFalse);
    await db1.close();

    final AppDatabase db2 = AppDatabase.forTesting(NativeDatabase(dbFile));
    final CaptureRow captureRow = await (db2.select(db2.captures)).getSingle();
    final TaskRow taskRow = await (db2.select(db2.tasks)).getSingle();
    expect(captureRow.status, CaptureStatus.triaged.wire);
    expect(captureRow.resultingType, ResultingType.task.name);
    expect(captureRow.resultingId, taskRow.id);
    expect(taskRow.captureId, captureRow.id);
    expect(taskRow.title, 'Call dentist tomorrow');
    final events = await DriftEventsRepository(
      db2,
    ).getSince(DateTime.utc(2000));
    final triaged = events.singleWhere(
      (event) => event.eventType == 'capture_triaged',
    );
    expect(triaged.metadata['resulting_type'], 'task');
    expect(triaged.metadata['latency_ms'], 9000);
    await db2.close();
  });

  test(
    'category override routes once to note and habit repositories',
    () async {
      final _P4Harness harness = await _P4Harness.openMemory();
      addTearDown(harness.close);
      final _FakeNativeApi native = _FakeNativeApi(<NativeCapturedAudio>[]);
      final CaptureTriageService triage = CaptureTriageService(
        userId: 'u1',
        captures: harness.repos.captures,
        tasks: harness.repos.tasks,
        notes: harness.repos.notes,
        habits: harness.repos.habits,
        goals: harness.repos.goals,
        emitter: harness.repos.emitter,
        nativeApi: native,
        pendingQueue: Future<PendingAudioQueue>.value(harness.queue),
        barrier: CaptureIngestionBarrier(),
        db: harness.db,
      );
      final Capture note = await harness.repos.captures.create(source: 'fab');
      final Capture habit = await harness.repos.captures.create(source: 'fab');

      await triage.save(
        note.id,
        const CaptureTriageDraft(
          type: ResultingType.note,
          title: 'A useful idea',
          details: 'Keep this context.',
        ),
      );
      final Future<CaptureTriageResult> firstHabit = triage.save(
        habit.id,
        const CaptureTriageDraft(
          type: ResultingType.habit,
          title: 'Stretch after lunch',
          details: 'Attach it to clearing the plate.',
          habitLevel: HabitLevel.mini,
        ),
      );
      final Future<CaptureTriageResult> duplicateHabit = triage.save(
        habit.id,
        const CaptureTriageDraft(
          type: ResultingType.habit,
          title: 'Stretch after lunch',
          details: 'Attach it to clearing the plate.',
          habitLevel: HabitLevel.mini,
        ),
      );
      expect(identical(firstHabit, duplicateHabit), isTrue);
      await Future.wait(<Future<CaptureTriageResult>>[
        firstHabit,
        duplicateHabit,
      ]);

      expect(
        (await harness.db.select(harness.db.notes).get()).single.captureId,
        note.id,
      );
      final HabitRow habitRow =
          (await harness.db.select(harness.db.habits).get()).single;
      expect(habitRow.captureId, habit.id);
      expect(habitRow.levelConfig, contains('"suggested_level":"mini"'));
    },
  );

  test(
    'two triage service instances converge on one deterministic typed row',
    () async {
      final _P4Harness harness = await _P4Harness.openMemory();
      addTearDown(harness.close);
      final Capture capture = await harness.captures.create(source: 'fab');
      final CaptureIngestionBarrier barrier = CaptureIngestionBarrier();
      CaptureTriageService service() => CaptureTriageService(
        userId: 'u1',
        captures: harness.repos.captures,
        tasks: harness.repos.tasks,
        notes: harness.repos.notes,
        habits: harness.repos.habits,
        goals: harness.repos.goals,
        emitter: harness.repos.emitter,
        nativeApi: _FakeNativeApi(<NativeCapturedAudio>[]),
        pendingQueue: Future<PendingAudioQueue>.value(harness.queue),
        barrier: barrier,
        db: harness.db,
      );

      final List<CaptureTriageResult> results =
          await Future.wait(<Future<CaptureTriageResult>>[
            service().save(
              capture.id,
              const CaptureTriageDraft(
                type: ResultingType.task,
                title: 'One task',
                details: 'Created from one capture.',
              ),
            ),
            service().save(
              capture.id,
              const CaptureTriageDraft(
                type: ResultingType.task,
                title: 'One task',
                details: 'Created from one capture.',
              ),
            ),
          ]);

      final List<TaskRow> rows = await harness.db
          .select(harness.db.tasks)
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.id, capture.id);
      expect(
        results.map((CaptureTriageResult result) => result.id).toSet(),
        <String>{capture.id},
      );
    },
  );

  test(
    'discard never acknowledges before its terminal row is durable',
    () async {
      final _P4Harness harness = await _P4Harness.openMemory();
      addTearDown(harness.close);
      final PendingAudio audio = await harness.queue.enqueueBytes(<int>[5, 5]);
      final Capture capture = await harness.captures.create(
        audioPath: audio.file.path,
        source: 'trigger',
      );
      final _FakeNativeApi native = _FakeNativeApi(<NativeCapturedAudio>[
        NativeCapturedAudio(
          eventId: 'must-stay-pending',
          audioPath: audio.file.path,
          capturedAt: capture.capturedAt,
          ownerId: 'u1',
        ),
      ]);
      final CaptureTriageService triage = CaptureTriageService(
        userId: 'u1',
        captures: _FailingUpdateCapturesRepository(harness.captures),
        tasks: harness.repos.tasks,
        notes: harness.repos.notes,
        habits: harness.repos.habits,
        goals: harness.repos.goals,
        emitter: harness.repos.emitter,
        nativeApi: native,
        pendingQueue: Future<PendingAudioQueue>.value(harness.queue),
        barrier: CaptureIngestionBarrier(),
        db: harness.db,
      );

      await expectLater(triage.discard(capture.id), throwsStateError);

      expect(native.acknowledged, isEmpty);
      expect(audio.file.existsSync(), isTrue);
    },
  );

  test('auth drain waits for an in-flight terminal triage save', () async {
    final _P4Harness harness = await _P4Harness.openMemory();
    addTearDown(harness.close);
    final Capture capture = await harness.captures.create(source: 'fab');
    final CaptureIngestionBarrier barrier = CaptureIngestionBarrier();
    final _BlockingTasksRepository blocking = _BlockingTasksRepository(
      harness.repos.tasks,
    );
    final CaptureTriageService triage = CaptureTriageService(
      userId: 'u1',
      captures: harness.captures,
      tasks: blocking,
      notes: harness.repos.notes,
      habits: harness.repos.habits,
      goals: harness.repos.goals,
      emitter: harness.repos.emitter,
      nativeApi: _FakeNativeApi(<NativeCapturedAudio>[]),
      pendingQueue: Future<PendingAudioQueue>.value(harness.queue),
      barrier: barrier,
      db: harness.db,
    );

    final Future<CaptureTriageResult> saving = triage.save(
      capture.id,
      const CaptureTriageDraft(
        type: ResultingType.task,
        title: 'Drain safely',
        details: 'Finish before sign-out wipes the database.',
      ),
    );
    await blocking.started.future;
    var drained = false;
    final Future<void> draining = barrier.closeAndDrain().then((_) {
      drained = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(drained, isFalse);

    blocking.release();
    await saving;
    await draining;
    expect(drained, isTrue);
  });

  test('discard wins against a stale in-flight Gemini completion', () async {
    final _P4Harness harness = await _P4Harness.openMemory();
    addTearDown(harness.close);
    final PendingAudio audio = await harness.queue.enqueueBytes(<int>[8, 6]);
    final Capture capture = await harness.captures.create(
      audioPath: audio.file.path,
      source: 'trigger',
    );
    final CaptureIngestionBarrier barrier = CaptureIngestionBarrier();
    final _BlockingGemini gemini = _BlockingGemini();
    final CaptureProcessingService processing = CaptureProcessingService(
      captures: harness.captures,
      gemini: gemini,
      connectivity: _OfflineConnectivity(),
      barrier: barrier,
      triage: _triageFor(harness, barrier),
      idGenerator: IdGenerator(),
      baseRetryDelay: const Duration(days: 1),
    );
    addTearDown(processing.dispose);
    final _FakeNativeApi native = _FakeNativeApi(<NativeCapturedAudio>[
      NativeCapturedAudio(
        eventId: 'discard-during-gemini',
        audioPath: audio.file.path,
        capturedAt: capture.capturedAt,
        ownerId: 'u1',
      ),
    ]);
    final CaptureTriageService triage = CaptureTriageService(
      userId: 'u1',
      captures: harness.captures,
      tasks: harness.repos.tasks,
      notes: harness.repos.notes,
      habits: harness.repos.habits,
      goals: harness.repos.goals,
      emitter: harness.repos.emitter,
      nativeApi: native,
      pendingQueue: Future<PendingAudioQueue>.value(harness.queue),
      barrier: barrier,
      db: harness.db,
    );

    final Future<void> processingFuture = processing.processById(capture.id);
    await gemini.started.future;
    await triage.discard(capture.id);
    gemini.complete(
      const CaptureAnalysis(
        rawTranscript: 'A response that arrived too late.',
        items: <ProposedItem>[
          ProposedItem(
            id: '',
            kind: ResultingType.task,
            title: 'Stale response',
            confidence: DraftConfidence.high,
            details: 'This must not resurrect the capture.',
          ),
        ],
      ),
    );
    await processingFuture;

    final Capture after = (await harness.captures.getByIds(<String>[
      capture.id,
    ])).single;
    expect(after.status, CaptureStatus.discarded);
    expect(native.acknowledged, <String>['discard-during-gemini']);
    expect(audio.file.existsSync(), isFalse);
  });

  test(
    'discard emits capture_discarded and drains acknowledged audio',
    () async {
      final _P4Harness harness = await _P4Harness.openMemory();
      addTearDown(harness.close);
      final PendingAudio audio = await harness.queue.enqueueBytes(<int>[4, 2]);
      final Capture capture = await harness.captures.create(
        audioPath: audio.file.path,
        source: 'trigger',
      );
      final _FakeNativeApi native = _FakeNativeApi(<NativeCapturedAudio>[
        NativeCapturedAudio(
          eventId: 'discard-native',
          audioPath: audio.file.path,
          capturedAt: capture.capturedAt,
          ownerId: 'u1',
        ),
      ]);
      final CaptureTriageService triage = CaptureTriageService(
        userId: 'u1',
        captures: harness.repos.captures,
        tasks: harness.repos.tasks,
        notes: harness.repos.notes,
        habits: harness.repos.habits,
        goals: harness.repos.goals,
        emitter: harness.repos.emitter,
        nativeApi: native,
        pendingQueue: Future<PendingAudioQueue>.value(harness.queue),
        barrier: CaptureIngestionBarrier(),
        db: harness.db,
      );

      await triage.discard(capture.id);
      await harness.repos.emitter.settle();

      expect(native.acknowledged, <String>['discard-native']);
      expect(audio.file.existsSync(), isFalse);
      final Capture after = (await harness.captures.getByIds(<String>[
        capture.id,
      ])).single;
      expect(after.status, CaptureStatus.discarded);
      final events = await DriftEventsRepository(
        harness.db,
      ).getSince(DateTime.utc(2000));
      expect(
        events.where((event) => event.eventType == 'capture_discarded'),
        hasLength(1),
      );
    },
  );

  test('energy selector persists and emits the semantic event', () async {
    final _P4Harness harness = await _P4Harness.openMemory();
    addTearDown(harness.close);
    final ProfileRepositoryImpl profiles = ProfileRepositoryImpl(
      db: harness.db,
      userId: 'u1',
    );
    final EnergyModeService energy = EnergyModeService(
      userId: 'u1',
      profiles: profiles,
      emitter: harness.repos.emitter,
    );

    await energy.setMode(EnergyMode.charged);
    await harness.repos.emitter.settle();

    expect((await profiles.get())!.prefs['energy_mode'], 'charged');
    final events = await DriftEventsRepository(
      harness.db,
    ).getSince(DateTime.utc(2000));
    final changed = events.singleWhere(
      (event) => event.eventType == 'energy_mode_changed',
    );
    expect(changed.metadata, <String, Object?>{
      'from': 'normal',
      'to': 'charged',
      'auto': false,
    });
  });

  group('Capture decomposition (rant → many items)', () {
    Future<Capture> runProcessing(
      _P4Harness harness,
      CaptureAnalysis analysis, {
      NativeCaptureApi? native,
      required String eventId,
    }) async {
      final PendingAudio queued = await harness.queue.enqueueBytes(<int>[1, 2]);
      final Capture capture = await harness.captures.create(
        audioPath: queued.file.path,
        source: 'trigger',
      );
      final NativeCaptureApi nativeApi =
          native ??
          _FakeNativeApi(<NativeCapturedAudio>[
            NativeCapturedAudio(
              eventId: eventId,
              audioPath: queued.file.path,
              capturedAt: capture.capturedAt,
              ownerId: 'u1',
            ),
          ]);
      final CaptureIngestionBarrier barrier = CaptureIngestionBarrier();
      final CaptureProcessingService processing = CaptureProcessingService(
        captures: harness.captures,
        gemini: _FixedGemini(analysis),
        connectivity: _OfflineConnectivity(),
        barrier: barrier,
        triage: _triageFor(harness, barrier, native: nativeApi),
        idGenerator: IdGenerator(),
        baseRetryDelay: const Duration(days: 1),
      );
      addTearDown(processing.dispose);
      await processing.processById(capture.id);
      await harness.repos.emitter.settle();
      return (await harness.captures.getByIds(<String>[capture.id])).single;
    }

    test('auto-commits a concise all-task capture to real rows', () async {
      final _P4Harness harness = await _P4Harness.openMemory();
      addTearDown(harness.close);
      final Capture after = await runProcessing(
        harness,
        const CaptureAnalysis(
          rawTranscript: 'Put the food in the fridge and feed the dogs.',
          items: <ProposedItem>[
            ProposedItem(
              id: '',
              kind: ResultingType.task,
              title: 'Put food in the fridge',
              confidence: DraftConfidence.high,
            ),
            ProposedItem(
              id: '',
              kind: ResultingType.task,
              title: 'Feed the dogs',
              confidence: DraftConfidence.high,
            ),
          ],
        ),
        eventId: 'auto-commit',
      );

      expect(after.status, CaptureStatus.triaged);
      expect(after.proposedItems, hasLength(2));
      final List<TaskRow> tasks = await harness.db
          .select(harness.db.tasks)
          .get();
      expect(tasks, hasLength(2));
      expect(tasks.every((TaskRow t) => t.captureId == after.id), isTrue);
      // Each materialised row's id IS its draft's stable client id (§11).
      expect(
        tasks.map((TaskRow t) => t.id).toSet(),
        after.proposedItems!.map((ProposedItem d) => d.id).toSet(),
      );
    });

    test('no cross-item context: a plain sibling task stays plain', () async {
      final _P4Harness harness = await _P4Harness.openMemory();
      addTearDown(harness.close);
      final Capture after = await runProcessing(
        harness,
        const CaptureAnalysis(
          rawTranscript: 'Fridge when home, and feed the dogs.',
          items: <ProposedItem>[
            ProposedItem(
              id: '',
              kind: ResultingType.task,
              title: 'Put food in the fridge',
              confidence: DraftConfidence.high,
              location: DraftLocation(name: 'Home'),
            ),
            ProposedItem(
              id: '',
              kind: ResultingType.task,
              title: 'Feed the dogs',
              confidence: DraftConfidence.high,
            ),
          ],
        ),
        eventId: 'no-cross',
      );
      expect(after.status, CaptureStatus.triaged);
      final ProposedItem dogs = after.proposedItems!.firstWhere(
        (ProposedItem d) => d.title == 'Feed the dogs',
      );
      expect(dogs.location, isNull);
    });

    test('a mixed capture (task + habit) waits in review', () async {
      final _P4Harness harness = await _P4Harness.openMemory();
      addTearDown(harness.close);
      final Capture after = await runProcessing(
        harness,
        const CaptureAnalysis(
          rawTranscript: 'Call the dentist and start stretching after lunch.',
          items: <ProposedItem>[
            ProposedItem(
              id: '',
              kind: ResultingType.task,
              title: 'Call the dentist',
              confidence: DraftConfidence.high,
            ),
            ProposedItem(
              id: '',
              kind: ResultingType.habit,
              title: 'Stretch after lunch',
              confidence: DraftConfidence.high,
            ),
          ],
        ),
        eventId: 'mixed',
      );
      expect(after.status, CaptureStatus.ready);
      expect(after.proposedItems, hasLength(2));
      expect(await harness.db.select(harness.db.tasks).get(), isEmpty);
      expect(await harness.db.select(harness.db.habits).get(), isEmpty);
    });

    test('a low-confidence task capture waits in review', () async {
      final _P4Harness harness = await _P4Harness.openMemory();
      addTearDown(harness.close);
      final Capture after = await runProcessing(
        harness,
        const CaptureAnalysis(
          rawTranscript: 'Maybe email someone about the thing.',
          items: <ProposedItem>[
            ProposedItem(
              id: '',
              kind: ResultingType.task,
              title: 'Email someone',
              confidence: DraftConfidence.low,
            ),
          ],
        ),
        eventId: 'low-conf',
      );
      expect(after.status, CaptureStatus.ready);
      expect(await harness.db.select(harness.db.tasks).get(), isEmpty);
    });

    test('more than three tasks exceeds the auto-commit cap', () async {
      final _P4Harness harness = await _P4Harness.openMemory();
      addTearDown(harness.close);
      final Capture after = await runProcessing(
        harness,
        const CaptureAnalysis(
          rawTranscript: 'Four quick things.',
          items: <ProposedItem>[
            ProposedItem(
              id: '',
              kind: ResultingType.task,
              title: 'One',
              confidence: DraftConfidence.high,
            ),
            ProposedItem(
              id: '',
              kind: ResultingType.task,
              title: 'Two',
              confidence: DraftConfidence.high,
            ),
            ProposedItem(
              id: '',
              kind: ResultingType.task,
              title: 'Three',
              confidence: DraftConfidence.high,
            ),
            ProposedItem(
              id: '',
              kind: ResultingType.task,
              title: 'Four',
              confidence: DraftConfidence.high,
            ),
          ],
        ),
        eventId: 'over-cap',
      );
      expect(after.status, CaptureStatus.ready);
      expect(after.proposedItems, hasLength(4));
      expect(await harness.db.select(harness.db.tasks).get(), isEmpty);
    });

    test('empty extraction falls back to a single note draft', () async {
      final _P4Harness harness = await _P4Harness.openMemory();
      addTearDown(harness.close);
      final Capture after = await runProcessing(
        harness,
        const CaptureAnalysis(
          rawTranscript: 'Just some rambling with nothing to do.',
          items: <ProposedItem>[],
        ),
        eventId: 'empty',
      );
      expect(after.status, CaptureStatus.ready);
      expect(after.proposedItems, hasLength(1));
      expect(after.proposedItems!.single.kind, ResultingType.note);
      expect(after.proposedItems!.single.details, contains('rambling'));
      // A note is never auto-committed.
      expect(await harness.db.select(harness.db.notes).get(), isEmpty);
    });

    test('saveAll materialises each kind once across replays', () async {
      final _P4Harness harness = await _P4Harness.openMemory();
      addTearDown(harness.close);
      final Capture capture = await harness.repos.captures.create(
        source: 'fab',
      );
      const List<ProposedItem> drafts = <ProposedItem>[
        ProposedItem(
          id: 'd-task',
          kind: ResultingType.task,
          title: 'A task',
          confidence: DraftConfidence.high,
        ),
        ProposedItem(
          id: 'd-note',
          kind: ResultingType.note,
          title: 'A note',
          confidence: DraftConfidence.low,
        ),
        ProposedItem(
          id: 'd-goal',
          kind: ResultingType.goal,
          title: 'A goal',
          confidence: DraftConfidence.low,
          why: 'because',
        ),
        ProposedItem(
          id: 'd-habit',
          kind: ResultingType.habit,
          title: 'A habit',
          confidence: DraftConfidence.low,
        ),
      ];
      final CaptureTriageService triage = _triageFor(
        harness,
        CaptureIngestionBarrier(),
      );

      final List<CaptureTriageResult> first = await triage.saveAll(
        capture.id,
        drafts,
      );
      final List<CaptureTriageResult> second = await triage.saveAll(
        capture.id,
        drafts,
      );

      expect(await harness.db.select(harness.db.tasks).get(), hasLength(1));
      expect(await harness.db.select(harness.db.notes).get(), hasLength(1));
      expect(await harness.db.select(harness.db.habits).get(), hasLength(1));
      final List<GoalRow> goals = await harness.db
          .select(harness.db.goals)
          .get();
      expect(goals, hasLength(1));
      expect(goals.single.id, 'd-goal');
      expect(goals.single.captureId, capture.id);
      expect(
        first.map((CaptureTriageResult r) => r.id).toList(),
        second.map((CaptureTriageResult r) => r.id).toList(),
      );
      expect(
        (await harness.captures.getByIds(<String>[capture.id])).single.status,
        CaptureStatus.triaged,
      );
    });

    test('bulk materialization rolls back every child on failure', () async {
      final _P4Harness harness = await _P4Harness.openMemory();
      addTearDown(harness.close);
      final Capture capture = await harness.captures.create(source: 'fab');
      const List<ProposedItem> drafts = <ProposedItem>[
        ProposedItem(
          id: 'atomic-task',
          kind: ResultingType.task,
          title: 'First',
          confidence: DraftConfidence.low,
        ),
        ProposedItem(
          id: 'atomic-note',
          kind: ResultingType.note,
          title: 'Second',
          confidence: DraftConfidence.low,
        ),
      ];
      await harness.captures.update(
        capture.copyWith(proposedItems: drafts, status: CaptureStatus.ready),
      );
      final CaptureTriageService triage = CaptureTriageService(
        userId: 'u1',
        captures: harness.captures,
        tasks: harness.repos.tasks,
        notes: _FailingNotesRepository(harness.repos.notes),
        habits: harness.repos.habits,
        goals: harness.repos.goals,
        emitter: harness.repos.emitter,
        nativeApi: _FakeNativeApi(<NativeCapturedAudio>[]),
        pendingQueue: Future<PendingAudioQueue>.value(harness.queue),
        barrier: CaptureIngestionBarrier(),
        db: harness.db,
      );

      await expectLater(triage.saveAll(capture.id, drafts), throwsStateError);

      expect(await harness.db.select(harness.db.tasks).get(), isEmpty);
      expect(
        (await harness.captures.getByIds(<String>[capture.id])).single.status,
        CaptureStatus.ready,
      );
    });

    test('partial approval stays ready and re-entry finishes it', () async {
      final _P4Harness harness = await _P4Harness.openMemory();
      addTearDown(harness.close);
      final Capture capture = await harness.captures.create(source: 'fab');
      const List<ProposedItem> drafts = <ProposedItem>[
        ProposedItem(
          id: 'partial-1',
          kind: ResultingType.task,
          title: 'Now',
          confidence: DraftConfidence.low,
        ),
        ProposedItem(
          id: 'partial-2',
          kind: ResultingType.task,
          title: 'Later',
          confidence: DraftConfidence.low,
        ),
      ];
      await harness.captures.update(
        capture.copyWith(proposedItems: drafts, status: CaptureStatus.ready),
      );
      final CaptureTriageService triage = _triageFor(
        harness,
        CaptureIngestionBarrier(),
      );

      const ProposedItem editedLater = ProposedItem(
        id: 'partial-2',
        kind: ResultingType.goal,
        title: 'Edited later',
        confidence: DraftConfidence.low,
        why: 'Keep this edit',
      );
      await expectLater(
        triage.saveAll(
          capture.id,
          <ProposedItem>[drafts.first],
          editedItems: <ProposedItem>[
            drafts.first,
            editedLater.copyWith(title: '   '),
          ],
        ),
        throwsArgumentError,
      );
      expect(await harness.repos.tasks.watchAll().first, isEmpty);
      await triage.saveAll(
        capture.id,
        <ProposedItem>[drafts.first],
        editedItems: <ProposedItem>[drafts.first, editedLater],
      );
      Capture after = (await harness.captures.getByIds(<String>[
        capture.id,
      ])).single;
      expect(after.status, CaptureStatus.ready);
      expect(after.dispositionedItemIds, <String>['partial-1']);
      expect(after.proposedItems!.last.title, 'Edited later');
      expect(after.proposedItems!.last.kind, ResultingType.goal);
      expect(after.proposedItems!.last.why, 'Keep this edit');
      expect(await harness.repos.tasks.watchAll().first, hasLength(1));

      await triage.saveAll(capture.id, <ProposedItem>[
        after.proposedItems!.last,
      ]);
      after = (await harness.captures.getByIds(<String>[capture.id])).single;
      expect(after.status, CaptureStatus.triaged);
      expect(await harness.repos.tasks.watchAll().first, hasLength(1));
      expect(await harness.repos.goals.watchAll().first, hasLength(1));
      await harness.repos.emitter.settle();
      final List<DomainEvent> events = await DriftEventsRepository(
        harness.db,
      ).getSince(DateTime.utc(2000));
      final DomainEvent triaged = events.singleWhere(
        (DomainEvent event) => event.eventType == 'capture_triaged',
      );
      expect(triaged.metadata['item_count'], 2);
      expect(triaged.metadata['kinds'], <Object?>['task', 'goal']);
    });

    test(
      'partial dispositions suppress ready checkpoint auto-commit',
      () async {
        final _P4Harness harness = await _P4Harness.openMemory();
        addTearDown(harness.close);
        final Capture capture = await harness.captures.create(source: 'fab');
        const List<ProposedItem> drafts = <ProposedItem>[
          ProposedItem(
            id: 'reviewed-high-1',
            kind: ResultingType.task,
            title: 'Approved manually',
            confidence: DraftConfidence.high,
          ),
          ProposedItem(
            id: 'deferred-high-2',
            kind: ResultingType.task,
            title: 'Still needs review',
            confidence: DraftConfidence.high,
          ),
        ];
        await harness.captures.update(
          capture.copyWith(proposedItems: drafts, status: CaptureStatus.ready),
        );
        final CaptureTriageService triage = _triageFor(
          harness,
          CaptureIngestionBarrier(),
        );
        await triage.saveAll(capture.id, <ProposedItem>[drafts.first]);

        final CaptureProcessingService restarted = CaptureProcessingService(
          captures: harness.captures,
          gemini: _FailingGemini(),
          connectivity: _OfflineConnectivity(),
          barrier: CaptureIngestionBarrier(),
          triage: triage,
          idGenerator: IdGenerator(),
          baseRetryDelay: const Duration(days: 1),
        );
        addTearDown(restarted.dispose);
        await restarted.retryNow();

        expect(await harness.repos.tasks.watchAll().first, hasLength(1));
        final Capture stillReady = (await harness.captures.getByIds(<String>[
          capture.id,
        ])).single;
        expect(stillReady.status, CaptureStatus.ready);
        expect(stillReady.dispositionedItemIds, <String>['reviewed-high-1']);
      },
    );

    test(
      'defer-all review durably suppresses checkpoint auto-commit',
      () async {
        final _P4Harness harness = await _P4Harness.openMemory();
        addTearDown(harness.close);
        final Capture capture = await harness.captures.create(source: 'fab');
        const ProposedItem originalGoal = ProposedItem(
          id: 'defer-all',
          kind: ResultingType.goal,
          title: 'A goal requiring review',
          confidence: DraftConfidence.high,
        );
        await harness.captures.update(
          capture.copyWith(
            proposedItems: const <ProposedItem>[originalGoal],
            status: CaptureStatus.ready,
          ),
        );
        final CaptureTriageService triage = _triageFor(
          harness,
          CaptureIngestionBarrier(),
        );
        const ProposedItem editedDeferredTask = ProposedItem(
          id: 'defer-all',
          kind: ResultingType.task,
          title: 'Still deferred',
          confidence: DraftConfidence.high,
        );
        await triage.saveAll(
          capture.id,
          const <ProposedItem>[],
          editedItems: const <ProposedItem>[editedDeferredTask],
        );
        final Capture deferred = (await harness.captures.getByIds(<String>[
          capture.id,
        ])).single;
        expect(deferred.dispositionedItemIds, isEmpty);
        expect(deferred.proposedItems!.single.kind, ResultingType.task);
        expect(deferred.proposedItems!.single.confidence, DraftConfidence.low);

        final CaptureProcessingService restarted = CaptureProcessingService(
          captures: harness.captures,
          gemini: _FailingGemini(),
          connectivity: _OfflineConnectivity(),
          barrier: CaptureIngestionBarrier(),
          triage: triage,
          idGenerator: IdGenerator(),
          baseRetryDelay: const Duration(days: 1),
        );
        addTearDown(restarted.dispose);
        await restarted.retryNow();

        expect(await harness.repos.tasks.watchAll().first, isEmpty);
        expect(
          (await harness.captures.getByIds(<String>[capture.id])).single.status,
          CaptureStatus.ready,
        );
      },
    );

    test(
      'eligible ready checkpoint is recovered without Gemini replay',
      () async {
        final _P4Harness harness = await _P4Harness.openMemory();
        addTearDown(harness.close);
        final Capture capture = await harness.captures.create(source: 'fab');
        const List<ProposedItem> drafts = <ProposedItem>[
          ProposedItem(
            id: 'checkpoint-task',
            kind: ResultingType.task,
            title: 'Recovered',
            confidence: DraftConfidence.high,
          ),
        ];
        await harness.captures.update(
          capture.copyWith(proposedItems: drafts, status: CaptureStatus.ready),
        );
        final CaptureIngestionBarrier barrier = CaptureIngestionBarrier();
        final CaptureProcessingService processing = CaptureProcessingService(
          captures: harness.captures,
          gemini: _FailingGemini(),
          connectivity: _OfflineConnectivity(),
          barrier: barrier,
          triage: _triageFor(harness, barrier),
          idGenerator: IdGenerator(),
        );
        addTearDown(processing.dispose);

        await processing.retryNow();

        final Capture after = (await harness.captures.getByIds(<String>[
          capture.id,
        ])).single;
        expect(after.status, CaptureStatus.triaged);
        expect(after.autoCommittedAt, isNotNull);
        expect(await harness.repos.tasks.watchAll().first, hasLength(1));
      },
    );

    test('the auto-commit gate is structural', () {
      ProposedItem task(DraftConfidence c) => ProposedItem(
        id: 'x',
        kind: ResultingType.task,
        title: 't',
        confidence: c,
      );
      expect(
        AutoCommit.isEligible(<ProposedItem>[task(DraftConfidence.high)]),
        isTrue,
      );
      expect(AutoCommit.isEligible(<ProposedItem>[]), isFalse);
      expect(
        AutoCommit.isEligible(<ProposedItem>[
          task(DraftConfidence.high),
          task(DraftConfidence.low),
        ]),
        isFalse,
      );
      expect(
        AutoCommit.isEligible(<ProposedItem>[
          const ProposedItem(
            id: 'g',
            kind: ResultingType.goal,
            title: 'g',
            confidence: DraftConfidence.high,
          ),
        ]),
        isFalse,
      );
      expect(
        AutoCommit.isEligible(
          List<ProposedItem>.filled(4, task(DraftConfidence.high)),
        ),
        isFalse,
      );
    });

    test('ProposedItem survives a stored JSON round-trip', () {
      const ProposedItem original = ProposedItem(
        id: 'abc',
        kind: ResultingType.task,
        title: 'Call the dentist',
        confidence: DraftConfidence.high,
        details: 'Book a morning slot',
        schedule: DraftSchedule(date: '2026-07-19', time: '09:00'),
        reminder: true,
      );
      final ProposedItem parsed = ProposedItem.fromStored(original.toJson());
      expect(parsed.id, 'abc');
      expect(parsed.kind, ResultingType.task);
      expect(parsed.title, 'Call the dentist');
      expect(parsed.confidence, DraftConfidence.high);
      expect(parsed.details, 'Book a morning slot');
      expect(parsed.schedule?.date, '2026-07-19');
      expect(parsed.schedule?.time, '09:00');
      expect(parsed.reminder, isTrue);
      expect(parsed.scheduledAt, DateTime(2026, 7, 19, 9));
    });

    test('a Gemini draft with no id is rejected when read as stored', () {
      expect(
        () => ProposedItem.fromStored(<String, Object?>{
          'kind': 'task',
          'title': 'x',
          'confidence': 'high',
        }),
        throwsA(isA<ProposedItemFormatException>()),
      );
    });

    test('undoAutoCommit removes items, reopens capture, reissues ids', () async {
      final _P4Harness harness = await _P4Harness.openMemory();
      addTearDown(harness.close);
      final Capture capture = await harness.repos.captures.create(
        source: 'fab',
      );
      const List<ProposedItem> drafts = <ProposedItem>[
        ProposedItem(
          id: 'auto-1',
          kind: ResultingType.task,
          title: 'Buy milk',
          confidence: DraftConfidence.high,
        ),
        ProposedItem(
          id: 'auto-2',
          kind: ResultingType.task,
          title: 'Email Sam',
          confidence: DraftConfidence.high,
        ),
      ];
      // The processing service persists `proposed_items` at the `ready`
      // checkpoint before auto-committing; undo reads them back to know what to
      // remove, so mirror that here.
      await harness.repos.captures.update(
        capture.copyWith(proposedItems: drafts, status: CaptureStatus.ready),
      );
      final CaptureTriageService triage = _triageFor(
        harness,
        CaptureIngestionBarrier(),
      );

      await triage.saveAll(capture.id, drafts, autoCommitted: true);
      expect(await harness.repos.tasks.watchAll().first, hasLength(2));

      await triage.undoAutoCommit(capture.id);

      // Children soft-deleted; capture returns to the inbox for review.
      expect(await harness.repos.tasks.watchAll().first, isEmpty);
      final Capture reopened = (await harness.captures.getByIds(<String>[
        capture.id,
      ])).single;
      expect(reopened.status, CaptureStatus.ready);

      // Drafts retained but re-stamped so the tombstoned ids are not reused.
      final List<ProposedItem> reissued = reopened.proposedItems!;
      expect(reissued.map((ProposedItem i) => i.title), <String>[
        'Buy milk',
        'Email Sam',
      ]);
      final Set<String> newIds = reissued.map((ProposedItem i) => i.id).toSet();
      expect(newIds.intersection(<String>{'auto-1', 'auto-2'}), isEmpty);
      expect(
        reissued.every((ProposedItem i) => i.confidence == DraftConfidence.low),
        isTrue,
        reason: 'Undo durably suppresses automatic checkpoint recovery',
      );

      // A cold-start/resume retry must leave an explicitly undone capture in
      // review instead of interpreting its ready checkpoint as a crash and
      // recreating the tasks.
      final CaptureProcessingService restarted = CaptureProcessingService(
        captures: harness.captures,
        gemini: _FailingGemini(),
        connectivity: _OfflineConnectivity(),
        barrier: CaptureIngestionBarrier(),
        triage: triage,
        idGenerator: IdGenerator(),
        baseRetryDelay: const Duration(days: 1),
      );
      addTearDown(restarted.dispose);
      await restarted.retryNow();
      expect(await harness.repos.tasks.watchAll().first, isEmpty);
      expect(
        (await harness.captures.getByIds(<String>[capture.id])).single.status,
        CaptureStatus.ready,
      );

      // Re-saving under the fresh ids creates brand-new active rows; the
      // originals stay tombstoned (4 rows total, 2 live).
      await triage.saveAll(capture.id, reissued);
      expect(await harness.repos.tasks.watchAll().first, hasLength(2));
      expect(await harness.db.select(harness.db.tasks).get(), hasLength(4));
    });

    test(
      'undoAutoCommit rolls back every tombstone when one delete fails',
      () async {
        final _P4Harness harness = await _P4Harness.openMemory();
        addTearDown(harness.close);
        final Capture capture = await harness.captures.create(source: 'fab');
        const List<ProposedItem> drafts = <ProposedItem>[
          ProposedItem(
            id: 'undo-atomic-1',
            kind: ResultingType.task,
            title: 'First',
            confidence: DraftConfidence.high,
          ),
          ProposedItem(
            id: 'undo-atomic-2',
            kind: ResultingType.task,
            title: 'Second',
            confidence: DraftConfidence.high,
          ),
        ];
        await harness.captures.update(
          capture.copyWith(proposedItems: drafts, status: CaptureStatus.ready),
        );
        final CaptureTriageService writer = _triageFor(
          harness,
          CaptureIngestionBarrier(),
        );
        await writer.saveAll(capture.id, drafts, autoCommitted: true);
        final CaptureTriageService undo = CaptureTriageService(
          userId: 'u1',
          captures: harness.captures,
          tasks: _FailingDeleteTasksRepository(
            harness.repos.tasks,
            failId: 'undo-atomic-2',
          ),
          notes: harness.repos.notes,
          habits: harness.repos.habits,
          goals: harness.repos.goals,
          emitter: harness.repos.emitter,
          nativeApi: _FakeNativeApi(<NativeCapturedAudio>[]),
          pendingQueue: Future<PendingAudioQueue>.value(harness.queue),
          barrier: CaptureIngestionBarrier(),
          db: harness.db,
        );

        await expectLater(undo.undoAutoCommit(capture.id), throwsStateError);

        expect(await harness.repos.tasks.watchAll().first, hasLength(2));
        final Capture unchanged = (await harness.captures.getByIds(<String>[
          capture.id,
        ])).single;
        expect(unchanged.status, CaptureStatus.triaged);
        expect(unchanged.autoCommittedAt, isNotNull);
      },
    );

    test('stale auto-commit Undo cannot delete accepted tasks', () async {
      final _P4Harness harness = await _P4Harness.openMemory();
      addTearDown(harness.close);
      final Capture capture = await harness.captures.create(source: 'fab');
      const List<ProposedItem> drafts = <ProposedItem>[
        ProposedItem(
          id: 'stale-undo-task',
          kind: ResultingType.task,
          title: 'Keep me',
          confidence: DraftConfidence.high,
        ),
      ];
      await harness.captures.update(
        capture.copyWith(proposedItems: drafts, status: CaptureStatus.ready),
      );
      DateTime now = DateTime.utc(2026, 7, 18, 12);
      final CaptureTriageService triage = CaptureTriageService(
        userId: 'u1',
        captures: harness.captures,
        tasks: harness.repos.tasks,
        notes: harness.repos.notes,
        habits: harness.repos.habits,
        goals: harness.repos.goals,
        emitter: harness.repos.emitter,
        nativeApi: _FakeNativeApi(<NativeCapturedAudio>[]),
        pendingQueue: Future<PendingAudioQueue>.value(harness.queue),
        barrier: CaptureIngestionBarrier(),
        db: harness.db,
        clock: () => now,
        autoCommitUndoWindow: const Duration(seconds: 30),
      );
      await triage.saveAll(capture.id, drafts, autoCommitted: true);
      now = now.add(const Duration(seconds: 31));

      await expectLater(triage.undoAutoCommit(capture.id), throwsStateError);

      expect(await harness.repos.tasks.watchAll().first, hasLength(1));
      final Capture unchanged = (await harness.captures.getByIds(<String>[
        capture.id,
      ])).single;
      expect(unchanged.status, CaptureStatus.triaged);
      expect(unchanged.autoCommittedAt, isNotNull);
    });
  });
}

CaptureTriageService _triageFor(
  _P4Harness harness,
  CaptureIngestionBarrier barrier, {
  NativeCaptureApi? native,
}) => CaptureTriageService(
  userId: 'u1',
  captures: harness.repos.captures,
  tasks: harness.repos.tasks,
  notes: harness.repos.notes,
  habits: harness.repos.habits,
  goals: harness.repos.goals,
  emitter: harness.repos.emitter,
  nativeApi: native ?? _FakeNativeApi(<NativeCapturedAudio>[]),
  pendingQueue: Future<PendingAudioQueue>.value(harness.queue),
  barrier: barrier,
  db: harness.db,
);

Map<String, Object?> _validEnvelope() => <String, Object?>{
  'candidates': <Object?>[
    <String, Object?>{
      'content': <String, Object?>{
        'parts': <Object?>[
          <String, Object?>{
            'text': '''```json
{"raw_transcript":"Lazem akalem el dentist bokra.","items":[{"kind":"task","title":"Call the dentist","details":"Book an appointment tomorrow.","confidence":"high","schedule":{"date":"2026-07-19","time":"09:00"}}]}
```''',
          },
        ],
      },
    },
  ],
};

Map<String, Object?> _malformedEnvelope() => <String, Object?>{
  'candidates': <Object?>[
    <String, Object?>{
      'content': <String, Object?>{
        'parts': <Object?>[
          <String, Object?>{'text': '```json\nnot-json\n```'},
        ],
      },
    },
  ],
};

Map<String, Object?> _envelopeWithText(String text) => <String, Object?>{
  'candidates': <Object?>[
    <String, Object?>{
      'content': <String, Object?>{
        'parts': <Object?>[
          <String, Object?>{'text': text},
        ],
      },
    },
  ],
};

class _FixtureTransport implements GeminiTransport {
  _FixtureTransport(this.response);
  final Map<String, Object?> response;
  Map<String, Object?>? lastBody;

  @override
  Future<Map<String, Object?>> postJson({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    lastBody = body;
    return response;
  }
}

class _SequenceTransport implements GeminiTransport {
  _SequenceTransport(this.responses);
  final List<Map<String, Object?>> responses;
  int calls = 0;

  @override
  Future<Map<String, Object?>> postJson({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async => responses[calls++];
}

class _FailingGemini implements GeminiClient {
  @override
  Future<CaptureAnalysis> analyzeCaptureAudio(File audioFile) =>
      Future<CaptureAnalysis>.error(const SocketException('offline'));
}

class _FixedGemini implements GeminiClient {
  _FixedGemini(this.analysis);
  final CaptureAnalysis analysis;

  @override
  Future<CaptureAnalysis> analyzeCaptureAudio(File audioFile) async => analysis;
}

class _BlockingGemini implements GeminiClient {
  final Completer<void> started = Completer<void>();
  final Completer<CaptureAnalysis> _result = Completer<CaptureAnalysis>();

  void complete(CaptureAnalysis analysis) => _result.complete(analysis);

  @override
  Future<CaptureAnalysis> analyzeCaptureAudio(File audioFile) {
    started.complete();
    return _result.future;
  }
}

class _OfflineConnectivity implements ConnectivityService {
  @override
  Future<bool> isConnected() async => false;

  @override
  Stream<bool> get onConnectedChanged => const Stream<bool>.empty();
}

class _FailingUpdateCapturesRepository implements CapturesRepository {
  _FailingUpdateCapturesRepository(this.delegate);
  final CapturesRepository delegate;

  @override
  Future<Capture> create({
    String? audioPath,
    DateTime? capturedAt,
    String source = 'trigger',
  }) => delegate.create(
    audioPath: audioPath,
    capturedAt: capturedAt,
    source: source,
  );
  @override
  Future<void> delete(String id) => delegate.delete(id);
  @override
  Future<List<Capture>> getByIds(List<String> ids) => delegate.getByIds(ids);
  @override
  Future<void> update(Capture capture) =>
      Future<void>.error(StateError('disk write failed'));
  @override
  Stream<List<Capture>> watchAll() => delegate.watchAll();
  @override
  Stream<List<Capture>> watchByStatuses(Set<CaptureStatus> statuses) =>
      delegate.watchByStatuses(statuses);
}

class _BlockingTasksRepository
    implements TasksRepository, CaptureLinkedTasksRepository {
  _BlockingTasksRepository(this.delegate);
  final TasksRepositoryImpl delegate;
  final Completer<void> started = Completer<void>();
  final Completer<void> _released = Completer<void>();

  void release() => _released.complete();

  @override
  Future<Task> createForCapture({
    required String captureId,
    required String title,
    String? id,
    String? details,
    DateTime? scheduledAt,
  }) async {
    started.complete();
    await _released.future;
    return delegate.createForCapture(
      captureId: captureId,
      id: id,
      title: title,
      details: details,
      scheduledAt: scheduledAt,
    );
  }

  @override
  Future<Task> create({
    required String title,
    String? details,
    String? captureId,
    String? goalId,
    DateTime? scheduledAt,
  }) => delegate.create(
    title: title,
    details: details,
    captureId: captureId,
    goalId: goalId,
    scheduledAt: scheduledAt,
  );
  @override
  Future<void> delete(String id) => delegate.delete(id);
  @override
  Future<void> update(Task task) => delegate.update(task);
  @override
  Stream<List<Task>> watchAll() => delegate.watchAll();
  @override
  Stream<List<Task>> watchByStatus(TaskStatus status) =>
      delegate.watchByStatus(status);
}

class _FailingNotesRepository
    implements NotesRepository, CaptureLinkedNotesRepository {
  _FailingNotesRepository(this.delegate);
  final NotesRepositoryImpl delegate;

  @override
  Future<Note> createForCapture({
    required String captureId,
    String? id,
    String? title,
    String? body,
  }) => Future<Note>.error(StateError('second child failed'));

  @override
  Future<Note> create({String? title, String? body, String? captureId}) =>
      delegate.create(title: title, body: body, captureId: captureId);

  @override
  Future<void> delete(String id) => delegate.delete(id);

  @override
  Future<void> update(Note note) => delegate.update(note);

  @override
  Stream<List<Note>> watchAll() => delegate.watchAll();
}

class _FailingDeleteTasksRepository
    implements TasksRepository, CaptureLinkedTasksRepository {
  _FailingDeleteTasksRepository(this.delegate, {required this.failId});
  final TasksRepositoryImpl delegate;
  final String failId;

  @override
  Future<void> delete(String id) {
    if (id == failId) return Future<void>.error(StateError('delete failed'));
    return delegate.delete(id);
  }

  @override
  Future<Task> create({
    required String title,
    String? details,
    String? captureId,
    String? goalId,
    DateTime? scheduledAt,
  }) => delegate.create(
    title: title,
    details: details,
    captureId: captureId,
    goalId: goalId,
    scheduledAt: scheduledAt,
  );

  @override
  Future<Task> createForCapture({
    required String captureId,
    required String title,
    String? id,
    String? details,
    DateTime? scheduledAt,
  }) => delegate.createForCapture(
    captureId: captureId,
    title: title,
    id: id,
    details: details,
    scheduledAt: scheduledAt,
  );

  @override
  Future<void> update(Task task) => delegate.update(task);

  @override
  Stream<List<Task>> watchAll() => delegate.watchAll();

  @override
  Stream<List<Task>> watchByStatus(TaskStatus status) =>
      delegate.watchByStatus(status);
}

class _Repositories {
  _Repositories(this.db)
    : emitter = EventEmitter(DriftEventsRepository(db), IdGenerator()),
      captures = CapturesRepositoryImpl(
        db: db,
        emitter: EventEmitter(DriftEventsRepository(db), IdGenerator()),
        idGenerator: IdGenerator(),
        userId: 'u1',
      ),
      tasks = TasksRepositoryImpl(
        db: db,
        emitter: EventEmitter(DriftEventsRepository(db), IdGenerator()),
        idGenerator: IdGenerator(),
        userId: 'u1',
      ),
      notes = NotesRepositoryImpl(
        db: db,
        emitter: EventEmitter(DriftEventsRepository(db), IdGenerator()),
        idGenerator: IdGenerator(),
        userId: 'u1',
      ),
      habits = HabitsRepositoryImpl(
        db: db,
        emitter: EventEmitter(DriftEventsRepository(db), IdGenerator()),
        idGenerator: IdGenerator(),
        userId: 'u1',
      ),
      goals = GoalsRepositoryImpl(
        db: db,
        emitter: EventEmitter(DriftEventsRepository(db), IdGenerator()),
        idGenerator: IdGenerator(),
        userId: 'u1',
      );

  final AppDatabase db;
  final EventEmitter emitter;
  final CapturesRepositoryImpl captures;
  final TasksRepositoryImpl tasks;
  final NotesRepositoryImpl notes;
  final HabitsRepositoryImpl habits;
  final GoalsRepositoryImpl goals;
}

class _P4Harness {
  _P4Harness._(this.db, this.temp, this.queue, this.repos);
  final AppDatabase db;
  final Directory temp;
  final DirectoryPendingAudioQueue queue;
  final _Repositories repos;
  CapturesRepositoryImpl get captures => repos.captures;

  static Future<_P4Harness> openMemory() async {
    final Directory temp = await Directory.systemTemp.createTemp(
      'sidekick-p4-',
    );
    final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
    return _P4Harness._(
      db,
      temp,
      DirectoryPendingAudioQueue(baseDir: temp),
      _Repositories(db),
    );
  }

  Future<void> close() async {
    await db.close();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  }
}

class _FakeNativeApi implements NativeCaptureApi {
  _FakeNativeApi(this.events);
  final List<NativeCapturedAudio> events;
  final List<String> acknowledged = <String>[];

  @override
  Stream<NativeCaptureSignal> get signals =>
      const Stream<NativeCaptureSignal>.empty();
  @override
  Future<void> acknowledge(String eventId) async => acknowledged.add(eventId);
  @override
  Future<void> configureTrigger(CaptureTriggerConfig config) async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> isAccessibilityEnabled() async => true;
  @override
  Future<bool> isRecording(String ownerId) async => false;
  @override
  Future<void> openAccessibilitySettings() async {}
  @override
  Future<List<NativeCapturedAudio>> pendingEvents(String ownerId) async =>
      events;
  @override
  Future<List<NativeCapturedAudio>> retryFailed(String ownerId) async => events;
  @override
  Future<void> setOwner(String? ownerId) async {}
  @override
  Future<void> startCapture() async {}
  @override
  Future<void> stopCapture() async {}
}
