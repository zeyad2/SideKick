import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/core/capture/capture_contract.dart';
import 'package:sidekick/core/capture/capture_ingestion_barrier.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/sync/connectivity_service.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';
import 'package:sidekick/features/reminders/application/audio_reminder_retry_controller.dart';

void main() {
  test('connectivity recovery retries pending audio capture', () async {
    final _FakeCaptures captures = _FakeCaptures(<Capture>[
      _capture(status: CaptureStatus.pending),
    ]);
    final _FakeConnectivity connectivity = _FakeConnectivity(false);
    final StreamController<CapturedAudioEvent> events =
        StreamController<CapturedAudioEvent>.broadcast();
    final List<String> processed = <String>[];
    final AudioReminderRetryController controller =
        AudioReminderRetryController(
          captures: captures,
          connectivity: connectivity,
          captureEvents: events.stream,
          barrier: CaptureIngestionBarrier(),
          processAudio: (Capture capture) async {
            processed.add(capture.id);
            captures.rows[0] = capture.copyWith(status: CaptureStatus.ready);
          },
          acknowledgeProcessed: (_) async {},
        )..start();

    connectivity.emit(true);
    await Future<void>.delayed(Duration.zero);
    await controller.retryEligible();

    expect(processed, <String>['capture-1']);
    await controller.dispose();
    await events.close();
    await connectivity.close();
  });

  test(
    'live durable capture is drafted without opening Capture screen',
    () async {
      final _FakeCaptures captures = _FakeCaptures(<Capture>[
        _capture(status: CaptureStatus.pending),
      ]);
      final _FakeConnectivity connectivity = _FakeConnectivity(false);
      final StreamController<CapturedAudioEvent> events =
          StreamController<CapturedAudioEvent>.broadcast();
      final Completer<String> processed = Completer<String>();
      final AudioReminderRetryController controller =
          AudioReminderRetryController(
            captures: captures,
            connectivity: connectivity,
            captureEvents: events.stream,
            barrier: CaptureIngestionBarrier(),
            processAudio: (Capture capture) async =>
                processed.complete(capture.id),
            acknowledgeProcessed: (_) async {},
          )..start();

      events.add(
        const CapturedAudioEvent(
          nativeEventId: 'native-1',
          audioFilePath: '/pending/audio.aac',
          captureRowId: 'capture-1',
        ),
      );

      expect(await processed.future, 'capture-1');
      await controller.dispose();
      await events.close();
      await connectivity.close();
    },
  );

  test('unclear audio failure is never automatically retried', () async {
    final Capture unclear = _capture(
      status: CaptureStatus.failed,
      error:
          'sidekick_state:{"review_drafts":[],"audio_attempts":1,'
          '"message":"Audio was unclear. Try recording again."}',
    );
    expect(
      AudioReminderRetryController.automaticRetryEligible(unclear),
      isFalse,
    );
  });

  test('transient Gemini failure is eligible for automatic retry', () async {
    final Capture failed = _capture(
      status: CaptureStatus.failed,
      error:
          'sidekick_state:{"review_drafts":[],"message":'
          '"Gemini reminder drafting failed (503)."}',
    );
    expect(AudioReminderRetryController.automaticRetryEligible(failed), isTrue);
  });

  test('persisted processing audio recovers and ACKs after restart', () async {
    final _FakeCaptures captures = _FakeCaptures(<Capture>[
      _capture(status: CaptureStatus.processing),
    ]);
    final _FakeConnectivity connectivity = _FakeConnectivity(true);
    final StreamController<CapturedAudioEvent> events =
        StreamController<CapturedAudioEvent>.broadcast();
    final Completer<String> processed = Completer<String>();
    final List<String> acknowledged = <String>[];
    final AudioReminderRetryController controller =
        AudioReminderRetryController(
          captures: captures,
          connectivity: connectivity,
          captureEvents: events.stream,
          barrier: CaptureIngestionBarrier(),
          processAudio: (Capture capture) async {
            processed.complete(capture.id);
          },
          acknowledgeProcessed: (Capture capture) async {
            acknowledged.add(capture.id);
          },
        )..start();

    expect(await processed.future, 'capture-1');
    await Future<void>.delayed(Duration.zero);
    expect(acknowledged, <String>['capture-1']);
    await controller.dispose();
    await events.close();
    await connectivity.close();
  });

  test('sign-out drains drafting and preserves native replay ACK', () async {
    final _FakeCaptures captures = _FakeCaptures(<Capture>[
      _capture(status: CaptureStatus.pending),
    ]);
    final _FakeConnectivity connectivity = _FakeConnectivity(false);
    final StreamController<CapturedAudioEvent> events =
        StreamController<CapturedAudioEvent>.broadcast();
    final CaptureIngestionBarrier barrier = CaptureIngestionBarrier();
    final Completer<void> parseStarted = Completer<void>();
    final Completer<void> finishParse = Completer<void>();
    final List<String> writes = <String>[];
    final List<String> acknowledged = <String>[];
    final AudioReminderRetryController controller =
        AudioReminderRetryController(
          captures: captures,
          connectivity: connectivity,
          captureEvents: events.stream,
          barrier: barrier,
          processAudio: (Capture capture) async {
            parseStarted.complete();
            await finishParse.future;
            writes.add(capture.userId);
          },
          acknowledgeProcessed: (Capture capture) async {
            acknowledged.add(capture.id);
          },
        )..start();

    events.add(
      const CapturedAudioEvent(
        nativeEventId: 'native-signout',
        audioFilePath: '/pending/audio.aac',
        captureRowId: 'capture-1',
      ),
    );
    await parseStarted.future;
    var drained = false;
    final Future<void> closing = barrier.closeAndDrain().then((_) {
      drained = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(drained, isFalse);

    finishParse.complete();
    await closing;
    writes.clear(); // Simulate the database wipe after the barrier drains.
    await Future<void>.delayed(Duration.zero);

    expect(writes, isEmpty, reason: 'no outgoing-user write lands post-wipe');
    expect(acknowledged, isEmpty, reason: 'native replay survives sign-out');
    await controller.dispose();
    await events.close();
    await connectivity.close();
  });

  test('sign-out drains a live capture lookup before database wipe', () async {
    final _BlockingLookupCaptures captures = _BlockingLookupCaptures(<Capture>[
      _capture(status: CaptureStatus.pending),
    ]);
    final _FakeConnectivity connectivity = _FakeConnectivity(false);
    final StreamController<CapturedAudioEvent> events =
        StreamController<CapturedAudioEvent>.broadcast();
    final CaptureIngestionBarrier barrier = CaptureIngestionBarrier();
    final List<String> writes = <String>[];
    final List<String> acknowledged = <String>[];
    final AudioReminderRetryController controller =
        AudioReminderRetryController(
          captures: captures,
          connectivity: connectivity,
          captureEvents: events.stream,
          barrier: barrier,
          processAudio: (Capture capture) async => writes.add(capture.userId),
          acknowledgeProcessed: (Capture capture) async {
            acknowledged.add(capture.id);
          },
        )..start();

    events.add(
      const CapturedAudioEvent(
        nativeEventId: 'native-lookup-race',
        audioFilePath: '/pending/audio.aac',
        captureRowId: 'capture-1',
      ),
    );
    await captures.lookupStarted.future;
    var drained = false;
    final Future<void> closing = barrier.closeAndDrain().then((_) {
      drained = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(drained, isFalse);

    captures.releaseLookup.complete();
    await closing;
    writes.clear(); // Simulate wipe only after the protected lookup/write.
    await Future<void>.delayed(Duration.zero);

    expect(writes, isEmpty);
    expect(acknowledged, isEmpty, reason: 'invalidated lookup cannot ACK');
    await controller.dispose();
    await events.close();
    await connectivity.close();
  });
}

Capture _capture({required CaptureStatus status, String? error}) => Capture(
  id: 'capture-1',
  userId: 'user-1',
  source: CaptureSource.audio,
  audioPath: '/pending/audio.aac',
  status: status,
  error: error,
  capturedAt: DateTime.utc(2026, 8, 24),
  createdAt: DateTime.utc(2026, 8, 24),
  updatedAt: DateTime.utc(2026, 8, 24),
);

class _FakeConnectivity implements ConnectivityService {
  _FakeConnectivity(this.connected);
  bool connected;
  final StreamController<bool> _changes = StreamController<bool>.broadcast();

  void emit(bool value) {
    connected = value;
    _changes.add(value);
  }

  Future<void> close() => _changes.close();

  @override
  Future<bool> isConnected() async => connected;

  @override
  Stream<bool> get onConnectedChanged => _changes.stream;
}

class _FakeCaptures implements CapturesRepository {
  _FakeCaptures(this.rows);
  final List<Capture> rows;

  @override
  Future<Capture> create({
    String? inputText,
    String? audioPath,
    DateTime? capturedAt,
    String source = 'audio',
  }) => throw UnimplementedError();

  @override
  Future<void> delete(String id) async {}

  @override
  Future<List<Capture>> getByIds(List<String> ids) async =>
      rows.where((Capture capture) => ids.contains(capture.id)).toList();

  @override
  Future<void> update(Capture capture) async {}

  @override
  Stream<List<Capture>> watchAll() => Stream<List<Capture>>.value(rows);

  @override
  Stream<List<Capture>> watchByStatuses(Set<CaptureStatus> statuses) =>
      Stream<List<Capture>>.value(
        rows
            .where((Capture capture) => statuses.contains(capture.status))
            .toList(),
      );
}

class _BlockingLookupCaptures extends _FakeCaptures {
  _BlockingLookupCaptures(super.rows);

  final Completer<void> lookupStarted = Completer<void>();
  final Completer<void> releaseLookup = Completer<void>();

  @override
  Future<List<Capture>> getByIds(List<String> ids) async {
    lookupStarted.complete();
    await releaseLookup.future;
    return super.getByIds(ids);
  }
}
