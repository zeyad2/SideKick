import 'dart:async';

import 'package:sidekick/core/capture/capture_contract.dart';
import 'package:sidekick/core/capture/capture_ingestion_barrier.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/sync/connectivity_service.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';
import 'package:sidekick/features/reminders/application/reminder_creation_service.dart';

/// Retries durable audio captures when a network transport becomes available.
///
/// Unclear audio is a user-input problem, not a transport failure, so it stays
/// in the explicit two-retry review flow instead of being retried automatically.
class AudioReminderRetryController {
  AudioReminderRetryController({
    required this.captures,
    required this.connectivity,
    required this.captureEvents,
    required this.barrier,
    required this.processAudio,
    required this.acknowledgeProcessed,
  });

  final CapturesRepository captures;
  final ConnectivityService connectivity;
  final Stream<CapturedAudioEvent> captureEvents;
  final CaptureIngestionBarrier barrier;
  final Future<void> Function(Capture capture) processAudio;
  final Future<void> Function(Capture capture) acknowledgeProcessed;

  final Map<String, Future<void>> _inFlight = <String, Future<void>>{};
  final Set<Future<void>> _lookups = <Future<void>>{};
  StreamSubscription<CapturedAudioEvent>? _captureSubscription;
  StreamSubscription<bool>? _connectivitySubscription;
  Future<void>? _sweep;
  bool _disposed = false;

  void start() {
    _captureSubscription ??= captureEvents.listen((CapturedAudioEvent event) {
      _handleCaptureEvent(event);
    });
    _connectivitySubscription ??= connectivity.onConnectedChanged.listen((
      bool connected,
    ) {
      if (connected) unawaited(retryEligible());
    });
    unawaited(
      connectivity.isConnected().then((bool connected) {
        if (connected && !_disposed) return retryEligible();
      }),
    );
  }

  void _handleCaptureEvent(CapturedAudioEvent event) {
    if (_disposed) return;
    final CaptureIngestionLease lease;
    try {
      lease = barrier.enter();
    } on StateError {
      return;
    }
    final Future<void> lookup = _processById(event.captureRowId, lease);
    _lookups.add(lookup);
    unawaited(
      lookup.whenComplete(() {
        _lookups.remove(lookup);
      }),
    );
  }

  Future<void> retryEligible() {
    if (_disposed) return Future<void>.value();
    final Future<void>? running = _sweep;
    if (running != null) return running;
    final CaptureIngestionLease lease;
    try {
      lease = barrier.enter();
    } on StateError {
      return Future<void>.value();
    }
    final Future<void> sweep = _retryEligibleOnce(lease);
    _sweep = sweep;
    return sweep.whenComplete(() {
      if (identical(_sweep, sweep)) _sweep = null;
    });
  }

  Future<void> _retryEligibleOnce(CaptureIngestionLease lease) async {
    try {
      final List<Capture> rows = await captures.watchByStatuses(<CaptureStatus>{
        CaptureStatus.pending,
        CaptureStatus.processing,
        CaptureStatus.failed,
      }).first;
      for (final Capture capture in rows) {
        if (automaticRetryEligible(capture)) {
          await _process(capture, lease: lease, ownsLease: false);
        }
      }
    } finally {
      lease.close();
    }
  }

  Future<void> _processById(String id, CaptureIngestionLease lease) async {
    try {
      final List<Capture> rows = await captures.getByIds(<String>[id]);
      if (rows.isEmpty) return;
      final Capture capture = rows.single;
      if (automaticRetryEligible(capture)) {
        await _process(capture, lease: lease, ownsLease: false);
      }
    } finally {
      lease.close();
    }
  }

  Future<void> _process(
    Capture capture, {
    required CaptureIngestionLease lease,
    required bool ownsLease,
  }) async {
    final Future<void>? existing = _inFlight[capture.id];
    if (existing != null) return existing;
    final Future<void> future = _processOnce(capture, lease, ownsLease);
    _inFlight[capture.id] = future;
    try {
      await future;
    } finally {
      if (identical(_inFlight[capture.id], future)) {
        unawaited(_inFlight.remove(capture.id));
      }
    }
  }

  Future<void> _processOnce(
    Capture capture,
    CaptureIngestionLease lease,
    bool ownsLease,
  ) async {
    try {
      await processAudio(capture);
      if (!lease.invalidated) {
        await acknowledgeProcessed(capture);
      }
    } catch (_) {
      // ReminderCreationService persists the failure on the durable capture.
      // A later connectivity transition or explicit user retry can try again.
    } finally {
      if (ownsLease) lease.close();
    }
  }

  static bool automaticRetryEligible(Capture capture) {
    if (capture.audioPath == null || capture.audioPath!.isEmpty) return false;
    if (capture.status == CaptureStatus.pending ||
        capture.status == CaptureStatus.processing) {
      return true;
    }
    if (capture.status != CaptureStatus.failed ||
        ReminderCreationService.audioRetryLimitReachedFor(capture)) {
      return false;
    }
    final String message =
        ReminderCreationService.captureStateMessageFor(
          capture,
        )?.toLowerCase() ??
        '';
    if (message.isEmpty) return false;
    return message.contains('socketexception') ||
        message.contains('handshakeexception') ||
        message.contains('httpexception') ||
        message.contains('failed host lookup') ||
        message.contains('network is unreachable') ||
        message.contains('connection reset') ||
        message.contains('connection refused') ||
        message.contains('timed out') ||
        message.contains('timeout') ||
        RegExp(
          r'gemini reminder drafting failed \((408|429|500|502|503|504)\)',
        ).hasMatch(message);
  }

  Future<void> dispose() async {
    _disposed = true;
    await _captureSubscription?.cancel();
    await _connectivitySubscription?.cancel();
    await _sweep;
    await Future.wait<void>(_lookups.toList(growable: false));
    await Future.wait<void>(_inFlight.values.toList(growable: false));
  }
}
