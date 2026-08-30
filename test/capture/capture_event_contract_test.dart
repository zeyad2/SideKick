import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/core/capture/capture_contract.dart';
import 'package:sidekick/core/capture/capture_coordinator.dart';
import 'package:sidekick/core/capture/capture_ingestion_barrier.dart';
import 'package:sidekick/core/capture/capture_ingestion_service.dart';
import 'package:sidekick/core/capture/native_capture_api.dart';
import 'package:sidekick/core/data/id_generator.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/events/event_emitter.dart';
import 'package:sidekick/core/events/events_repository.dart';
import 'package:sidekick/features/inbox/data/captures_repository_impl.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';
import 'package:sidekick/features/profile/domain/profile.dart';

void main() {
  late AppDatabase db;
  late CapturesRepositoryImpl repository;
  late _FakeNativeCaptureApi native;
  late CaptureIngestionService ingestion;
  late CaptureIngestionBarrier barrier;
  late Directory temp;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final EventEmitter emitter = EventEmitter(
      DriftEventsRepository(db),
      IdGenerator(),
    );
    repository = CapturesRepositoryImpl(
      db: db,
      emitter: emitter,
      idGenerator: IdGenerator(),
      userId: 'capture-user',
    );
    native = _FakeNativeCaptureApi();
    barrier = CaptureIngestionBarrier();
    ingestion = CaptureIngestionService(
      repository: repository,
      nativeApi: native,
      ownerId: 'capture-user',
      barrier: barrier,
    );
    temp = await Directory.systemTemp.createTemp('sidekick-p3-');
  });

  tearDown(() async {
    await ingestion.dispose();
    await db.close();
    await temp.delete(recursive: true);
  });

  test(
    'frozen event carries audio file path + CapturesRepository row id',
    () async {
      final File audio = File('${temp.path}/capture.aac')
        ..writeAsBytesSync(<int>[1, 2, 3], flush: true);
      final NativeCapturedAudio nativeEvent = NativeCapturedAudio(
        eventId: 'native-1',
        audioPath: audio.path,
        capturedAt: DateTime.utc(2026, 7, 14, 20),
        ownerId: 'capture-user',
      );
      final Future<CapturedAudioEvent> emitted = ingestion.events.first;

      final CapturedAudioEvent result = await ingestion.ingest(nativeEvent);

      expect(await emitted, same(result));
      expect(result.nativeEventId, nativeEvent.eventId);
      expect(result.audioFilePath, audio.path);
      final CaptureRow row = await (db.select(db.captures)).getSingle();
      expect(result.captureRowId, row.id);
      expect(row.audioPath, audio.path);
      expect(row.dirty, isTrue, reason: 'P2 repository owns local-first write');
      expect(native.acknowledged, isEmpty);
    },
  );

  test(
    'native replay is idempotent after a crash before acknowledgement',
    () async {
      final NativeCapturedAudio event = NativeCapturedAudio(
        eventId: 'native-replayed',
        audioPath: '${temp.path}/replayed.aac',
        capturedAt: DateTime.utc(2026, 7, 14, 21),
        ownerId: 'capture-user',
      );

      final CapturedAudioEvent first = await ingestion.ingest(event);
      final CapturedAudioEvent replay = await ingestion.ingest(event);

      expect(replay.captureRowId, first.captureRowId);
      expect((await db.select(db.captures).get()).length, 1);
      expect(native.acknowledged, isEmpty);
    },
  );

  test(
    'terminal replay acknowledges the journal without recreating a capture',
    () async {
      final NativeCapturedAudio event = NativeCapturedAudio(
        eventId: 'native-terminal-replay',
        audioPath: '${temp.path}/terminal.aac',
        capturedAt: DateTime.utc(2026, 7, 14, 21, 30),
        ownerId: 'capture-user',
      );
      final CapturedAudioEvent first = await ingestion.ingest(event);
      final Capture capture = (await repository.getByIds(<String>[
        first.captureRowId,
      ])).single;
      await repository.update(
        capture.copyWith(status: CaptureStatus.discarded),
      );

      final CapturedAudioEvent replay = await ingestion.ingest(event);

      expect(replay.captureRowId, first.captureRowId);
      expect((await db.select(db.captures).get()), hasLength(1));
      expect(native.acknowledged, <String>['native-terminal-replay']);
    },
  );

  test('trigger configuration is read from profile preferences', () {
    final CaptureTriggerConfig configured = CaptureTriggerConfig.fromPrefs(
      <String, Object?>{
        'capture_trigger': <String, Object?>{
          'key': 'volume_down',
          'press_count': 2,
          'window_ms': 1200,
        },
      },
    );

    expect(configured.key, 'volume_down');
    expect(configured.pressCount, 2);
    expect(configured.windowMs, 1200);
  });

  test(
    'live signal and startup replay are deduplicated concurrently',
    () async {
      final NativeCapturedAudio event = NativeCapturedAudio(
        eventId: 'native-concurrent',
        audioPath: '${temp.path}/concurrent.aac',
        capturedAt: DateTime.utc(2026, 7, 14, 22),
        ownerId: 'capture-user',
      );

      final List<CapturedAudioEvent> results = await Future.wait(
        <Future<CapturedAudioEvent>>[
          ingestion.ingest(event),
          ingestion.ingest(event),
        ],
      );

      expect(results[0].captureRowId, results[1].captureRowId);
      expect((await db.select(db.captures).get()).length, 1);
    },
  );

  test('a pending event can never cross repository owners', () async {
    final NativeCapturedAudio wrongOwner = NativeCapturedAudio(
      eventId: 'native-owner-a',
      audioPath: '${temp.path}/owner-a.aac',
      capturedAt: DateTime.utc(2026, 7, 14, 23),
      ownerId: 'owner-a',
    );

    await expectLater(ingestion.ingest(wrongOwner), throwsStateError);

    expect(await db.select(db.captures).get(), isEmpty);
    expect(native.acknowledged, isEmpty);
  });

  test(
    'coordinator disposal does not kill shared native API on re-login',
    () async {
      final _FakeProfileRepository profiles = _FakeProfileRepository(
        'capture-user',
      );
      final CaptureCoordinator first = CaptureCoordinator(
        nativeApi: native,
        ingestion: ingestion,
        profileRepository: profiles,
        userId: 'capture-user',
      );
      await first.initialize();
      await first.dispose();
      expect(native.disposed, isFalse);

      final CaptureIngestionService secondIngestion = CaptureIngestionService(
        repository: repository,
        nativeApi: native,
        ownerId: 'capture-user',
        barrier: barrier,
      );
      final CaptureCoordinator second = CaptureCoordinator(
        nativeApi: native,
        ingestion: secondIngestion,
        profileRepository: profiles,
        userId: 'capture-user',
      );
      await second.initialize();
      final Future<CapturedAudioEvent> delivered =
          second.capturedAudioEvents.first;
      native.emit(
        NativeCaptureSaved(
          NativeCapturedAudio(
            eventId: 'after-relogin',
            audioPath: '${temp.path}/after-relogin.aac',
            capturedAt: DateTime.utc(2026, 7, 15),
            ownerId: 'capture-user',
          ),
        ),
      );

      expect((await delivered).audioFilePath, contains('after-relogin.aac'));
      await second.dispose();
    },
  );

  test('coordinator initialization never starts recording', () async {
    final CaptureCoordinator coordinator = CaptureCoordinator(
      nativeApi: native,
      ingestion: ingestion,
      profileRepository: _FakeProfileRepository('capture-user'),
      userId: 'capture-user',
    );

    await coordinator.initialize();

    expect(native.startCount, 0);
    await coordinator.dispose();
  });

  test('cancel discards the live recording and closes the overlay', () async {
    final CaptureCoordinator coordinator = CaptureCoordinator(
      nativeApi: native,
      ingestion: ingestion,
      profileRepository: _FakeProfileRepository('capture-user'),
      userId: 'capture-user',
    );
    await coordinator.initialize();
    native.emit(
      NativeRecordingStarted(
        NativeCapturedAudio(
          eventId: 'cancel-me',
          audioPath: '${temp.path}/cancel-me.aac',
          capturedAt: DateTime.utc(2026, 7, 15),
          ownerId: 'capture-user',
        ),
      ),
    );
    await pumpEventQueue();

    await coordinator.cancelCapture();

    expect(native.cancelCount, 1);
    expect(coordinator.currentState.stage, CaptureOverlayStage.hidden);
    await coordinator.dispose();
  });

  test(
    'auth-transition barrier drains writes and keeps native replay durable',
    () async {
      final _BlockingCapturesRepository blocking = _BlockingCapturesRepository(
        repository,
      );
      final CaptureIngestionService service = CaptureIngestionService(
        repository: blocking,
        nativeApi: native,
        ownerId: 'capture-user',
        barrier: barrier,
      );
      final NativeCapturedAudio event = NativeCapturedAudio(
        eventId: 'during-signout',
        audioPath: '${temp.path}/during-signout.aac',
        capturedAt: DateTime.utc(2026, 7, 15, 1),
        ownerId: 'capture-user',
      );

      final Future<CapturedAudioEvent> writing = service.ingest(event);
      await blocking.watchRequested.future;
      var drained = false;
      final Future<void> closing = barrier.closeAndDrain().then((_) {
        drained = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(drained, isFalse, reason: 'sign-out waits for capture writes');

      blocking.release();
      await writing;
      await closing;
      expect(native.acknowledged, isEmpty, reason: 'journal survives DB wipe');

      await db.wipeAllData();
      expect(await db.select(db.captures).get(), isEmpty);
      barrier.reopen();
      final CapturedAudioEvent replayed = await ingestion.ingest(event);
      expect(replayed.captureRowId, isNotEmpty);
      expect((await db.select(db.captures).get()).length, 1);
      await service.dispose();
    },
  );
}

class _FakeNativeCaptureApi implements NativeCaptureApi {
  final StreamController<NativeCaptureSignal> _signals =
      StreamController<NativeCaptureSignal>.broadcast();
  final List<String> acknowledged = <String>[];
  bool disposed = false;
  String? ownerId;
  int startCount = 0;
  int cancelCount = 0;

  void emit(NativeCaptureSignal signal) => _signals.add(signal);

  @override
  Stream<NativeCaptureSignal> get signals => _signals.stream;

  @override
  Future<void> acknowledge(String eventId) async => acknowledged.add(eventId);

  @override
  Future<void> configureTrigger(CaptureTriggerConfig config) async {}

  @override
  Future<void> dispose() async {
    disposed = true;
    await _signals.close();
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> isAccessibilityEnabled() async => false;

  @override
  Future<bool> isRecording(String ownerId) async => false;

  @override
  Future<void> openAccessibilitySettings() async {}

  @override
  Future<List<NativeCapturedAudio>> pendingEvents(String ownerId) async =>
      const <NativeCapturedAudio>[];

  @override
  Future<List<NativeCapturedAudio>> retryFailed(String ownerId) async =>
      const <NativeCapturedAudio>[];

  @override
  Future<void> setOwner(String? ownerId) async => this.ownerId = ownerId;

  @override
  Future<void> startCapture() async => startCount += 1;

  @override
  Future<void> stopCapture() async {}

  @override
  Future<void> cancelCapture() async => cancelCount += 1;
}

class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository(this.userId);
  final String userId;

  Profile get _profile => Profile(
    id: userId,
    personaResponseLanguage: PersonaLanguage.english,
    theme: 'analog_companion',
    prefs: const <String, Object?>{},
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );

  @override
  Future<Profile> ensureExists() async => _profile;

  @override
  Future<Profile?> get() async => _profile;

  @override
  Future<void> mergePrefs(Map<String, Object?> values) async {}

  @override
  Future<void> setPersonaLanguage(PersonaLanguage language) async {}

  @override
  Future<void> setTheme(String theme) async {}

  @override
  Stream<Profile?> watch() => Stream<Profile?>.value(_profile);
}

class _BlockingCapturesRepository implements CapturesRepository {
  _BlockingCapturesRepository(this.delegate);
  final CapturesRepository delegate;
  final Completer<void> watchRequested = Completer<void>();
  final StreamController<List<Capture>> _watch =
      StreamController<List<Capture>>();

  void release() => _watch.add(const <Capture>[]);

  @override
  Future<Capture> create({
    String? inputText,
    String? audioPath,
    DateTime? capturedAt,
    String source = 'shortcut',
  }) => delegate.create(
    inputText: inputText,
    audioPath: audioPath,
    capturedAt: capturedAt,
    source: source,
  );

  @override
  Future<void> delete(String id) => delegate.delete(id);

  @override
  Future<List<Capture>> getByIds(List<String> ids) => delegate.getByIds(ids);

  @override
  Future<void> update(Capture capture) => delegate.update(capture);

  @override
  Stream<List<Capture>> watchAll() {
    if (!watchRequested.isCompleted) watchRequested.complete();
    return _watch.stream;
  }

  @override
  Stream<List<Capture>> watchByStatuses(Set<CaptureStatus> statuses) =>
      delegate.watchByStatuses(statuses);
}
