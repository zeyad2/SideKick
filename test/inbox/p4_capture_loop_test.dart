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
import 'package:sidekick/core/events/event_emitter.dart';
import 'package:sidekick/core/events/events_repository.dart';
import 'package:sidekick/core/sync/connectivity_service.dart';
import 'package:sidekick/features/habits/data/habits_repository_impl.dart';
import 'package:sidekick/features/inbox/application/capture_processing_service.dart';
import 'package:sidekick/features/inbox/application/capture_triage_service.dart';
import 'package:sidekick/features/inbox/application/energy_mode_service.dart';
import 'package:sidekick/features/inbox/data/captures_repository_impl.dart';
import 'package:sidekick/features/inbox/data/gemini_client.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';
import 'package:sidekick/features/inbox/domain/capture_analysis.dart';
import 'package:sidekick/features/notes/data/notes_repository_impl.dart';
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

        expect(analysis.type, LlmType.task);
        expect(analysis.title, 'Call the dentist');
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
      final CaptureProcessingService processing = CaptureProcessingService(
        captures: harness.captures,
        gemini: client,
        connectivity: _OfflineConnectivity(),
        barrier: CaptureIngestionBarrier(),
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
    final CaptureProcessingService processing = CaptureProcessingService(
      captures: harness.captures,
      gemini: _FailingGemini(),
      connectivity: _OfflineConnectivity(),
      barrier: CaptureIngestionBarrier(),
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
      emitter: repos1.emitter,
      nativeApi: native,
      pendingQueue: Future<PendingAudioQueue>.value(queue),
      barrier: CaptureIngestionBarrier(),
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
        emitter: harness.repos.emitter,
        nativeApi: native,
        pendingQueue: Future<PendingAudioQueue>.value(harness.queue),
        barrier: CaptureIngestionBarrier(),
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
        emitter: harness.repos.emitter,
        nativeApi: _FakeNativeApi(<NativeCapturedAudio>[]),
        pendingQueue: Future<PendingAudioQueue>.value(harness.queue),
        barrier: barrier,
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
        emitter: harness.repos.emitter,
        nativeApi: native,
        pendingQueue: Future<PendingAudioQueue>.value(harness.queue),
        barrier: CaptureIngestionBarrier(),
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
      emitter: harness.repos.emitter,
      nativeApi: _FakeNativeApi(<NativeCapturedAudio>[]),
      pendingQueue: Future<PendingAudioQueue>.value(harness.queue),
      barrier: barrier,
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
      emitter: harness.repos.emitter,
      nativeApi: native,
      pendingQueue: Future<PendingAudioQueue>.value(harness.queue),
      barrier: barrier,
    );

    final Future<void> processingFuture = processing.processById(capture.id);
    await gemini.started.future;
    await triage.discard(capture.id);
    gemini.complete(
      const CaptureAnalysis(
        type: LlmType.task,
        title: 'Stale response',
        details: 'This must not resurrect the capture.',
        suggestedSchedule: null,
        rawTranscript: 'A response that arrived too late.',
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
        emitter: harness.repos.emitter,
        nativeApi: native,
        pendingQueue: Future<PendingAudioQueue>.value(harness.queue),
        barrier: CaptureIngestionBarrier(),
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
}

Map<String, Object?> _validEnvelope() => <String, Object?>{
  'candidates': <Object?>[
    <String, Object?>{
      'content': <String, Object?>{
        'parts': <Object?>[
          <String, Object?>{
            'text': '''```json
{"type":"task","title":"Call the dentist","details":"Book an appointment tomorrow.","suggested_schedule":{"day":"tomorrow"},"raw_transcript":"Lazem akalem el dentist bokra."}
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

class _FailingGemini implements GeminiClient {
  @override
  Future<CaptureAnalysis> analyzeCaptureAudio(File audioFile) =>
      Future<CaptureAnalysis>.error(const SocketException('offline'));
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
    String? details,
    DateTime? scheduledAt,
  }) async {
    started.complete();
    await _released.future;
    return delegate.createForCapture(
      captureId: captureId,
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
      );

  final AppDatabase db;
  final EventEmitter emitter;
  final CapturesRepositoryImpl captures;
  final TasksRepositoryImpl tasks;
  final NotesRepositoryImpl notes;
  final HabitsRepositoryImpl habits;
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
